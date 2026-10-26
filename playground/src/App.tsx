// tslint:disable
/* eslint-disable */
import React, {useCallback, useEffect, useRef, useState} from 'react';
import {
  Play,
  RotateCw,
  Shield,
  AlertTriangle,
} from 'lucide-react';
import {getConfig, AUDIO_TRACKS, AudioTrackType} from './constants';
import BackgroundMusic from './utils/BackgroundMusic';
import {TacticalHUD} from './TacticalHUD';
import {
  createFixedStepper,
  gameAudio,
  GameState,
  MenuOverlay,
  prepareCanvas,
  useInput,
} from './utils/helper';
import {
  usePlayground,
  usePlaygroundGameLifecycle,
} from './utils/usePlayground';

// --- CANONICAL GRID SYSTEM (CELL_SIZE = 32) ---
// Cell (0,0) has its exact center at world (0,0).
// Its boundaries are [-16..16] x [-16..16].
export const CELL_SIZE = 32;

/**
 * Converts world coordinates to integer grid coordinates
 */
export function worldToGrid(x: number, y: number): {gridX: number; gridY: number} {
  return {
    gridX: Math.round(x / CELL_SIZE),
    gridY: Math.round(y / CELL_SIZE),
  };
}

/**
 * Converts integer grid coordinates to the world center of the cell
 */
export function gridToCenter(gridX: number, gridY: number): {x: number; y: number} {
  return {
    x: gridX * CELL_SIZE,
    y: gridY * CELL_SIZE,
  };
}

/**
 * Checks if integer cell is part of the Nexus Core occupying gridX: -1..+1, gridY: -1..+1
 * Centered exactly at (0, 0) and spanning 96px x 96px from -48px to +48px.
 */
export function isCoreCell(gridX: number, gridY: number): boolean {
  return Math.abs(gridX) <= 1 && Math.abs(gridY) <= 1;
}

// Inner gate ring boundary (Zone 0) ~136px / ~4.2 cells from Core (0, 0)
export const GATE_RING_RADIUS = 136;

/**
 * Checks if integer cell is within Zone 0 / Gate Ring (radius <= 136px).
 * In this entire zone, open turret building is strictly prohibited;
 * building is ONLY allowed on the 6 designated Core Hardpoints.
 */
export function isCellInsideGateRing(gridX: number, gridY: number): boolean {
  const center = gridToCenter(gridX, gridY);
  return Math.hypot(center.x, center.y) <= GATE_RING_RADIUS;
}

/**
 * Checks if a grid cell (gridX, gridY) is traversed by any active rift enemy path corridor.
 */
export function isCellOnPath(
  gridX: number,
  gridY: number,
  portals: RiftPortal[],
): boolean {
  for (const portal of portals) {
    if (!portal.active || !portal.path || portal.path.length < 2) continue;
    for (let s = 0; s < portal.path.length - 1; s++) {
      const p1 = portal.path[s];
      const p2 = portal.path[s + 1];
      const g1 = worldToGrid(p1.x, p1.y);
      const g2 = worldToGrid(p2.x, p2.y);

      const minX = Math.min(g1.gridX, g2.gridX);
      const maxX = Math.max(g1.gridX, g2.gridX);
      const minY = Math.min(g1.gridY, g2.gridY);
      const maxY = Math.max(g1.gridY, g2.gridY);

      if (g1.gridX === g2.gridX) {
        // Vertical path segment
        if (gridX === g1.gridX && gridY >= minY && gridY <= maxY) {
          return true;
        }
      } else if (g1.gridY === g2.gridY) {
        // Horizontal path segment
        if (gridY === g1.gridY && gridX >= minX && gridX <= maxX) {
          return true;
        }
      } else {
        // Diagonal segment (e.g. final approach into Core)
        if (gridX >= minX && gridX <= maxX && gridY >= minY && gridY <= maxY) {
          const center = gridToCenter(gridX, gridY);
          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          const lenSq = dx * dx + dy * dy;
          if (lenSq > 0) {
            const t = Math.max(0, Math.min(1, ((center.x - p1.x) * dx + (center.y - p1.y) * dy) / lenSq));
            const projX = p1.x + t * dx;
            const projY = p1.y + t * dy;
            if (Math.hypot(center.x - projX, center.y - projY) < CELL_SIZE * 0.7) {
              return true;
            }
          }
        }
      }
    }
  }
  return false;
}

// --- GAME TYPES ---
export type TowerType = 'basic' | 'rapid' | 'sniper' | 'arc';
export type EnemyType =
  | 'basic'
  | 'fast'
  | 'tank'
  | 'splitter'
  | 'mini'
  | 'bulwark'
  | 'shifter'
  | 'boss';
export type TargetPriority = 'first' | 'closest' | 'strongest' | 'weakest';
export type MutationType = 'CRIMSON' | 'VOID' | 'TITAN' | 'PHASE' | 'NEON' | null;

export const MUTATION_PROFILES: Record<
  NonNullable<MutationType>,
  {hp: number; speed: number; reward: number; label: string; color: string}
> = {
  CRIMSON: {hp: 1.6, speed: 1.2, reward: 2.0, label: 'CRIMSON (×1.6 HP, ×1.2 SPD, ×2.0 REW)', color: '#ff1144'},
  VOID: {hp: 1.4, speed: 1.5, reward: 2.5, label: 'VOID (×1.4 HP, ×1.5 SPD, ×2.5 REW)', color: '#9900ff'},
  TITAN: {hp: 3.0, speed: 0.7, reward: 3.0, label: 'TITAN (×3.0 HP, ×0.7 SPD, ×3.0 REW)', color: '#ff6600'},
  PHASE: {hp: 1.2, speed: 2.0, reward: 1.5, label: 'PHASE (×1.2 HP, ×2.0 SPD, ×1.5 REW)', color: '#00e5ff'},
  NEON: {hp: 1.8, speed: 1.3, reward: 2.0, label: 'NEON (×1.8 HP, ×1.3 SPD, ×2.0 REW)', color: '#39ff14'},
};

export interface Hardpoint {
  id: number;
  gridX: number;
  gridY: number;
  x: number;
  y: number;
  ring: number; // 0 = Core Hardpoint, 1 = Inner Micro, 2 = Mid Micro, 3 = Outer Micro
  isCoreHardpoint: boolean;
  tower: Tower | null;
}

export interface Tower {
  id: number;
  type: TowerType;
  hardpointId: number | null; // null if built on an open grid cell
  gridX: number;
  gridY: number;
  x: number;
  y: number;
  level: number;
  angle: number;
  targetId: number | null;
  cooldown: number;
  totalInvested: number;
  priority: TargetPriority;
  kills: number;
  damageDealt: number;
  isCoreBonus?: boolean;
  barrelToggle?: number;
  lastFiredBarrel?: number;
  barrelFlashTimer?: number;
}

export interface Enemy {
  id: number;
  type: EnemyType;
  x: number;
  y: number;
  hp: number;
  maxHp: number;
  speed: number;
  shield: number;
  maxShield: number;
  angle: number;
  waypointIndex: number;
  path: {x: number; y: number}[];
  slowTimer: number;
  stunTimer: number;
  stunImmunityTimer: number;
  staticCharge: number; // Stuns for 0.5s at 100 charge (150 for Boss)
  isCloaked: boolean;
  cloakTimer: number;
  distanceTraveled: number;
  mutation: MutationType;
  bounty: number;
  riftTier: number;
  color: string;
  size: number;
}

export interface Projectile {
  id: number;
  type: TowerType | 'core_turret';
  x: number;
  y: number;
  prevX: number;
  prevY: number;
  targetX: number;
  targetY: number;
  vx: number;
  vy: number;
  damage: number;
  pierce: number;
  targetId: number | null;
  life: number;
  color: string;
  hitEnemyIds?: Set<number>;
}

export interface LaserBeam {
  startX: number;
  startY: number;
  endX: number;
  endY: number;
  color: string;
  width: number;
  alpha: number;
}

export interface LightningArc {
  points: {x: number; y: number}[];
  alpha: number;
  color: string;
}

export interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  color: string;
  size: number;
  life: number;
  maxLife: number;
}

export interface DamagePopup {
  x: number;
  y: number;
  text: string;
  color: string;
  life: number;
}

export interface Shockwave {
  x: number;
  y: number;
  radius: number;
  maxRadius: number;
  color: string;
  alpha: number;
}

export const MAX_PARTICLES = 120;

export interface RiftPortal {
  id: number;
  x: number;
  y: number;
  angle: number;
  active: boolean;
  pulseTimer: number;
  path: {x: number; y: number}[];
  doorIndex: number;
  mutation: MutationType;
  tier: number;
  zone: number;
}

// Concentric Zone Definitions & Dynamic Infinite Generator
// Radii are integer multiples of CELL_SIZE (32px): Zone 1 = 160 (5 cells), Zone 2 = 256 (8 cells), Zone 3 = 352 (11 cells), Zone 4 = 448 (14 cells)...
// Expanding outward with dynamic endless capacity (Zone N capacity = N + 1).
export function getZoneSpec(zoneNumber: number): {
  zone: number;
  radius: number;
  capacity: number;
  label: string;
} {
  const safeZone = Math.max(1, zoneNumber);
  // Spawn distance at least 380px to 550px from center (Zones 1-3)
  const radius = 400 + (safeZone - 1) * 80;
  const capacity = safeZone + 1;
  const standardLabels = ['INNER', 'MID', 'OUTER', 'PERIMETER'];
  const label =
    safeZone <= 4
      ? `ZONE ${safeZone} (${standardLabels[safeZone - 1]})`
      : `ZONE ${safeZone} (RING ${safeZone})`;
  return {
    zone: safeZone,
    radius,
    capacity,
    label,
  };
}

// Paced Rift Expansion Milestones:
// Wave 1–3: Exactly 1 Rift (gives player time to establish solid perimeter)
// Wave 4–7: 2 Rifts (manageable second front)
// Wave 8–11: 3 Rifts (steady progression)
// Wave 12–15: 4 Rifts
// Wave 16–19: 5 Rifts
// Wave 20+: 6 Rifts (deep late-game milestone)
export const getTargetRiftCountForWave = (targetWave: number): number => {
  if (targetWave <= 3) return 1;
  if (targetWave <= 7) return 2;
  if (targetWave <= 11) return 3;
  if (targetWave <= 15) return 4;
  if (targetWave <= 19) return 5;
  return 6 + Math.floor(Math.max(0, targetWave - 20) / 5);
};

/**
 * Checks if a wave is a rift milestone where a new rift opens (e.g. Wave 1, 4, 8, 12, 16, 20...)
 */
export const isRiftMilestone = (w: number): boolean => {
  if ([1, 4, 8, 12, 16, 20].includes(w)) return true;
  if (w > 20 && (w - 20) % 5 === 0) return true;
  return false;
};

/**
 * Decouples mutations from rifts: never trigger on a rift opening wave OR the wave immediately following!
 */
export const isRiftProximityWave = (w: number): boolean => {
  return isRiftMilestone(w) || isRiftMilestone(w - 1);
};

/**
 * Randomly schedules next cosmic mutation wave spaced 6-9 waves ahead,
 * guaranteeing at least 4 calm waves in between and never on or adjacent to rift appearances.
 */
export function scheduleNextMutationWave(currentWave: number): number {
  const interval = 6 + Math.floor(Math.random() * 4); // 6, 7, 8, or 9
  let candidate = Math.max(currentWave + 5, currentWave + interval);
  while (isRiftProximityWave(candidate)) {
    candidate++;
  }
  return candidate;
}

// Exactly 6 Symmetrical Core Gates surrounding the Nexus Core at radius ~4 cells (128px):
// Gate 1 (East): (+4, 0)
// Gate 2 (Bottom-Right): (+2, +3)
// Gate 3 (Bottom-Left): (-2, +3)
// Gate 4 (West): (-4, 0)
// Gate 5 (Top-Left): (-2, -3)
// Gate 6 (Top-Right): (+2, -3)
// Bilateral horizontal (X = -X) and vertical (Y = -Y) reflection symmetry.
export const CORE_DOORS: {
  gridX: number;
  gridY: number;
  x: number;
  y: number;
  entryGridX: number;
  entryGridY: number;
}[] = [
  { gridX: 4, gridY: 0, x: 4 * CELL_SIZE, y: 0, entryGridX: 1, entryGridY: 0 },
  { gridX: 2, gridY: 3, x: 2 * CELL_SIZE, y: 3 * CELL_SIZE, entryGridX: 1, entryGridY: 1 },
  { gridX: -2, gridY: 3, x: -2 * CELL_SIZE, y: 3 * CELL_SIZE, entryGridX: -1, entryGridY: 1 },
  { gridX: -4, gridY: 0, x: -4 * CELL_SIZE, y: 0, entryGridX: -1, entryGridY: 0 },
  { gridX: -2, gridY: -3, x: -2 * CELL_SIZE, y: -3 * CELL_SIZE, entryGridX: -1, entryGridY: -1 },
  { gridX: 2, gridY: -3, x: 2 * CELL_SIZE, y: -3 * CELL_SIZE, entryGridX: 1, entryGridY: -1 },
];

// Tower Blueprint Specs (Canonical Core Reference & Balanced Tuning)
export const TOWER_SPECS: Record<
  TowerType,
  {
    name: string;
    cost: number;
    range: number;
    damage: number;
    cooldownFrames: number; // Cooldown in frames (at 60fps)
    color: string;
    description: string;
    hotkey: string;
  }
> = {
  basic: {
    name: 'Laser Turret',
    cost: 100,
    range: 100,
    damage: 10,
    cooldownFrames: 30, // 0.50s, 20.0 DPS
    color: '#00f0ff',
    description: 'Continuous coherent Cyan beam. High-frequency thermal burn.',
    hotkey: 'Q',
  },
  rapid: {
    name: 'Rapid Pulse',
    cost: 130, // Tuned cost (130) for early viability vs swarms
    range: 92, // Tuned range (92) to catch fast movers cleanly
    damage: 4.5, // 0.15s CD, 30.0 DPS base (+50% vs Fast/Minis/Splitters)
    cooldownFrames: 9,
    color: '#f59e0b',
    description: 'Twin amber plasma bolts. Excels at shredding Fast & Mini swarms (+50% bonus).',
    hotkey: 'W',
  },
  sniper: {
    name: 'Railgun Sniper',
    cost: 220,
    range: 260,
    damage: 55, // 1.50s CD, 36.7 DPS base (+20% vs Tanks, Bulwarks, Bosses)
    cooldownFrames: 90,
    color: '#c084fc',
    description: 'Hypersonic magnetic kinetic slug. Pierces 4 targets with heavy armor punch.',
    hotkey: 'E',
  },
  arc: {
    name: 'Tesla Arc',
    cost: 240,
    range: 100,
    damage: 8,
    cooldownFrames: 34, // 0.57s, 14.1 DPS
    color: '#2563eb', // Distinct Deep Cobalt Blue
    description: 'Cobalt coils discharging chain lightning with balanced static stun (+3/+1.5 charge).',
    hotkey: 'R',
  },
};

/**
 * Calculates tower upgrade cost with accessible 0.4x progression multiplier
 */
export function getTowerUpgradeCost(type: TowerType, level: number): number {
  const baseCost = TOWER_SPECS[type]?.cost || 100;
  return Math.floor(baseCost * 0.4 * level);
}

export const RANGE_CAP = 800;

// Dynamic Camera Zoom Limits
export const MIN_ZOOM = 0.15;
export const MAX_ZOOM = 2.5;

/**
 * Shared vector renderer for both battlefield canvas rendering and HUD turret preview icons.
 * Guarantees 100% visual parity with zero discrepancy between button icons and in-game turrets.
 */
export function drawTurretModel(
  ctx: CanvasRenderingContext2D,
  type: TowerType,
  angle = 0,
  options: {
    barrelFlashTimer?: number;
    lastFiredBarrel?: number;
  } = {},
) {
  ctx.save();
  ctx.rotate(angle);

  if (type === 'basic') {
    // Laser Turret:
    // Square chassis with neon cyan outline, glowing inner optical lens, and focused forward optical barrel
    ctx.fillStyle = '#041424';
    ctx.strokeStyle = '#00f0ff';
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    ctx.rect(-8, -8, 16, 16);
    ctx.fill();
    ctx.stroke();

    // Internal optical lens ring
    ctx.strokeStyle = '#38bdf8';
    ctx.lineWidth = 1.0;
    ctx.beginPath();
    ctx.arc(0, 0, 4.5, 0, Math.PI * 2);
    ctx.stroke();

    // Forward laser focusing barrel
    ctx.fillStyle = '#00f0ff';
    ctx.fillRect(0, -2, 13, 4);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(8, -1, 5, 2);

    // Central optical core lens
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(0, 0, 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#00f0ff';
    ctx.beginPath();
    ctx.arc(0, 0, 1, 0, Math.PI * 2);
    ctx.fill();
  } else if (type === 'rapid') {
    // Rapid Pulse:
    // Faceted octagonal amber chassis with distinctive twin parallel autocannons protruding forward
    ctx.fillStyle = '#211503';
    ctx.strokeStyle = '#f59e0b';
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    const r = 8.5;
    for (let i = 0; i < 8; i++) {
      const a = (i * Math.PI) / 4 + Math.PI / 8;
      const px = Math.cos(a) * r;
      const py = Math.sin(a) * r;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Twin parallel autocannons protruding forward
    const isFlashing = (options.barrelFlashTimer ?? 0) > 0;
    const lastBarrel = options.lastFiredBarrel ?? 0;
    const recoil0 = isFlashing && lastBarrel === 0 ? 1.6 : 0;
    const recoil1 = isFlashing && lastBarrel === 1 ? 1.6 : 0;

    // Left barrel (-3.5px center)
    ctx.fillStyle = isFlashing && lastBarrel === 0 ? '#fbbf24' : '#f59e0b';
    ctx.fillRect(-recoil0, -4.75, 12, 2.5);
    ctx.fillStyle = '#fef08a';
    ctx.fillRect(7 - recoil0, -4.25, 4, 1.5);

    // Right barrel (+3.5px center)
    ctx.fillStyle = isFlashing && lastBarrel === 1 ? '#fbbf24' : '#f59e0b';
    ctx.fillRect(-recoil1, 2.25, 12, 2.5);
    ctx.fillStyle = '#fef08a';
    ctx.fillRect(7 - recoil1, 2.75, 4, 1.5);

    if (isFlashing) {
      const flashY = lastBarrel === 0 ? -3.5 : 3.5;
      const flashX = 12 - (lastBarrel === 0 ? recoil0 : recoil1);
      ctx.fillStyle = '#ffffff';
      ctx.beginPath();
      ctx.arc(flashX + 1, flashY, 2.0, 0, Math.PI * 2);
      ctx.fill();
    }

    // Central rotary capacitor core
    ctx.fillStyle = '#382103';
    ctx.strokeStyle = '#f59e0b';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(0, 0, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#fef08a';
    ctx.beginPath();
    ctx.arc(0, 0, 1.8, 0, Math.PI * 2);
    ctx.fill();
  } else if (type === 'sniper') {
    // Railgun Sniper:
    // Violet heavy chassis with two extended parallel electromagnetic accelerator rails with transverse coils
    ctx.fillStyle = '#170729';
    ctx.strokeStyle = '#c084fc';
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    ctx.rect(-8, -7, 13, 14);
    ctx.fill();
    ctx.stroke();

    // Dual extended electromagnetic accelerator rails
    ctx.fillStyle = '#a855f7';
    ctx.fillRect(1, -4, 15, 2);
    ctx.fillRect(1, 2, 15, 2);

    // Transverse electromagnetic accelerator coils
    ctx.fillStyle = '#c084fc';
    ctx.fillRect(4, -5, 2, 10);
    ctx.fillRect(9, -5, 2, 10);

    // Breech capacitor core
    ctx.fillStyle = '#3b0764';
    ctx.strokeStyle = '#e9d5ff';
    ctx.lineWidth = 1;
    ctx.fillRect(-5, -3, 6, 6);
    ctx.strokeRect(-5, -3, 6, 6);
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(-2, 0, 1.4, 0, Math.PI * 2);
    ctx.fill();
  } else if (type === 'arc') {
    // Tesla Arc:
    // Cobalt blue chassis with concentric capacitor rings/rhombus and top electric spark emitter
    ctx.fillStyle = '#081432';
    ctx.strokeStyle = '#2563eb';
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.arc(0, 0, 9.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    // Concentric Tesla capacitor rings
    ctx.strokeStyle = '#60a5fa';
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.arc(0, 0, 6, 0, Math.PI * 2);
    ctx.stroke();

    // Central spherical lightning discharge emitter
    ctx.fillStyle = '#1d4ed8';
    ctx.strokeStyle = '#93c5fd';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(0, 0, 3.2, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(0, 0, 1.4, 0, Math.PI * 2);
    ctx.fill();

    // Electric discharge spikes / electrode prongs along forward & lateral axes
    ctx.strokeStyle = '#60a5fa';
    ctx.lineWidth = 1.4;
    ctx.beginPath();
    ctx.moveTo(9.5, 0); ctx.lineTo(13.5, 0);
    ctx.moveTo(0, -9.5); ctx.lineTo(0, -12.5);
    ctx.moveTo(0, 9.5); ctx.lineTo(0, 12.5);
    ctx.stroke();
  }

  ctx.restore();
}

/**
 * TurretIcon component that literally renders the actual in-game turret model
 * using a high-DPI mini canvas. Ensures 100% visual parity with zero discrepancy.
 */
export function TurretIcon({
  type,
  size = 26,
  className = '',
}: {
  type: TowerType;
  size?: number;
  className?: string;
}) {
  const iconCanvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = iconCanvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const dpr = typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1;
    canvas.width = Math.round(size * dpr);
    canvas.height = Math.round(size * dpr);
    ctx.resetTransform?.();
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, size, size);

    ctx.save();
    ctx.translate(size / 2, size / 2);
    // Scale slightly to fit inside the icon bounds comfortably
    const scale = size / 28;
    ctx.scale(scale, scale);
    // Draw turret model facing forward / upward (-Math.PI / 2)
    drawTurretModel(ctx, type, -Math.PI / 2);
    ctx.restore();
  }, [type, size]);

  return (
    <canvas
      ref={iconCanvasRef}
      style={{width: size, height: size}}
      className={`shrink-0 pointer-events-none ${className}`}
    />
  );
}

function spawnParticle(
  particles: Particle[],
  x: number,
  y: number,
  vx: number,
  vy: number,
  color: string,
  size: number,
  life: number,
) {
  if (particles.length >= MAX_PARTICLES) {
    particles.shift();
  }
  particles.push({
    x,
    y,
    vx,
    vy,
    color,
    size,
    life,
    maxLife: life,
  });
}

/**
 * Calculates Arc network size for a given Arc tower:
 * Arc towers within 3 grid tiles (cardinally aligned) link up,
 * multiplying damage and fire rate up to x5 (scaling with network size, capped at 5).
 */
export function getArcNetworkSize(
  tower: Tower,
  allTowers: Tower[],
): number {
  if (tower.type !== 'arc') return 1;
  const arcTowers = allTowers.filter((t) => t.type === 'arc');

  const adjacency = new Map<number, number[]>();
  arcTowers.forEach((t) => adjacency.set(t.id, []));

  for (let i = 0; i < arcTowers.length; i++) {
    for (let j = i + 1; j < arcTowers.length; j++) {
      const a = arcTowers[i];
      const b = arcTowers[j];
      const dx = Math.abs(a.gridX - b.gridX);
      const dy = Math.abs(a.gridY - b.gridY);
      const isCardinallyAlignedWithin3 =
        (a.gridY === b.gridY && dx <= 3) ||
        (a.gridX === b.gridX && dy <= 3);

      if (isCardinallyAlignedWithin3) {
        adjacency.get(a.id)!.push(b.id);
        adjacency.get(b.id)!.push(a.id);
      }
    }
  }

  const visited = new Set<number>();
  const queue = [tower.id];
  visited.add(tower.id);

  while (queue.length > 0) {
    const curId = queue.shift()!;
    const neighbors = adjacency.get(curId) || [];
    for (const nId of neighbors) {
      if (!visited.has(nId)) {
        visited.add(nId);
        queue.push(nId);
      }
    }
  }

  return Math.min(5, Math.max(1, visited.size));
}

/**
 * Calculates effective tower range with canonical upgrade scaling:
 * range = Math.min(800, baseRange * Math.pow(1.1, level - 1) * hardpointMult * ocMult)
 */
export function getTowerEffectiveRange(
  type: TowerType,
  level: number = 1,
  isCoreBonus: boolean = false,
  isOverclocked: boolean = false,
): number {
  const base = TOWER_SPECS[type].range;
  const levelMult = Math.pow(1.1, level - 1);
  const coreMult = isCoreBonus ? 1.06 : 1.0;
  const ocMult = isOverclocked ? 1.25 : 1.0;
  return Math.min(RANGE_CAP, Math.round(base * levelMult * coreMult * ocMult));
}

/**
 * Calculates effective tower damage with canonical upgrade scaling:
 * damage = baseDamage * Math.pow(1.2, level - 1) * hardpointMult * networkMult
 */
export function getTowerEffectiveDamage(
  type: TowerType,
  level: number = 1,
  isCoreBonus: boolean = false,
  networkMult: number = 1.0,
): number {
  const base = TOWER_SPECS[type].damage;
  const levelMult = Math.pow(1.2, level - 1);
  const coreMult = isCoreBonus ? 1.08 : 1.0;
  return Math.round(base * levelMult * coreMult * networkMult * 10) / 10;
}

/**
 * Calculates effective cooldown in seconds:
 * cooldown = (cooldownFrames / 60) * coreMult * (isOverclocked ? 0.5 : 1.0) / networkMult
 */
export function getTowerEffectiveCooldown(
  type: TowerType,
  isCoreBonus: boolean = false,
  isOverclocked: boolean = false,
  networkMult: number = 1.0,
): number {
  const baseSec = TOWER_SPECS[type].cooldownFrames / 60;
  const coreMult = isCoreBonus ? 0.95 : 1.0;
  const ocMult = isOverclocked ? 0.5 : 1.0;
  return (baseSec * coreMult * ocMult) / networkMult;
}

/**
 * Calculates Core Turret effective damage (level 1 to 10):
 * 20 + 10 * (level - 1)
 */
export function getCoreTurretDamage(level: number = 1): number {
  return 20 + 10 * (level - 1);
}

/**
 * Calculates Core Turret effective range (level 1 to 10):
 * 150 + 30 * (level - 1)
 */
export function getCoreTurretEffectiveRange(level: number = 1): number {
  return 150 + 30 * (level - 1);
}

/**
 * Calculates Core Turret cooldown in frames (at 60fps):
 * Math.max(8, 35 - 5 * level)
 */
export function getCoreTurretCooldownFrames(level: number = 1): number {
  return Math.max(8, 35 - 5 * level);
}

// Canonical Enemy Blueprint Specs (# The Neon Defense: Enemy Reference)
export const ENEMY_SPECS: Record<
  EnemyType,
  {
    name: string;
    hp: number;
    speed: number;
    reward: number;
    size: number;
    color: string;
    scoreVal: number;
    unlockWave: number;
  }
> = {
  basic: {
    name: 'Basic',
    hp: 30,
    speed: 1.3,
    reward: 10,
    size: 20,
    color: '#ff0000',
    scoreVal: 50,
    unlockWave: 1,
  },
  fast: {
    name: 'Fast',
    hp: 20,
    speed: 2.1,
    reward: 12,
    size: 16,
    color: '#ffff00',
    scoreVal: 40,
    unlockWave: 3,
  },
  tank: {
    name: 'Tank',
    hp: 100,
    speed: 0.75,
    reward: 25,
    size: 24,
    color: '#ff00ff',
    scoreVal: 150,
    unlockWave: 5,
  },
  splitter: {
    name: 'Splitter',
    hp: 70,
    speed: 1.1,
    reward: 26,
    size: 28,
    color: '#00ff41',
    scoreVal: 90,
    unlockWave: 12,
  },
  mini: {
    name: 'Mini',
    hp: 14,
    speed: 1.5,
    reward: 6,
    size: 12,
    color: '#00ff41',
    scoreVal: 25,
    unlockWave: 12,
  },
  bulwark: {
    name: 'Bulwark',
    hp: 280,
    speed: 0.55,
    reward: 30,
    size: 32,
    color: '#fcee0a',
    scoreVal: 120,
    unlockWave: 5,
  },
  shifter: {
    name: 'Shifter',
    hp: 55,
    speed: 1.3,
    reward: 32,
    size: 20,
    color: '#ff00ac',
    scoreVal: 80,
    unlockWave: 16,
  },
  boss: {
    name: 'Titan Prime',
    hp: 700,
    speed: 0.45,
    reward: 250,
    size: 40,
    color: '#ff8800',
    scoreVal: 1500,
    unlockWave: 10,
  },
};

/**
 * Snaps a 2D coordinate to cell center
 */
function snapToGrid(x: number, y: number): {x: number; y: number; gridX: number; gridY: number} {
  const gridX = Math.round(x / CELL_SIZE);
  const gridY = Math.round(y / CELL_SIZE);
  return {
    gridX,
    gridY,
    x: gridX * CELL_SIZE,
    y: gridY * CELL_SIZE,
  };
}

/**
 * Tests if an orthogonal straight line segment between (x1, y1) and (x2, y2)
 * is completely free of obstacles.
 * If allowEndpoint is true, the final cell (x2, y2) is permitted even if in obstacleSet (e.g. Gate door).
 */
function isOrthogonalSegmentClear(
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  obstacleSet: Set<string>,
  allowEndpoint = false,
): boolean {
  if (x1 !== x2 && y1 !== y2) return false;
  const dx = Math.sign(x2 - x1);
  const dy = Math.sign(y2 - y1);
  let curX = x1;
  let curY = y1;

  while (curX !== x2 || curY !== y2) {
    curX += dx;
    curY += dy;
    if (curX === x2 && curY === y2 && allowEndpoint) break;
    if (obstacleSet.has(`${curX},${curY}`)) return false;
  }
  return true;
}

/**
 * Tries simple, clean 1-bend (L-turn) or 2-bend (Z-turn) orthogonal routing.
 * Strictly guarantees corridors with AT MOST 1 OR 2 BENDS and ZERO alternating staircases.
 */
function tryDirectOrthogonalRoutes(
  startGx: number,
  startGy: number,
  targetGx: number,
  targetGy: number,
  obstacleSet: Set<string>,
): {gx: number; gy: number}[] | null {
  // 1. Direct Straightaway (horizontally or vertically aligned)
  if (startGx === targetGx || startGy === targetGy) {
    if (isOrthogonalSegmentClear(startGx, startGy, targetGx, targetGy, obstacleSet, true)) {
      return [{gx: startGx, gy: startGy}, {gx: targetGx, gy: targetGy}];
    }
  }

  // 2. Route A: Horizontal First, then Vertical (Corner at (targetGx, startGy))
  const cornerA = {gx: targetGx, gy: startGy};
  const cornerAFree = !obstacleSet.has(`${cornerA.gx},${cornerA.gy}`);
  const routeAClear =
    cornerAFree &&
    isOrthogonalSegmentClear(startGx, startGy, cornerA.gx, cornerA.gy, obstacleSet, false) &&
    isOrthogonalSegmentClear(cornerA.gx, cornerA.gy, targetGx, targetGy, obstacleSet, true);

  // 3. Route B: Vertical First, then Horizontal (Corner at (startGx, targetGy))
  const cornerB = {gx: startGx, gy: targetGy};
  const cornerBFree = !obstacleSet.has(`${cornerB.gx},${cornerB.gy}`);
  const routeBClear =
    cornerBFree &&
    isOrthogonalSegmentClear(startGx, startGy, cornerB.gx, cornerB.gy, obstacleSet, false) &&
    isOrthogonalSegmentClear(cornerB.gx, cornerB.gy, targetGx, targetGy, obstacleSet, true);

  if (routeAClear && routeBClear) {
    const distA = Math.hypot(cornerA.gx, cornerA.gy);
    const distB = Math.hypot(cornerB.gx, cornerB.gy);
    return distA <= distB
      ? [{gx: startGx, gy: startGy}, cornerA, {gx: targetGx, gy: targetGy}]
      : [{gx: startGx, gy: startGy}, cornerB, {gx: targetGx, gy: targetGy}];
  } else if (routeAClear) {
    return [{gx: startGx, gy: startGy}, cornerA, {gx: targetGx, gy: targetGy}];
  } else if (routeBClear) {
    return [{gx: startGx, gy: startGy}, cornerB, {gx: targetGx, gy: targetGy}];
  }

  // 4. Route C: 2-bend Z-routes via intermediate columns midX
  const dx = Math.sign(targetGx - startGx);
  if (dx !== 0) {
    const midCols: number[] = [];
    for (let x = startGx + dx; x !== targetGx; x += dx) {
      midCols.push(x);
    }
    const midTarget = (startGx + targetGx) / 2;
    midCols.sort((a, b) => Math.abs(a - midTarget) - Math.abs(b - midTarget));

    for (const mx of midCols) {
      const c1 = {gx: mx, gy: startGy};
      const c2 = {gx: mx, gy: targetGy};
      if (!obstacleSet.has(`${c1.gx},${c1.gy}`) && !obstacleSet.has(`${c2.gx},${c2.gy}`)) {
        if (
          isOrthogonalSegmentClear(startGx, startGy, c1.gx, c1.gy, obstacleSet, false) &&
          isOrthogonalSegmentClear(c1.gx, c1.gy, c2.gx, c2.gy, obstacleSet, false) &&
          isOrthogonalSegmentClear(c2.gx, c2.gy, targetGx, targetGy, obstacleSet, true)
        ) {
          return [{gx: startGx, gy: startGy}, c1, c2, {gx: targetGx, gy: targetGy}];
        }
      }
    }
  }

  // 5. Route D: 2-bend Z-routes via intermediate rows midY
  const dy = Math.sign(targetGy - startGy);
  if (dy !== 0) {
    const midRows: number[] = [];
    for (let y = startGy + dy; y !== targetGy; y += dy) {
      midRows.push(y);
    }
    const midTarget = (startGy + targetGy) / 2;
    midRows.sort((a, b) => Math.abs(a - midTarget) - Math.abs(b - midTarget));

    for (const my of midRows) {
      const c1 = {gx: startGx, gy: my};
      const c2 = {gx: targetGx, gy: my};
      if (!obstacleSet.has(`${c1.gx},${c1.gy}`) && !obstacleSet.has(`${c2.gx},${c2.gy}`)) {
        if (
          isOrthogonalSegmentClear(startGx, startGy, c1.gx, c1.gy, obstacleSet, false) &&
          isOrthogonalSegmentClear(c1.gx, c1.gy, c2.gx, c2.gy, obstacleSet, false) &&
          isOrthogonalSegmentClear(c2.gx, c2.gy, targetGx, targetGy, obstacleSet, true)
        ) {
          return [{gx: startGx, gy: startGy}, c1, c2, {gx: targetGx, gy: targetGy}];
        }
      }
    }
  }

  return null;
}

/**
 * Removes redundant points along straight horizontal or vertical lines.
 */
function simplifyCollinearGridPoints(
  points: {gx: number; gy: number}[],
): {gx: number; gy: number}[] {
  if (points.length <= 2) return [...points];
  const cleaned: {gx: number; gy: number}[] = [points[0]];

  for (let i = 1; i < points.length - 1; i++) {
    const prev = cleaned[cleaned.length - 1];
    const curr = points[i];
    const next = points[i + 1];

    if (curr.gx === prev.gx && curr.gy === prev.gy) continue;

    const sameLineX = prev.gx === curr.gx && curr.gx === next.gx;
    const sameLineY = prev.gy === curr.gy && curr.gy === next.gy;
    if (!sameLineX && !sameLineY) {
      cleaned.push(curr);
    }
  }

  const last = points[points.length - 1];
  if (cleaned[cleaned.length - 1].gx !== last.gx || cleaned[cleaned.length - 1].gy !== last.gy) {
    cleaned.push(last);
  }
  return cleaned;
}

/**
 * Strict Path Post-Processor:
 * Collapses any collinear or micro-staircase segments into direct clean lines.
 * Strictly enforces orthogonal doglegs with at most 1 or 2 bends.
 */
function collapseStaircasesAndDogleg(
  points: {gx: number; gy: number}[],
  obstacleSet: Set<string>,
): {gx: number; gy: number}[] {
  if (points.length <= 2) return points;

  let current = simplifyCollinearGridPoints(points);
  let passes = 0;
  let changed = true;

  while (changed && passes++ < 6) {
    changed = false;
    const nextList: {gx: number; gy: number}[] = [current[0]];
    let i = 0;

    while (i < current.length - 1) {
      let furthest = -1;
      let bestRoute: {gx: number; gy: number}[] | null = null;

      // Greedy backward search: find furthest point that can be reached with <= 2 bends
      for (let j = current.length - 1; j > i + 1; j--) {
        const route = tryDirectOrthogonalRoutes(
          current[i].gx,
          current[i].gy,
          current[j].gx,
          current[j].gy,
          obstacleSet,
        );
        if (route && route.length >= 2) {
          furthest = j;
          bestRoute = route;
          break;
        }
      }

      if (bestRoute && furthest !== -1) {
        for (let k = 1; k < bestRoute.length; k++) {
          nextList.push(bestRoute[k]);
        }
        i = furthest;
        changed = true;
      } else {
        nextList.push(current[i + 1]);
        i++;
      }
    }

    current = simplifyCollinearGridPoints(nextList);

    // Micro-staircase elimination: detect and collapse any short alternating steps
    const microCleaned: {gx: number; gy: number}[] = [current[0]];
    let m = 0;
    while (m < current.length - 1) {
      if (m + 3 < current.length) {
        const p0 = current[m];
        const p1 = current[m + 1];
        const p2 = current[m + 2];
        const p3 = current[m + 3];

        const len1 = Math.hypot(p1.gx - p0.gx, p1.gy - p0.gy);
        const len2 = Math.hypot(p2.gx - p1.gx, p2.gy - p1.gy);
        const len3 = Math.hypot(p3.gx - p2.gx, p3.gy - p2.gy);

        if (len1 <= 3 && len2 <= 3 && len3 <= 3) {
          const direct = tryDirectOrthogonalRoutes(
            p0.gx,
            p0.gy,
            p3.gx,
            p3.gy,
            obstacleSet,
          );
          if (direct && direct.length < 4) {
            for (let k = 1; k < direct.length; k++) {
              microCleaned.push(direct[k]);
            }
            m += 3;
            changed = true;
            continue;
          }
        }
      }
      microCleaned.push(current[m + 1]);
      m++;
    }
    current = simplifyCollinearGridPoints(microCleaned);
  }

  return current;
}

/**
 * A* Orthogonal Grid Pathfinder with heavy turn penalty (cost + 40)
 * ensuring strictly straightaway corridors and 90-degree tactical bends.
 */
function findOrthogonalGridPath(
  startGx: number,
  startGy: number,
  targetGx: number,
  targetGy: number,
  obstacleSet: Set<string>,
): {x: number; y: number}[] {
  if (startGx === targetGx && startGy === targetGy) {
    return [gridToCenter(startGx, startGy)];
  }

  // Attempt direct clean 1-bend or 2-bend orthogonal route first
  const directRoute = tryDirectOrthogonalRoutes(
    startGx,
    startGy,
    targetGx,
    targetGy,
    obstacleSet,
  );

  if (directRoute && directRoute.length >= 2) {
    return directRoute.map((p) => gridToCenter(p.gx, p.gy));
  }

  // Fallback to A* with heavy turn penalty (cost + 40)
  interface Node {
    gx: number;
    gy: number;
    g: number;
    f: number;
    dirX: number;
    dirY: number;
    parent: Node | null;
  }

  const openList: Node[] = [];
  const closedSet = new Map<string, number>();

  const startNode: Node = {
    gx: startGx,
    gy: startGy,
    g: 0,
    f: Math.abs(startGx - targetGx) + Math.abs(startGy - targetGy),
    dirX: 0,
    dirY: 0,
    parent: null,
  };

  openList.push(startNode);

  const directions = [
    {dx: 1, dy: 0},
    {dx: -1, dy: 0},
    {dx: 0, dy: 1},
    {dx: 0, dy: -1},
  ];

  let iterations = 0;
  const maxIterations = 8000;
  let reachedNode: Node | null = null;
  const startDistCore = Math.hypot(startGx, startGy);

  while (openList.length > 0 && iterations++ < maxIterations) {
    let bestIdx = 0;
    for (let i = 1; i < openList.length; i++) {
      if (
        openList[i].f < openList[bestIdx].f ||
        (openList[i].f === openList[bestIdx].f && openList[i].g > openList[bestIdx].g)
      ) {
        bestIdx = i;
      }
    }

    const current = openList.splice(bestIdx, 1)[0];
    const stateKey = `${current.gx},${current.gy},${current.dirX},${current.dirY}`;

    if (current.gx === targetGx && current.gy === targetGy) {
      reachedNode = current;
      break;
    }

    const prevCost = closedSet.get(stateKey);
    if (prevCost !== undefined && prevCost <= current.g) {
      continue;
    }
    closedSet.set(stateKey, current.g);

    const curDistCore = Math.hypot(current.gx, current.gy);

    for (const dir of directions) {
      const nextGx = current.gx + dir.dx;
      const nextGy = current.gy + dir.dy;
      const isTarget = nextGx === targetGx && nextGy === targetGy;

      if (!isTarget && obstacleSet.has(`${nextGx},${nextGy}`)) {
        continue;
      }

      const nextDistCore = Math.hypot(nextGx, nextGy);
      if (!isTarget && nextDistCore > startDistCore + 1.0) {
        continue;
      }

      const hasPrevDir = current.dirX !== 0 || current.dirY !== 0;
      const isTurn = hasPrevDir && (current.dirX !== dir.dx || current.dirY !== dir.dy);
      // Heavy turn penalty (40.0) strictly prevents 1-tile zigzag staircase steps!
      const turnPenalty = isTurn ? 40.0 : 0;
      const outwardPenalty = nextDistCore > curDistCore ? (nextDistCore - curDistCore) * 25 : 0;
      const moveCost = 1.0 + turnPenalty + outwardPenalty;
      const tentativeG = current.g + moveCost;

      const nextStateKey = `${nextGx},${nextGy},${dir.dx},${dir.dy}`;
      if (closedSet.has(nextStateKey) && closedSet.get(nextStateKey)! <= tentativeG) {
        continue;
      }

      const h = Math.abs(nextGx - targetGx) + Math.abs(nextGy - targetGy);

      const existingOpen = openList.find(
        (n) => n.gx === nextGx && n.gy === nextGy && n.dirX === dir.dx && n.dirY === dir.dy,
      );

      if (existingOpen) {
        if (tentativeG < existingOpen.g) {
          existingOpen.g = tentativeG;
          existingOpen.f = tentativeG + h;
          existingOpen.parent = current;
        }
      } else {
        openList.push({
          gx: nextGx,
          gy: nextGy,
          g: tentativeG,
          f: tentativeG + h,
          dirX: dir.dx,
          dirY: dir.dy,
          parent: current,
        });
      }
    }
  }

  // Backtrack full cell path
  const gridCells: {gx: number; gy: number}[] = [];
  let curr = reachedNode;
  while (curr) {
    gridCells.unshift({gx: curr.gx, gy: curr.gy});
    curr = curr.parent;
  }

  if (gridCells.length === 0) {
    gridCells.push({gx: startGx, gy: startGy});
    gridCells.push({gx: targetGx, gy: targetGy});
  }

  // Strictly collapse any staircases into clean doglegs
  const simplified = collapseStaircasesAndDogleg(gridCells, obstacleSet);

  return simplified.map((p) => gridToCenter(p.gx, p.gy));
}

/**
 * Strict Downstream Distance Validator and Staircase Eliminator:
 * Validates that every waypoint connects cleanly to Gate and Core,
 * strictly eliminating any staircases or micro-jogs.
 */
function sanitizeAndValidateMonotonicPath(
  path: {x: number; y: number}[],
  startX: number,
  startY: number,
  targetDoor: typeof CORE_DOORS[number],
  obstacleSet: Set<string>,
): {x: number; y: number}[] {
  const startGrid = worldToGrid(startX, startY);
  const rawCells: {gx: number; gy: number}[] = [{gx: startGrid.gridX, gy: startGrid.gridY}];

  for (let i = 0; i < path.length; i++) {
    const g = worldToGrid(path[i].x, path[i].y);
    const prev = rawCells[rawCells.length - 1];
    if (g.gridX === prev.gx && g.gridY === prev.gy) continue;
    rawCells.push({gx: g.gridX, gy: g.gridY});
  }

  // Ensure path reaches targetDoor
  const lastCell = rawCells[rawCells.length - 1];
  if (lastCell.gx !== targetDoor.gridX || lastCell.gy !== targetDoor.gridY) {
    rawCells.push({gx: targetDoor.gridX, gy: targetDoor.gridY});
  }

  // Run full dogleg shortcutter & staircase elimination post-processor
  const cleanedCells = collapseStaircasesAndDogleg(rawCells, obstacleSet);

  const finalPath = cleanedCells.map((c) => gridToCenter(c.gx, c.gy));

  // Approach into Core center (0, 0)
  const lastPt = finalPath[finalPath.length - 1];
  if (Math.hypot(lastPt.x, lastPt.y) > 2) {
    finalPath.push({x: 0, y: 0});
  }

  return finalPath;
}

function drawHexagonPath(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  radius: number,
) {
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const angle = (i * Math.PI) / 3;
    const px = x + radius * Math.cos(angle);
    const py = y + radius * Math.sin(angle);
    if (i === 0) ctx.moveTo(px, py);
    else ctx.lineTo(px, py);
  }
  ctx.closePath();
}

/**
 * Draws electric discharge directly between two points (can be diagonal)
 * with natural high-voltage jagged jitters for attacks.
 * Highly optimized without expensive shadowBlur for smooth 60+ FPS.
 */
function drawDirectLightning(
  ctx: CanvasRenderingContext2D,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  color: string,
  width: number,
) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const dist = Math.hypot(dx, dy);
  if (dist < 1) return;

  const steps = Math.max(3, Math.floor(dist / 14));
  const perpX = -dy / dist;
  const perpY = dx / dist;

  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const pts: {x: number; y: number}[] = [{x: x1, y: y1}];
  for (let i = 1; i < steps; i++) {
    const t = i / steps;
    const jitter = (Math.random() - 0.5) * 10;
    pts.push({
      x: x1 + dx * t + perpX * jitter,
      y: y1 + dy * t + perpY * jitter,
    });
  }
  pts.push({x: x2, y: y2});

  // Layer 1: Outer glow stroke (fast alpha without shadowBlur)
  ctx.strokeStyle = color;
  ctx.globalAlpha = 0.45;
  ctx.lineWidth = width * 2.2;
  ctx.beginPath();
  pts.forEach((p, idx) => {
    if (idx === 0) ctx.moveTo(p.x, p.y);
    else ctx.lineTo(p.x, p.y);
  });
  ctx.stroke();

  // Layer 2: Main colored core
  ctx.globalAlpha = 0.9;
  ctx.lineWidth = width;
  ctx.stroke();

  // Layer 3: White-hot inner core
  ctx.strokeStyle = '#ffffff';
  ctx.globalAlpha = 1.0;
  ctx.lineWidth = Math.max(1, width * 0.45);
  ctx.stroke();

  ctx.restore();
}

/**
 * Draws electric conduits strictly along horizontal and vertical Manhattan
 * axes with zero diagonal lines. Stepped pulses and jitters are strictly
 * orthogonal right angles (dx = 0 or dy = 0).
 * Highly optimized without expensive shadowBlur.
 */
function drawOrthogonalLightning(
  ctx: CanvasRenderingContext2D,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  color: string,
  width: number,
) {
  ctx.save();
  ctx.lineCap = 'square';
  ctx.lineJoin = 'miter';

  const drawCardinalSegment = (
    sx: number,
    sy: number,
    ex: number,
    ey: number,
  ) => {
    if (sx === ex && sy === ey) return;

    if (sy === ey) {
      const len = Math.abs(ex - sx);
      const dir = ex > sx ? 1 : -1;
      const stepCount = Math.max(1, Math.floor(len / 16));
      let curX = sx;

      for (let s = 0; s < stepCount; s++) {
        const nextX = sx + dir * ((s + 1) / stepCount) * len;
        if (s < stepCount - 1 && Math.random() < 0.4) {
          const midX = curX + dir * (len / stepCount) * 0.5;
          const jitterY = (Math.random() > 0.5 ? 1 : -1) * (2 + Math.random() * 3);
          ctx.lineTo(midX, sy);
          ctx.lineTo(midX, sy + jitterY);
          ctx.lineTo(midX + dir * 3, sy + jitterY);
          ctx.lineTo(midX + dir * 3, sy);
        }
        ctx.lineTo(nextX, sy);
        curX = nextX;
      }
    } else if (sx === ex) {
      const len = Math.abs(ey - sy);
      const dir = ey > sy ? 1 : -1;
      const stepCount = Math.max(1, Math.floor(len / 16));
      let curY = sy;

      for (let s = 0; s < stepCount; s++) {
        const nextY = sy + dir * ((s + 1) / stepCount) * len;
        if (s < stepCount - 1 && Math.random() < 0.4) {
          const midY = curY + dir * (len / stepCount) * 0.5;
          const jitterX = (Math.random() > 0.5 ? 1 : -1) * (2 + Math.random() * 3);
          ctx.lineTo(sx, midY);
          ctx.lineTo(sx + jitterX, midY);
          ctx.lineTo(sx + jitterX, midY + dir * 3);
          ctx.lineTo(sx, midY + dir * 3);
        }
        ctx.lineTo(sx, nextY);
        curY = nextY;
      }
    }
  };

  // Outer glow
  ctx.strokeStyle = color;
  ctx.globalAlpha = 0.35;
  ctx.lineWidth = width * 2.2;
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  if (x1 === x2) {
    drawCardinalSegment(x1, y1, x1, y2);
  } else if (y1 === y2) {
    drawCardinalSegment(x1, y1, x2, y1);
  } else {
    drawCardinalSegment(x1, y1, x2, y1);
    drawCardinalSegment(x2, y1, x2, y2);
  }
  ctx.stroke();

  // Core line
  ctx.globalAlpha = 0.95;
  ctx.lineWidth = width;
  ctx.stroke();

  if (x1 !== x2 && y1 !== y2) {
    ctx.fillStyle = '#93c5fd';
    ctx.fillRect(x2 - 1.5, y1 - 1.5, 3, 3);
  }

  ctx.restore();
}

export default function App() {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stepperRef = useRef<ReturnType<typeof createFixedStepper>>();

  // --- PLAYGROUND SDK INTEGRATION ---
  const {sdk} = usePlayground();

  // Track dynamic canvas viewport dimensions
  const [canvasSize, setCanvasSize] = useState({width: 1376, height: 768});
  const canvasSizeRef = useRef({width: 1376, height: 768});

  if (!stepperRef.current) {
    const stepMs = getConfig('stepMs');
    const maxSubSteps = getConfig('maxSubSteps');
    stepperRef.current = createFixedStepper(stepMs, maxSubSteps);
  }

  // --- REACTIVE STATE FOR HUD & UI ---
  const [gameState, setGameState] = useState<GameState>({
    status: 'START',
    score: 0,
    level: 1, // Current Wave
  });

  const [credits, setCredits] = useState<number>(getConfig('startingCredits') || 200);
  const [coreLives, setCoreLives] = useState<number>(20);
  const [coreRepairsCount, setCoreRepairsCount] = useState<number>(0);
  const [coreTurretLevel, setCoreTurretLevel] = useState<number>(1);
  const [energy, setEnergy] = useState<number>(50); // max 100
  const [selectedBuildType, setSelectedBuildType] = useState<TowerType | null>(null);
  const selectedBuildTypeRef = useRef<TowerType | null>(null);
  selectedBuildTypeRef.current = selectedBuildType;
  const [selectedHardpointId, setSelectedHardpointId] = useState<number | null>(null);
  const [selectedTowerId, setSelectedTowerId] = useState<number | null>(null);
  const [hoveredHardpointId, setHoveredHardpointId] = useState<number | null>(null);
  const [isCoreSelected, setIsCoreSelected] = useState<boolean>(false);
  const [selectedGateIndex, setSelectedGateIndex] = useState<number | null>(null);
  const [hoveredGateIndex, setHoveredGateIndex] = useState<number | null>(null);

  // 30s Prep Phase timer & wave phase
  const [isPrepPhase, setIsPrepPhase] = useState<boolean>(true);
  const [prepTimer, setPrepTimer] = useState<number>(30);
  const [isWaveActive, setIsWaveActive] = useState<boolean>(false);
  const [activeMutation, setActiveMutation] = useState<MutationType>(null);

  // Anomaly warning for the wave immediately preceding a mutation
  const [anomalyWarningText, setAnomalyWarningText] = useState<string | null>(null);
  const [nextMutationWave, setNextMutationWave] = useState<number>(() => scheduleNextMutationWave(1));
  const nextMutationWaveRef = useRef<number>(nextMutationWave);
  nextMutationWaveRef.current = nextMutationWave;
  const energyRegenAccRef = useRef<number>(0);

  // Abilities cooldown
  const [empCooldownLeft, setEmpCooldownLeft] = useState<number>(0);
  const [overclockCooldownLeft, setOverclockCooldownLeft] = useState<number>(0);
  const [isOverclockActive, setIsOverclockActive] = useState<boolean>(false);
  const [isEmpTargeting, setIsEmpTargeting] = useState<boolean>(false);
  const [telemetry, setTelemetry] = useState({
    fps: 60,
    enemies: 0,
    turrets: 0,
    rifts: 1,
    projectiles: 0,
  });
  const frameCountRef = useRef(0);
  const lastFpsUpdateTimeRef = useRef(performance.now());

  // Audio levels and dynamic soundtrack states
  const [isSfxMuted, setIsSfxMuted] = useState<boolean>(false);
  const [isMusicMuted, setIsMusicMuted] = useState<boolean>(false);
  const [masterVolume, setMasterVolume] = useState<number>(8);
  const [sfxVolume, setSfxVolume] = useState<number>(7);
  const [threatVolume, setThreatVolume] = useState<number>(6);
  const [activeMusicTrack, setActiveMusicTrack] = useState<AudioTrackType>('tactical');
  const activeMusicTrackRef = useRef<AudioTrackType>('tactical');
  const [tacticalBanner, setTacticalBanner] = useState<{
    type: 'boss' | 'mutation';
    text: string;
    trackName: string;
  } | null>(null);

  // Sync SFX volume changes to gameAudio
  useEffect(() => {
    const effSfx = (masterVolume / 10) * (sfxVolume / 10);
    gameAudio.setVolume(effSfx);
  }, [masterVolume, sfxVolume]);

  // Modal overlays & Dev drawer
  const [isGameMenuOpen, setIsGameMenuOpen] = useState<boolean>(false);
  const [isDevDrawerOpen, setIsDevDrawerOpen] = useState<boolean>(false);
  const [isDevAuthenticated, setIsDevAuthenticated] = useState<boolean>(false);

  // Telemetry run statistics for debrief
  const totalKillsRef = useRef<number>(0);
  const totalCreditsEarnedRef = useRef<number>(200);
  const wavesSurvivedRef = useRef<number>(0);

  // High-performance 60 FPS simulation refs
  const nextEntityIdRef = useRef(1);
  const hardpointsRef = useRef<Hardpoint[]>([]);
  const freeTowersRef = useRef<Tower[]>([]); // Towers built on open grid cells
  const enemiesRef = useRef<Enemy[]>([]);
  const projectilesRef = useRef<Projectile[]>([]);
  const lasersRef = useRef<LaserBeam[]>([]);
  const arcsRef = useRef<LightningArc[]>([]);
  const particlesRef = useRef<Particle[]>([]);
  const popupsRef = useRef<DamagePopup[]>([]);
  const shockwavesRef = useRef<Shockwave[]>([]);
  const portalsRef = useRef<RiftPortal[]>([]);
  const mouseWorldPosRef = useRef({x: 0, y: 0});
  const keysDownRef = useRef<Set<string>>(new Set());

  // Simulation parameters in refs
  const creditsRef = useRef(credits);
  creditsRef.current = credits;
  const coreLivesRef = useRef(coreLives);
  coreLivesRef.current = coreLives;
  const coreRepairsCountRef = useRef(coreRepairsCount);
  coreRepairsCountRef.current = coreRepairsCount;
  const coreTurretLevelRef = useRef(coreTurretLevel);
  coreTurretLevelRef.current = coreTurretLevel;
  const coreTurretCooldownRef = useRef(0);
  const energyRef = useRef(energy);
  energyRef.current = energy;
  const scoreRef = useRef(gameState.score);
  scoreRef.current = gameState.score;
  const waveRef = useRef(gameState.level);
  waveRef.current = gameState.level;
  const isWaveActiveRef = useRef(isWaveActive);
  isWaveActiveRef.current = isWaveActive;
  const isPrepPhaseRef = useRef(isPrepPhase);
  isPrepPhaseRef.current = isPrepPhase;
  const prepTimerRef = useRef(prepTimer);
  prepTimerRef.current = prepTimer;

  const selectedHardpointIdRef = useRef(selectedHardpointId);
  selectedHardpointIdRef.current = selectedHardpointId;
  const selectedTowerIdRef = useRef(selectedTowerId);
  selectedTowerIdRef.current = selectedTowerId;
  const isCoreSelectedRef = useRef(isCoreSelected);
  isCoreSelectedRef.current = isCoreSelected;
  const selectedGateIndexRef = useRef(selectedGateIndex);
  selectedGateIndexRef.current = selectedGateIndex;

  // Wave spawn queue
  const waveSpawnQueueRef = useRef<{type: EnemyType; delay: number; riftId: number}[]>([]);
  const waveSpawnTimerRef = useRef(0);

  // Abilities refs
  const empCdRef = useRef(0);
  const ocCdRef = useRef(0);
  const ocActiveTimeRef = useRef(0);
  const isEmpTargetingRef = useRef(false);
  isEmpTargetingRef.current = isEmpTargeting;

  // Camera & Viewport with Smooth Framing
  const cameraRef = useRef<{
    x: number;
    y: number;
    zoom: number;
    isDragging: boolean;
    dragStartX: number;
    dragStartY: number;
    startCamX: number;
    startCamY: number;
    hasDragged: boolean;
    hasManuallyAdjusted: boolean;
  }>({
    x: 0,
    y: 0,
    zoom: 1,
    isDragging: false,
    dragStartX: 0,
    dragStartY: 0,
    startCamX: 0,
    startCamY: 0,
    hasDragged: false,
    hasManuallyAdjusted: false,
  });

  const cameraTargetRef = useRef<{
    x: number;
    y: number;
    zoom: number;
    active: boolean;
  }>({
    x: 0,
    y: 0,
    zoom: 1,
    active: false,
  });

  const [cameraZoomDisplay, setCameraZoomDisplay] = useState<number>(1);

  const gameStateRef = useRef(gameState);
  gameStateRef.current = gameState;
  const isGameMenuOpenRef = useRef(isGameMenuOpen);
  isGameMenuOpenRef.current = isGameMenuOpen;

  useEffect(() => {
    (window as any).canHandleBackKey =
      gameState.status !== 'START' || isGameMenuOpen;
  }, [gameState.status, isGameMenuOpen]);

  useInput(canvasRef, true);

  // --- HARDPOINTS INITIALIZATION ---
  // Exactly 6 Core Hardpoints in Zone 0 alternating with 6 Core Gates
  // Plus 24 Generously Spaced Micro Hardpoints (8 Inner, 8 Mid, 8 Outer)
  const initHardpoints = useCallback(() => {
    const list: Hardpoint[] = [];
    let id = 1;
    const usedCells = new Set<string>();

    // Reserve Nexus Core cells: gridX: -1..+1, gridY: -1..+1 (9 cells total)
    for (let gx = -1; gx <= 1; gx++) {
      for (let gy = -1; gy <= 1; gy++) {
        usedCells.add(`${gx},${gy}`);
      }
    }
    // Reserve 6 Core Gate cells
    CORE_DOORS.forEach((d) => usedCells.add(`${d.gridX},${d.gridY}`));

    // 6 Core Hardpoints in Zone 0 (radius ~4 cells = 128px) interleaved cleanly with the 6 Gates:
    // Core HP North: (0, -4)
    // Core HP Top-Right: (+3, -2)
    // Core HP Bottom-Right: (+3, +2)
    // Core HP South: (0, +4)
    // Core HP Bottom-Left: (-3, +2)
    // Core HP Top-Left: (-3, -2)
    const coreHpGridCoords = [
      {gridX: 0, gridY: -4},
      {gridX: 3, gridY: -2},
      {gridX: 3, gridY: 2},
      {gridX: 0, gridY: 4},
      {gridX: -3, gridY: 2},
      {gridX: -3, gridY: -2},
    ];

    coreHpGridCoords.forEach((coord) => {
      usedCells.add(`${coord.gridX},${coord.gridY}`);
      const center = gridToCenter(coord.gridX, coord.gridY);
      list.push({
        id: id++,
        gridX: coord.gridX,
        gridY: coord.gridY,
        x: center.x,
        y: center.y,
        ring: 0,
        isCoreHardpoint: true,
        tower: null,
      });
    });

    // 24 Outer Micro Hardpoints with generous spacing across concentric rings:
    // Inner Micro Ring (8 hardpoints): Radius ~6 to 7 cells, positioned at cardinal and 45-degree points:
    //   (+6, 0), (-6, 0), (0, +6), (0, -6), (+5, +5), (-5, +5), (+5, -5), (-5, -5). (Min spacing ~5.1 cells)
    // Mid Micro Ring (8 hardpoints): Radius ~9 cells:
    //   (+9, +3), (+9, -3), (-9, +3), (-9, -3), (+3, +9), (-3, +9), (+3, -9), (-3, -9).
    // Outer Micro Ring (8 hardpoints): Radius ~12 cells:
    //   (+12, 0), (-12, 0), (0, +12), (0, -12), (+9, +9), (-9, +9), (+9, -9), (-9, -9).
    const symmetricZones = [
      {
        ring: 1,
        coords: [
          {gridX: 6, gridY: 0}, {gridX: -6, gridY: 0},
          {gridX: 0, gridY: 6}, {gridX: 0, gridY: -6},
          {gridX: 5, gridY: 5}, {gridX: -5, gridY: 5},
          {gridX: 5, gridY: -5}, {gridX: -5, gridY: -5},
        ],
      },
      {
        ring: 2,
        coords: [
          {gridX: 9, gridY: 3}, {gridX: 9, gridY: -3},
          {gridX: -9, gridY: 3}, {gridX: -9, gridY: -3},
          {gridX: 3, gridY: 9}, {gridX: -3, gridY: 9},
          {gridX: 3, gridY: -9}, {gridX: -3, gridY: -9},
        ],
      },
      {
        ring: 3,
        coords: [
          {gridX: 12, gridY: 0}, {gridX: -12, gridY: 0},
          {gridX: 0, gridY: 12}, {gridX: 0, gridY: -12},
          {gridX: 9, gridY: 9}, {gridX: -9, gridY: 9},
          {gridX: 9, gridY: -9}, {gridX: -9, gridY: -9},
        ],
      },
      {
        ring: 4,
        coords: [
          {gridX: 15, gridY: 4}, {gridX: 15, gridY: -4},
          {gridX: -15, gridY: 4}, {gridX: -15, gridY: -4},
          {gridX: 4, gridY: 15}, {gridX: -4, gridY: 15},
          {gridX: 4, gridY: -15}, {gridX: -4, gridY: -15},
        ],
      },
    ];

    symmetricZones.forEach((spec) => {
      spec.coords.forEach((coord) => {
        usedCells.add(`${coord.gridX},${coord.gridY}`);
        const center = gridToCenter(coord.gridX, coord.gridY);
        list.push({
          id: id++,
          gridX: coord.gridX,
          gridY: coord.gridY,
          x: center.x,
          y: center.y,
          ring: spec.ring,
          isCoreHardpoint: false,
          tower: null,
        });
      });
    });

    hardpointsRef.current = list;
    freeTowersRef.current = [];
  }, []);

  // --- CHECK AND REFUND TOWERS CUT BY A NEW PATH ---
  const checkDisplacedTowers = (newPath: {x: number; y: number}[]) => {
    const freeTowers = freeTowersRef.current;
    for (let i = freeTowers.length - 1; i >= 0; i--) {
      const t = freeTowers[i];
      let hits = false;

      // Check grid corridor intersection
      for (let s = 0; s < newPath.length - 1; s++) {
        const p1 = newPath[s];
        const p2 = newPath[s + 1];
        const g1 = worldToGrid(p1.x, p1.y);
        const g2 = worldToGrid(p2.x, p2.y);

        if (g1.gridX === g2.gridX && t.gridX === g1.gridX) {
          const minY = Math.min(g1.gridY, g2.gridY);
          const maxY = Math.max(g1.gridY, g2.gridY);
          if (t.gridY >= minY && t.gridY <= maxY) {
            hits = true;
            break;
          }
        } else if (g1.gridY === g2.gridY && t.gridY === g1.gridY) {
          const minX = Math.min(g1.gridX, g2.gridX);
          const maxX = Math.max(g1.gridX, g2.gridX);
          if (t.gridX >= minX && t.gridX <= maxX) {
            hits = true;
            break;
          }
        } else {
          // Diagonal segment
          const minX = Math.min(g1.gridX, g2.gridX);
          const maxX = Math.max(g1.gridX, g2.gridX);
          const minY = Math.min(g1.gridY, g2.gridY);
          const maxY = Math.max(g1.gridY, g2.gridY);
          if (t.gridX >= minX && t.gridX <= maxX && t.gridY >= minY && t.gridY <= maxY) {
            const center = gridToCenter(t.gridX, t.gridY);
            const dx = p2.x - p1.x;
            const dy = p2.y - p1.y;
            const lenSq = dx * dx + dy * dy;
            if (lenSq > 0) {
              const projT = Math.max(0, Math.min(1, ((center.x - p1.x) * dx + (center.y - p1.y) * dy) / lenSq));
              const projX = p1.x + projT * dx;
              const projY = p1.y + projT * dy;
              if (Math.hypot(center.x - projX, center.y - projY) < CELL_SIZE * 0.7) {
                hits = true;
                break;
              }
            }
          }
        }
      }

      if (hits) {
        const refund = Math.floor(t.totalInvested * 0.7);
        setCredits((prev) => prev + refund);
        popupsRef.current.push({
          x: t.x,
          y: t.y - 20,
          text: `[PATH DISPLACEMENT] +$${refund} (70% REFUND)`,
          color: '#f97316',
          life: 3.0,
        });
        freeTowers.splice(i, 1);
        gameAudio.playCoinPickup();
      }
    }
  };

  // --- CREATE OR ADD A RIFT WITH CONCENTRIC ZONE TOPOLOGY ---
  // Truly endless: inner zones fill up according to capacity (Zone N has N + 1 slots),
  // dynamically expanding to Zone 5, Zone 6, Zone 7... with zero upper limit!
  const addRiftWithTreeTopology = useCallback(
    (customX?: number, customY?: number, isWave1 = false): RiftPortal | null => {
      const currentPortals = portalsRef.current;

      let targetZone = 1;
      if (customX !== undefined && customY !== undefined) {
        const d = Math.hypot(customX, customY);
        targetZone = Math.max(1, Math.round((d - 160) / 96) + 1);
      } else if (isWave1) {
        targetZone = 1;
      } else {
        // Endless filling order: find first orbital shell that has open capacity!
        let z = 1;
        while (true) {
          const spec = getZoneSpec(z);
          const countInZ = currentPortals.filter((p) => p.zone === z).length;
          if (countInZ < spec.capacity) {
            targetZone = z;
            break;
          }
          z++;
        }
      }

      const zoneSpec = getZoneSpec(targetZone);
      const targetRadius = zoneSpec.radius;

      let chosenX: number;
      let chosenY: number;

      if (customX !== undefined && customY !== undefined) {
        const g = snapToGrid(customX, customY);
        chosenX = g.x;
        chosenY = g.y;
      } else {
        // Stratified 8-sector 360-degree radial distribution across all 4 quadrants (N, S, E, W, NE, NW, SE, SW)
        const SECTOR_COUNT = 8;
        const sectorCounts = new Array(SECTOR_COUNT).fill(0);

        currentPortals.forEach((p) => {
          let ang = Math.atan2(p.y, p.x);
          if (ang < 0) ang += Math.PI * 2;
          const s = Math.floor(((ang + Math.PI / SECTOR_COUNT) % (Math.PI * 2)) / ((Math.PI * 2) / SECTOR_COUNT));
          sectorCounts[s]++;
        });

        // Determine least populated sectors to guarantee proportional omnidirectional distribution
        const minCount = Math.min(...sectorCounts);
        const leastPopulatedSectors: number[] = [];
        for (let s = 0; s < SECTOR_COUNT; s++) {
          if (sectorCounts[s] === minCount) {
            leastPopulatedSectors.push(s);
          }
        }

        // Shuffle least populated sectors for entropy
        for (let i = leastPopulatedSectors.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [leastPopulatedSectors[i], leastPopulatedSectors[j]] = [leastPopulatedSectors[j], leastPopulatedSectors[i]];
        }

        let bestCandidate: {x: number; y: number} | null = null;
        // Rifts must spawn at least 380px to 550px away from the center (runway buffer)
        const zoneRadiusMin = Math.max(380, targetRadius - 24);
        const zoneRadiusMax = Math.max(zoneRadiusMin + 40, targetRadius + 24);

        if (currentPortals.length === 0) {
          // Wave 1 / Initial rift: Completely random 360-degree angle with >= 380px distance
          const initialAngle = Math.random() * Math.PI * 2;
          const initialRadius = zoneRadiusMin + Math.random() * (zoneRadiusMax - zoneRadiusMin);
          const cand = snapToGrid(
            Math.cos(initialAngle) * initialRadius,
            Math.sin(initialAngle) * initialRadius,
          );
          bestCandidate = {x: cand.x, y: cand.y};
        } else {
          // Multi-rift: Try candidate positions in the least-populated sectors
          for (const targetSector of leastPopulatedSectors) {
            const sectorBaseAngle = targetSector * ((Math.PI * 2) / SECTOR_COUNT);

            for (let attempt = 0; attempt < 24; attempt++) {
              // Stratified angular jitter within sector (±0.32 rad)
              const angleJitter = (Math.random() - 0.5) * ((Math.PI * 2) / SECTOR_COUNT * 0.75);
              const ang = sectorBaseAngle + angleJitter;
              // Randomized radial distance within zone ring (>= 380px)
              const radius = zoneRadiusMin + Math.random() * (zoneRadiusMax - zoneRadiusMin);

              const rawX = Math.cos(ang) * radius;
              const rawY = Math.sin(ang) * radius;
              const cand = snapToGrid(rawX, rawY);

              // Minimum distance check between rifts >= 4 cells (128px)
              let tooClose = false;
              for (const p of currentPortals) {
                if (Math.hypot(p.x - cand.x, p.y - cand.y) < 4 * CELL_SIZE) {
                  tooClose = true;
                  break;
                }
              }
              if (tooClose) continue;

              // Proximity check: strictly enforce >= 380px away from the Core center
              if (Math.hypot(cand.x, cand.y) < 380) continue;

              // Ensure it does not collide with doors or hardpoints
              const onDoor = CORE_DOORS.some((d) => d.gridX === cand.gridX && d.gridY === cand.gridY);
              if (onDoor) continue;
              const onHp = hardpointsRef.current.some((h) => h.gridX === cand.gridX && h.gridY === cand.gridY);
              if (onHp) continue;

              bestCandidate = {x: cand.x, y: cand.y};
              break;
            }

            if (bestCandidate) break;
          }
        }

        // Fallback: If constrained, generate random 360-degree position with >= 380px spacing
        if (!bestCandidate) {
          const randAngle = Math.random() * Math.PI * 2;
          const randRad = zoneRadiusMin + Math.random() * (zoneRadiusMax - zoneRadiusMin);
          const cand = snapToGrid(Math.cos(randAngle) * randRad, Math.sin(randAngle) * randRad);
          bestCandidate = {x: cand.x, y: cand.y};
        }

        // Final guard: strictly ensure minimum 380px runway distance from Core
        if (Math.hypot(bestCandidate.x, bestCandidate.y) < 380) {
          const ang = Math.atan2(bestCandidate.y, bestCandidate.x);
          const cand = snapToGrid(Math.cos(ang) * 384, Math.sin(ang) * 384);
          bestCandidate = {x: cand.x, y: cand.y};
        }

        chosenX = bestCandidate.x;
        chosenY = bestCandidate.y;
      }

      // Determine single target Gate: select gate closest in angle/quadrant to rift
      const riftAngle = Math.atan2(chosenY, chosenX);
      let targetDoorIdx = 0;
      let minAngleScore = Infinity;
      CORE_DOORS.forEach((door, idx) => {
        const doorAngle = Math.atan2(door.y, door.x);
        let diff = Math.abs(riftAngle - doorAngle);
        if (diff > Math.PI) diff = 2 * Math.PI - diff;
        const dist = Math.hypot(chosenX - door.x, chosenY - door.y);
        const score = diff * 1000 + dist * 0.1;
        if (score < minAngleScore) {
          minAngleScore = score;
          targetDoorIdx = idx;
        }
      });
      const targetDoor = CORE_DOORS[targetDoorIdx];

      // Build impassable obstacle set (ALL Hardpoints + Nexus Core cells + ALL OTHER 5 GATES + ALL EXISTING RIFTS)
      const obstacleSet = new Set<string>();
      hardpointsRef.current.forEach((hp) => {
        obstacleSet.add(`${hp.gridX},${hp.gridY}`);
      });
      // Nexus Core cells: -1..+1, -1..+1
      for (let gx = -1; gx <= 1; gx++) {
        for (let gy = -1; gy <= 1; gy++) {
          obstacleSet.add(`${gx},${gy}`);
        }
      }
      // CRITICAL: Strictly mark all OTHER gates as impassable obstacles so paths never route through them!
      CORE_DOORS.forEach((door, idx) => {
        if (idx !== targetDoorIdx) {
          obstacleSet.add(`${door.gridX},${door.gridY}`);
        }
      });
      // CRITICAL: Mark all existing rift portals (and 1-tile buffer) as impassable obstacles so paths NEVER route to/through them!
      currentPortals.forEach((p) => {
        const pg = worldToGrid(p.x, p.y);
        for (let dx = -1; dx <= 1; dx++) {
          for (let dy = -1; dy <= 1; dy++) {
            obstacleSet.add(`${pg.gridX + dx},${pg.gridY + dy}`);
          }
        }
      });

      const startGrid = worldToGrid(chosenX, chosenY);
      obstacleSet.delete(`${startGrid.gridX},${startGrid.gridY}`);

      let fullPath: {x: number; y: number}[];

      // Tree Merging: only merge with existing paths targeting the EXACT SAME Gate!
      // Must merge before or at that gate so all paths entering a gate go strictly [Gate -> Core].
      const chosenDist = Math.hypot(chosenX, chosenY);
      const gateDistFromCore = Math.hypot(targetDoor.x, targetDoor.y);
      let bestMergePoint: {x: number; y: number} | null = null;
      let bestExistingPath: {x: number; y: number}[] | null = null;
      let bestWaypointIdx = -1;
      let minMergeDist = Infinity;

      if (!isWave1 && currentPortals.length > 0) {
        // Strictly filter to portals sharing the same targetDoorIdx
        const matchingPortals = currentPortals.filter(
          (p) => p.doorIndex === targetDoorIdx,
        );

        for (const p of matchingPortals) {
          // Check waypoints before the Core:
          // CRITICAL: idx MUST start at 1 (NEVER idx 0, which is the spawning portal itself!)
          // And idx must be strictly before Core (length - 1 is Core (0,0))
          for (let idx = 1; idx < p.path.length - 1; idx++) {
            const wp = p.path[idx];
            const distFromCore = Math.hypot(wp.x, wp.y);

            // Never merge at or near any rift portal
            let nearAnyRift = false;
            for (const otherP of currentPortals) {
              if (Math.hypot(wp.x - otherP.x, wp.y - otherP.y) < 48) {
                nearAnyRift = true;
                break;
              }
            }
            if (nearAnyRift) continue;

            // Must be strictly closer to Core than the new rift, but outside or at the gate
            if (distFromCore < chosenDist - 28 && distFromCore >= gateDistFromCore - 4) {
              const d = Math.hypot(chosenX - wp.x, chosenY - wp.y);
              if (d < minMergeDist) {
                minMergeDist = d;
                bestMergePoint = wp;
                bestExistingPath = p.path;
                bestWaypointIdx = idx;
              }
            }
          }
        }
      }

      if (bestMergePoint && bestExistingPath && bestWaypointIdx >= 1) {
        const mergeGrid = worldToGrid(bestMergePoint.x, bestMergePoint.y);
        obstacleSet.delete(`${mergeGrid.gridX},${mergeGrid.gridY}`);

        const branch = findOrthogonalGridPath(
          startGrid.gridX,
          startGrid.gridY,
          mergeGrid.gridX,
          mergeGrid.gridY,
          obstacleSet,
        );
        const lastBranchPt = branch[branch.length - 1];

        if (
          Math.hypot(lastBranchPt.x - bestMergePoint.x, lastBranchPt.y - bestMergePoint.y) < 6
        ) {
          // Downstream slice strictly towards Gate and Core!
          // bestExistingPath is ordered [Rift (0), ..., Junction (bestWaypointIdx), ..., Gate, Core]
          const remainingTrunk = bestExistingPath.slice(bestWaypointIdx + 1);
          fullPath = [...branch, ...remainingTrunk];
        } else {
          // Fallback to direct door path if branch pathfinding could not connect cleanly
          const trunk = findOrthogonalGridPath(
            startGrid.gridX,
            startGrid.gridY,
            targetDoor.gridX,
            targetDoor.gridY,
            obstacleSet,
          );
          fullPath = [...trunk, {x: 0, y: 0}];
        }
      } else {
        const trunk = findOrthogonalGridPath(
          startGrid.gridX,
          startGrid.gridY,
          targetDoor.gridX,
          targetDoor.gridY,
          obstacleSet,
        );
        // Direct approach from Gate to Core crystal center (0, 0)
        fullPath = [...trunk, {x: 0, y: 0}];
      }

      // Strictly validate and sanitize monotonic distance down to Gate and Core
      fullPath = sanitizeAndValidateMonotonicPath(
        fullPath,
        chosenX,
        chosenY,
        targetDoor,
        obstacleSet,
      );

      // Check and refund any open-grid player towers cut by the new path
      checkDisplacedTowers(fullPath);

      // New portal defaults to tier 1 with no mutation
      const newPortal: RiftPortal = {
        id: nextEntityIdRef.current++,
        x: chosenX,
        y: chosenY,
        angle: Math.atan2(-chosenY, -chosenX),
        active: true,
        pulseTimer: 0,
        path: fullPath,
        doorIndex: targetDoorIdx,
        mutation: null,
        tier: 1,
        zone: targetZone,
      };

      portalsRef.current.push(newPortal);

      shockwavesRef.current.push({
        x: chosenX,
        y: chosenY,
        radius: 12,
        maxRadius: 90,
        color: '#ef4444',
        alpha: 1,
      });

      return newPortal;
    },
    [],
  );

  // Dynamic Map bounding box for camera framing including Core and all active rifts
  const getMapBoundingBox = useCallback(() => {
    // Start with Core bounds (-64 to +64) and Gate Ring (radius 136px)
    let minX = -136;
    let maxX = 136;
    let minY = -136;
    let maxY = 136;

    // Include all active rifts (or all rifts if none explicitly marked active) with generous margin
    const activePortals = portalsRef.current.filter((p) => p.active);
    const portalPool = activePortals.length > 0 ? activePortals : portalsRef.current;

    portalPool.forEach((p) => {
      minX = Math.min(minX, p.x - 48);
      maxX = Math.max(maxX, p.x + 48);
      minY = Math.min(minY, p.y - 48);
      maxY = Math.max(maxY, p.y + 48);
    });

    // Also include any outer hardpoints with built towers
    hardpointsRef.current.forEach((h) => {
      if (h.tower) {
        minX = Math.min(minX, h.x - 32);
        maxX = Math.max(maxX, h.x + 32);
        minY = Math.min(minY, h.y - 32);
        maxY = Math.max(maxY, h.y + 32);
      }
    });

    freeTowersRef.current.forEach((t) => {
      minX = Math.min(minX, t.x - 32);
      maxX = Math.max(maxX, t.x + 32);
      minY = Math.min(minY, t.y - 32);
      maxY = Math.max(maxY, t.y + 32);
    });

    const spanW = maxX - minX;
    const spanH = maxY - minY;

    return {
      minX,
      maxX,
      minY,
      maxY,
      spanW,
      spanH,
      centerX: (minX + maxX) / 2,
      centerY: (minY + maxY) / 2,
    };
  }, []);

  const fitCameraToScreen = useCallback((smooth = true) => {
    const bounds = getMapBoundingBox();
    const cw = canvasSizeRef.current.width;
    const ch = canvasSizeRef.current.height;

    // Viewport sizing respecting top bar (50px) and bottom trays (80px)
    const availW = cw * 0.88;
    const availH = Math.max(120, (ch - 130) * 0.90);

    const zoomX = availW / Math.max(180, bounds.spanW);
    const zoomY = availH / Math.max(180, bounds.spanH);

    // Expand minimum zoom from 0.45x down to 0.15x, allowing even Zone 10-12+ outer shells to be framed
    const optimalZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, Math.min(zoomX, zoomY)));

    // Camera offset to center on bounding box center, with slight vertical offset for HUD clearance
    const targetCamX = -bounds.centerX * optimalZoom;
    const targetCamY = -bounds.centerY * optimalZoom - 6;

    if (smooth) {
      cameraTargetRef.current = {
        x: targetCamX,
        y: targetCamY,
        zoom: optimalZoom,
        active: true,
      };
    } else {
      cameraRef.current.zoom = optimalZoom;
      cameraRef.current.x = targetCamX;
      cameraRef.current.y = targetCamY;
      cameraTargetRef.current.active = false;
    }

    cameraRef.current.hasManuallyAdjusted = false;
    setCameraZoomDisplay(optimalZoom);
  }, [getMapBoundingBox]);

  // Initialize rifts matching target wave schedule
  const initPortals = useCallback((targetWave: number = 1) => {
    portalsRef.current = [];
    const targetCount = getTargetRiftCountForWave(targetWave);
    for (let i = 0; i < targetCount; i++) {
      addRiftWithTreeTopology(undefined, undefined, i === 0);
    }
  }, [addRiftWithTreeTopology]);

  // Check if wave schedule triggers a new rift arrival
  const checkRiftArrivalSchedule = useCallback((targetWave: number) => {
    const targetCount = getTargetRiftCountForWave(targetWave);
    let anyAdded = false;
    while (portalsRef.current.length < targetCount) {
      const added = addRiftWithTreeTopology();
      if (added) {
        anyAdded = true;
        popupsRef.current.push({
          x: added.x,
          y: added.y - 30,
          text: `NEW RIFT OPENED (ZONE ${added.zone} · GATE G${added.doorIndex + 1})`,
          color: '#ef4444',
          life: 3.0,
        });
        gameAudio.playArcadeLaser();
      } else {
        break;
      }
    }

    if (anyAdded && !cameraRef.current.hasManuallyAdjusted) {
      fitCameraToScreen(true);
    }
  }, [addRiftWithTreeTopology, fitCameraToScreen]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const handleResize = () => {
      const rect = container.getBoundingClientRect();
      const w = Math.max(320, Math.floor(rect.width));
      const h = Math.max(240, Math.floor(rect.height));

      if (
        w !== canvasSizeRef.current.width ||
        h !== canvasSizeRef.current.height
      ) {
        canvasSizeRef.current = {width: w, height: h};
        setCanvasSize({width: w, height: h});

        if (!cameraRef.current.hasManuallyAdjusted) {
          fitCameraToScreen();
        }
      }
    };

    handleResize();
    const observer = new ResizeObserver(() => handleResize());
    observer.observe(container);
    window.addEventListener('resize', handleResize);

    return () => {
      observer.disconnect();
      window.removeEventListener('resize', handleResize);
    };
  }, [fitCameraToScreen]);

  // Rebuild entire rift topology respecting radial zones
  const rebuildRiftTopology = useCallback(() => {
    const count = Math.max(1, portalsRef.current.length);
    portalsRef.current = [];
    for (let i = 0; i < count; i++) {
      addRiftWithTreeTopology(undefined, undefined, i === 0);
    }
    popupsRef.current.push({
      x: 0,
      y: -90,
      text: `TOPOLOGY REBUILT (${portalsRef.current.length} RIFTS ACROSS 360°)`,
      color: '#00f0ff',
      life: 2.0,
    });
    gameAudio.playPowerupChime();
  }, [addRiftWithTreeTopology]);

  // --- INITIALIZE GAME RUN ---
  const initGame = useCallback(() => {
    initHardpoints();
    initPortals(1);
    enemiesRef.current = [];
    projectilesRef.current = [];
    lasersRef.current = [];
    arcsRef.current = [];
    particlesRef.current = [];
    popupsRef.current = [];
    shockwavesRef.current = [];
    waveSpawnQueueRef.current = [];

    const startingCreds = getConfig('startingCredits') || 200;
    const maxLives = 20;

    totalKillsRef.current = 0;
    totalCreditsEarnedRef.current = startingCreds;
    wavesSurvivedRef.current = 0;

    setCredits(startingCreds);
    setCoreLives(maxLives);
    setCoreRepairsCount(0);
    setCoreTurretLevel(1);
    setEnergy(50);
    energyRegenAccRef.current = 0;
    setIsPrepPhase(true);
    setPrepTimer(30);
    setIsWaveActive(false);
    setActiveMutation(null);
    setSelectedBuildType(null);
    const initialNextMut = scheduleNextMutationWave(1);
    nextMutationWaveRef.current = initialNextMut;
    setNextMutationWave(initialNextMut);
    setAnomalyWarningText(null);
    setSelectedHardpointId(null);
    setSelectedTowerId(null);
    setHoveredHardpointId(null);
    setIsCoreSelected(false);
    setSelectedGateIndex(null);
    setHoveredGateIndex(null);
    empCdRef.current = 0;
    ocCdRef.current = 0;
    ocActiveTimeRef.current = 0;
    setEmpCooldownLeft(0);
    setOverclockCooldownLeft(0);
    setIsOverclockActive(false);
    setIsEmpTargeting(false);
    setActiveMusicTrack('tactical');
    activeMusicTrackRef.current = 'tactical';
    setTacticalBanner(null);
    setIsGameMenuOpen(false);
    setIsDevDrawerOpen(false);

    fitCameraToScreen();

    setGameState({
      status: 'PLAYING',
      score: 0,
      level: 1,
    });

    if (sdk) {
      sdk.startGame();
    }
  }, [initHardpoints, initPortals, fitCameraToScreen, sdk]);

  usePlaygroundGameLifecycle(gameState, sdk);

  // Autoplay query param check
  const hasAutoplayed = useRef(false);
  useEffect(() => {
    if (
      !hasAutoplayed.current &&
      new URLSearchParams(window.location.search).has('autoplay')
    ) {
      hasAutoplayed.current = true;
      initGame();
    }
  }, [initGame]);

  // Canonical Wave Generation & Scaled Difficulty
  const buildWaveDef = (wave: number) => {
    const queue: EnemyType[] = [];
    const portals = portalsRef.current;
    const getRandomRiftId = () =>
      portals.length > 0
        ? portals[Math.floor(Math.random() * portals.length)].id
        : 1;

    // Increased enemy density per wave: 6 + Math.floor(wave * 2.5)
    const waveSize = 6 + Math.floor(wave * 2.5);

    // Helper for wave 10+ slot roll with tactical variety
    const rollWave10PlusSlot = (): EnemyType => {
      const r = Math.random();
      // Shifter (from wave 16)
      if (r < 0.10) {
        if (wave >= 16) return 'shifter';
        return 'bulwark';
      }
      // Bulwark
      if (r < 0.25) {
        return 'bulwark';
      }
      // Splitter (from wave 12)
      if (r < 0.40) {
        if (wave >= 12) return 'splitter';
        return 'fast';
      }
      // Fast runner
      if (r < 0.60) {
        return 'fast';
      }
      // Armored Tank
      if (r < 0.80) {
        return 'tank';
      }
      // Basic creep
      return 'basic';
    };

    if (wave <= 2) {
      // Waves 1-2: 100% Basic
      for (let i = 0; i < waveSize; i++) {
        queue.push('basic');
      }
    } else if (wave <= 4) {
      // Waves 3-4: 35% Fast runner mix, 65% Basic
      for (let i = 0; i < waveSize; i++) {
        queue.push(Math.random() < 0.35 ? 'fast' : 'basic');
      }
    } else if (wave === 5) {
      // Wave 5: 3rd Rift awakened + guaranteed Mini-Boss / Tank & Bulwark wave!
      queue.push('tank', 'tank', 'bulwark');
      const rem = Math.max(0, waveSize - 3);
      for (let i = 0; i < rem; i++) {
        const r = Math.random();
        if (r < 0.35) queue.push('fast');
        else if (r < 0.60) queue.push('tank');
        else queue.push('basic');
      }
    } else if (wave <= 9) {
      // Waves 6-9: Fast runners, heavy Tanks, Bulwarks with armored plating
      for (let i = 0; i < waveSize; i++) {
        const r = Math.random();
        if (r < 0.25) queue.push('fast');
        else if (r < 0.45) queue.push('tank');
        else if (r < 0.60) queue.push('bulwark');
        else queue.push('basic');
      }
    } else {
      // Waves 10+: Full roster with guaranteed armor on multiples of 5
      let slots = waveSize;
      if (wave % 5 === 0) {
        queue.push('tank', 'bulwark');
        slots = Math.max(0, waveSize - 2);
      }
      for (let i = 0; i < slots; i++) {
        queue.push(rollWave10PlusSlot());
      }
    }

    // Titan Prime Boss insertion: Guaranteed every 10th wave (Wave 10, 20, 30...)
    const isEvery10th = wave % 10 === 0;
    const isSurpriseBoss =
      wave > 25 && wave % 5 === 0 && wave % 10 !== 0 && Math.random() < 0.25;

    if (isEvery10th || isSurpriseBoss) {
      const insertIdx = Math.floor(queue.length / 2);
      queue.splice(insertIdx, 0, 'boss');
    }

    // Spawn interval: 1 enemy every 50 frames (0.83s at 60fps), distributed across all active rifts
    const spawnDelay = Math.max(0.65, 1.0 - Math.min(0.35, wave * 0.025));
    return queue.map((type) => ({
      type,
      delay: spawnDelay,
      riftId: getRandomRiftId(),
    }));
  };

  // Start Next Wave with decoupled mutations & veteran rift tier progression
  const startNextWave = useCallback(() => {
    if (isWaveActiveRef.current) return;
    const currentWave = waveRef.current;

    // Reset mutations on all rifts first
    portalsRef.current.forEach((p) => {
      p.mutation = null;
    });

  // Decoupled Cosmic Anomaly: only triggers on scheduled mutation wave (never on or adjacent to rift wave)
    const isMutationWave =
      currentWave === nextMutationWaveRef.current && !isRiftProximityWave(currentWave);

    if (isMutationWave && portalsRef.current.length > 0) {
      const mutList: (keyof typeof MUTATION_PROFILES)[] = [
        'CRIMSON',
        'VOID',
        'TITAN',
        'PHASE',
        'NEON',
      ];
      const chosenMut = mutList[Math.floor(Math.random() * mutList.length)];
      const targetRift =
        portalsRef.current[Math.floor(Math.random() * portalsRef.current.length)];
      targetRift.mutation = chosenMut;
      setActiveMutation(chosenMut);
      setTacticalBanner({
        type: 'mutation',
        text: `[⚡ ANOMALY DETECTED: ${chosenMut} MUTATION]`,
        trackName: 'Mutation Surge',
      });
      popupsRef.current.push({
        x: targetRift.x,
        y: targetRift.y - 45,
        text: `MUTATION ACTIVE: ${chosenMut}!`,
        color: MUTATION_PROFILES[chosenMut].color,
        life: 4.0,
      });

      // Schedule next mutation 6-9 waves ahead (spaced by at least 4 calm waves, never near rifts)
      const nextMut = scheduleNextMutationWave(currentWave);
      nextMutationWaveRef.current = nextMut;
      setNextMutationWave(nextMut);
      setAnomalyWarningText(null);

      // Clear mutation banner after 5.5s so it's a brief tactical cue
      setTimeout(() => {
        setTacticalBanner((prev) => (prev?.type === 'mutation' ? null : prev));
      }, 5500);
    } else {
      setActiveMutation(null);
      setTacticalBanner((prev) => (prev?.type === 'mutation' ? null : prev));
      // If wave advanced past nextMutationWave without triggering, resync schedule
      if (currentWave >= nextMutationWaveRef.current) {
        const nextMut = scheduleNextMutationWave(currentWave);
        nextMutationWaveRef.current = nextMut;
        setNextMutationWave(nextMut);
      }
    }

    // Veteran Rift Tiers (from wave 51):
    // Each wave >= 51: each rift has a 10% chance to gain +1 tier.
    if (currentWave >= 51) {
      portalsRef.current.forEach((portal) => {
        if (Math.random() < 0.1) {
          portal.tier = (portal.tier || 1) + 1;
          popupsRef.current.push({
            x: portal.x,
            y: portal.y - 35,
            text: `RIFT UPGRADE: TIER ${portal.tier}!`,
            color: '#f59e0b',
            life: 2.5,
          });
        }
      });
    }

    const queue = buildWaveDef(currentWave);
    waveSpawnQueueRef.current = queue;
    waveSpawnTimerRef.current = 0;
    setIsWaveActive(true);
    isWaveActiveRef.current = true;
    setIsPrepPhase(false);
    isPrepPhaseRef.current = false;
    gameAudio.playArcadeLaser();
  }, []);

  // Skip Prep Phase early
  const skipPrepPhase = useCallback(() => {
    if (!isPrepPhaseRef.current) return;
    setCredits((prev) => prev + 20);
    popupsRef.current.push({
      x: 0,
      y: -60,
      text: 'EARLY WAVE CALL (+ $20)',
      color: '#eab308',
      life: 1.5,
    });
    startNextWave();
  }, [startNextWave]);

  // Spawn an Enemy using the canonical 3-step Stacking Order:
  // 1. Wave HP scaling: hp = Math.round(baseHp * (1 + wave * 0.4))
  // 2. Rift tier: hp * tierHpMul, speed * tierSpeedMul, reward * tierRewardMul
  // 3. Mutation: hp * mutHpMul, speed * mutSpeedMul, reward * mutRewardMul
  const spawnEnemy = (
    type: EnemyType,
    designatedRiftId?: number,
  ) => {
    const spec = ENEMY_SPECS[type];
    const portals = portalsRef.current;
    let portal = portals.find((p) => p.id === designatedRiftId);
    if (!portal && portals.length > 0) {
      portal = portals[Math.floor(Math.random() * portals.length)];
    }

    const path = portal ? portal.path : [{x: 300, y: 0}, {x: 0, y: 0}];
    const startX = portal ? portal.x : 300;
    const startY = portal ? portal.y : 0;
    const waypointIndex = 1;

    const initialAngle =
      path[waypointIndex] != null
        ? Math.atan2(
            path[waypointIndex].y - startY,
            path[waypointIndex].x - startX,
          )
        : 0;

    const currentWave = waveRef.current;
    const riftTier = portal?.tier || 1;
    const mutation = portal?.mutation || null;

    // Step 1: Wave HP scaling: gentle progression hp = baseHp * (1 + (wave - 1) * 0.16)
    // Speed and reward do NOT scale with wave (only rift tier and mutation change them)
    let hp = Math.max(1, Math.round(spec.hp * (1 + (currentWave - 1) * 0.16)));
    let speed = Math.min(2.4, spec.speed);
    let reward = spec.reward;

    // Step 2: Rift tier (Per tier above T1: HP +50%, Speed +15%, Reward +50%)
    if (riftTier > 1) {
      const tierHpMul = 1 + (riftTier - 1) * 0.5;
      const tierSpeedMul = 1 + (riftTier - 1) * 0.15;
      const tierRewardMul = 1 + (riftTier - 1) * 0.5;
      hp = Math.round(hp * tierHpMul);
      speed = speed * tierSpeedMul;
      reward = Math.round(reward * tierRewardMul);
    }

    // Step 3: Mutation
    if (mutation && MUTATION_PROFILES[mutation]) {
      const prof = MUTATION_PROFILES[mutation];
      hp = Math.round(hp * prof.hp);
      speed = speed * prof.speed;
      reward = Math.round(reward * prof.reward);
    }

    const enemy: Enemy = {
      id: nextEntityIdRef.current++,
      type,
      x: startX,
      y: startY,
      hp,
      maxHp: hp,
      shield: 0,
      maxShield: 0,
      speed,
      angle: initialAngle,
      waypointIndex,
      path,
      slowTimer: 0,
      stunTimer: 0,
      stunImmunityTimer: 0,
      staticCharge: 0,
      isCloaked: false,
      cloakTimer: 0,
      distanceTraveled: 0,
      mutation,
      bounty: reward,
      riftTier,
      color: spec.color,
      size: spec.size,
    };

    enemiesRef.current.push(enemy);

    // Boss spawn: Orange flash and threat announcement
    if (type === 'boss') {
      shockwavesRef.current.push({
        x: startX,
        y: startY,
        radius: 12,
        maxRadius: 260,
        color: '#ff8800',
        alpha: 1,
      });
      popupsRef.current.push({
        x: startX,
        y: startY - 45,
        text: '⚠ TITAN PRIME INCOMING! ⚠',
        color: '#ff8800',
        life: 4.0,
      });
      gameAudio.playGunshotBlast();
      setTacticalBanner({
        type: 'boss',
        text: '[⚠ THREAT LEVEL OMEGA: APEX TITAN ENGAGED]',
        trackName: 'Boss Clash',
      });
      // Auto-dismiss threat banner after 4.5s so it never lingers or blocks UI
      setTimeout(() => {
        setTacticalBanner((prev) => (prev?.type === 'boss' ? null : prev));
      }, 4500);
    }
  };

  // Spawn Mini from Splitter death (inherits Parent's color, rift tier, and mutation)
  const spawnMiniEnemy = (parent: Enemy) => {
    const parentTier = parent.riftTier || 1;
    const parentMutation = parent.mutation;
    const miniHp = Math.max(1, Math.round(parent.maxHp * 0.2));
    const miniSpeed = parent.speed * 1.5;

    const tierRewardMul = 1 + (parentTier - 1) * 0.5;
    const mutRewardMul = parentMutation ? MUTATION_PROFILES[parentMutation].reward : 1;
    const miniReward = Math.round(5 * tierRewardMul * mutRewardMul);

    // Slight separation jitter
    const jx = (Math.random() - 0.5) * 8;
    const jy = (Math.random() - 0.5) * 8;

    const miniEnemy: Enemy = {
      id: nextEntityIdRef.current++,
      type: 'mini',
      x: parent.x + jx,
      y: parent.y + jy,
      hp: miniHp,
      maxHp: miniHp,
      shield: 0,
      maxShield: 0,
      speed: miniSpeed,
      angle: parent.angle,
      waypointIndex: parent.waypointIndex,
      path: parent.path,
      slowTimer: 0,
      stunTimer: 0,
      stunImmunityTimer: 0,
      staticCharge: 0,
      isCloaked: false,
      cloakTimer: 0,
      distanceTraveled: parent.distanceTraveled,
      mutation: parentMutation,
      bounty: miniReward,
      riftTier: parentTier,
      color: parent.color,
      size: 12,
    };

    enemiesRef.current.push(miniEnemy);
  };

  // --- COMMANDER ACTIONS & CORE REPAIRS ---

  // Trigger EMP Shockwave (Cost 40 energy)
  const triggerEMP = (targetX: number, targetY: number) => {
    if (energyRef.current < 40) {
      gameAudio.playErrorBuzz();
      return;
    }
    setEnergy((prev) => Math.max(0, prev - 40));
    empCdRef.current = getConfig('empCooldown') || 25;
    setEmpCooldownLeft(empCdRef.current);
    setIsEmpTargeting(false);

    shockwavesRef.current.push({
      x: targetX,
      y: targetY,
      radius: 10,
      maxRadius: 240,
      color: '#00f0ff',
      alpha: 1,
    });

    gameAudio.playChiptuneExplosion();

    const empRadius = 240;
    enemiesRef.current.forEach((enemy) => {
      const d = Math.hypot(enemy.x - targetX, enemy.y - targetY);
      if (d <= empRadius) {
        enemy.stunTimer = 4.0;
        enemy.hp -= 140;
        enemy.shield = 0;
        popupsRef.current.push({
          x: enemy.x,
          y: enemy.y - 12,
          text: 'EMP STUN (4s)',
          color: '#38bdf8',
          life: 1.2,
        });

        for (let i = 0; i < 6; i++) {
          spawnParticle(
            particlesRef.current,
            enemy.x,
            enemy.y,
            (Math.random() - 0.5) * 120,
            (Math.random() - 0.5) * 120,
            '#00f0ff',
            2.5,
            0.35,
          );
        }
      }
    });
  };

  // Trigger Overclock (Cost 25 energy, 10s duration)
  const triggerOverclock = () => {
    if (energyRef.current < 25) {
      gameAudio.playErrorBuzz();
      return;
    }
    setEnergy((prev) => Math.max(0, prev - 25));
    ocCdRef.current = getConfig('overclockCooldown') || 20;
    ocActiveTimeRef.current = 10.0;
    setOverclockCooldownLeft(ocCdRef.current);
    setIsOverclockActive(true);
    gameAudio.playPowerupChime();

    shockwavesRef.current.push({
      x: 0,
      y: 0,
      radius: 20,
      maxRadius: 500,
      color: '#ec4899',
      alpha: 1,
    });
  };

  // Repair Core: base $100 + repairs * $50
  const repairCore = () => {
    const currentRepairs = coreRepairsCountRef.current;
    const cost = 100 + currentRepairs * 50;

    if (creditsRef.current < cost) {
      gameAudio.playErrorBuzz();
      return;
    }
    if (coreLivesRef.current >= 20) {
      popupsRef.current.push({
        x: 0,
        y: -45,
        text: 'CORE AT MAX 20 LIVES',
        color: '#eab308',
        life: 1.2,
      });
      return;
    }

    setCredits((prev) => prev - cost);
    setCoreLives((prev) => Math.min(20, prev + 1));
    setCoreRepairsCount((prev) => prev + 1);
    gameAudio.playPowerupChime();

    popupsRef.current.push({
      x: 0,
      y: -45,
      text: '+1 CORE LIFE RESTORED',
      color: '#00ff66',
      life: 1.5,
    });
  };

  // Upgrade Core Turret (Max Level 10, cost progression: Math.floor(120 * lvl))
  const upgradeCoreTurret = () => {
    const lvl = coreTurretLevelRef.current;
    if (lvl >= 10) return;
    const cost = Math.floor(120 * lvl);
    if (creditsRef.current < cost) {
      gameAudio.playErrorBuzz();
      return;
    }

    setCredits((prev) => prev - cost);
    setCoreTurretLevel((prev) => prev + 1);
    gameAudio.playLevelUpStinger();

    popupsRef.current.push({
      x: 0,
      y: -40,
      text: `CORE TURRET LV.${lvl + 1}/10! (-$${cost})`,
      color: '#00ff66',
      life: 1.5,
    });
  };

  // Construct Tower on Hardpoint or Open Grid Cell
  const buildTower = (
    type: TowerType,
    hardpointId: number | null,
    cellPos?: {gridX: number; gridY: number},
  ) => {
    const spec = TOWER_SPECS[type];
    if (creditsRef.current < spec.cost) {
      gameAudio.playErrorBuzz();
      return;
    }

    let tx: number;
    let ty: number;
    let gridX: number;
    let gridY: number;
    let isCoreBonus = false;

    if (hardpointId !== null) {
      const hp = hardpointsRef.current.find((h) => h.id === hardpointId);
      if (!hp || hp.tower) return;

      if (isCellOnPath(hp.gridX, hp.gridY, portalsRef.current)) {
        popupsRef.current.push({
          x: hp.x,
          y: hp.y - 18,
          text: 'BLOCKED: ENEMY PATH',
          color: '#ef4444',
          life: 1.2,
        });
        gameAudio.playErrorBuzz();
        return;
      }

      gridX = hp.gridX;
      gridY = hp.gridY;
      tx = hp.x;
      ty = hp.y;
      isCoreBonus = hp.isCoreHardpoint;
    } else if (cellPos) {
      gridX = cellPos.gridX;
      gridY = cellPos.gridY;
      const center = gridToCenter(gridX, gridY);
      tx = center.x;
      ty = center.y;

      // Strictly block placement inside Gate ring (Zone 0) - Core Hardpoints only
      if (isCellInsideGateRing(gridX, gridY)) {
        popupsRef.current.push({
          x: tx,
          y: ty - 18,
          text: 'RESTRICTED: CORE ZONE 0 (Hardpoints only)',
          color: '#ef4444',
          life: 1.5,
        });
        gameAudio.playErrorBuzz();
        return;
      }

      // Strictly check if cell is traversed by an enemy path
      if (isCellOnPath(gridX, gridY, portalsRef.current)) {
        popupsRef.current.push({
          x: tx,
          y: ty - 18,
          text: 'BLOCKED: ENEMY PATH',
          color: '#ef4444',
          life: 1.2,
        });
        gameAudio.playErrorBuzz();
        return;
      }

      // Ensure not occupied by another free tower
      const occupied = freeTowersRef.current.some(
        (t) => t.gridX === gridX && t.gridY === gridY,
      );
      if (occupied) return;

      // Ensure not on a hardpoint
      const onHp = hardpointsRef.current.some(
        (h) => h.gridX === gridX && h.gridY === gridY,
      );
      if (onHp) return;

      // Ensure not inside Nexus Core
      if (isCoreCell(gridX, gridY)) return;

      // Ensure not on a door
      const onDoor = CORE_DOORS.some((d) => d.gridX === gridX && d.gridY === gridY);
      if (onDoor) return;
    } else {
      return;
    }

    setCredits((prev) => prev - spec.cost);
    const newTower: Tower = {
      id: nextEntityIdRef.current++,
      type,
      hardpointId,
      gridX,
      gridY,
      x: tx,
      y: ty,
      level: 1,
      angle: 0,
      targetId: null,
      cooldown: 0,
      totalInvested: spec.cost,
      priority: 'first',
      kills: 0,
      damageDealt: 0,
      isCoreBonus,
      barrelToggle: 0,
    };

    if (hardpointId !== null) {
      const hp = hardpointsRef.current.find((h) => h.id === hardpointId);
      if (hp) hp.tower = newTower;
      setSelectedHardpointId(hardpointId);
    } else {
      freeTowersRef.current.push(newTower);
      setSelectedTowerId(newTower.id);
    }

    gameAudio.playConfirmSelect();

    for (let i = 0; i < 6; i++) {
      spawnParticle(
        particlesRef.current,
        tx,
        ty,
        (Math.random() - 0.5) * 100,
        (Math.random() - 0.5) * 100,
        spec.color,
        2.5,
        0.4,
      );
    }
  };

  // Upgrade Tower (Shared Upgrade Rules: Math.floor(baseCost * 0.4 * currentLevel), Max Level 10)
  const upgradeTower = (tower: Tower) => {
    if (tower.level >= 10) return;

    const baseCost = TOWER_SPECS[tower.type].cost;
    const upgradeCost = Math.floor(baseCost * 0.4 * tower.level);

    if (creditsRef.current < upgradeCost) {
      gameAudio.playErrorBuzz();
      return;
    }

    setCredits((prev) => prev - upgradeCost);
    tower.level++;
    tower.totalInvested += upgradeCost;
    gameAudio.playLevelUpStinger();

    popupsRef.current.push({
      x: tower.x,
      y: tower.y - 25,
      text: `UPGRADE LV.${tower.level}/10`,
      color: '#eab308',
      life: 1.2,
    });

    for (let i = 0; i < 6; i++) {
      spawnParticle(
        particlesRef.current,
        tower.x,
        tower.y,
        (Math.random() - 0.5) * 120,
        (Math.random() - 0.5) * 120,
        '#eab308',
        3,
        0.4,
      );
    }
  };

  // Sell Tower (Strictly 70% refund of total invested credits)
  const sellTower = (tower: Tower) => {
    const refund = Math.floor(tower.totalInvested * 0.7);
    setCredits((prev) => prev + refund);
    gameAudio.playCoinPickup();

    popupsRef.current.push({
      x: tower.x,
      y: tower.y - 20,
      text: `+$${refund} (70% REFUND)`,
      color: '#00ff66',
      life: 1.0,
    });

    if (tower.hardpointId !== null) {
      const hp = hardpointsRef.current.find((h) => h.id === tower.hardpointId);
      if (hp) hp.tower = null;
      setSelectedHardpointId(null);
    } else {
      const idx = freeTowersRef.current.findIndex((t) => t.id === tower.id);
      if (idx !== -1) freeTowersRef.current.splice(idx, 1);
      setSelectedTowerId(null);
    }
  };

  // Cycle Tower Priority
  const cycleTowerPriority = (tower: Tower) => {
    const order: TargetPriority[] = ['first', 'closest', 'strongest', 'weakest'];
    const idx = order.indexOf(tower.priority);
    tower.priority = order[(idx + 1) % order.length];
    gameAudio.playCrispClick();
  };

  // Active selected tower helper
  const getActiveSelectedTower = (): Tower | null => {
    const hpId = selectedHardpointIdRef.current;
    if (hpId !== null) {
      const hp = hardpointsRef.current.find((h) => h.id === hpId);
      return hp?.tower || null;
    }
    const tId = selectedTowerIdRef.current;
    if (tId !== null) {
      return freeTowersRef.current.find((t) => t.id === tId) || null;
    }
    return null;
  };

  // --- KEYBOARD SHORTCUTS & PAN CONTROLS ---
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.isContentEditable)
      ) {
        return;
      }

      const key = e.key.toLowerCase();
      keysDownRef.current.add(key);

      if (gameStateRef.current.status !== 'PLAYING') return;

      // While paused only ESC works. Every other hotkey is ignored.
      if (isGameMenuOpenRef.current && key !== 'escape') return;

      // Prevent browser scrolling on arrow keys during gameplay
      if (
        e.key === 'ArrowUp' ||
        e.key === 'ArrowDown' ||
        e.key === 'ArrowLeft' ||
        e.key === 'ArrowRight'
      ) {
        e.preventDefault();
      }

      // Build Hotkeys: Q (Laser), W (Rapid), E (Railgun), R (Tesla Arc) - Toggle off if already selected!
      if (key === 'q') setSelectedBuildType((prev) => (prev === 'basic' ? null : 'basic'));
      if (key === 'w') setSelectedBuildType((prev) => (prev === 'rapid' ? null : 'rapid'));
      if (key === 'e') setSelectedBuildType((prev) => (prev === 'sniper' ? null : 'sniper'));
      if (key === 'r') setSelectedBuildType((prev) => (prev === 'arc' ? null : 'arc'));

      // Deselect / Free Cursor hotkeys: X or C
      if (key === 'x' || key === 'c') {
        if (selectedBuildTypeRef.current !== null || isEmpTargetingRef.current) {
          setSelectedBuildType(null);
          setIsEmpTargeting(false);
          gameAudio.playCrispClick();
        } else if (
          selectedHardpointIdRef.current !== null ||
          selectedTowerIdRef.current !== null ||
          isCoreSelectedRef.current ||
          selectedGateIndexRef.current !== null
        ) {
          setSelectedHardpointId(null);
          setSelectedTowerId(null);
          setIsCoreSelected(false);
          setSelectedGateIndex(null);
          gameAudio.playCrispClick();
        }
      }

      // Abilities: 1 / F for EMP, 2 / V for Overclock
      if (key === '1' || key === 'f') {
        setIsEmpTargeting((prev) => !prev);
      }
      if (key === '2' || key === 'v') {
        triggerOverclock();
      }

      // Space: Start next wave / Skip countdown timer OR clear selection if in combat / not starting wave
      if (e.key === ' ' || key === ' ' || e.code === 'Space') {
        e.preventDefault();
        if (isPrepPhaseRef.current) {
          skipPrepPhase();
        } else if (!isWaveActiveRef.current) {
          startNextWave();
        } else if (selectedBuildTypeRef.current !== null) {
          setSelectedBuildType(null);
          gameAudio.playCrispClick();
        }
      }

      // U: Upgrade currently selected tower or Core (if affordable)
      if (key === 'u') {
        const selTower = getActiveSelectedTower();
        if (selTower) {
          upgradeTower(selTower);
        } else if (isCoreSelectedRef.current) {
          upgradeCoreTurret();
        }
      }

      // S (and Delete / Backspace): Sell currently selected tower (with 70% refund)
      if (key === 's' || key === 'delete' || key === 'backspace') {
        const selTower = getActiveSelectedTower();
        if (selTower) {
          sellTower(selTower);
        }
      }

      // Keyboard Zoom: + / - to step, 0 to Fit All Rifts
      if (key === '+' || key === '=') {
        cameraTargetRef.current.active = false;
        const newZoom = Math.min(MAX_ZOOM, cameraRef.current.zoom * 1.15);
        cameraRef.current.zoom = newZoom;
        cameraRef.current.hasManuallyAdjusted = true;
        setCameraZoomDisplay(newZoom);
      } else if (key === '-' || key === '_') {
        cameraTargetRef.current.active = false;
        const newZoom = Math.max(MIN_ZOOM, cameraRef.current.zoom * 0.85);
        cameraRef.current.zoom = newZoom;
        cameraRef.current.hasManuallyAdjusted = true;
        setCameraZoomDisplay(newZoom);
      } else if (key === '0') {
        fitCameraToScreen(true);
      }

      // Escape: Deselect turret / cancel build mode, close modals, or toggle pause menu
      if (key === 'escape') {
        if (isEmpTargetingRef.current) {
          setIsEmpTargeting(false);
          gameAudio.playCrispClick();
        } else if (selectedBuildTypeRef.current !== null) {
          setSelectedBuildType(null);
          gameAudio.playCrispClick();
        } else if (
          selectedHardpointIdRef.current !== null ||
          selectedTowerIdRef.current !== null ||
          isCoreSelectedRef.current ||
          selectedGateIndexRef.current !== null
        ) {
          setSelectedHardpointId(null);
          setSelectedTowerId(null);
          setIsCoreSelected(false);
          setSelectedGateIndex(null);
          gameAudio.playCrispClick();
        } else {
          setIsGameMenuOpen((prev) => !prev);
        }
      } else if (key === 'p') {
        setIsGameMenuOpen((prev) => !prev);
      }
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      const key = e.key.toLowerCase();
      keysDownRef.current.delete(key);
    };

    const handleWindowBlur = () => {
      keysDownRef.current.clear();
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    window.addEventListener('blur', handleWindowBlur);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
      window.removeEventListener('blur', handleWindowBlur);
    };
  }, [skipPrepPhase, startNextWave, fitCameraToScreen]);

  // --- POINTER / CLICK / DRAG EVENT HANDLING ---
  const handlePointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    // Right click (button 2) or middle click (button 1) cancels placement / targeting
    if (e.button === 2 || e.button === 1) {
      e.preventDefault();
      if (selectedBuildTypeRef.current !== null || isEmpTargetingRef.current) {
        setSelectedBuildType(null);
        setIsEmpTargeting(false);
        gameAudio.playCrispClick();
      } else if (
        selectedHardpointIdRef.current !== null ||
        selectedTowerIdRef.current !== null ||
        isCoreSelectedRef.current ||
        selectedGateIndexRef.current !== null
      ) {
        setSelectedHardpointId(null);
        setSelectedTowerId(null);
        setIsCoreSelected(false);
        setSelectedGateIndex(null);
        gameAudio.playCrispClick();
      }
      return;
    }

    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const clientX = e.clientX - rect.left;
    const clientY = e.clientY - rect.top;

    const cam = cameraRef.current;
    cam.isDragging = true;
    cam.hasDragged = false;
    cam.dragStartX = clientX;
    cam.dragStartY = clientY;
    cam.startCamX = cam.x;
    cam.startCamY = cam.y;
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const cam = cameraRef.current;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const clientX = e.clientX - rect.left;
    const clientY = e.clientY - rect.top;

    if (cam.isDragging) {
      const dx = clientX - cam.dragStartX;
      const dy = clientY - cam.dragStartY;

      if (Math.hypot(dx, dy) > 5) {
        cam.hasDragged = true;
        cam.hasManuallyAdjusted = true;
        cameraTargetRef.current.active = false;
      }

      if (cam.hasDragged) {
        cam.x = cam.startCamX + dx;
        cam.y = cam.startCamY + dy;
        const maxRiftDist = Math.max(
          4000,
          ...portalsRef.current.map((r) => Math.hypot(r.x, r.y) + 2000),
        );
        const maxPan = maxRiftDist * cam.zoom;
        cam.x = Math.max(-maxPan, Math.min(maxPan, cam.x));
        cam.y = Math.max(-maxPan, Math.min(maxPan, cam.y));
      }
    }

    const cw = canvasSizeRef.current.width;
    const ch = canvasSizeRef.current.height;
    const cx = cw / 2;
    const cy = ch / 2;
    const worldX = (clientX - cx - cam.x) / cam.zoom;
    const worldY = (clientY - cy - cam.y) / cam.zoom;
    mouseWorldPosRef.current = {x: worldX, y: worldY};

    const mouseGrid = worldToGrid(worldX, worldY);
    const hovered = hardpointsRef.current.find(
      (hp) => hp.gridX === mouseGrid.gridX && hp.gridY === mouseGrid.gridY,
    );
    setHoveredHardpointId(hovered ? hovered.id : null);

    const hoveredGate = CORE_DOORS.findIndex(
      (d) => d.gridX === mouseGrid.gridX && d.gridY === mouseGrid.gridY,
    );
    setHoveredGateIndex(hoveredGate !== -1 ? hoveredGate : null);
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (e.button === 2 || e.button === 1) return;
    const cam = cameraRef.current;
    const wasDragging = cam.hasDragged;
    cam.isDragging = false;

    if (wasDragging) return;

    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const clientX = e.clientX - rect.left;
    const clientY = e.clientY - rect.top;

    const cw = canvasSizeRef.current.width;
    const ch = canvasSizeRef.current.height;
    const cx = cw / 2;
    const cy = ch / 2;
    const worldX = (clientX - cx - cam.x) / cam.zoom;
    const worldY = (clientY - cy - cam.y) / cam.zoom;
    const mouseGrid = worldToGrid(worldX, worldY);

    if (isEmpTargetingRef.current) {
      const center = gridToCenter(mouseGrid.gridX, mouseGrid.gridY);
      triggerEMP(center.x, center.y);
      return;
    }

    // 0. Check Core Gate click
    const clickedGateIdx = CORE_DOORS.findIndex(
      (d) => d.gridX === mouseGrid.gridX && d.gridY === mouseGrid.gridY,
    );
    if (clickedGateIdx !== -1) {
      setSelectedGateIndex(clickedGateIdx);
      setIsCoreSelected(false);
      setSelectedHardpointId(null);
      setSelectedTowerId(null);
      gameAudio.playCrispClick();
      return;
    }
    setSelectedGateIndex(null);

    // 1. Check Core click (Nexus Core)
    if (isCoreCell(mouseGrid.gridX, mouseGrid.gridY)) {
      setIsCoreSelected(true);
      setSelectedHardpointId(null);
      setSelectedTowerId(null);
      gameAudio.playCrispClick();
      return;
    }
    setIsCoreSelected(false);

    // 2. Check Hardpoint click
    const clickedHp = hardpointsRef.current.find(
      (hp) => hp.gridX === mouseGrid.gridX && hp.gridY === mouseGrid.gridY,
    );
    if (clickedHp) {
      setSelectedHardpointId(clickedHp.id);
      setSelectedTowerId(null);
      if (!clickedHp.tower && selectedBuildType) {
        buildTower(selectedBuildType, clickedHp.id);
      } else {
        gameAudio.playCrispClick();
      }
      return;
    }

    // 3. Check Free Tower click
    const clickedFreeTower = freeTowersRef.current.find(
      (t) => t.gridX === mouseGrid.gridX && t.gridY === mouseGrid.gridY,
    );
    if (clickedFreeTower) {
      setSelectedTowerId(clickedFreeTower.id);
      setSelectedHardpointId(null);
      gameAudio.playCrispClick();
      return;
    }

    // 4. Check Open Grid Cell Building (only when build type is actively primed)
    if (selectedBuildType) {
      const isDoor = CORE_DOORS.some(
        (d) => d.gridX === mouseGrid.gridX && d.gridY === mouseGrid.gridY,
      );
      const center = gridToCenter(mouseGrid.gridX, mouseGrid.gridY);
      const distToCore = Math.hypot(center.x, center.y);

      // Strictly forbid open cell placement inside Zone 0 Gate ring (Hardpoints only)
      if (isCellInsideGateRing(mouseGrid.gridX, mouseGrid.gridY)) {
        popupsRef.current.push({
          x: center.x,
          y: center.y - 18,
          text: 'RESTRICTED: CORE ZONE 0 (Hardpoints only)',
          color: '#ef4444',
          life: 1.5,
        });
        gameAudio.playErrorBuzz();
        return;
      }

      const maxAllowedBuildDist = Math.max(
        520,
        ...portalsRef.current.map((p) => Math.hypot(p.x, p.y) + 80),
      );

      if (!isDoor && distToCore >= 48 && distToCore <= maxAllowedBuildDist) {
        buildTower(selectedBuildType, null, {
          gridX: mouseGrid.gridX,
          gridY: mouseGrid.gridY,
        });
        return;
      }
    }

    // Clicking open terrain in Free Cursor mode clears entity selection cleanly
    setSelectedHardpointId(null);
    setSelectedTowerId(null);
  };

  const handleWheel = (e: React.WheelEvent<HTMLCanvasElement>) => {
    e.preventDefault();
    const canvas = canvasRef.current;
    if (!canvas) return;

    cameraTargetRef.current.active = false;

    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const cw = canvasSizeRef.current.width;
    const ch = canvasSizeRef.current.height;
    const cx = cw / 2;
    const cy = ch / 2;

    const cam = cameraRef.current;
    // Geometric zoom step: zoom *= 1.15 on wheel up, zoom *= 0.85 on wheel down, clamped [0.15, 2.5]
    const zoomFactor = e.deltaY < 0 ? 1.15 : 0.85;
    const newZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, cam.zoom * zoomFactor));

    if (Math.abs(newZoom - cam.zoom) < 0.001) return;

    const worldX = (mx - cx - cam.x) / cam.zoom;
    const worldY = (my - cy - cam.y) / cam.zoom;

    cam.x = mx - cx - worldX * newZoom;
    cam.y = my - cy - worldY * newZoom;
    cam.zoom = newZoom;
    cam.hasManuallyAdjusted = true;
    setCameraZoomDisplay(newZoom);
  };

  // --- CORE GAME UPDATE LOOP (60 FPS) ---
  const update = (dt: number) => {
    // Smooth camera transition if active
    if (cameraTargetRef.current.active) {
      const target = cameraTargetRef.current;
      const cam = cameraRef.current;
      const lerpSpeed = Math.min(1, 9 * dt);

      cam.x += (target.x - cam.x) * lerpSpeed;
      cam.y += (target.y - cam.y) * lerpSpeed;
      cam.zoom += (target.zoom - cam.zoom) * lerpSpeed;

      if (
        Math.abs(target.x - cam.x) < 0.5 &&
        Math.abs(target.y - cam.y) < 0.5 &&
        Math.abs(target.zoom - cam.zoom) < 0.002
      ) {
        cam.x = target.x;
        cam.y = target.y;
        cam.zoom = target.zoom;
        cameraTargetRef.current.active = false;
      }
      setCameraZoomDisplay(cam.zoom);
    }

    // Keyboard Camera Pan (Dedicated Arrow Keys Only - WASD reserved strictly for hotkeys: W = Rapid Pulse, S = Sell)
    const keysDown = keysDownRef.current;
    if (keysDown.size > 0 && !isGameMenuOpenRef.current) {
      let kdx = 0;
      let kdy = 0;
      if (keysDown.has('arrowleft')) kdx += 1;
      if (keysDown.has('arrowright')) kdx -= 1;
      if (keysDown.has('arrowup')) kdy += 1;
      if (keysDown.has('arrowdown')) kdy -= 1;

      if (kdx !== 0 || kdy !== 0) {
        const len = Math.hypot(kdx, kdy) || 1;
        const panSpeed = 1200 * dt;
        const cam = cameraRef.current;
        cam.x += (kdx / len) * panSpeed;
        cam.y += (kdy / len) * panSpeed;
        cam.hasManuallyAdjusted = true;
        cameraTargetRef.current.active = false;

        const maxRiftDist = Math.max(
          4000,
          ...portalsRef.current.map((r) => Math.hypot(r.x, r.y) + 2000),
        );
        const maxPan = maxRiftDist * cam.zoom;
        cam.x = Math.max(-maxPan, Math.min(maxPan, cam.x));
        cam.y = Math.max(-maxPan, Math.min(maxPan, cam.y));
      }
    }

    if (gameStateRef.current.status !== 'PLAYING' || isGameMenuOpenRef.current)
      return;

    // Dynamic Soundtrack Controller: Determine target music track based on threats
    const hasLiveBoss = enemiesRef.current.some((e) => e.type === 'boss');
    const hasLiveMutation = activeMutation !== null;

    let targetTrack: AudioTrackType = 'tactical';
    if (hasLiveBoss) {
      targetTrack = 'boss';
    } else if (hasLiveMutation) {
      targetTrack = 'mutation';
    } else {
      targetTrack = 'tactical';
    }

    if (targetTrack !== activeMusicTrackRef.current) {
      activeMusicTrackRef.current = targetTrack;
      setActiveMusicTrack(targetTrack);
    }

    // Passive reactor energy regeneration: 3.5 NRG/s
    energyRegenAccRef.current += 3.5 * dt;
    if (energyRegenAccRef.current >= 1) {
      const whole = Math.floor(energyRegenAccRef.current);
      energyRegenAccRef.current -= whole;
      setEnergy((prev) => Math.min(100, prev + whole));
    }

    // Cooldown updates
    if (empCdRef.current > 0) {
      empCdRef.current = Math.max(0, empCdRef.current - dt);
      setEmpCooldownLeft(Math.ceil(empCdRef.current));
    }
    if (ocCdRef.current > 0) {
      ocCdRef.current = Math.max(0, ocCdRef.current - dt);
      setOverclockCooldownLeft(Math.ceil(ocCdRef.current));
    }
    if (ocActiveTimeRef.current > 0) {
      ocActiveTimeRef.current = Math.max(0, ocActiveTimeRef.current - dt);
      if (ocActiveTimeRef.current === 0) {
        setIsOverclockActive(false);
      }
    }

    // Portal pulsation
    portalsRef.current.forEach((portal) => {
      portal.pulseTimer += dt * 3.5;
    });

    // --- PREP PHASE VS WAVE PHASE ---
    if (isPrepPhaseRef.current) {
      setPrepTimer((prev) => {
        const next = Math.max(0, prev - dt);
        if (next === 0 && prev > 0) {
          startNextWave();
        }
        return next;
      });
    } else if (isWaveActiveRef.current) {
      if (waveSpawnQueueRef.current.length > 0) {
        waveSpawnTimerRef.current -= dt;
        if (waveSpawnTimerRef.current <= 0) {
          const item = waveSpawnQueueRef.current.shift()!;
          spawnEnemy(item.type, item.riftId);
          waveSpawnTimerRef.current = item.delay;
        }
      } else if (enemiesRef.current.length === 0) {
        isWaveActiveRef.current = false;
        setIsWaveActive(false);
        const nextWave = waveRef.current + 1;

        // Wave clear completion bonus: $30 + (wave * $10) bonus credits awarded at end of each wave
        const waveBonus = 30 + waveRef.current * 10;
        totalCreditsEarnedRef.current += waveBonus;
        wavesSurvivedRef.current = waveRef.current;
        setCredits((prev) => prev + waveBonus);
        setGameState((prev) => ({
          ...prev,
          score: prev.score + waveBonus * 2,
          level: nextWave,
        }));

        checkRiftArrivalSchedule(nextWave);

        // Check if next wave has an upcoming anomaly signature
        if (nextWave === nextMutationWaveRef.current) {
          const warnText = 'SECTOR SCAN: ANOMALY SIGNATURE DETECTED FOR NEXT WAVE';
          setAnomalyWarningText(warnText);
          popupsRef.current.push({
            x: 0,
            y: -85,
            text: `⚠ ${warnText}`,
            color: '#fbbf24',
            life: 4.0,
          });
        } else {
          setAnomalyWarningText(null);
        }

        popupsRef.current.push({
          x: 0,
          y: -60,
          text: `WAVE ${waveRef.current} CLEARED! +$${waveBonus}`,
          color: '#00ff66',
          life: 2.2,
        });

        gameAudio.playConfirmSelect();

        setIsPrepPhase(true);
        isPrepPhaseRef.current = true;
        setPrepTimer(30);
      }
    }

    const enemies = enemiesRef.current;

    // --- CORE TURRET AUTO-DEFENSE (CANONICAL CORE TURRET LV.1 - 10) ---
    coreTurretCooldownRef.current = Math.max(0, coreTurretCooldownRef.current - dt);
    const coreLvl = coreTurretLevelRef.current;
    const coreRange = getCoreTurretEffectiveRange(coreLvl);
    const coreRangeSq = coreRange * coreRange;
    const coreDmg = getCoreTurretDamage(coreLvl);
    const coreCooldownSec = getCoreTurretCooldownFrames(coreLvl) / 60;

    if (coreTurretCooldownRef.current <= 0) {
      const coreCandidates: Enemy[] = [];
      for (let j = 0; j < enemies.length; j++) {
        const e = enemies[j];
        if (e.isCloaked) continue;
        if (e.x > coreRange || e.x < -coreRange || e.y > coreRange || e.y < -coreRange) continue;
        const dSq = e.x * e.x + e.y * e.y;
        if (dSq <= coreRangeSq) {
          coreCandidates.push(e);
        }
      }

      // TAUNTER PRIORITY: Core Turret prioritizes Bulwarks if in range
      const coreBulwarks = coreCandidates.filter((e) => e.type === 'bulwark');
      const corePool = coreBulwarks.length > 0 ? coreBulwarks : coreCandidates;
      let target: Enemy | null = null;
      let minCoreDistSq = Infinity;

      for (let j = 0; j < corePool.length; j++) {
        const e = corePool[j];
        const dSq = e.x * e.x + e.y * e.y;
        if (dSq < minCoreDistSq) {
          minCoreDistSq = dSq;
          target = e;
        }
      }

      if (target) {
        coreTurretCooldownRef.current = coreCooldownSec;
        const ang = Math.atan2(target.y, target.x);
        projectilesRef.current.push({
          id: nextEntityIdRef.current++,
          type: 'core_turret',
          x: Math.cos(ang) * 14,
          y: Math.sin(ang) * 14,
          prevX: Math.cos(ang) * 14,
          prevY: Math.sin(ang) * 14,
          targetX: target.x,
          targetY: target.y,
          vx: Math.cos(ang) * 700,
          vy: Math.sin(ang) * 700,
          damage: coreDmg,
          pierce: 1,
          targetId: target.id,
          life: 0.8,
          color: '#00ff66',
        });
        gameAudio.playArcadeLaser();
      }
    }

    // --- UPDATE ENEMIES ---
    const breachedEnemies: Enemy[] = [];

    for (let i = enemies.length - 1; i >= 0; i--) {
      const enemy = enemies[i];

      if (enemy.stunTimer > 0) {
        enemy.stunTimer = Math.max(0, enemy.stunTimer - dt);
        continue;
      }

      if (enemy.stunImmunityTimer > 0) {
        enemy.stunImmunityTimer = Math.max(0, enemy.stunImmunityTimer - dt);
      }

      let currentSpeed = Math.min(2.4, enemy.speed);
      if (enemy.slowTimer > 0) {
        enemy.slowTimer = Math.max(0, enemy.slowTimer - dt);
        currentSpeed *= 0.55;
      }

      // Shifter invisibility cycle: while cloaked, cannot be targeted by towers
      if (enemy.type === 'shifter' || enemy.mutation === 'PHASE') {
        enemy.cloakTimer += dt;
        if (enemy.isCloaked && enemy.cloakTimer > 2.0) {
          enemy.isCloaked = false;
          enemy.cloakTimer = 0;
        } else if (!enemy.isCloaked && enemy.cloakTimer > 2.5) {
          enemy.isCloaked = true;
          enemy.cloakTimer = 0;
        }
      }

      // Titan Prime Boss: Periodic pulsing shockwaves
      if (enemy.type === 'boss' && Math.random() < 0.02) {
        shockwavesRef.current.push({
          x: enemy.x,
          y: enemy.y,
          radius: 8,
          maxRadius: 46,
          color: '#ff8800',
          alpha: 0.6,
        });
      }

      const targetWaypoint = enemy.path[enemy.waypointIndex];
      if (targetWaypoint) {
        const dx = targetWaypoint.x - enemy.x;
        const dy = targetWaypoint.y - enemy.y;
        const dist = Math.hypot(dx, dy);
        // Canonical speed in px/frame at 60 FPS: 60 * currentSpeed * dt
        const moveStep = currentSpeed * 60 * dt;

        if (dist <= moveStep) {
          enemy.x = targetWaypoint.x;
          enemy.y = targetWaypoint.y;
          enemy.distanceTraveled += dist;
          enemy.waypointIndex++;

          const nextWp = enemy.path[enemy.waypointIndex];
          if (nextWp) {
            enemy.angle = Math.atan2(nextWp.y - enemy.y, nextWp.x - enemy.x);
          }
        } else {
          enemy.x += (dx / dist) * moveStep;
          enemy.y += (dy / dist) * moveStep;
          enemy.angle = Math.atan2(dy, dx);
          enemy.distanceTraveled += moveStep;
        }
      }

      // Breach check: breached if reaches end of path or inside Nexus Core
      const enemyGrid = worldToGrid(enemy.x, enemy.y);
      if (
        enemy.waypointIndex >= enemy.path.length ||
        isCoreCell(enemyGrid.gridX, enemyGrid.gridY) ||
        Math.hypot(enemy.x, enemy.y) < 38
      ) {
        breachedEnemies.push(enemy);
        enemies.splice(i, 1);
      }
    }

    // Handle breaches
    if (breachedEnemies.length > 0) {
      breachedEnemies.forEach((enemy) => {
        const livesLost = enemy.type === 'boss' ? 3 : 1;
        coreLivesRef.current = Math.max(0, coreLivesRef.current - livesLost);
        setCoreLives(coreLivesRef.current);

        shockwavesRef.current.push({
          x: 0,
          y: 0,
          radius: 12,
          maxRadius: 110,
          color: '#ef4444',
          alpha: 1,
        });

        popupsRef.current.push({
          x: 0,
          y: -20,
          text: `BREACH! -${livesLost} LIFE`,
          color: '#ef4444',
          life: 1.5,
        });

        gameAudio.playChiptuneExplosion();

        if (coreLivesRef.current <= 0) {
          setGameState((prev) => ({...prev, status: 'GAME_OVER'}));
          gameAudio.playDefeatMotif();
        }
      });
    }

    // --- UPDATE ALL TOWERS (CANONICAL TOWER STATS & ARC NETWORK) ---
    const allTowers: Tower[] = [];
    hardpointsRef.current.forEach((hp) => {
      if (hp.tower) allTowers.push(hp.tower);
    });
    freeTowersRef.current.forEach((t) => allTowers.push(t));

    const isOverclocked = ocActiveTimeRef.current > 0;

    allTowers.forEach((tower) => {
      const spec = TOWER_SPECS[tower.type];
      const networkSize = tower.type === 'arc' ? getArcNetworkSize(tower, allTowers) : 1;
      const networkMult = Math.min(5, Math.max(1, networkSize));

      const range = getTowerEffectiveRange(
        tower.type,
        tower.level,
        !!tower.isCoreBonus,
        isOverclocked,
      );
      const rangeSq = range * range;
      const damage = getTowerEffectiveDamage(
        tower.type,
        tower.level,
        !!tower.isCoreBonus,
        networkMult,
      );
      const cooldownSec = getTowerEffectiveCooldown(
        tower.type,
        !!tower.isCoreBonus,
        isOverclocked,
        networkMult,
      );

      tower.cooldown = Math.max(0, tower.cooldown - dt);
      if (tower.barrelFlashTimer && tower.barrelFlashTimer > 0) {
        tower.barrelFlashTimer = Math.max(0, tower.barrelFlashTimer - dt);
      }

      // Fast candidate filtering without Math.hypot
      const candidateEnemies: Enemy[] = [];
      for (let j = 0; j < enemies.length; j++) {
        const e = enemies[j];
        // Shifter untargetable while invisible
        if (e.isCloaked) continue;
        const dx = e.x - tower.x;
        if (dx > range || dx < -range) continue;
        const dy = e.y - tower.y;
        if (dy > range || dy < -range) continue;
        if (dx * dx + dy * dy <= rangeSq) {
          candidateEnemies.push(e);
        }
      }

      // TAUNTER PRIORITY: If any Bulwark is in range, towers MUST prioritize Bulwark over other targets!
      const bulwarksInRange = candidateEnemies.filter((e) => e.type === 'bulwark');
      const targetPool = bulwarksInRange.length > 0 ? bulwarksInRange : candidateEnemies;

      let target: Enemy | null = null;
      if (targetPool.length > 0) {
        if (tower.priority === 'first') {
          // Furthest along the path (closest to core)
          target = targetPool[0];
          for (let k = 1; k < targetPool.length; k++) {
            const curr = targetPool[k];
            if (curr.distanceTraveled > target.distanceTraveled) {
              target = curr;
            }
          }
        } else if (tower.priority === 'closest') {
          target = targetPool[0];
          let minD2 = (target.x - tower.x) ** 2 + (target.y - tower.y) ** 2;
          for (let k = 1; k < targetPool.length; k++) {
            const curr = targetPool[k];
            const d2 = (curr.x - tower.x) ** 2 + (curr.y - tower.y) ** 2;
            if (d2 < minD2) {
              minD2 = d2;
              target = curr;
            }
          }
        } else if (tower.priority === 'strongest') {
          target = targetPool[0];
          for (let k = 1; k < targetPool.length; k++) {
            if (targetPool[k].hp > target.hp) target = targetPool[k];
          }
        } else if (tower.priority === 'weakest') {
          target = targetPool[0];
          for (let k = 1; k < targetPool.length; k++) {
            if (targetPool[k].hp < target.hp) target = targetPool[k];
          }
        }
      }

      if (target) {
        tower.targetId = target.id;
        const targetAngle = Math.atan2(target.y - tower.y, target.x - tower.x);
        tower.angle = targetAngle;

        if (tower.cooldown <= 0) {
          tower.cooldown = cooldownSec;

          if (tower.type === 'basic') {
            // LASER TURRET: Continuous coherent Cyan beam connecting muzzle directly to target!
            const muzzleX = tower.x + Math.cos(targetAngle) * 12;
            const muzzleY = tower.y + Math.sin(targetAngle) * 12;

            lasersRef.current.push({
              startX: muzzleX,
              startY: muzzleY,
              endX: target.x,
              endY: target.y,
              color: '#00f0ff',
              width: 2.8,
              alpha: 1.0,
            });

            applyDamageToEnemy(target, damage, tower);
            gameAudio.playArcadeLaser();

            // Focused thermal burn sparks at target point
            spawnParticle(
              particlesRef.current,
              target.x,
              target.y,
              (Math.random() - 0.5) * 80,
              (Math.random() - 0.5) * 80,
              '#00f0ff',
              2,
              0.2,
            );
            spawnParticle(
              particlesRef.current,
              target.x,
              target.y,
              (Math.random() - 0.5) * 60,
              (Math.random() - 0.5) * 60,
              '#ffffff',
              1.5,
              0.15,
            );
          } else if (tower.type === 'rapid') {
            // RAPID PULSE: High-frequency twin amber plasma bolts alternating left / right barrels
            const speed = 880;
            const currentBarrel = (tower.barrelToggle ?? 0) % 2; // 0 = left (-3.5px), 1 = right (+3.5px)
            const forwardDist = 11.5;
            const lateralOffset = currentBarrel === 0 ? -3.5 : 3.5;

            const muzzleX =
              tower.x +
              Math.cos(targetAngle) * forwardDist -
              Math.sin(targetAngle) * lateralOffset;
            const muzzleY =
              tower.y +
              Math.sin(targetAngle) * forwardDist +
              Math.cos(targetAngle) * lateralOffset;

            projectilesRef.current.push({
              id: nextEntityIdRef.current++,
              type: 'rapid',
              x: muzzleX,
              y: muzzleY,
              prevX: muzzleX,
              prevY: muzzleY,
              targetX: target.x,
              targetY: target.y,
              vx: Math.cos(targetAngle) * speed,
              vy: Math.sin(targetAngle) * speed,
              damage,
              pierce: 1,
              targetId: target.id,
              life: 0.9,
              color: '#f59e0b',
            });

            // Small muzzle flash / spark specifically at the active muzzle position
            for (let s = 0; s < 2; s++) {
              spawnParticle(
                particlesRef.current,
                muzzleX,
                muzzleY,
                Math.cos(targetAngle) * (30 + Math.random() * 40) + (Math.random() - 0.5) * 25,
                Math.sin(targetAngle) * (30 + Math.random() * 40) + (Math.random() - 0.5) * 25,
                '#fef08a',
                1.5,
                0.12,
              );
            }

            tower.lastFiredBarrel = currentBarrel;
            tower.barrelFlashTimer = 0.08;
            tower.barrelToggle = (currentBarrel + 1) % 2;
            gameAudio.playCrispClick();
          } else if (tower.type === 'sniper') {
            // RAILGUN SNIPER: Kinetic magnetic mass accelerator firing a heavy hypersonic slug!
            const speed = 2200; // 2200 px/s hypersonic velocity
            const muzzleX = tower.x + Math.cos(targetAngle) * 15;
            const muzzleY = tower.y + Math.sin(targetAngle) * 15;

            projectilesRef.current.push({
              id: nextEntityIdRef.current++,
              type: 'sniper',
              x: muzzleX,
              y: muzzleY,
              prevX: muzzleX,
              prevY: muzzleY,
              targetX: target.x,
              targetY: target.y,
              vx: Math.cos(targetAngle) * speed,
              vy: Math.sin(targetAngle) * speed,
              damage,
              pierce: 4, // Pierces through up to 4 targets
              targetId: target.id,
              life: (range + 60) / speed,
              color: '#c084fc',
              hitEnemyIds: new Set<number>(),
            });
            gameAudio.playGunshotBlast();

            // Supersonic muzzle shock cone
            shockwavesRef.current.push({
              x: muzzleX,
              y: muzzleY,
              radius: 2,
              maxRadius: 18,
              color: '#a855f7',
              alpha: 0.8,
            });
          } else if (tower.type === 'arc') {
            // TESLA ARC: Chain lightning with optimized search
            const hitTargets: Enemy[] = [target];
            const primaryCharge = Math.min(6, 3 * (1 + (networkSize - 1) * 0.25));
            const chainCharge = Math.min(3, 1.5 * (1 + (networkSize - 1) * 0.25));

            applyArcHit(target, damage, primaryCharge, tower);

            let current = target;
            const maxExtraJumps = 3;
            const arcLinkRadiusSq = 100 * 100;

            for (let j = 1; j <= maxExtraJumps; j++) {
              let nextTarget: Enemy | null = null;
              for (let k = 0; k < candidateEnemies.length; k++) {
                const ce = candidateEnemies[k];
                if (hitTargets.includes(ce)) continue;
                const dx = ce.x - current.x;
                if (dx > 100 || dx < -100) continue;
                const dy = ce.y - current.y;
                if (dy > 100 || dy < -100) continue;
                if (dx * dx + dy * dy <= arcLinkRadiusSq) {
                  nextTarget = ce;
                  break;
                }
              }

              if (nextTarget) {
                hitTargets.push(nextTarget);
                const jumpDamage = Math.round(damage * Math.pow(0.7, j) * 10) / 10;
                applyArcHit(nextTarget, jumpDamage, chainCharge, tower);
                current = nextTarget;
              } else {
                break;
              }
            }

            const pts: {x: number; y: number}[] = [{x: tower.x, y: tower.y}];
            hitTargets.forEach((t) => pts.push({x: t.x, y: t.y}));
            arcsRef.current.push({
              points: pts,
              alpha: 1,
              color: '#3b82f6',
            });
            gameAudio.playArcadeLaser();
          }
        }
      } else {
        tower.targetId = null;
      }
    });

    // --- UPDATE PROJECTILES ---
    const projectiles = projectilesRef.current;
    for (let i = projectiles.length - 1; i >= 0; i--) {
      const p = projectiles[i];
      p.prevX = p.x;
      p.prevY = p.y;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.life -= dt;

      if (p.type === 'sniper') {
        // Hypersonic Railgun kinetic slug: piercing line segment swept-sphere test
        const segDx = p.x - p.prevX;
        const segDy = p.y - p.prevY;
        const segLenSq = segDx * segDx + segDy * segDy;
        const pad = 24;
        const minX = Math.min(p.prevX, p.x) - pad;
        const maxX = Math.max(p.prevX, p.x) + pad;
        const minY = Math.min(p.prevY, p.y) - pad;
        const maxY = Math.max(p.prevY, p.y) + pad;

        for (let j = 0; j < enemies.length; j++) {
          const e = enemies[j];
          if (e.isCloaked || p.hitEnemyIds?.has(e.id)) continue;
          if (e.x < minX || e.x > maxX || e.y < minY || e.y > maxY) continue;

          let t = 0;
          if (segLenSq > 0) {
            t = Math.max(0, Math.min(1, ((e.x - p.prevX) * segDx + (e.y - p.prevY) * segDy) / segLenSq));
          }
          const projX = p.prevX + t * segDx;
          const projY = p.prevY + t * segDy;
          const hitRadius = e.size * 0.5 + 8;
          const distSq = (e.x - projX) ** 2 + (e.y - projY) ** 2;

          if (distSq <= hitRadius * hitRadius) {
            p.hitEnemyIds?.add(e.id);
            applyDamageToEnemy(e, p.damage);
            p.pierce--;

            // Heavy kinetic impact shock ring & debris
            shockwavesRef.current.push({
              x: e.x,
              y: e.y,
              radius: 4,
              maxRadius: 26,
              color: '#c084fc',
              alpha: 0.9,
            });

            for (let s = 0; s < 3; s++) {
              spawnParticle(
                particlesRef.current,
                e.x,
                e.y,
                (Math.random() - 0.5) * 130,
                (Math.random() - 0.5) * 130,
                '#e9d5ff',
                2,
                0.22,
              );
            }

            if (p.pierce <= 0) break;
          }
        }

        if (p.pierce <= 0 || p.life <= 0) {
          projectiles.splice(i, 1);
        }
      } else {
        // Standard projectile (rapid pulse, core turret)
        let hit = false;
        for (let j = 0; j < enemies.length; j++) {
          const e = enemies[j];
          if (e.isCloaked) continue;
          const dx = e.x - p.x;
          if (dx > 25 || dx < -25) continue;
          const dy = e.y - p.y;
          if (dy > 25 || dy < -25) continue;
          const hitRad = e.size * 0.5 + 6;
          if (dx * dx + dy * dy <= hitRad * hitRad) {
            applyDamageToEnemy(e, p.damage);
            p.pierce--;
            hit = true;

            for (let s = 0; s < 2; s++) {
              spawnParticle(
                particlesRef.current,
                p.x,
                p.y,
                (Math.random() - 0.5) * 80,
                (Math.random() - 0.5) * 80,
                p.color,
                2,
                0.2,
              );
            }
            if (p.pierce <= 0) break;
          }
        }

        if ((hit && p.pierce <= 0) || p.life <= 0) {
          projectiles.splice(i, 1);
        }
      }
    }

    // Clean defeated enemies
    for (let i = enemies.length - 1; i >= 0; i--) {
      const e = enemies[i];
      if (e.hp <= 0) {
        handleEnemyDeath(e);
        enemies.splice(i, 1);
      }
    }

    // Fade lasers, arcs, shockwaves, particles, popups
    for (let i = lasersRef.current.length - 1; i >= 0; i--) {
      lasersRef.current[i].alpha -= dt * 7;
      if (lasersRef.current[i].alpha <= 0) lasersRef.current.splice(i, 1);
    }
    for (let i = arcsRef.current.length - 1; i >= 0; i--) {
      arcsRef.current[i].alpha -= dt * 3.5;
      if (arcsRef.current[i].alpha <= 0) arcsRef.current.splice(i, 1);
    }
    for (let i = shockwavesRef.current.length - 1; i >= 0; i--) {
      const sw = shockwavesRef.current[i];
      sw.radius += (sw.maxRadius - sw.radius) * 9 * dt;
      sw.alpha -= dt * 2.2;
      if (sw.alpha <= 0) shockwavesRef.current.splice(i, 1);
    }
    for (let i = particlesRef.current.length - 1; i >= 0; i--) {
      const pt = particlesRef.current[i];
      pt.x += pt.vx * dt;
      pt.y += pt.vy * dt;
      pt.life -= dt;
      if (pt.life <= 0) particlesRef.current.splice(i, 1);
    }
    for (let i = popupsRef.current.length - 1; i >= 0; i--) {
      const pop = popupsRef.current[i];
      pop.y -= 25 * dt;
      pop.life -= dt;
      if (pop.life <= 0) popupsRef.current.splice(i, 1);
    }

    // Performance bounds & hard caps
    if (particlesRef.current.length > MAX_PARTICLES) {
      particlesRef.current.splice(0, particlesRef.current.length - MAX_PARTICLES);
    }
    if (popupsRef.current.length > 25) popupsRef.current.splice(0, popupsRef.current.length - 25);
    if (shockwavesRef.current.length > 15) shockwavesRef.current.splice(0, shockwavesRef.current.length - 15);
    if (lasersRef.current.length > 30) lasersRef.current.splice(0, lasersRef.current.length - 30);
    if (arcsRef.current.length > 35) arcsRef.current.splice(0, arcsRef.current.length - 35);
    if (projectilesRef.current.length > 250) projectilesRef.current.splice(0, projectilesRef.current.length - 250);
  };

  const applyArcHit = (
    enemy: Enemy,
    dmg: number,
    chargeAmount = 3.0,
    tower?: Tower,
  ) => {
    applyDamageToEnemy(enemy, dmg, tower);

    // Stun immunity window: enemy cannot accumulate static charge or be re-stunned
    if (enemy.stunTimer > 0 || (enemy.stunImmunityTimer && enemy.stunImmunityTimer > 0)) {
      return;
    }

    const isBoss = enemy.type === 'boss';
    // Titan Prime Boss has enhanced stun resistance (180 charge threshold, 0.3s duration, 3s immunity)
    const stunThreshold = isBoss ? 180 : 100;
    const stunDuration = isBoss ? 0.3 : 0.5;
    const stunImmunity = isBoss ? 3.0 : 1.0;

    enemy.staticCharge = (enemy.staticCharge || 0) + chargeAmount;

    // Balanced Stun Trigger: Stuns when staticCharge reaches threshold
    if (enemy.staticCharge >= stunThreshold) {
      enemy.staticCharge = 0;
      enemy.stunTimer = stunDuration;
      enemy.stunImmunityTimer = stunImmunity;
      popupsRef.current.push({
        x: enemy.x,
        y: enemy.y - 14,
        text: isBoss ? 'BOSS STUN (0.35s)' : 'STATIC STUN (0.5s)',
        color: '#60a5fa',
        life: 0.8,
      });

      // Blue electric burst effect upon reaching stun threshold
      shockwavesRef.current.push({
        x: enemy.x,
        y: enemy.y,
        radius: 4,
        maxRadius: isBoss ? 38 : 26,
        color: '#38bdf8',
        alpha: 0.9,
      });

      for (let s = 0; s < 4; s++) {
        spawnParticle(
          particlesRef.current,
          enemy.x,
          enemy.y,
          (Math.random() - 0.5) * 90,
          (Math.random() - 0.5) * 90,
          '#60a5fa',
          2,
          0.25,
        );
      }
    }
  };

  const applyDamageToEnemy = (enemy: Enemy, rawDamage: number, tower?: Tower) => {
    let damage = rawDamage;

    if (tower?.type === 'rapid') {
      // Rapid Pulse Niche: Excels at shredding high-speed Swarms, Minis, and Fast enemies (+50%)
      if (enemy.type === 'fast' || enemy.type === 'mini' || enemy.type === 'splitter') {
        damage *= 1.5;
      }
      // Moderated armor reduction (25% reduction instead of 45%, so damage is 0.75x)
      if (enemy.type === 'bulwark' || enemy.type === 'tank' || enemy.type === 'boss') {
        damage *= 0.75;
      }
    } else if (tower?.type === 'sniper') {
      // Railgun Sniper Niche: Heavy kinetic penetrator punch piercing through heavy armor (+30%)
      if (enemy.type === 'tank' || enemy.type === 'bulwark' || enemy.type === 'boss') {
        damage *= 1.30;
      }
    }

    if (enemy.shield > 0) {
      const shieldDmg = Math.min(enemy.shield, damage);
      enemy.shield -= shieldDmg;
      damage -= shieldDmg;
    }

    if (damage > 0) {
      enemy.hp -= damage;
    }

    if (tower) {
      tower.damageDealt += damage;
    }
  };

  const handleEnemyDeath = (enemy: Enemy) => {
    const bounty = enemy.bounty;
    const scoreVal = ENEMY_SPECS[enemy.type].scoreVal;

    totalKillsRef.current++;
    totalCreditsEarnedRef.current += bounty;

    setCredits((prev) => prev + bounty);
    setEnergy((prev) => Math.min(100, prev + 1));
    setGameState((prev) => ({...prev, score: prev.score + scoreVal}));

    if (enemy.type === 'boss') {
      const remainingBoss = enemiesRef.current.some(
        (e) => e.id !== enemy.id && e.type === 'boss',
      );
      if (!remainingBoss) {
        setTacticalBanner((prev) => (prev?.type === 'boss' ? null : prev));
      }
    }

    gameAudio.playCoinPickup();

    popupsRef.current.push({
      x: enemy.x,
      y: enemy.y - 12,
      text: `+$${bounty}`,
      color: '#eab308',
      life: 0.8,
    });

    const count = enemy.type === 'boss' ? 10 : 4;
    for (let i = 0; i < count; i++) {
      spawnParticle(
        particlesRef.current,
        enemy.x,
        enemy.y,
        (Math.random() - 0.5) * 120,
        (Math.random() - 0.5) * 120,
        enemy.color,
        2.5,
        0.4,
      );
    }

    // Splitter breaks into 2 or 3 Minis on death
    if (enemy.type === 'splitter') {
      const miniCount = Math.random() < 0.5 ? 2 : 3;
      for (let s = 0; s < miniCount; s++) {
        spawnMiniEnemy(enemy);
      }
    }
  };

  // --- DEV AUTHENTICATION HANDLERS ---
  const handleDevLock = () => {
    setIsDevAuthenticated(false);
    setIsDevDrawerOpen(false);
    gameAudio.playCrispClick();
    popupsRef.current.push({
      x: 0,
      y: -60,
      text: 'DEV CONSOLE LOCKED // SECURITY ACTIVE',
      color: '#f59e0b',
      life: 2.0,
    });
  };

  // --- ULTRA-DENSITY FPS STRESS TEST BENCHMARK ---
  const runStressBenchmark = useCallback(() => {
    // 1. Expand rifts up to 22+ distributed across Zones 1 through 6
    const targetRiftCount = Math.max(22, portalsRef.current.length + 6);
    while (portalsRef.current.length < targetRiftCount) {
      addRiftWithTreeTopology();
    }
    fitCameraToScreen();

    // 2. Max out Core Turret to Lv 10
    setCoreTurretLevel(10);
    coreTurretLevelRef.current = 10;

    // 3. Inject resources & energize
    setCredits((prev) => prev + 5000000);
    creditsRef.current += 5000000;
    setEnergy(100);
    energyRef.current = 100;

    // 4. Overclock all turrets for 30s
    ocActiveTimeRef.current = 30.0;
    setIsOverclockActive(true);

    // 5. Populate and max all 6 Core Hardpoints (mixing Laser, Railgun, Rapid, Tesla Arc)
    const coreHpTypes: TowerType[] = ['basic', 'sniper', 'arc', 'rapid', 'sniper', 'arc'];
    hardpointsRef.current.forEach((hp) => {
      if (hp.isCoreHardpoint) {
        const type = coreHpTypes[(hp.id - 1) % coreHpTypes.length];
        hp.tower = {
          id: nextEntityIdRef.current++,
          type,
          hardpointId: hp.id,
          gridX: hp.gridX,
          gridY: hp.gridY,
          x: hp.x,
          y: hp.y,
          level: 10,
          angle: 0,
          targetId: null,
          cooldown: 0,
          totalInvested: 5000,
          priority: 'closest',
          kills: 0,
          damageDealt: 0,
          isCoreBonus: true,
          barrelToggle: 0,
        };
      } else {
        // Populate and max all 24 Micro Hardpoints
        const microTypes: TowerType[] = ['arc', 'rapid', 'sniper', 'arc', 'basic', 'rapid'];
        const type = microTypes[hp.id % microTypes.length];
        hp.tower = {
          id: nextEntityIdRef.current++,
          type,
          hardpointId: hp.id,
          gridX: hp.gridX,
          gridY: hp.gridY,
          x: hp.x,
          y: hp.y,
          level: 10,
          angle: 0,
          targetId: null,
          cooldown: 0,
          totalInvested: 4200,
          priority: hp.id % 2 === 0 ? 'strongest' : 'first',
          kills: 0,
          damageDealt: 0,
          isCoreBonus: false,
          barrelToggle: 0,
        };
      }
    });

    // 6. Deploy strategic dense grid arrays of open-cell turrets outside Zone 0 Gate ring
    // Lines of Tesla Arc towers (gx, gy) spaced cardinally by 2 tiles so they link massive lightning conduits!
    // Plus Railguns Snipers and Rapid Pulses.
    const plannedCoords: {gx: number; gy: number; type: TowerType}[] = [];
    for (let gx = -9; gx <= 9; gx += 2) {
      plannedCoords.push({gx, gy: -7, type: 'arc'});
      plannedCoords.push({gx, gy: 7, type: 'arc'});
      plannedCoords.push({gx, gy: -9, type: 'sniper'});
      plannedCoords.push({gx, gy: 9, type: 'rapid'});
    }
    for (let gy = -9; gy <= 9; gy += 2) {
      plannedCoords.push({gx: -7, gy, type: 'arc'});
      plannedCoords.push({gx: 7, gy, type: 'arc'});
      plannedCoords.push({gx: -9, gy, type: 'sniper'});
      plannedCoords.push({gx: 9, gy, type: 'rapid'});
    }

    plannedCoords.forEach((pt) => {
      if (isCellInsideGateRing(pt.gx, pt.gy)) return;
      if (isCoreCell(pt.gx, pt.gy)) return;
      if (CORE_DOORS.some((d) => d.gridX === pt.gx && d.gridY === pt.gy)) return;
      if (hardpointsRef.current.some((h) => h.gridX === pt.gx && h.gridY === pt.gy)) return;
      if (freeTowersRef.current.some((t) => t.gridX === pt.gx && t.gridY === pt.gy)) return;
      if (isCellOnPath(pt.gx, pt.gy, portalsRef.current)) return;

      const center = gridToCenter(pt.gx, pt.gy);
      freeTowersRef.current.push({
        id: nextEntityIdRef.current++,
        type: pt.type,
        hardpointId: null,
        gridX: pt.gx,
        gridY: pt.gy,
        x: center.x,
        y: center.y,
        level: 8,
        angle: 0,
        targetId: null,
        cooldown: 0,
        totalInvested: 3800,
        priority: 'first',
        kills: 0,
        damageDealt: 0,
        isCoreBonus: false,
        barrelToggle: 0,
      });
    });

    // 7. Spawn a massive 180+ enemy composite swarm
    const swarmGroups: {type: EnemyType; count: number}[] = [
      {type: 'boss', count: 6},
      {type: 'tank', count: 18},
      {type: 'bulwark', count: 26},
      {type: 'splitter', count: 28},
      {type: 'shifter', count: 26},
      {type: 'fast', count: 48},
      {type: 'basic', count: 36},
    ];

    swarmGroups.forEach((grp) => {
      for (let i = 0; i < grp.count; i++) {
        spawnEnemy(grp.type);
      }
    });

    setIsWaveActive(true);
    isWaveActiveRef.current = true;
    setIsPrepPhase(false);
    isPrepPhaseRef.current = false;

    const totalTurretCount =
      hardpointsRef.current.filter((h) => h.tower !== null).length +
      freeTowersRef.current.length;

    popupsRef.current.push({
      x: 0,
      y: -80,
      text: `BENCHMARK ACTIVE: 180+ SWARM | ${totalTurretCount} TURRETS | ${portalsRef.current.length} RIFTS`,
      color: '#ec4899',
      life: 3.5,
    });

    gameAudio.playPowerupChime();
    gameAudio.playGunshotBlast();
  }, [addRiftWithTreeTopology]);

  // Dev Wave Overrides
  const devSetWave = useCallback((targetWave: number) => {
    const nextW = Math.max(1, Math.floor(targetWave));
    waveRef.current = nextW;
    setGameState((prev) => ({...prev, level: nextW}));

    // Reset combat state to clean prep phase for new wave
    enemiesRef.current = [];
    projectilesRef.current = [];
    lasersRef.current = [];
    arcsRef.current = [];
    waveSpawnQueueRef.current = [];
    isWaveActiveRef.current = false;
    setIsWaveActive(false);
    setIsPrepPhase(true);
    isPrepPhaseRef.current = true;
    setPrepTimer(30);

    // Sync rifts to match wave schedule
    checkRiftArrivalSchedule(nextW);

    popupsRef.current.push({
      x: 0,
      y: -60,
      text: `DEV: JUMPED TO WAVE ${nextW}`,
      color: '#fbbf24',
      life: 2.0,
    });
    gameAudio.playConfirmSelect();
  }, [checkRiftArrivalSchedule]);

  const devJumpWave = useCallback((delta: number) => {
    devSetWave(waveRef.current + delta);
  }, [devSetWave]);

  // Purge all active benchmark hostiles & VFX
  const purgeBenchmark = useCallback(() => {
    enemiesRef.current = [];
    projectilesRef.current = [];
    lasersRef.current = [];
    arcsRef.current = [];
    particlesRef.current = [];
    shockwavesRef.current = [];
    popupsRef.current = [];
    gameAudio.playChiptuneExplosion();
    popupsRef.current.push({
      x: 0,
      y: -60,
      text: 'BENCHMARK PURGED: ALL HOSTILES & VFX CLEARED',
      color: '#38bdf8',
      life: 2.0,
    });
  }, []);

  // Clear deployed free turrets and reset hardpoint defenses
  const resetBenchmarkTurrets = useCallback(() => {
    freeTowersRef.current = [];
    hardpointsRef.current.forEach((hp) => {
      hp.tower = null;
    });
    setSelectedTowerId(null);
    setSelectedHardpointId(null);
    gameAudio.playCrispClick();
    popupsRef.current.push({
      x: 0,
      y: -60,
      text: 'TURRETS DISMANTLED & HARDPOINTS CLEARED',
      color: '#eab308',
      life: 2.0,
    });
  }, []);

  // --- CORE CANVAS DRAW FUNCTION: PURE VECTOR NEON RENDERING ---
  const draw = (ctx: CanvasRenderingContext2D) => {
    const cw = canvasSizeRef.current.width;
    const ch = canvasSizeRef.current.height;
    prepareCanvas(ctx, cw, ch);

    const cam = cameraRef.current;

    // Viewport background
    ctx.fillStyle = '#050814';
    ctx.fillRect(0, 0, cw, ch);

    ctx.save();
    ctx.translate(cw / 2 + cam.x, ch / 2 + cam.y);
    ctx.scale(cam.zoom, cam.zoom);

    // 1. Dynamic Infinite Viewport Bounds: Seamless infinite grid across any camera pan coordinate
    const viewHalfW = (cw / 2) / cam.zoom;
    const viewHalfH = (ch / 2) / cam.zoom;
    const worldCenterX = -cam.x / cam.zoom;
    const worldCenterY = -cam.y / cam.zoom;

    const visLeft = worldCenterX - viewHalfW - CELL_SIZE * 2;
    const visRight = worldCenterX + viewHalfW + CELL_SIZE * 2;
    const visTop = worldCenterY - viewHalfH - CELL_SIZE * 2;
    const visBottom = worldCenterY + viewHalfH + CELL_SIZE * 2;

    const startGx = Math.floor(visLeft / CELL_SIZE);
    const endGx = Math.ceil(visRight / CELL_SIZE);
    const startGy = Math.floor(visTop / CELL_SIZE);
    const endGy = Math.ceil(visBottom / CELL_SIZE);

    // Subtle atmospheric cyber-star field across visible viewport
    const starGridSize = 160;
    const sStarX = Math.floor(visLeft / starGridSize);
    const eStarX = Math.ceil(visRight / starGridSize);
    const sStarY = Math.floor(visTop / starGridSize);
    const eStarY = Math.ceil(visBottom / starGridSize);

    ctx.fillStyle = '#38bdf8';
    ctx.beginPath();
    for (let sx = sStarX; sx <= eStarX; sx++) {
      for (let sy = sStarY; sy <= eStarY; sy++) {
        const hash = ((sx * 73856093) ^ (sy * 19349663)) >>> 0;
        const offX = ((hash % 1000) / 1000) * starGridSize;
        const offY = (((hash >> 10) % 1000) / 1000) * starGridSize;
        const starSize = ((hash >> 20) % 10) > 7 ? 1.4 : 0.75;
        const px = sx * starGridSize + offX;
        const py = sy * starGridSize + offY;
        ctx.moveTo(px + starSize, py);
        ctx.arc(px, py, starSize, 0, Math.PI * 2);
      }
    }
    ctx.globalAlpha = 0.35;
    ctx.fill();
    ctx.globalAlpha = 1.0;

    // Minor 1-cell grid (32px): smoothly fade out at extreme zoom-out (<0.32x) to eliminate moiré
    if (cam.zoom >= 0.22) {
      const minorAlpha = Math.min(1, Math.max(0, (cam.zoom - 0.22) / 0.14));
      ctx.strokeStyle = `rgba(12, 22, 40, ${minorAlpha})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      const step = cam.zoom < 0.35 ? 2 : 1;
      const adjStartGx = startGx - (((startGx % step) + step) % step);
      for (let gx = adjStartGx; gx <= endGx; gx += step) {
        const lineCoord = gx * CELL_SIZE - CELL_SIZE / 2;
        ctx.moveTo(lineCoord, visTop);
        ctx.lineTo(lineCoord, visBottom);
      }
      const adjStartGy = startGy - (((startGy % step) + step) % step);
      for (let gy = adjStartGy; gy <= endGy; gy += step) {
        const lineCoord = gy * CELL_SIZE - CELL_SIZE / 2;
        ctx.moveTo(visLeft, lineCoord);
        ctx.lineTo(visRight, lineCoord);
      }
      ctx.stroke();
    }

    // Subtle major grid lines every 5 cells (160px)
    const majorAlpha = cam.zoom < 0.35 ? 0.08 : 0.04;
    ctx.strokeStyle = `rgba(0, 240, 255, ${majorAlpha})`;
    ctx.lineWidth = Math.max(1, 0.4 / cam.zoom);
    ctx.beginPath();
    const adjMajorX = startGx - (((startGx % 5) + 5) % 5);
    for (let gx = adjMajorX; gx <= endGx; gx += 5) {
      const lineCoord = gx * CELL_SIZE - CELL_SIZE / 2;
      ctx.moveTo(lineCoord, visTop);
      ctx.lineTo(lineCoord, visBottom);
    }
    const adjMajorY = startGy - (((startGy % 5) + 5) % 5);
    for (let gy = adjMajorY; gy <= endGy; gy += 5) {
      const lineCoord = gy * CELL_SIZE - CELL_SIZE / 2;
      ctx.moveTo(visLeft, lineCoord);
      ctx.lineTo(visRight, lineCoord);
    }
    ctx.stroke();

    // Macro Orbital Sector Lines every 20 cells (640px) for high tactical clarity at 0.15x zoom
    if (cam.zoom < 0.45) {
      ctx.strokeStyle = 'rgba(0, 240, 255, 0.08)';
      ctx.lineWidth = Math.max(1.2, 0.7 / cam.zoom);
      ctx.beginPath();
      const adjMacroX = startGx - (((startGx % 20) + 20) % 20);
      for (let gx = adjMacroX; gx <= endGx; gx += 20) {
        const lineCoord = gx * CELL_SIZE - CELL_SIZE / 2;
        ctx.moveTo(lineCoord, visTop);
        ctx.lineTo(lineCoord, visBottom);
      }
      const adjMacroY = startGy - (((startGy % 20) + 20) % 20);
      for (let gy = adjMacroY; gy <= endGy; gy += 20) {
        const lineCoord = gy * CELL_SIZE - CELL_SIZE / 2;
        ctx.moveTo(visLeft, lineCoord);
        ctx.lineTo(visRight, lineCoord);
      }
      ctx.stroke();
    }

    // 2. Batched Dashed Glowing Cyan Paths with 90-degree turns & Tree Merging junctions
    ctx.save();
    ctx.strokeStyle = 'rgba(0, 240, 255, 0.08)';
    ctx.lineWidth = 14;
    ctx.beginPath();
    portalsRef.current.forEach((portal) => {
      if (!portal.active || !portal.path || portal.path.length < 2) return;
      portal.path.forEach((pt, idx) => {
        if (idx === 0) ctx.moveTo(pt.x, pt.y);
        else ctx.lineTo(pt.x, pt.y);
      });
    });
    ctx.stroke();

    // Outer subtle glow stroke without shadowBlur
    ctx.strokeStyle = 'rgba(0, 240, 255, 0.25)';
    ctx.lineWidth = 4.5;
    ctx.setLineDash([10, 8]);
    ctx.lineDashOffset = -(Date.now() / 45) % 18;
    ctx.stroke();

    ctx.strokeStyle = '#00f0ff';
    ctx.lineWidth = 1.8;
    ctx.stroke();
    ctx.setLineDash([]);

    // Batched junction dots at turns
    ctx.fillStyle = '#00f0ff';
    ctx.beginPath();
    portalsRef.current.forEach((portal) => {
      if (!portal.active || !portal.path) return;
      for (let k = 1; k < portal.path.length - 1; k++) {
        const jPt = portal.path[k];
        ctx.moveTo(jPt.x + 3, jPt.y);
        ctx.arc(jPt.x, jPt.y, 3, 0, Math.PI * 2);
      }
    });
    ctx.fill();
    ctx.restore();

    // 3. Render 6 Core Gates strictly within their 32x32 grid cells, borders exactly matching grid lines
    CORE_DOORS.forEach((door, idx) => {
      ctx.save();
      const left = door.gridX * CELL_SIZE - CELL_SIZE / 2;
      const top = door.gridY * CELL_SIZE - CELL_SIZE / 2;
      const isSelected = selectedGateIndex === idx;
      const isHovered = hoveredGateIndex === idx;

      ctx.strokeStyle = isSelected
        ? '#ffffff'
        : isHovered
        ? '#34d399'
        : 'rgba(16, 185, 129, 0.85)';
      ctx.lineWidth = isSelected ? 1.5 : 1;

      ctx.fillStyle = isSelected
        ? 'rgba(16, 185, 129, 0.28)'
        : isHovered
        ? 'rgba(16, 185, 129, 0.18)'
        : 'rgba(16, 185, 129, 0.10)';

      ctx.fillRect(left, top, CELL_SIZE, CELL_SIZE);
      ctx.strokeRect(left + 0.5, top + 0.5, CELL_SIZE - 1, CELL_SIZE - 1);

      // Sleek, compact G1-G6 badge centered with generous negative space
      ctx.fillStyle = isSelected
        ? '#ffffff'
        : isHovered
        ? '#a7f3d0'
        : '#6ee7b7';
      ctx.font = 'bold 10px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(`G${idx + 1}`, door.x, door.y);

      ctx.restore();
    });

    // 4. Rifts: Glowing doughnut rings with mutation aura (lightweight vector)
    portalsRef.current.forEach((portal) => {
      ctx.save();
      ctx.translate(portal.x, portal.y);

      const haloColor = portal.mutation ? '#ec4899' : '#ef4444';
      const halo = ctx.createRadialGradient(0, 0, 8, 0, 0, 44);
      halo.addColorStop(0, `${haloColor}60`);
      halo.addColorStop(0.7, `${haloColor}18`);
      halo.addColorStop(1, `${haloColor}00`);
      ctx.fillStyle = halo;
      ctx.beginPath();
      ctx.arc(0, 0, 44, 0, Math.PI * 2);
      ctx.fill();

      // Outer ring
      const pulseR = Math.sin(portal.pulseTimer * 2) * 2;
      ctx.strokeStyle = haloColor;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, 0, 24 + pulseR, 0, Math.PI * 2);
      ctx.stroke();

      // Inner ring
      ctx.strokeStyle = '#fca5a5';
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.arc(0, 0, 15, 0, Math.PI * 2);
      ctx.stroke();

      // Zone Tier badge - scales cleanly so distant rifts remain identifiable
      const riftFontSize = Math.max(9, Math.min(18, Math.round(9 / Math.sqrt(Math.max(0.2, cam.zoom)))));
      ctx.fillStyle = '#fca5a5';
      ctx.font = `bold ${riftFontSize}px monospace`;
      ctx.textAlign = 'center';
      ctx.fillText(`ZONE ${portal.zone}`, 0, portal.mutation ? -(32 + riftFontSize * 0.9) : -(24 + riftFontSize * 0.7));

      // Mutation badge
      if (portal.mutation) {
        ctx.fillStyle = '#ec4899';
        ctx.font = `bold ${riftFontSize}px monospace`;
        ctx.textAlign = 'center';
        ctx.fillText(`[${portal.mutation}]`, 0, -(24 + riftFontSize * 0.7));
      }

      ctx.restore();
    });

    // Zone 0 Gate Ring boundary (radius ~116px / ~3.6 cells)
    ctx.save();
    ctx.strokeStyle = 'rgba(16, 185, 129, 0.22)';
    ctx.lineWidth = 1.2;
    ctx.setLineDash([5, 5]);
    ctx.beginPath();
    ctx.arc(0, 0, GATE_RING_RADIUS, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();

    // 5. Central Core: Nexus Core crystal centered at (0, 0)
    ctx.save();
    ctx.translate(0, 0);

    const corePulse = Math.sin(Date.now() / 350) * 0.06 + 0.94;
    const coreHalo = ctx.createRadialGradient(0, 0, 12, 0, 0, 96);
    coreHalo.addColorStop(0, 'rgba(0, 255, 102, 0.35)');
    coreHalo.addColorStop(0.5, 'rgba(16, 185, 129, 0.15)');
    coreHalo.addColorStop(1, 'rgba(0, 255, 102, 0)');
    ctx.fillStyle = coreHalo;
    ctx.beginPath();
    ctx.arc(0, 0, 96, 0, Math.PI * 2);
    ctx.fill();

    const coreSize = CELL_SIZE * 3; // 96px
    const halfCore = coreSize / 2; // 48px

    // Core cells background grid fill (perfectly symmetric 96x96 square from -48 to +48)
    ctx.fillStyle = 'rgba(0, 255, 102, 0.12)';
    ctx.fillRect(-halfCore, -halfCore, coreSize, coreSize);
    ctx.strokeStyle = 'rgba(0, 255, 102, 0.5)';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(-halfCore + 0.5, -halfCore + 0.5, coreSize - 1, coreSize - 1);

    // Internal grid crosshair lines separating the grid cells (lines at x = ±16, y = ±16)
    ctx.strokeStyle = 'rgba(0, 255, 102, 0.25)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(-halfCore, -CELL_SIZE / 2);
    ctx.lineTo(halfCore, -CELL_SIZE / 2);
    ctx.moveTo(-halfCore, CELL_SIZE / 2);
    ctx.lineTo(halfCore, CELL_SIZE / 2);
    ctx.moveTo(-CELL_SIZE / 2, -halfCore);
    ctx.lineTo(-CELL_SIZE / 2, halfCore);
    ctx.moveTo(CELL_SIZE / 2, -halfCore);
    ctx.lineTo(CELL_SIZE / 2, halfCore);
    ctx.stroke();

    // Green Faceted Emerald Crystal Core (centered at (0, 0))
    const diaRadius = 34 * corePulse;

    // Outer faceted diamond
    ctx.beginPath();
    ctx.moveTo(0, -diaRadius);
    ctx.lineTo(diaRadius, 0);
    ctx.lineTo(0, diaRadius);
    ctx.lineTo(-diaRadius, 0);
    ctx.closePath();
    ctx.fillStyle = 'rgba(0, 255, 102, 0.32)';
    ctx.fill();
    ctx.strokeStyle = '#00ff66';
    ctx.lineWidth = 2.2;
    ctx.stroke();

    // Inner faceted diamond
    const innerDia = diaRadius * 0.58;
    ctx.beginPath();
    ctx.moveTo(0, -innerDia);
    ctx.lineTo(innerDia, 0);
    ctx.lineTo(0, innerDia);
    ctx.lineTo(-innerDia, 0);
    ctx.closePath();
    ctx.fillStyle = 'rgba(16, 185, 129, 0.5)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(0, 255, 102, 0.9)';
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Diamond facet lines from outer points to inner points
    ctx.strokeStyle = 'rgba(0, 255, 102, 0.6)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, -diaRadius); ctx.lineTo(0, -innerDia);
    ctx.moveTo(diaRadius, 0); ctx.lineTo(innerDia, 0);
    ctx.moveTo(0, diaRadius); ctx.lineTo(0, innerDia);
    ctx.moveTo(-diaRadius, 0); ctx.lineTo(-innerDia, 0);
    ctx.stroke();

    // Core Lives indicator (circle)
    ctx.fillStyle = '#10b981';
    ctx.beginPath();
    ctx.arc(0, 0, 13, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#00ff66';
    ctx.lineWidth = 1.4;
    ctx.stroke();

    // Core Turret barrel rotating towards closest threat
    const nearestEnemy = enemiesRef.current.find(
      (e) => !e.isCloaked && Math.hypot(e.x, e.y) < 160,
    );
    const coreTurretAng = nearestEnemy
      ? Math.atan2(nearestEnemy.y, nearestEnemy.x)
      : Date.now() / 1000;

    ctx.save();
    ctx.rotate(coreTurretAng);
    ctx.fillStyle = '#00ff66';
    ctx.fillRect(0, -2.5, 15, 5);
    ctx.restore();

    // Text in center of Core: Lives
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 11px monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(`${coreLivesRef.current}`, 0, 1);

    // Core selection box & range indicator
    if (isCoreSelected) {
      const coreRange = getCoreTurretEffectiveRange(coreTurretLevelRef.current);
      ctx.save();
      ctx.fillStyle = 'rgba(0, 255, 102, 0.06)';
      ctx.beginPath();
      ctx.arc(0, 0, coreRange, 0, Math.PI * 2);
      ctx.fill();

      ctx.strokeStyle = 'rgba(0, 255, 102, 0.8)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.stroke();
      ctx.restore();

      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2;
      ctx.strokeRect(-halfCore + 0.5, -halfCore + 0.5, coreSize - 1, coreSize - 1);
    }

    ctx.restore();

    // 6. Hardpoint Sockets strictly in integer grid cells (orthogonal frames)
    hardpointsRef.current.forEach((hp) => {
      ctx.save();

      const isSelected = selectedHardpointId === hp.id;
      const isHovered = hoveredHardpointId === hp.id;

      if (isSelected || isHovered) {
        const left = hp.gridX * CELL_SIZE - CELL_SIZE / 2;
        const top = hp.gridY * CELL_SIZE - CELL_SIZE / 2;

        ctx.strokeStyle = isSelected ? '#ffffff' : 'rgba(255, 255, 255, 0.6)';
        ctx.lineWidth = isSelected ? 2 : 1.2;
        ctx.strokeRect(left + 0.5, top + 0.5, CELL_SIZE - 1, CELL_SIZE - 1);

        ctx.fillStyle = isSelected
          ? 'rgba(0, 240, 255, 0.12)'
          : 'rgba(255, 255, 255, 0.05)';
        ctx.fillRect(left + 1, top + 1, CELL_SIZE - 2, CELL_SIZE - 2);

        // Only draw range ring if socket contains a tower OR a build type is primed
        if (hp.tower || selectedBuildType) {
          const targetRange = hp.tower
            ? getTowerEffectiveRange(
                hp.tower.type,
                hp.tower.level,
                hp.tower.isCoreBonus,
                ocActiveTimeRef.current > 0,
              )
            : getTowerEffectiveRange(
                selectedBuildType!,
                1,
                hp.isCoreHardpoint,
                ocActiveTimeRef.current > 0,
              );

          const rangeColor = hp.tower
            ? TOWER_SPECS[hp.tower.type].color
            : TOWER_SPECS[selectedBuildType!].color;

          ctx.save();
          ctx.fillStyle = isSelected ? `${rangeColor}14` : `${rangeColor}08`;
          ctx.beginPath();
          ctx.arc(hp.x, hp.y, targetRange, 0, Math.PI * 2);
          ctx.fill();

          ctx.strokeStyle = isSelected ? rangeColor : `${rangeColor}80`;
          ctx.lineWidth = isSelected ? 1.5 : 1;
          ctx.setLineDash([4, 4]);
          ctx.stroke();
          ctx.restore();
        }
      }

      ctx.translate(hp.x, hp.y);

      if (hp.isCoreHardpoint) {
        // Zone 0 Core Hardpoint: Emerald reinforced frame
        const sz = 24;
        const hsz = sz / 2;
        ctx.fillStyle = 'rgba(6, 12, 28, 0.92)';
        ctx.strokeStyle = '#00ff66';
        ctx.lineWidth = 1.8;
        ctx.fillRect(-hsz, -hsz, sz, sz);
        ctx.strokeRect(-hsz, -hsz, sz, sz);

        ctx.strokeStyle = 'rgba(0, 255, 102, 0.5)';
        ctx.lineWidth = 1;
        const inner = hsz - 4;
        ctx.strokeRect(-inner, -inner, inner * 2, inner * 2);

        ctx.fillStyle = '#00ff66';
        ctx.beginPath();
        ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
        ctx.fill();
      } else {
        // Micro Hardpoint: Clean standalone hexagonal socket node
        ctx.fillStyle = 'rgba(6, 12, 28, 0.92)';
        ctx.strokeStyle = '#38bdf8';
        ctx.lineWidth = 1.4;

        drawHexagonPath(ctx, 0, 0, 12);
        ctx.fill();
        ctx.stroke();

        ctx.strokeStyle = 'rgba(56, 189, 248, 0.45)';
        ctx.lineWidth = 1;
        drawHexagonPath(ctx, 0, 0, 7.5);
        ctx.stroke();

        ctx.fillStyle = '#38bdf8';
        ctx.beginPath();
        ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.restore();
    });

    // 7. Arc Towers Interconnection Conduits (Cardinally aligned within 3 grid tiles)
    const allBuiltArcTowers = [
      ...hardpointsRef.current.map((h) => h.tower),
      ...freeTowersRef.current,
    ].filter((t): t is Tower => t !== null && t.type === 'arc');

    for (let i = 0; i < allBuiltArcTowers.length; i++) {
      for (let j = i + 1; j < allBuiltArcTowers.length; j++) {
        const t1 = allBuiltArcTowers[i];
        const t2 = allBuiltArcTowers[j];

        const isSameRow = t1.gridY === t2.gridY;
        const isSameCol = t1.gridX === t2.gridX;

        if (isSameRow) {
          const tileDist = Math.abs(t1.gridX - t2.gridX);
          if (tileDist <= 3) {
            const hasBetween = allBuiltArcTowers.some(
              (mid) =>
                mid.id !== t1.id &&
                mid.id !== t2.id &&
                mid.gridY === t1.gridY &&
                ((mid.gridX > t1.gridX && mid.gridX < t2.gridX) ||
                  (mid.gridX > t2.gridX && mid.gridX < t1.gridX)),
            );
            if (!hasBetween) {
              drawOrthogonalLightning(ctx, t1.x, t1.y, t2.x, t2.y, '#3b82f6', 1.8);
            }
          }
        } else if (isSameCol) {
          const tileDist = Math.abs(t1.gridY - t2.gridY);
          if (tileDist <= 3) {
            const hasBetween = allBuiltArcTowers.some(
              (mid) =>
                mid.id !== t1.id &&
                mid.id !== t2.id &&
                mid.gridX === t1.gridX &&
                ((mid.gridY > t1.gridY && mid.gridY < t2.gridY) ||
                  (mid.gridY > t2.gridY && mid.gridY < t1.gridY)),
            );
            if (!hasBetween) {
              drawOrthogonalLightning(ctx, t1.x, t1.y, t2.x, t2.y, '#3b82f6', 1.8);
            }
          }
        }
      }
    }

    // 8. Turrets (both on Hardpoints and Open Grid cells)
    const renderTowers: Tower[] = [];
    hardpointsRef.current.forEach((hp) => {
      if (hp.tower) renderTowers.push(hp.tower);
    });
    freeTowersRef.current.forEach((t) => renderTowers.push(t));

    renderTowers.forEach((tower) => {
      ctx.save();

      if (selectedTowerId === tower.id) {
        const left = tower.gridX * CELL_SIZE - CELL_SIZE / 2;
        const top = tower.gridY * CELL_SIZE - CELL_SIZE / 2;

        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 1.8;
        ctx.strokeRect(left + 0.5, top + 0.5, CELL_SIZE - 1, CELL_SIZE - 1);

        ctx.fillStyle = 'rgba(0, 240, 255, 0.12)';
        ctx.fillRect(left + 1, top + 1, CELL_SIZE - 2, CELL_SIZE - 2);

        const targetRange = getTowerEffectiveRange(
          tower.type,
          tower.level,
          tower.isCoreBonus,
          ocActiveTimeRef.current > 0,
        );

        const rangeColor = TOWER_SPECS[tower.type].color;
        ctx.save();
        ctx.fillStyle = `${rangeColor}14`;
        ctx.beginPath();
        ctx.arc(tower.x, tower.y, targetRange, 0, Math.PI * 2);
        ctx.fill();

        ctx.strokeStyle = rangeColor;
        ctx.lineWidth = 1.2;
        ctx.setLineDash([4, 4]);
        ctx.stroke();
        ctx.restore();
      }

      ctx.translate(tower.x, tower.y);

      // Render canonical turret model (100% visual parity with build HUD icons)
      drawTurretModel(ctx, tower.type, tower.angle, tower);

      if (tower.level > 1) {
        ctx.fillStyle = '#eab308';
        ctx.font = 'bold 8px monospace';
        ctx.textAlign = 'right';
        ctx.textBaseline = 'bottom';
        ctx.fillText(`★${tower.level}`, 13, 14);
      }

      ctx.restore();
    });

    // 9. Laser Beams & Arcs
    // Laser Turret: continuous coherent Cyan beam connecting muzzle directly to target with burn spot
    lasersRef.current.forEach((beam) => {
      ctx.save();
      // Outer glow sheath (subtle alpha, zero shadowBlur)
      ctx.strokeStyle = `rgba(0, 240, 255, ${beam.alpha * 0.35})`;
      ctx.lineWidth = 5.5;
      ctx.beginPath();
      ctx.moveTo(beam.startX, beam.startY);
      ctx.lineTo(beam.endX, beam.endY);
      ctx.stroke();

      // Core coherent cyan beam
      ctx.strokeStyle = `rgba(0, 240, 255, ${beam.alpha * 0.95})`;
      ctx.lineWidth = 2.4;
      ctx.stroke();

      // Ultra-hot white laser core
      ctx.strokeStyle = `rgba(255, 255, 255, ${beam.alpha * 0.9})`;
      ctx.lineWidth = 1.0;
      ctx.stroke();

      // Focused heat shimmer / burn spot at impact point
      ctx.fillStyle = `rgba(0, 240, 255, ${beam.alpha * 0.8})`;
      ctx.beginPath();
      ctx.arc(beam.endX, beam.endY, 3.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = `rgba(255, 255, 255, ${beam.alpha * 0.95})`;
      ctx.beginPath();
      ctx.arc(beam.endX, beam.endY, 1.8, 0, Math.PI * 2);
      ctx.fill();

      ctx.restore();
    });

    arcsRef.current.forEach((arc) => {
      ctx.save();
      ctx.globalAlpha = arc.alpha;
      for (let i = 0; i < arc.points.length - 1; i++) {
        drawDirectLightning(
          ctx,
          arc.points[i].x,
          arc.points[i].y,
          arc.points[i + 1].x,
          arc.points[i + 1].y,
          arc.color,
          2.5,
        );
      }
      ctx.restore();
    });

    // 10. Projectiles (Hypersonic Railgun kinetic slug, Amber rapid pulse, Core turret)
    projectilesRef.current.forEach((p) => {
      ctx.save();
      if (p.type === 'sniper') {
        // Hypersonic Railgun kinetic slug: elongated high-velocity mass-driver needle with sonic wake
        const ang = Math.atan2(p.vy, p.vx);
        ctx.translate(p.x, p.y);
        ctx.rotate(ang);

        // Supersonic sonic-boom Mach cone trail
        ctx.fillStyle = 'rgba(192, 132, 252, 0.28)';
        ctx.beginPath();
        ctx.moveTo(10, 0);
        ctx.lineTo(-24, -4.5);
        ctx.lineTo(-20, 0);
        ctx.lineTo(-24, 4.5);
        ctx.closePath();
        ctx.fill();

        // Elongated kinetic dart sabot
        ctx.fillStyle = '#c084fc';
        ctx.beginPath();
        ctx.moveTo(10, 0);
        ctx.lineTo(-14, -2.5);
        ctx.lineTo(-12, 0);
        ctx.lineTo(-14, 2.5);
        ctx.closePath();
        ctx.fill();

        // White-hot penetrator core
        ctx.fillStyle = '#ffffff';
        ctx.beginPath();
        ctx.moveTo(10, 0);
        ctx.lineTo(-4, -1.2);
        ctx.lineTo(-4, 1.2);
        ctx.closePath();
        ctx.fill();
      } else if (p.type === 'rapid') {
        const ang = Math.atan2(p.vy, p.vx);
        ctx.translate(p.x, p.y);
        ctx.rotate(ang);
        // Amber plasma pellet
        ctx.fillStyle = 'rgba(245, 158, 11, 0.4)';
        ctx.fillRect(-8, -3, 14, 6);
        ctx.fillStyle = '#f59e0b';
        ctx.fillRect(-6, -2, 11, 4);
        ctx.fillStyle = '#fef08a';
        ctx.fillRect(-2, -1, 6, 2);
      } else {
        ctx.translate(p.x, p.y);
        ctx.fillStyle = p.color;
        ctx.beginPath();
        ctx.arc(0, 0, 4, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    });

    // 11. Geometric Enemies (Canonical colors and shapes per # The Neon Defense: Enemy Reference)
    enemiesRef.current.forEach((e) => {
      ctx.save();
      ctx.translate(e.x, e.y);

      if (e.isCloaked) {
        ctx.globalAlpha = 0.18;
      }

      ctx.rotate(e.angle);

      if (e.type === 'basic') {
        // Basic: Size 20, Color #ff0000 (Red)
        ctx.fillStyle = '#ff0000';
        ctx.beginPath();
        ctx.arc(0, 0, 10, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#ff6666';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      } else if (e.type === 'fast') {
        // Fast: Size 16, Color #ffff00 (Yellow)
        ctx.fillStyle = '#ffff00';
        ctx.beginPath();
        ctx.moveTo(0, -8);
        ctx.lineTo(8, 0);
        ctx.lineTo(0, 8);
        ctx.lineTo(-8, 0);
        ctx.closePath();
        ctx.fill();
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 1.4;
        ctx.stroke();
      } else if (e.type === 'tank') {
        // Tank: Size 24, Color #ff00ff (Magenta)
        ctx.fillStyle = '#ff00ff';
        drawHexagonPath(ctx, 0, 0, 12);
        ctx.fill();
        ctx.strokeStyle = '#ff99ff';
        ctx.lineWidth = 2.0;
        drawHexagonPath(ctx, 0, 0, 7.5);
        ctx.stroke();
      } else if (e.type === 'splitter') {
        // Splitter: Size 28, Color #00ff41 (Green)
        ctx.fillStyle = '#00ff41';
        ctx.beginPath();
        ctx.moveTo(14, 0);
        ctx.lineTo(-10, -11);
        ctx.lineTo(-10, 11);
        ctx.closePath();
        ctx.fill();
        ctx.strokeStyle = '#bbf7d0';
        ctx.lineWidth = 1.6;
        ctx.stroke();
      } else if (e.type === 'mini') {
        // Mini: Size 12, inherits parent's color
        ctx.fillStyle = e.color || '#00ff41';
        ctx.beginPath();
        ctx.moveTo(6, 0);
        ctx.lineTo(-4.5, -5);
        ctx.lineTo(-4.5, 5);
        ctx.closePath();
        ctx.fill();
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 1.0;
        ctx.stroke();
      } else if (e.type === 'bulwark') {
        // Bulwark: Size 32, Color #fcee0a (Yellow) - Taunter
        ctx.fillStyle = '#fcee0a';
        ctx.fillRect(-16, -16, 32, 32);
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2.0;
        ctx.strokeRect(-16, -16, 32, 32);

        // Heavy core armor cross
        ctx.fillStyle = '#ca8a04';
        ctx.fillRect(-10, -4, 20, 8);
        ctx.fillRect(-4, -10, 8, 20);

        // Taunt pulse rings
        ctx.save();
        ctx.strokeStyle = 'rgba(252, 238, 10, 0.45)';
        ctx.lineWidth = 1.2;
        ctx.setLineDash([3, 3]);
        ctx.beginPath();
        ctx.arc(0, 0, 22, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      } else if (e.type === 'shifter') {
        // Shifter: Size 20, Color #ff00ac (Pink)
        ctx.fillStyle = '#ff00ac';
        ctx.beginPath();
        ctx.moveTo(0, -10);
        ctx.lineTo(10, 0);
        ctx.lineTo(0, 10);
        ctx.lineTo(-10, 0);
        ctx.closePath();
        ctx.fill();
        ctx.strokeStyle = '#fbcfe8';
        ctx.lineWidth = 1.5;
        ctx.stroke();

        if (e.isCloaked) {
          ctx.strokeStyle = '#00f0ff';
          ctx.setLineDash([2, 2]);
          ctx.strokeRect(-8, -8, 16, 16);
        }
      } else if (e.type === 'boss') {
        // Boss: Size 40, Color #ff8800 (Orange)
        const bRadius = 20;
        ctx.fillStyle = '#ff8800';
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2.4;
        ctx.beginPath();
        for (let s = 0; s < 10; s++) {
          const ang = (s * Math.PI * 2) / 10 + Date.now() / 1500;
          const r = s % 2 === 0 ? bRadius + 6 : bRadius;
          const bx = Math.cos(ang) * r;
          const by = Math.sin(ang) * r;
          if (s === 0) ctx.moveTo(bx, by);
          else ctx.lineTo(bx, by);
        }
        ctx.closePath();
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = '#7c2d12';
        ctx.beginPath();
        ctx.arc(0, 0, 9, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.restore();

      // Enemy health bar
      if (!e.isCloaked) {
        const barW = Math.max(20, e.size);
        const barH = 3.5;
        const barX = e.x - barW / 2;
        const barY = e.y - e.size / 2 - 7;

        ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
        ctx.fillRect(barX, barY, barW, barH);

        const hpW = Math.max(0, (e.hp / e.maxHp) * barW);
        ctx.fillStyle = e.type === 'boss' ? '#ef4444' : '#00ff66';
        ctx.fillRect(barX, barY, hpW, barH);

        if (e.maxShield > 0 && e.shield > 0) {
          const shieldW = Math.max(0, (e.shield / e.maxShield) * barW);
          ctx.fillStyle = '#00f0ff';
          ctx.fillRect(barX, barY - 3, shieldW, 2);
        }

        // Static charge meter or stun immunity resistance indicator
        if (e.staticCharge > 0) {
          const maxCharge = e.type === 'boss' ? 150 : 100;
          const chargeW = Math.min(barW, (e.staticCharge / maxCharge) * barW);
          ctx.fillStyle = 'rgba(15, 23, 42, 0.85)';
          ctx.fillRect(barX, barY + barH + 1, barW, 2);
          ctx.fillStyle = '#38bdf8';
          ctx.fillRect(barX, barY + barH + 1, chargeW, 2);
        } else if (e.stunImmunityTimer > 0) {
          const maxImmunity = e.type === 'boss' ? 2.0 : 1.0;
          const immW = Math.min(barW, (e.stunImmunityTimer / maxImmunity) * barW);
          ctx.fillStyle = 'rgba(15, 23, 42, 0.85)';
          ctx.fillRect(barX, barY + barH + 1, barW, 2);
          ctx.fillStyle = '#f59e0b';
          ctx.fillRect(barX, barY + barH + 1, immW, 2);
        }

        // Stunned indicator ring while stun is active
        if (e.stunTimer > 0) {
          ctx.save();
          ctx.strokeStyle = '#38bdf8';
          ctx.lineWidth = 1.4;
          ctx.setLineDash([3, 3]);
          ctx.lineDashOffset = -(Date.now() / 60) % 6;
          ctx.beginPath();
          ctx.arc(e.x, e.y, e.size / 2 + 5, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        } else if (e.stunImmunityTimer > 0) {
          ctx.save();
          ctx.strokeStyle = 'rgba(245, 158, 11, 0.65)';
          ctx.lineWidth = 1.2;
          ctx.setLineDash([2, 2]);
          ctx.beginPath();
          ctx.arc(e.x, e.y, e.size / 2 + 4, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }
      }
    });

    // 12. Shockwaves, Particles, Popups
    shockwavesRef.current.forEach((sw) => {
      ctx.save();
      ctx.strokeStyle = sw.color;
      ctx.globalAlpha = sw.alpha;
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.arc(sw.x, sw.y, sw.radius, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    });

    particlesRef.current.forEach((pt) => {
      ctx.fillStyle = pt.color;
      ctx.globalAlpha = Math.max(0, pt.life / pt.maxLife);
      ctx.beginPath();
      // Ensure particles remain visible sparks even at 0.15x
      const ptRadius = Math.max(pt.size, 0.6 / cam.zoom);
      ctx.arc(pt.x, pt.y, ptRadius, 0, Math.PI * 2);
      ctx.fill();
    });
    ctx.globalAlpha = 1.0;

    popupsRef.current.forEach((pop) => {
      ctx.save();
      ctx.fillStyle = pop.color;
      const popupFontSize = Math.max(11, Math.min(22, Math.round(11 / Math.sqrt(Math.max(0.2, cam.zoom)))));
      ctx.font = `bold ${popupFontSize}px monospace`;
      ctx.textAlign = 'center';
      ctx.fillText(pop.text, pop.x, pop.y);
      ctx.restore();
    });

    // EMP Reticle
    if (isEmpTargetingRef.current) {
      const mx = mouseWorldPosRef.current.x;
      const my = mouseWorldPosRef.current.y;
      ctx.save();
      ctx.strokeStyle = '#00f0ff';
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 6]);
      ctx.beginPath();
      ctx.arc(mx, my, 240, 0, Math.PI * 2);
      ctx.stroke();

      ctx.fillStyle = 'rgba(0, 240, 255, 0.12)';
      ctx.beginPath();
      ctx.arc(mx, my, 240, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    // Free cursor mode unobtrusive tile inspection reticle (clean corner brackets, no ghost turret ring)
    if (
      !selectedBuildType &&
      !cam.isDragging &&
      hoveredHardpointId === null &&
      !isCoreSelected &&
      !isEmpTargetingRef.current
    ) {
      const mx = mouseWorldPosRef.current.x;
      const my = mouseWorldPosRef.current.y;
      const mg = worldToGrid(mx, my);
      const isCore = isCoreCell(mg.gridX, mg.gridY);
      const isDoor = CORE_DOORS.some((d) => d.gridX === mg.gridX && d.gridY === mg.gridY);
      const isHp = hardpointsRef.current.some((h) => h.gridX === mg.gridX && h.gridY === mg.gridY);
      const isTower = freeTowersRef.current.some((t) => t.gridX === mg.gridX && t.gridY === mg.gridY);

      if (!isCore && !isDoor && !isHp && !isTower) {
        const left = mg.gridX * CELL_SIZE - CELL_SIZE / 2;
        const top = mg.gridY * CELL_SIZE - CELL_SIZE / 2;

        ctx.save();
        ctx.strokeStyle = 'rgba(0, 240, 255, 0.4)';
        ctx.lineWidth = 1;
        const cLen = 5;

        // Top-left corner
        ctx.beginPath();
        ctx.moveTo(left, top + cLen);
        ctx.lineTo(left, top);
        ctx.lineTo(left + cLen, top);

        // Top-right corner
        ctx.moveTo(left + CELL_SIZE - cLen, top);
        ctx.lineTo(left + CELL_SIZE, top);
        ctx.lineTo(left + CELL_SIZE, top + cLen);

        // Bottom-left corner
        ctx.moveTo(left, top + CELL_SIZE - cLen);
        ctx.lineTo(left, top + CELL_SIZE);
        ctx.lineTo(left + cLen, top + CELL_SIZE);

        // Bottom-right corner
        ctx.moveTo(left + CELL_SIZE - cLen, top + CELL_SIZE);
        ctx.lineTo(left + CELL_SIZE, top + CELL_SIZE);
        ctx.lineTo(left + CELL_SIZE, top + CELL_SIZE - cLen);
        ctx.stroke();
        ctx.restore();
      }
    }

    // Open grid placement preview range indicator
    if (
      selectedBuildType &&
      !cam.isDragging &&
      hoveredHardpointId === null &&
      !isCoreSelected &&
      !isEmpTargetingRef.current
    ) {
      const mx = mouseWorldPosRef.current.x;
      const my = mouseWorldPosRef.current.y;
      const mg = worldToGrid(mx, my);
      const isCore = isCoreCell(mg.gridX, mg.gridY);
      const isDoor = CORE_DOORS.some((d) => d.gridX === mg.gridX && d.gridY === mg.gridY);
      const isHp = hardpointsRef.current.some((h) => h.gridX === mg.gridX && h.gridY === mg.gridY);
      const isTower = freeTowersRef.current.some((t) => t.gridX === mg.gridX && t.gridY === mg.gridY);
      const isOnPath = isCellOnPath(mg.gridX, mg.gridY, portalsRef.current);

      const cellCenter = gridToCenter(mg.gridX, mg.gridY);
      const dToCore = Math.hypot(cellCenter.x, cellCenter.y);
      const maxAllowedBuildDist = Math.max(
        520,
        ...portalsRef.current.map((p) => Math.hypot(p.x, p.y) + 80),
      );

      if (!isCore && !isDoor && !isHp && !isTower && dToCore <= maxAllowedBuildDist) {
        const left = mg.gridX * CELL_SIZE - CELL_SIZE / 2;
        const top = mg.gridY * CELL_SIZE - CELL_SIZE / 2;
        const isRestrictedZone0 = isCellInsideGateRing(mg.gridX, mg.gridY);

        if (isRestrictedZone0) {
          ctx.save();
          ctx.strokeStyle = '#ef4444';
          ctx.lineWidth = 1.5;
          ctx.shadowColor = '#ef4444';
          ctx.shadowBlur = 6;
          ctx.strokeRect(left + 0.5, top + 0.5, CELL_SIZE - 1, CELL_SIZE - 1);
          ctx.fillStyle = 'rgba(239, 68, 68, 0.22)';
          ctx.fillRect(left + 1, top + 1, CELL_SIZE - 2, CELL_SIZE - 2);

          // Red X cross
          ctx.strokeStyle = '#ef4444';
          ctx.lineWidth = 1.8;
          ctx.beginPath();
          ctx.moveTo(left + 8, top + 8);
          ctx.lineTo(left + CELL_SIZE - 8, top + CELL_SIZE - 8);
          ctx.moveTo(left + CELL_SIZE - 8, top + 8);
          ctx.lineTo(left + 8, top + CELL_SIZE - 8);
          ctx.stroke();

          ctx.fillStyle = '#fca5a5';
          ctx.font = 'bold 7px monospace';
          ctx.textAlign = 'center';
          ctx.fillText('ZONE 0', cellCenter.x, top - 3);

          // Cursor cue text
          ctx.fillStyle = '#ef4444';
          ctx.font = 'bold 9px monospace';
          ctx.shadowColor = '#000000';
          ctx.shadowBlur = 4;
          ctx.fillText('RESTRICTED: CORE ZONE 0', cellCenter.x, top - 13);
          ctx.restore();
        } else if (isOnPath) {
          ctx.save();
          ctx.strokeStyle = '#ef4444';
          ctx.lineWidth = 1.5;
          ctx.shadowColor = '#ef4444';
          ctx.shadowBlur = 6;
          ctx.strokeRect(left + 0.5, top + 0.5, CELL_SIZE - 1, CELL_SIZE - 1);
          ctx.fillStyle = 'rgba(239, 68, 68, 0.22)';
          ctx.fillRect(left + 1, top + 1, CELL_SIZE - 2, CELL_SIZE - 2);

          // Red X cross
          ctx.strokeStyle = '#ef4444';
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.moveTo(left + 7, top + 7);
          ctx.lineTo(left + CELL_SIZE - 7, top + CELL_SIZE - 7);
          ctx.moveTo(left + CELL_SIZE - 7, top + 7);
          ctx.lineTo(left + 7, top + CELL_SIZE - 7);
          ctx.stroke();

          ctx.fillStyle = '#fca5a5';
          ctx.font = 'bold 7px monospace';
          ctx.textAlign = 'center';
          ctx.fillText('PATH', cellCenter.x, top - 3);
          ctx.restore();
        } else {
          const previewRange = getTowerEffectiveRange(
            selectedBuildType,
            1,
            false,
            ocActiveTimeRef.current > 0,
          );
          const previewColor = TOWER_SPECS[selectedBuildType].color;

          ctx.save();
          ctx.fillStyle = `${previewColor}10`;
          ctx.beginPath();
          ctx.arc(cellCenter.x, cellCenter.y, previewRange, 0, Math.PI * 2);
          ctx.fill();

          ctx.strokeStyle = `${previewColor}80`;
          ctx.lineWidth = 1;
          ctx.setLineDash([4, 4]);
          ctx.stroke();

          ctx.strokeStyle = previewColor;
          ctx.lineWidth = 1.5;
          ctx.setLineDash([]);
          ctx.shadowColor = previewColor;
          ctx.shadowBlur = 6;
          ctx.strokeRect(left + 0.5, top + 0.5, CELL_SIZE - 1, CELL_SIZE - 1);
          ctx.fillStyle = `${previewColor}18`;
          ctx.fillRect(left + 1, top + 1, CELL_SIZE - 2, CELL_SIZE - 2);
          ctx.restore();
        }
      }
    }

    ctx.restore();
  };

  const updateRef = useRef(update);
  const drawRef = useRef(draw);
  updateRef.current = update;
  drawRef.current = draw;

  // RAF loop
  useEffect(() => {
    let raf = 0;
    const loop = (time: number) => {
      frameCountRef.current++;
      if (time - lastFpsUpdateTimeRef.current >= 450) {
        const computedFps = Math.min(
          120,
          Math.round(
            (frameCountRef.current * 1000) /
              Math.max(1, time - lastFpsUpdateTimeRef.current),
          ),
        );
        const builtHpCount = hardpointsRef.current.filter((h) => h.tower !== null).length;
        const totalTurrets = builtHpCount + freeTowersRef.current.length;
        setTelemetry({
          fps: computedFps,
          enemies: enemiesRef.current.length,
          turrets: totalTurrets,
          rifts: portalsRef.current.length,
          projectiles: projectilesRef.current.length,
        });
        frameCountRef.current = 0;
        lastFpsUpdateTimeRef.current = time;
      }

      stepperRef.current?.(time, (dt) => updateRef.current(dt));
      const ctx = canvasRef.current?.getContext('2d');
      if (ctx) drawRef.current(ctx);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  const isMusicPlaying =
    gameState.status === 'PLAYING' && !isGameMenuOpen && !isMusicMuted;
  const effectiveMusicVolume = (masterVolume / 10) * (threatVolume / 10);

  const currentSelectedTower = getActiveSelectedTower();
  const currentSelectedHp = hardpointsRef.current.find(
    (h) => h.id === selectedHardpointId,
  );
  const repairCost = 100 + coreRepairsCount * 50;

  return (
    <div className="fixed inset-0 overflow-hidden touch-none bg-[#040711] text-white font-mono select-none">
      <BackgroundMusic
        url={AUDIO_TRACKS[activeMusicTrack]}
        isPlaying={isMusicPlaying}
        isMuted={isMusicMuted}
        volume={effectiveMusicVolume}
      />

      {/* --- FULLSCREEN CANVAS BATTLEFIELD --- */}
      <div
        ref={containerRef}
        className="absolute inset-0 w-full h-full bg-[#050814] overflow-hidden">
        <canvas
          ref={canvasRef}
          width={canvasSize.width}
          height={canvasSize.height}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onContextMenu={(e) => {
            e.preventDefault();
            if (selectedBuildTypeRef.current !== null || isEmpTargetingRef.current) {
              setSelectedBuildType(null);
              setIsEmpTargeting(false);
              gameAudio.playCrispClick();
            }
          }}
          onWheel={handleWheel}
          onDoubleClick={() => fitCameraToScreen(true)}
          className="w-full h-full block cursor-crosshair select-none"
        />
      </div>

      {/* Cybernetic Typography and Font Injection */}
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@500;600;700&family=JetBrains+Mono:wght@400;500;700&family=Rajdhani:wght@500;600;700&display=swap');
        .font-sans { font-family: 'Chakra Petch', 'Rajdhani', sans-serif !important; }
        .font-mono { font-family: 'JetBrains Mono', monospace !important; }
      `}</style>

      {/* --- SCREEN 01 to 06: TACTICAL HUD & UNIFIED DOCK & MODALS --- */}
      {gameState.status === 'PLAYING' && (
        <TacticalHUD
          wave={gameState.level}
          score={gameState.score}
          coreLives={coreLives}
          credits={credits}
          energy={energy}
          fps={telemetry.fps}
          enemyCount={telemetry.enemies}
          turretCount={telemetry.turrets}
          riftCount={telemetry.rifts}
          isWaveActive={isWaveActive}
          isPrepPhase={isPrepPhase}
          prepTimer={prepTimer}
          activeMutation={activeMutation}
          overclockActive={isOverclockActive}
          overclockTimeLeft={ocActiveTimeRef.current}
          cameraZoom={cameraZoomDisplay}
          selectedBuildType={selectedBuildType}
          selectedTower={currentSelectedTower}
          selectedHardpoint={currentSelectedHp || null}
          isCoreSelected={isCoreSelected}
          selectedGateIndex={selectedGateIndex}
          coreTurretLevel={coreTurretLevel}
          repairCost={repairCost}
          onSelectBuildType={(t) => {
            if (t === selectedBuildType) {
              setSelectedBuildType(null);
              gameAudio.playCrispClick();
              return;
            }
            if (t && selectedHardpointId !== null) {
              const hp = hardpointsRef.current.find((h) => h.id === selectedHardpointId);
              if (hp && !hp.tower) {
                buildTower(t, selectedHardpointId);
                setSelectedBuildType(null);
                return;
              }
            }
            setSelectedBuildType(t);
            gameAudio.playCrispClick();
          }}
          onStartWave={() => {
            if (isPrepPhaseRef.current) {
              skipPrepPhase();
            } else if (!isWaveActiveRef.current) {
              startNextWave();
            }
          }}
          onTriggerEMP={() => {
            setIsEmpTargeting((prev) => !prev);
          }}
          onTriggerOverclock={triggerOverclock}
          onRepairCore={repairCore}
          onUpgradeTower={upgradeTower}
          onSellTower={sellTower}
          onUpgradeCore={upgradeCoreTurret}
          onZoomIn={() => {
            cameraTargetRef.current.active = false;
            const newZoom = Math.min(MAX_ZOOM, cameraRef.current.zoom * 1.2);
            cameraRef.current.zoom = newZoom;
            cameraRef.current.hasManuallyAdjusted = true;
            setCameraZoomDisplay(newZoom);
          }}
          onZoomOut={() => {
            cameraTargetRef.current.active = false;
            const newZoom = Math.max(MIN_ZOOM, cameraRef.current.zoom / 1.2);
            cameraRef.current.zoom = newZoom;
            cameraRef.current.hasManuallyAdjusted = true;
            setCameraZoomDisplay(newZoom);
          }}
          onFitCamera={() => fitCameraToScreen(true)}
          onResetZoom={() => {
            cameraTargetRef.current = {x: 0, y: 0, zoom: 1, active: true};
            cameraRef.current.hasManuallyAdjusted = false;
            setCameraZoomDisplay(1);
          }}
          onDeselect={() => {
            setSelectedHardpointId(null);
            setSelectedTowerId(null);
            setIsCoreSelected(false);
            setSelectedGateIndex(null);
          }}
          onRebootGame={initGame}
          isMenuOpen={isGameMenuOpen}
          setIsMenuOpen={setIsGameMenuOpen}
          isDevAuthenticated={isDevAuthenticated}
          isDevDrawerOpen={isDevDrawerOpen}
          setIsDevDrawerOpen={setIsDevDrawerOpen}
          onDevAuthSubmit={(code) => {
            const cleaned = code.trim().toLowerCase();
            if (cleaned === 'neondev') {
              setIsDevAuthenticated(true);
              setIsDevDrawerOpen(true);
              gameAudio.playConfirmSelect();
              return true;
            }
            gameAudio.playErrorBuzz();
            return false;
          }}
          onDevLock={handleDevLock}
          onDevAddCredits={() => {
            setCredits((prev) => prev + 5000000);
            gameAudio.playCoinPickup();
          }}
          onDevAddEnergy={() => {
            setEnergy(100);
            gameAudio.playPowerupChime();
          }}
          onDevAddLives={() => {
            setCoreLives(20);
            coreLivesRef.current = 20;
            gameAudio.playPowerupChime();
          }}
          onDevBenchmark={runStressBenchmark}
          onDevPurge={purgeBenchmark}
          onDevClearTurrets={resetBenchmarkTurrets}
          onDevAddRift={() => {
            const added = addRiftWithTreeTopology();
            if (added) {
              popupsRef.current.push({
                x: added.x,
                y: added.y - 30,
                text: `NEW RIFT (ZONE ${added.zone})`,
                color: '#00f0ff',
                life: 1.8,
              });
              gameAudio.playPowerupChime();
            }
          }}
          onDevRebuildRifts={rebuildRiftTopology}
          onDevSpawnEnemy={(type) => spawnEnemy(type)}
          onDevJumpWave={devJumpWave}
          onDevSetWave={devSetWave}
          isMuted={isSfxMuted}
          onToggleMute={() => {
            const newMuted = gameAudio.toggleMute();
            setIsSfxMuted(newMuted);
          }}
          isMusicMuted={isMusicMuted}
          onToggleMusic={() => setIsMusicMuted((prev) => !prev)}
          masterVolume={masterVolume}
          setMasterVolume={setMasterVolume}
          sfxVolume={sfxVolume}
          setSfxVolume={setSfxVolume}
          threatVolume={threatVolume}
          setThreatVolume={setThreatVolume}
          currentTrack={activeMusicTrack}
          tacticalBanner={tacticalBanner}
          anomalyWarningText={anomalyWarningText}
        />
      )}

      {/* Targeting Indicator for EMP */}
      {isEmpTargeting && (
        <div
          style={{
            position: 'absolute',
            top: isDevAuthenticated && isDevDrawerOpen ? '106px' : '66px',
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 40,
            pointerEvents: 'none',
          }}
          className="px-4 py-1.5 rounded-[6px] bg-cyan-950/90 border border-cyan-400 text-cyan-300 font-bold text-xs shadow-[0_0_20px_rgba(0,240,255,0.4)] pointer-events-none animate-pulse font-sans tracking-[0.08em] transition-all duration-300 ease-out select-none">
          TARGET EMP SHOCKWAVE // CLICK GROUND TO DETONATE [ESC TO CANCEL]
        </div>
      )}

      {/* --- OVERLAYS: START MENU --- */}
      {gameState.status === 'START' && (
        <MenuOverlay tone="neutral" zIndex={40}>
          <div
            className="w-full max-w-xl rounded-[12px] p-8 flex flex-col items-center shadow-[0_0_60px_rgba(0,240,255,0.25)] text-center relative overflow-hidden"
            style={{
              backgroundColor: 'rgba(8, 12, 22, 0.96)',
              backdropFilter: 'blur(16px)',
              border: '1px solid rgba(0, 240, 255, 0.4)',
            }}>
            <div className="w-16 h-16 rounded-[8px] bg-cyan-950/80 border border-cyan-400 flex items-center justify-center mb-4 shadow-[0_0_20px_rgba(0,240,255,0.35)] relative">
              <Shield size={32} className="text-cyan-400 animate-pulse" />
              <div className="absolute -top-1 -right-1 w-3 h-3 bg-emerald-400 rounded-full border-2 border-[#060a16] animate-ping" />
            </div>

            <div className="inline-block px-3 py-1 rounded-[4px] bg-cyan-950/70 border border-cyan-500/40 text-[10px] text-cyan-300 font-bold font-sans tracking-[0.08em] uppercase mb-2">
              TACTICAL RADIAL DEFENSE
            </div>

            <h1 className="text-3xl md:text-5xl font-black text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-pink-400 to-emerald-400 mb-3 font-sans tracking-[0.08em]">
              THE NEON DEFENSE
            </h1>

            <div className="text-xs md:text-sm text-slate-300 mb-6 font-mono leading-relaxed max-w-lg space-y-1">
              <p>Defend the Nexus Core against relentless waves of neon invaders.</p>
              <p className="text-slate-400">
                Build turrets on strategic hardpoints, unleash EMP &amp; Overclock abilities, and hold the line!
              </p>
            </div>

            {/* Core Feature Badges */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 w-full mb-6 text-[11px] font-mono">
              <div className="bg-[#0c1220] border border-emerald-500/40 p-2.5 rounded-[6px] text-emerald-400 flex flex-col items-center justify-center text-center">
                <div className="font-bold text-white text-xs font-sans tracking-[0.08em]">NEXUS CORE</div>
                <div className="text-emerald-400/90 text-[11px] mt-0.5">20 Lives</div>
              </div>
              <div className="bg-[#0c1220] border border-cyan-500/40 p-2.5 rounded-[6px] text-cyan-400 flex flex-col items-center justify-center text-center">
                <div className="font-bold text-white text-xs font-sans tracking-[0.08em]">6 GATES</div>
                <div className="text-cyan-400/90 text-[11px] mt-0.5">Perimeter Shield</div>
              </div>
              <div className="bg-[#0c1220] border border-pink-500/40 p-2.5 rounded-[6px] text-pink-400 flex flex-col items-center justify-center text-center">
                <div className="font-bold text-white text-xs font-sans tracking-[0.08em]">ENDLESS WAVES</div>
                <div className="text-pink-400/90 text-[11px] mt-0.5">Procedural Rifts</div>
              </div>
              <div className="bg-[#0c1220] border border-amber-500/40 p-2.5 rounded-[6px] text-amber-400 flex flex-col items-center justify-center text-center">
                <div className="font-bold text-white text-xs font-sans tracking-[0.08em]">4 TURRETS</div>
                <div className="text-amber-400/90 text-[11px] mt-0.5">Upgrade &amp; Specialize</div>
              </div>
            </div>

            {/* Primary Action Button */}
            <button
              onClick={initGame}
              autoFocus
              data-testid="start-game-btn"
              className="w-full py-3.5 px-6 rounded-[6px] bg-[#00f0ff] hover:bg-cyan-300 text-black font-black text-base md:text-lg transition-all flex items-center justify-center gap-2 shadow-[0_0_25px_rgba(0,240,255,0.4)] font-sans tracking-[0.08em] active:scale-95 group">
              <Play size={20} className="fill-black group-hover:scale-110 transition-transform" />
              <span>START DEFENSE</span>
            </button>
          </div>
        </MenuOverlay>
      )}

      {/* --- OVERLAYS: GAME OVER --- */}
      {gameState.status === 'GAME_OVER' && (
        <MenuOverlay tone="danger" zIndex={50}>
          <div
            className="w-full max-w-lg rounded-[12px] p-8 flex flex-col items-center shadow-[0_0_60px_rgba(239,68,68,0.3)] text-center relative overflow-hidden"
            style={{
              backgroundColor: 'rgba(8, 12, 22, 0.96)',
              backdropFilter: 'blur(16px)',
              border: '1px solid rgba(239, 68, 68, 0.6)',
            }}>
            <div className="w-16 h-16 rounded-[8px] bg-red-950/80 border border-red-500 flex items-center justify-center mb-4 shadow-[0_0_25px_rgba(239,68,68,0.4)]">
              <AlertTriangle size={32} className="text-red-400 animate-pulse" />
            </div>

            <div className="inline-block px-3 py-1 rounded-[4px] bg-red-950/70 border border-red-500/40 text-[10px] text-red-300 font-bold font-sans tracking-[0.08em] uppercase mb-2">
              SECTOR SECURITY COMPROMISED
            </div>

            <h2 className="text-3xl md:text-4xl font-black text-transparent bg-clip-text bg-gradient-to-r from-red-400 via-pink-400 to-amber-400 mb-2 font-sans tracking-[0.08em]">
              CORE BREACHED
            </h2>

            <p className="text-xs md:text-sm text-slate-300 mb-6 font-mono leading-relaxed">
              Hostile forces pierced Zone 0 perimeter defense and collapsed the central crystal matrix.
            </p>

            {/* Mission Telemetry Report Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 w-full mb-6 font-mono text-xs">
              <div className="bg-[#0c1220] border border-red-500/30 p-2.5 rounded-[6px]">
                <span className="text-[10px] text-slate-400 block font-sans tracking-[0.08em]">WAVE REACHED</span>
                <span className="text-base font-black text-white">{gameState.level}</span>
              </div>
              <div className="bg-[#0c1220] border border-yellow-500/30 p-2.5 rounded-[6px]">
                <span className="text-[10px] text-slate-400 block font-sans tracking-[0.08em]">FINAL SCORE</span>
                <span className="text-base font-black text-yellow-400">{gameState.score}</span>
              </div>
              <div className="bg-[#0c1220] border border-cyan-500/30 p-2.5 rounded-[6px]">
                <span className="text-[10px] text-slate-400 block font-sans tracking-[0.08em]">HOSTILES KILLED</span>
                <span className="text-base font-black text-cyan-300">{totalKillsRef.current}</span>
              </div>
              <div className="bg-[#0c1220] border border-emerald-500/30 p-2.5 rounded-[6px]">
                <span className="text-[10px] text-slate-400 block font-sans tracking-[0.08em]">CREDITS MINED</span>
                <span className="text-base font-black text-emerald-400">${totalCreditsEarnedRef.current}</span>
              </div>
            </div>

            <button
              onClick={initGame}
              autoFocus
              className="w-full py-3.5 px-6 rounded-[6px] bg-gradient-to-r from-red-500 to-pink-500 hover:from-red-400 hover:to-pink-400 text-white font-black text-base transition-all flex items-center justify-center gap-2 shadow-[0_0_25px_rgba(239,68,68,0.4)] font-sans tracking-[0.08em] active:scale-95">
              <RotateCw size={18} />
              <span>REBOOT DEFENSE SIMULATION</span>
            </button>
          </div>
        </MenuOverlay>
      )}
    </div>
  );
}
