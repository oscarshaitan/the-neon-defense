import React, {useState, useEffect, useRef} from 'react';
import {
  Heart,
  DollarSign,
  Zap,
  Lock,
  Unlock,
  Menu,
  X,
  Play,
  TrendingUp,
  Shield,
  RotateCw,
  Terminal,
  Sparkles,
  Volume2,
  Eye,
  AlertTriangle,
  Plus,
  Minus,
  Crosshair,
  Wrench,
  Target,
} from 'lucide-react';
import {TowerType, EnemyType, Tower, Hardpoint, ENEMY_SPECS, TOWER_SPECS, getTowerUpgradeCost} from './App';

export interface UIProps {
  // Game state
  wave: number;
  score: number;
  coreLives: number;
  credits: number;
  energy: number;
  fps: number;
  enemyCount: number;
  turretCount: number;
  riftCount: number;
  isWaveActive: boolean;
  isPrepPhase: boolean;
  prepTimer: number;
  activeMutation: string | null;
  overclockActive: boolean;
  overclockTimeLeft: number;
  cameraZoom: number;

  // Selected entities
  selectedBuildType: TowerType | null;
  selectedTower: Tower | null;
  selectedHardpoint: Hardpoint | null;
  isCoreSelected: boolean;
  selectedGateIndex: number | null;
  coreTurretLevel: number;
  repairCost: number;

  // Actions
  onSelectBuildType: (type: TowerType | null) => void;
  onStartWave: () => void;
  onTriggerEMP: () => void;
  onTriggerOverclock: () => void;
  onRepairCore: () => void;
  onUpgradeTower: (tower: Tower) => void;
  onSellTower: (tower: Tower) => void;
  onUpgradeCore: () => void;
  onZoomIn: () => void;
  onZoomOut: () => void;
  onFitCamera: () => void;
  onResetZoom: () => void;
  onDeselect: () => void;
  onRebootGame: () => void;

  // Modals & Dev
  isMenuOpen: boolean;
  setIsMenuOpen: (open: boolean) => void;
  isDevAuthenticated: boolean;
  isDevDrawerOpen: boolean;
  setIsDevDrawerOpen: (open: boolean) => void;
  onDevAuthSubmit: (code: string) => boolean;
  onDevLock: () => void;
  onDevAddCredits: () => void;
  onDevAddEnergy: () => void;
  onDevAddLives: () => void;
  onDevBenchmark: () => void;
  onDevPurge: () => void;
  onDevClearTurrets: () => void;
  onDevAddRift: () => void;
  onDevRebuildRifts: () => void;
  onDevSpawnEnemy: (type: EnemyType) => void;
  onDevJumpWave: (delta: number) => void;
  onDevSetWave: (targetWave: number) => void;

  // Audio & Systems
  isMuted: boolean;
  onToggleMute: () => void;
  isMusicMuted: boolean;
  onToggleMusic: () => void;
  masterVolume: number;
  setMasterVolume: React.Dispatch<React.SetStateAction<number>>;
  sfxVolume: number;
  setSfxVolume: React.Dispatch<React.SetStateAction<number>>;
  threatVolume: number;
  setThreatVolume: React.Dispatch<React.SetStateAction<number>>;
  currentTrack: 'tactical' | 'boss' | 'mutation';
  tacticalBanner: {
    type: 'boss' | 'mutation';
    text: string;
    trackName: string;
  } | null;
}

// Vector Turret Silhouettes for Dock cards and Codex
export function TurretSilhouette({type, className = 'w-7 h-7'}: {type: TowerType; className?: string}) {
  if (type === 'basic') {
    return (
      <svg viewBox="-16 -16 32 32" className={className} fill="none">
        <rect x="-8" y="-8" width="16" height="16" fill="#041424" stroke="#00f0ff" strokeWidth="1.6" />
        <circle cx="0" cy="0" r="4.5" stroke="#38bdf8" strokeWidth="1.2" />
        <rect x="0" y="-2" width="13" height="4" fill="#00f0ff" />
        <rect x="8" y="-1" width="5" height="2" fill="#ffffff" />
        <circle cx="0" cy="0" r="2" fill="#ffffff" />
      </svg>
    );
  }
  if (type === 'rapid') {
    return (
      <svg viewBox="-16 -16 32 32" className={className} fill="none">
        <polygon points="-8,-4 -4,-8 4,-8 8,-4 8,4 4,8 -4,8 -8,4" fill="#211503" stroke="#fbbf24" strokeWidth="1.6" />
        <rect x="0" y="-4.75" width="12" height="2.5" fill="#f59e0b" />
        <rect x="7" y="-4.25" width="4" height="1.5" fill="#fef08a" />
        <rect x="0" y="2.25" width="12" height="2.5" fill="#f59e0b" />
        <rect x="7" y="2.75" width="4" height="1.5" fill="#fef08a" />
        <circle cx="0" cy="0" r="4" fill="#382103" stroke="#fbbf24" strokeWidth="1" />
        <circle cx="0" cy="0" r="1.8" fill="#fef08a" />
      </svg>
    );
  }
  if (type === 'sniper') {
    return (
      <svg viewBox="-16 -16 32 32" className={className} fill="none">
        <rect x="-8" y="-7" width="13" height="14" fill="#170729" stroke="#c084fc" strokeWidth="1.6" />
        <rect x="1" y="-4" width="15" height="2" fill="#a855f7" />
        <rect x="1" y="2" width="15" height="2" fill="#a855f7" />
        <rect x="4" y="-5" width="2" height="10" fill="#c084fc" />
        <rect x="9" y="-5" width="2" height="10" fill="#c084fc" />
        <rect x="-5" y="-3" width="6" height="6" fill="#3b0764" stroke="#e9d5ff" strokeWidth="1" />
      </svg>
    );
  }
  // Tesla Arc
  return (
    <svg viewBox="-16 -16 32 32" className={className} fill="none">
      <circle cx="0" cy="0" r="9.5" fill="#081432" stroke="#2563eb" strokeWidth="1.8" />
      <circle cx="0" cy="0" r="6" stroke="#60a5fa" strokeWidth="1.2" />
      <circle cx="0" cy="0" r="3.2" fill="#1d4ed8" stroke="#93c5fd" strokeWidth="1" />
      <circle cx="0" cy="0" r="1.4" fill="#ffffff" />
      <line x1="9.5" y1="0" x2="13.5" y2="0" stroke="#60a5fa" strokeWidth="1.4" />
      <line x1="0" y1="-9.5" x2="0" y2="-12.5" stroke="#60a5fa" strokeWidth="1.4" />
      <line x1="0" y1="9.5" x2="0" y2="12.5" stroke="#60a5fa" strokeWidth="1.4" />
    </svg>
  );
}

// Vector Enemy Silhouette for Codex
export function EnemySilhouette({type, className = 'w-10 h-10'}: {type: EnemyType; className?: string}) {
  if (type === 'basic') {
    return (
      <svg viewBox="-14 -14 28 28" className={className} fill="none">
        <circle cx="0" cy="0" r="10" fill="#ff0000" stroke="#ff6666" strokeWidth="1.5" />
      </svg>
    );
  }
  if (type === 'fast') {
    return (
      <svg viewBox="-14 -14 28 28" className={className} fill="none">
        <polygon points="0,-8 8,0 0,8 -8,0" fill="#ffff00" stroke="#ffffff" strokeWidth="1.4" />
      </svg>
    );
  }
  if (type === 'tank') {
    return (
      <svg viewBox="-16 -16 32 32" className={className} fill="none">
        <polygon points="0,-12 10.4,-6 10.4,6 0,12 -10.4,6 -10.4,-6" fill="#ff00ff" stroke="#ff99ff" strokeWidth="2" />
      </svg>
    );
  }
  if (type === 'splitter') {
    return (
      <svg viewBox="-16 -16 32 32" className={className} fill="none">
        <polygon points="14,0 -10,-11 -10,11" fill="#00ff41" stroke="#bbf7d0" strokeWidth="1.6" />
      </svg>
    );
  }
  if (type === 'bulwark') {
    return (
      <svg viewBox="-18 -18 36 36" className={className} fill="none">
        <rect x="-16" y="-16" width="32" height="32" fill="#fcee0a" stroke="#ffffff" strokeWidth="2" />
        <rect x="-10" y="-4" width="20" height="8" fill="#ca8a04" />
        <rect x="-4" y="-10" width="8" height="20" fill="#ca8a04" />
      </svg>
    );
  }
  if (type === 'shifter') {
    return (
      <svg viewBox="-14 -14 28 28" className={className} fill="none">
        <polygon points="0,-10 10,0 0,10 -10,0" fill="#ff00ac" stroke="#fbcfe8" strokeWidth="1.5" />
      </svg>
    );
  }
  if (type === 'boss') {
    return (
      <svg viewBox="-24 -24 48 48" className={className} fill="none">
        <circle cx="0" cy="0" r="18" fill="#ff8800" stroke="#ffffff" strokeWidth="2.5" />
        <circle cx="0" cy="0" r="8" fill="#7c2d12" stroke="#ea580c" strokeWidth="1.5" />
      </svg>
    );
  }
  return (
    <svg viewBox="-10 -10 20 20" className={className} fill="none">
      <polygon points="6,0 -4.5,-5 -4.5,5" fill="#00ff41" stroke="#ffffff" strokeWidth="1" />
    </svg>
  );
}

export const TacticalHUD: React.FC<UIProps> = (props) => {
  const {
    wave,
    score,
    coreLives,
    credits,
    energy,
    fps,
    enemyCount,
    turretCount,
    riftCount,
    isWaveActive,
    isPrepPhase,
    prepTimer,
    activeMutation,
    overclockActive,
    overclockTimeLeft,
    cameraZoom,
    selectedBuildType,
    selectedTower,
    selectedHardpoint,
    isCoreSelected,
    selectedGateIndex,
    coreTurretLevel,
    repairCost,
    onSelectBuildType,
    onStartWave,
    onTriggerEMP,
    onTriggerOverclock,
    onRepairCore,
    onUpgradeTower,
    onSellTower,
    onUpgradeCore,
    onZoomIn,
    onZoomOut,
    onFitCamera,
    onResetZoom,
    onDeselect,
    onRebootGame,
    isMenuOpen,
    setIsMenuOpen,
    isDevAuthenticated,
    isDevDrawerOpen,
    setIsDevDrawerOpen,
    onDevAuthSubmit,
    onDevLock,
    onDevAddCredits,
    onDevAddEnergy,
    onDevAddLives,
    onDevBenchmark,
    onDevPurge,
    onDevClearTurrets,
    onDevAddRift,
    onDevRebuildRifts,
    onDevSpawnEnemy,
    onDevJumpWave,
    onDevSetWave,
    isMuted,
    onToggleMute,
    isMusicMuted,
    onToggleMusic,
    masterVolume,
    setMasterVolume,
    sfxVolume,
    setSfxVolume,
    threatVolume,
    setThreatVolume,
    currentTrack,
    tacticalBanner,
    anomalyWarningText,
  } = props;

  // Local state for modals & sub-tabs
  const [customWaveInput, setCustomWaveInput] = useState('');
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const [authInput, setAuthInput] = useState('');
  const [authError, setAuthError] = useState(false);
  const [authSuccess, setAuthSuccess] = useState(false);
  const authInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isAuthModalOpen) {
      const timer = setTimeout(() => {
        authInputRef.current?.focus();
        authInputRef.current?.select();
      }, 50);
      return () => clearTimeout(timer);
    }
  }, [isAuthModalOpen]);

  // Menu Modal State (Screens 03 to 06)
  const [menuTab, setMenuTab] = useState<'directives' | 'codex' | 'systems' | 'reboot'>('directives');
  const [codexSubTab, setCodexSubTab] = useState<'command' | 'turrets' | 'hostiles'>('turrets');
  const [selectedCodexItem, setSelectedCodexItem] = useState<string>('basic');
  const [rebootStep, setRebootStep] = useState<1 | 2>(1);

  // Systems settings state
  const [particleDensity, setParticleDensity] = useState<'LOW' | 'MED' | 'HIGH'>('HIGH');
  const [telemetryOverlay, setTelemetryOverlay] = useState(true);
  const [uiScale, setUiScale] = useState<'80%' | '100%' | '120%'>('100%');
  const [reducedMotion, setReducedMotion] = useState(false);
  const [screenShake, setScreenShake] = useState(true);

  // Check if debug environment or query flag is active
  const isDebugMode =
    typeof window !== 'undefined' &&
    (window.location.search.includes('debug=true') ||
      window.location.search.includes('dev=true') ||
      window.location.hostname === 'localhost' ||
      window.location.hostname === '127.0.0.1' ||
      ((globalThis as unknown as {process?: {env?: {NODE_ENV?: string}}}).process?.env?.NODE_ENV === 'development'));

  // Discreet keyboard shortcut for dev access: Ctrl+Shift+D or Shift+~
  useEffect(() => {
    const handleHiddenShortcut = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.isContentEditable)
      ) {
        return;
      }

      if ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'D' || e.key === 'd')) {
        e.preventDefault();
        handleDevBtnClick();
      } else if (e.shiftKey && (e.key === '~' || e.key === '`')) {
        e.preventDefault();
        handleDevBtnClick();
      }
    };
    window.addEventListener('keydown', handleHiddenShortcut);
    return () => window.removeEventListener('keydown', handleHiddenShortcut);
  }, [isDevAuthenticated, isDevDrawerOpen]);

  // Handle Dev Auth Submit
  const handleAuthSubmit = (e?: React.FormEvent) => {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    const cleaned = authInput.trim().toLowerCase();
    if (cleaned === 'neondev') {
      onDevAuthSubmit(authInput);
      setAuthSuccess(true);
      setAuthError(false);
      setTimeout(() => {
        setIsAuthModalOpen(false);
        setIsDevDrawerOpen(true);
        setAuthSuccess(false);
        setAuthInput('');
      }, 250);
    } else {
      setAuthError(true);
      setTimeout(() => setAuthError(false), 1800);
    }
  };

  const handleDevBtnClick = () => {
    if (isDevAuthenticated) {
      setIsDevDrawerOpen(!isDevDrawerOpen);
    } else {
      setIsAuthModalOpen(true);
      setAuthError(false);
      setAuthSuccess(false);
      setAuthInput('');
    }
  };

  const formattedWave = wave < 10 ? `0${wave}` : `${wave}`;
  const isLivesLow = coreLives < 5;
  const isDevToolbarVisible = isDevAuthenticated && isDevDrawerOpen;

  return (
    <div className="pointer-events-none select-none text-slate-100 font-mono">
      {/* 
        ========================================================================
        SCREEN 01: IN PLAY - TOP COMMAND BRIDGE (Height 56px)
        ========================================================================
      */}
      <header
        className="pointer-events-auto absolute top-0 left-0 right-0 h-[56px] px-4 flex items-center justify-between z-30"
        style={{
          backgroundColor: 'rgba(8, 12, 22, 0.92)',
          backdropFilter: 'blur(16px)',
          borderBottom: '1px solid rgba(0, 240, 255, 0.3)',
        }}>
        {/* Left Cluster */}
        <div className="flex items-center gap-3">
          {/* Core Lives */}
          <div
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-[6px] border ${
              isLivesLow
                ? 'bg-red-950/60 border-red-500/80 text-[#ef4444]'
                : 'bg-emerald-950/40 border-emerald-500/40 text-[#10b981]'
            }`}
            title="Nexus Core Integrity">
            <Heart size={14} className={`fill-current ${isLivesLow ? 'animate-pulse text-[#ef4444]' : 'text-[#10b981]'}`} />
            <span className="text-[10px] tracking-[0.08em] uppercase text-slate-400 font-sans font-bold">CORE LIVES</span>
            <span className="font-bold text-sm tabular-nums">
              {coreLives} <span className="opacity-60 text-xs">/ 20</span>
            </span>
          </div>

          {/* Credits */}
          <div
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-[6px] bg-amber-950/40 border border-amber-500/40 text-[#fbbf24]"
            title="Tactical Reserve Credits">
            <DollarSign size={14} className="text-[#fbbf24]" />
            <span className="text-[10px] tracking-[0.08em] uppercase text-slate-400 font-sans font-bold">CREDITS</span>
            <span className="font-bold text-sm tabular-nums">${credits.toLocaleString()}</span>
          </div>

          {/* Energy Reactor with visible tick marks at 25 and 40 */}
          <div
            className="flex items-center gap-2.5 px-3 py-1.5 rounded-[6px] bg-[#0c1220] border border-pink-500/40 text-pink-300"
            title="Reactor Energy Pool (0-100)">
            <div className="flex items-center gap-1 text-pink-400">
              <Zap size={13} className="fill-pink-400" />
              <span className="text-[10px] tracking-[0.08em] uppercase text-slate-400 font-sans font-bold">NRG</span>
            </div>
            <div className="relative w-28 h-3.5 bg-slate-950 rounded-[4px] border border-pink-900/60 overflow-hidden">
              {/* Active fill */}
              <div
                className="h-full bg-gradient-to-r from-pink-500 to-[#ec4899] transition-all duration-200"
                style={{width: `${Math.min(100, Math.max(0, energy))}%`}}
              />
              {/* Tick at 25 NRG */}
              <div
                className="absolute top-0 bottom-0 w-[1.5px] bg-amber-400/80 z-10 pointer-events-none"
                style={{left: '25%'}}
                title="Overclock threshold (25 NRG)"
              />
              {/* Tick at 40 NRG */}
              <div
                className="absolute top-0 bottom-0 w-[1.5px] bg-cyan-400/80 z-10 pointer-events-none"
                style={{left: '40%'}}
                title="EMP threshold (40 NRG)"
              />
            </div>
            <span className="font-bold text-xs text-pink-200 tabular-nums">
              {energy}<span className="text-pink-400/60 text-[10px]">/100</span>
            </span>
          </div>

          {/* Wave */}
          <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-[6px] bg-[#0c1220] border border-cyan-500/40 text-[#00f0ff]">
            <span className="text-[10px] tracking-[0.08em] uppercase text-slate-400 font-sans font-bold">WAVE</span>
            <span className="font-bold text-sm tabular-nums text-[#00f0ff]">{formattedWave}</span>
            {isWaveActive && <span className="w-1.5 h-1.5 rounded-full bg-[#00f0ff] animate-ping" />}
          </div>

          {/* Score */}
          <div className="hidden lg:flex items-center gap-1.5 px-3 py-1.5 rounded-[6px] bg-[#0c1220] border border-slate-700/60 text-slate-200">
            <span className="text-[10px] tracking-[0.08em] uppercase text-slate-400 font-sans font-bold">SCORE</span>
            <span className="font-bold text-sm tabular-nums">{score.toLocaleString()}</span>
          </div>

          {/* Mutation badge if active */}
          {activeMutation && (
            <div className="flex items-center gap-1 px-2.5 py-1 rounded-[6px] bg-pink-950/80 border border-[#ec4899] text-[#ec4899] font-bold text-xs animate-pulse">
              <Eye size={13} />
              <span>{activeMutation}</span>
            </div>
          )}

          {/* Anomaly Signature Detected Warning for Next Wave */}
          {anomalyWarningText && !activeMutation && (
            <div className="flex items-center gap-1.5 px-3 py-1 rounded-[6px] bg-amber-950/85 border border-amber-400 text-amber-300 font-bold text-xs animate-pulse shadow-[0_0_15px_rgba(251,191,36,0.35)]">
              <AlertTriangle size={13} className="text-amber-400 shrink-0" />
              <span className="font-sans tracking-[0.08em] uppercase text-[11px]">{anomalyWarningText}</span>
            </div>
          )}
        </div>

        {/* Right Cluster */}
        <div className="flex items-center gap-2.5">
          {/* Telemetry chip */}
          {telemetryOverlay && (
            <div className="hidden xl:flex items-center gap-2 px-3 py-1 rounded-[6px] bg-[#0a0f1d] border border-slate-800 text-[11px] text-[#94a3b8]">
              <span className="text-emerald-400 font-bold tabular-nums">FPS {fps}</span>
              <span className="text-slate-700">|</span>
              <span className="text-red-400 font-bold tabular-nums">ENEMIES {enemyCount}</span>
              <span className="text-slate-700">|</span>
              <span className="text-cyan-400 font-bold tabular-nums">TURRETS {turretCount}</span>
              <span className="text-slate-700">|</span>
              <span className="text-purple-400 font-bold tabular-nums">RIFTS {riftCount}</span>
            </div>
          )}

          {/* Dev button (accessible in debug mode or when authenticated via shortcut) */}
          {(isDebugMode || isDevAuthenticated) && (
            <button
              onClick={handleDevBtnClick}
              className={`px-3 py-1.5 rounded-[6px] border flex items-center gap-1.5 text-xs font-bold transition-all ${
                isDevAuthenticated
                  ? 'bg-amber-950/60 border-[#fbbf24] text-[#fbbf24] hover:bg-amber-900/60 shadow-[0_0_8px_rgba(251,191,36,0.3)]'
                  : 'bg-[#0c1220] border-amber-500/50 text-[#fbbf24] hover:bg-amber-950/40'
              }`}>
              {isDevAuthenticated ? <Unlock size={13} /> : <Lock size={13} />}
              <span className="font-sans tracking-[0.08em]">DEV</span>
            </button>
          )}

          {/* Menu button */}
          <button
            onClick={() => setIsMenuOpen(true)}
            data-testid="main-menu-btn"
            className="px-3.5 py-1.5 rounded-[6px] bg-[#0c1220] hover:bg-[#38bdf8]/20 border border-[#38bdf8]/60 hover:border-[#38bdf8] text-[#38bdf8] hover:text-white flex items-center gap-1.5 text-xs font-bold transition-all shadow-[0_0_10px_rgba(56,189,248,0.2)]">
            <Menu size={14} />
            <span className="font-sans tracking-[0.08em]">MENU [ESC]</span>
          </button>
        </div>
      </header>

      {/* Tactical Audio & Threat Alert Banner */}
      {tacticalBanner && (
        <div
          style={{
            position: 'absolute',
            top: isDevToolbarVisible ? '106px' : '66px',
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 25,
            pointerEvents: 'none',
          }}
          className="pointer-events-none select-none transition-all duration-300 ease-out">
          <div
            className={`pointer-events-none px-5 py-2.5 rounded-[8px] border flex items-center gap-3 shadow-2xl backdrop-blur-md animate-pulse ${
              tacticalBanner.type === 'boss'
                ? 'bg-red-950/95 border-red-500 text-red-200 shadow-[0_0_35px_rgba(239,68,68,0.7)]'
                : 'bg-purple-950/95 border-purple-400 text-purple-200 shadow-[0_0_35px_rgba(168,85,247,0.7)]'
            }`}>
            <div
              className={`p-1.5 rounded-full ${
                tacticalBanner.type === 'boss'
                  ? 'bg-red-500/20 text-red-400'
                  : 'bg-purple-500/20 text-purple-400'
              }`}>
              {tacticalBanner.type === 'boss' ? (
                <AlertTriangle size={18} className="animate-spin" style={{animationDuration: '4s'}} />
              ) : (
                <Sparkles size={18} className="animate-pulse text-[#a855f7]" />
              )}
            </div>
            <div className="flex flex-col text-left">
              <span className="font-sans font-black text-sm tracking-[0.08em] uppercase text-white drop-shadow-md">
                {tacticalBanner.text}
              </span>
              <span className="text-[10px] text-cyan-300 font-mono tracking-widest flex items-center gap-1.5 mt-0.5">
                <Volume2 size={11} className="text-[#00f0ff]" />
                TRACK: {tacticalBanner.trackName.toUpperCase()}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* 
        ========================================================================
        SCREEN 02: DEV TERMINAL - DOCKED STRIP (Below 56px Top Bar)
        ========================================================================
      */}
      {isDevDrawerOpen && isDevAuthenticated && (
        <div
          className="pointer-events-auto absolute top-[56px] left-0 right-0 py-2 px-4 z-20 flex flex-wrap items-center justify-between gap-2.5 text-xs shadow-lg"
          style={{
            backgroundColor: 'rgba(8, 12, 22, 0.96)',
            backdropFilter: 'blur(16px)',
            borderBottom: '1px solid #fbbf24',
          }}>
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-[#fbbf24] font-bold text-xs flex items-center gap-1 shrink-0">
              <Terminal size={14} /> // DEV OVERRIDES:
            </span>

            {/* WAVE SCALING CONTROLS */}
            <div className="flex items-center gap-1 px-2 py-1 rounded-[5px] bg-[#050b18] border border-cyan-500/50 shadow-inner">
              <span className="text-[10px] text-cyan-400 font-bold uppercase font-sans mr-0.5">WAVE</span>
              <span className="font-bold text-xs text-[#00f0ff] font-mono tabular-nums px-1.5 py-0.5 bg-cyan-950/80 rounded border border-cyan-500/30">
                {wave}
              </span>
              <button
                onClick={() => onDevJumpWave(-1)}
                disabled={wave <= 1}
                className="px-1.5 py-0.5 bg-slate-900 hover:bg-slate-800 disabled:opacity-30 border border-slate-700 text-slate-300 hover:text-white rounded text-[11px] font-bold font-mono transition-colors"
                title="Decrease Wave by 1">
                -1
              </button>
              <button
                onClick={() => onDevJumpWave(1)}
                className="px-2 py-0.5 bg-cyan-950/80 hover:bg-cyan-900 border border-cyan-500/60 text-cyan-300 hover:text-white rounded text-[11px] font-bold font-mono transition-colors"
                title="Increment Wave by 1">
                +1 Wave
              </button>
              <button
                onClick={() => onDevJumpWave(5)}
                className="px-2 py-0.5 bg-cyan-950/80 hover:bg-cyan-900 border border-cyan-500/60 text-cyan-300 hover:text-white rounded text-[11px] font-bold font-mono transition-colors"
                title="Increment Wave by 5">
                +5
              </button>
              <button
                onClick={() => onDevJumpWave(10)}
                className="px-2 py-0.5 bg-cyan-950/80 hover:bg-cyan-900 border border-cyan-500/60 text-cyan-300 hover:text-white rounded text-[11px] font-bold font-mono transition-colors"
                title="Increment Wave by 10">
                +10
              </button>
              <div className="h-3 w-[1px] bg-slate-700 mx-0.5" />
              <button
                onClick={() => onDevSetWave(10)}
                className="px-1.5 py-0.5 bg-slate-900 hover:bg-slate-800 border border-slate-700 text-cyan-400 hover:text-cyan-200 rounded text-[10px] font-mono font-bold transition-colors"
                title="Jump directly to Wave 10">
                W:10
              </button>
              <button
                onClick={() => onDevSetWave(20)}
                className="px-1.5 py-0.5 bg-slate-900 hover:bg-slate-800 border border-slate-700 text-cyan-400 hover:text-cyan-200 rounded text-[10px] font-mono font-bold transition-colors"
                title="Jump directly to Wave 20">
                W:20
              </button>
              <button
                onClick={() => onDevSetWave(50)}
                className="px-1.5 py-0.5 bg-slate-900 hover:bg-slate-800 border border-slate-700 text-cyan-400 hover:text-cyan-200 rounded text-[10px] font-mono font-bold transition-colors"
                title="Jump directly to Wave 50">
                W:50
              </button>

              {/* Direct Numeric Input */}
              <div className="flex items-center gap-1 ml-1">
                <input
                  type="number"
                  min={1}
                  max={999}
                  placeholder="Set #"
                  value={customWaveInput}
                  onChange={(e) => setCustomWaveInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      const val = parseInt(customWaveInput, 10);
                      if (!isNaN(val) && val >= 1) {
                        onDevSetWave(val);
                        setCustomWaveInput('');
                      }
                    }
                  }}
                  className="w-14 px-1.5 py-0.5 bg-[#030611] border border-cyan-500/50 rounded text-cyan-300 text-[11px] font-mono text-center focus:outline-none focus:border-cyan-400"
                />
                <button
                  type="button"
                  onClick={() => {
                    const val = parseInt(customWaveInput, 10);
                    if (!isNaN(val) && val >= 1) {
                      onDevSetWave(val);
                      setCustomWaveInput('');
                    }
                  }}
                  className="px-2 py-0.5 bg-[#00f0ff] hover:bg-cyan-300 text-black rounded text-[10px] font-bold font-sans tracking-[0.05em] uppercase transition-colors">
                  GO
                </button>
              </div>
            </div>

            {/* BENCHMARK & ACTIONS */}
            <button
              onClick={onDevBenchmark}
              className="px-2.5 py-1 bg-gradient-to-r from-pink-600 to-purple-600 hover:from-pink-500 hover:to-purple-500 text-white font-bold rounded-[4px] shadow-sm flex items-center gap-1">
              <Sparkles size={12} />
              BENCHMARK 180+
            </button>
            <button
              onClick={onDevPurge}
              className="px-2 py-1 bg-red-950/80 hover:bg-red-900 border border-red-500/50 text-red-200 rounded-[4px]">
              PURGE SWARM
            </button>
            <button
              onClick={onDevClearTurrets}
              className="px-2 py-1 bg-amber-950/80 hover:bg-amber-900 border border-amber-500/50 text-amber-200 rounded-[4px]">
              CLEAR TURRETS
            </button>
            <button
              onClick={onDevAddCredits}
              className="px-2 py-1 bg-slate-900 hover:bg-slate-800 border border-slate-700 text-yellow-300 rounded-[4px]">
              +$5M CREDITS
            </button>
            <button
              onClick={onDevAddEnergy}
              className="px-2 py-1 bg-slate-900 hover:bg-slate-800 border border-slate-700 text-pink-300 rounded-[4px]">
              +100 NRG
            </button>
            <button
              onClick={onDevAddLives}
              className="px-2 py-1 bg-slate-900 hover:bg-slate-800 border border-slate-700 text-emerald-300 rounded-[4px]">
              20 LIVES
            </button>
            <button
              onClick={onDevAddRift}
              className="px-2 py-1 bg-slate-900 hover:bg-slate-800 border border-purple-500/40 text-purple-300 rounded-[4px]">
              + RIFT
            </button>
            <button
              onClick={onDevRebuildRifts}
              className="px-2 py-1 bg-slate-900 hover:bg-slate-800 border border-cyan-500/40 text-cyan-300 rounded-[4px]">
              REBUILD RIFTS
            </button>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              onClick={onDevLock}
              className="px-2.5 py-1 bg-red-950 hover:bg-red-900 border border-red-500/60 text-red-300 rounded-[4px] font-bold flex items-center gap-1">
              <Lock size={12} />
              LOCK
            </button>
            <button
              onClick={() => setIsDevDrawerOpen(false)}
              className="p-1 text-slate-400 hover:text-white">
              <X size={16} />
            </button>
          </div>
        </div>
      )}

      {/* 
        ========================================================================
        SCREEN 02: DEV AUTHENTICATION MODAL (12px chamfered, centered)
        ========================================================================
      */}
      {isAuthModalOpen && (
        <div className="pointer-events-auto fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md">
          <div
            className={`w-[480px] p-6 rounded-[12px] flex flex-col gap-4 text-left transition-transform ${
              authError ? 'animate-shake border-red-500 shadow-[0_0_30px_rgba(239,68,68,0.4)]' : 'border-amber-500 shadow-[0_0_30px_rgba(251,191,36,0.3)]'
            }`}
            style={{
              backgroundColor: 'rgba(8, 12, 22, 0.96)',
              border: `1px solid ${authError ? '#ef4444' : '#fbbf24'}`,
            }}>
            {/* Header */}
            <div className="flex items-start justify-between border-b border-slate-800 pb-3">
              <div>
                <span className="text-[11px] text-amber-400 font-sans tracking-[0.08em] font-bold block">
                  // RESTRICTED ACCESS
                </span>
                <h3 className="text-base font-bold text-white font-mono flex items-center gap-2 mt-0.5">
                  <Terminal size={16} className="text-amber-400" />
                  // RESTRICTED CONSOLE // AUTHENTICATION REQUIRED
                </h3>
              </div>
              <button
                onClick={() => setIsAuthModalOpen(false)}
                className="text-slate-400 hover:text-white p-1">
                <X size={18} />
              </button>
            </div>

            {/* Input Form */}
            <form
              onSubmit={(e) => {
                e.preventDefault();
                handleAuthSubmit(e);
              }}
              className="flex flex-col gap-3">
              <label className="text-xs text-slate-400 font-sans tracking-[0.08em] uppercase font-bold">
                SECURITY CODE:
              </label>
              <input
                ref={authInputRef}
                type="password"
                autoFocus
                value={authInput}
                onChange={(e) => setAuthInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    e.stopPropagation();
                    handleAuthSubmit();
                  }
                }}
                placeholder="ENTER ACCESS CODE..."
                autoComplete="off"
                spellCheck={false}
                className="w-full px-3 py-2 bg-[#040711] border border-amber-500/50 rounded-[6px] text-amber-300 font-mono tracking-wider text-sm focus:outline-none focus:border-amber-400"
              />

              {/* Status Badge */}
              {authSuccess && (
                <div className="p-2 bg-emerald-950/80 border border-emerald-500 text-emerald-300 rounded-[6px] text-xs font-bold text-center">
                  ACCESS GRANTED // INITIALIZING CONSOLE...
                </div>
              )}
              {authError && (
                <div className="p-2 bg-red-950/80 border border-red-500 text-red-300 rounded-[6px] text-xs font-bold text-center">
                  ACCESS DENIED // INVALID AUTHORIZATION CODE
                </div>
              )}

              {/* Buttons */}
              <div className="flex items-center gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => handleAuthSubmit()}
                  className="flex-1 py-2 rounded-[6px] bg-[#fbbf24] hover:bg-amber-300 text-black font-bold text-xs font-sans tracking-[0.08em] uppercase transition-colors">
                  AUTHORISE [ENTER]
                </button>
                <button
                  type="button"
                  onClick={() => setIsAuthModalOpen(false)}
                  className="px-4 py-2 rounded-[6px] bg-slate-900 hover:bg-slate-800 border border-slate-700 text-slate-300 text-xs font-sans tracking-[0.08em] uppercase transition-colors">
                  [ESC] cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* 
        ========================================================================
        SCREEN 01: MAP OVERLAYS (Pan & Zoom info, Vertical Pill, Sector tag)
        ========================================================================
      */}
      {/* Bottom-left Pan info */}
      <div className="pointer-events-none absolute bottom-3 left-4 text-[10px] text-[#94a3b8] font-sans tracking-[0.08em] z-10">
        Drag or arrow keys to pan — scroll to zoom
      </div>

      {/* Right side Zoom Controls Vertical Pill */}
      <div
        className="pointer-events-auto absolute right-4 bottom-[154px] flex flex-col items-center gap-1 p-1 rounded-[8px] z-20"
        style={{
          backgroundColor: 'rgba(8, 12, 22, 0.92)',
          backdropFilter: 'blur(16px)',
          border: '1px solid rgba(0, 240, 255, 0.3)',
        }}>
        <div className="text-[10px] font-bold text-[#00f0ff] px-1 py-0.5 tabular-nums">
          {Math.round(cameraZoom * 100)}%
        </div>
        <button
          onClick={onZoomIn}
          title="Zoom In (+)"
          className="w-7 h-7 rounded-[4px] hover:bg-cyan-950/60 text-[#00f0ff] flex items-center justify-center font-bold text-sm">
          +
        </button>
        <button
          onClick={onZoomOut}
          title="Zoom Out (-)"
          className="w-7 h-7 rounded-[4px] hover:bg-cyan-950/60 text-[#00f0ff] flex items-center justify-center font-bold text-sm">
          -
        </button>
        <button
          onClick={onFitCamera}
          title="Fit to Screen"
          className="w-7 h-7 rounded-[4px] hover:bg-cyan-950/60 text-[#00f0ff] flex items-center justify-center text-[9px] font-bold uppercase">
          fit
        </button>
        <button
          onClick={onResetZoom}
          title="1:1 Reset"
          className="w-7 h-7 rounded-[4px] hover:bg-cyan-950/60 text-[#00f0ff] flex items-center justify-center text-[9px] font-bold uppercase">
          1:1
        </button>
      </div>

      {/* Bottom-right Sector tag */}
      <div className="pointer-events-none absolute bottom-3 right-4 text-[10px] text-[#94a3b8] font-sans tracking-[0.08em] z-10">
        SECTOR X 128 - Y 128 - v1.0
      </div>

      {/* 
        ========================================================================
        SCREEN 01: BOTTOM UNIFIED DOCK (Height 136px, responsive)
        Divided into 3 integrated panels:
        - Panel A: BUILD TRAY
        - Panel B: COMBAT (EMP, Overclock, Start Wave)
        - Panel C: >_ TACTICAL TERMINAL (Inspector)
        ========================================================================
      */}
      <footer
        className="pointer-events-auto absolute bottom-0 left-0 right-0 h-[136px] px-4 flex items-center justify-between gap-3 z-30 overflow-hidden"
        style={{
          backgroundColor: 'rgba(8, 12, 22, 0.92)',
          backdropFilter: 'blur(16px)',
          borderTop: '1px solid rgba(0, 240, 255, 0.3)',
        }}>
        {/* PANEL A: BUILD TRAY */}
        <div className="flex items-center gap-2 overflow-x-auto shrink-0 pr-2 border-r border-slate-800">
          {/* 0. Free Cursor / Deselect Button */}
          <button
            onClick={() => onSelectBuildType(null)}
            className={`w-[84px] h-[116px] p-2 rounded-[6px] border flex flex-col justify-between items-center text-center transition-all ${
              selectedBuildType === null
                ? 'bg-cyan-950/80 border-[#00f0ff] text-[#00f0ff] shadow-[0_0_12px_rgba(0,240,255,0.4)] ring-1 ring-[#00f0ff]'
                : 'bg-[#0a0f1d] hover:bg-[#0c1428] border-slate-700/60 text-slate-400 hover:text-slate-200'
            }`}
            title="Free Cursor Mode (Navigate, Inspect, or Cancel Placement) [X/C/ESC]">
            <div className="flex items-center justify-between w-full">
              <span className={`text-[9px] font-bold font-sans tracking-[0.08em] ${selectedBuildType === null ? 'text-[#00f0ff]' : 'text-slate-400'}`}>
                FREE
              </span>
              <span className="text-[8px] text-slate-500 font-mono">[X]</span>
            </div>
            <div className="flex flex-col items-center justify-center my-1">
              <Crosshair size={26} className={selectedBuildType === null ? 'text-[#00f0ff] animate-pulse' : 'text-slate-400'} />
            </div>
            <div className="w-full">
              <div className={`text-[10px] font-bold font-sans tracking-[0.05em] uppercase ${selectedBuildType === null ? 'text-[#00f0ff]' : 'text-slate-300'}`}>
                {selectedBuildType === null ? 'ACTIVE' : 'DESELECT'}
              </div>
              <div className="text-[8px] text-slate-400 font-mono">Cursor</div>
            </div>
          </button>

          {/* 1. Laser Turret */}
          <button
            onClick={() => onSelectBuildType(selectedBuildType === 'basic' ? null : 'basic')}
            disabled={credits < 100}
            className={`w-[110px] h-[116px] p-2 rounded-[6px] border flex flex-col justify-between text-left transition-all ${
              selectedBuildType === 'basic'
                ? 'bg-cyan-950/80 border-[#00f0ff] shadow-[0_0_12px_rgba(0,240,255,0.4)] ring-1 ring-[#00f0ff]'
                : credits < 100
                ? 'bg-[#080d1a]/50 border-slate-800 opacity-35 cursor-not-allowed'
                : 'bg-[#0a0f1d] hover:bg-[#0c1428] border-cyan-500/40 text-slate-200'
            }`}>
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-[#00f0ff] font-sans tracking-[0.08em]">LASER</span>
              <span className="text-[9px] text-slate-400 font-mono">[Q]</span>
            </div>
            <div className="flex justify-center my-1">
              <TurretSilhouette type="basic" className="w-8 h-8" />
            </div>
            <div>
              <div className={`text-xs font-bold font-mono ${credits < 100 ? 'text-[#ef4444]' : 'text-[#fbbf24]'}`}>
                $100
              </div>
              <div className="text-[9px] text-[#00f0ff] font-mono">20.0 DPS</div>
            </div>
          </button>

          {/* 2. Rapid Pulse */}
          <button
            onClick={() => onSelectBuildType(selectedBuildType === 'rapid' ? null : 'rapid')}
            disabled={credits < 130}
            className={`w-[110px] h-[116px] p-2 rounded-[6px] border flex flex-col justify-between text-left transition-all ${
              selectedBuildType === 'rapid'
                ? 'bg-amber-950/80 border-[#fbbf24] shadow-[0_0_12px_rgba(251,191,36,0.4)] ring-1 ring-[#fbbf24]'
                : credits < 130
                ? 'bg-[#080d1a]/50 border-slate-800 opacity-35 cursor-not-allowed'
                : 'bg-[#0a0f1d] hover:bg-[#0c1428] border-amber-500/40 text-slate-200'
            }`}>
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-[#fbbf24] font-sans tracking-[0.08em]">RAPID</span>
              <span className="text-[9px] text-slate-400 font-mono">[W]</span>
            </div>
            <div className="flex justify-center my-1">
              <TurretSilhouette type="rapid" className="w-8 h-8" />
            </div>
            <div>
              <div className={`text-xs font-bold font-mono ${credits < 130 ? 'text-[#ef4444]' : 'text-[#fbbf24]'}`}>
                $130
              </div>
              <div className="text-[9px] text-[#fbbf24] font-mono">30.0 DPS</div>
            </div>
          </button>

          {/* 3. Railgun Sniper */}
          <button
            onClick={() => onSelectBuildType(selectedBuildType === 'sniper' ? null : 'sniper')}
            disabled={credits < 220}
            className={`w-[110px] h-[116px] p-2 rounded-[6px] border flex flex-col justify-between text-left transition-all ${
              selectedBuildType === 'sniper'
                ? 'bg-purple-950/80 border-[#c084fc] shadow-[0_0_12px_rgba(192,132,252,0.4)] ring-1 ring-[#c084fc]'
                : credits < 220
                ? 'bg-[#080d1a]/50 border-slate-800 opacity-35 cursor-not-allowed'
                : 'bg-[#0a0f1d] hover:bg-[#0c1428] border-purple-500/40 text-slate-200'
            }`}>
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-[#c084fc] font-sans tracking-[0.08em]">RAILGUN</span>
              <span className="text-[9px] text-slate-400 font-mono">[E]</span>
            </div>
            <div className="flex justify-center my-1">
              <TurretSilhouette type="sniper" className="w-8 h-8" />
            </div>
            <div>
              <div className={`text-xs font-bold font-mono ${credits < 220 ? 'text-[#ef4444]' : 'text-[#fbbf24]'}`}>
                $220
              </div>
              <div className="text-[9px] text-[#c084fc] font-mono">36.7 DPS</div>
            </div>
          </button>

          {/* 4. Tesla Arc */}
          <button
            onClick={() => onSelectBuildType(selectedBuildType === 'arc' ? null : 'arc')}
            disabled={credits < 240}
            className={`w-[110px] h-[116px] p-2 rounded-[6px] border flex flex-col justify-between text-left transition-all ${
              selectedBuildType === 'arc'
                ? 'bg-blue-950/80 border-[#2563eb] shadow-[0_0_12px_rgba(37,99,235,0.4)] ring-1 ring-[#2563eb]'
                : credits < 240
                ? 'bg-[#080d1a]/50 border-slate-800 opacity-35 cursor-not-allowed'
                : 'bg-[#0a0f1d] hover:bg-[#0c1428] border-blue-500/40 text-slate-200'
            }`}>
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-[#60a5fa] font-sans tracking-[0.08em]">TESLA ARC</span>
              <span className="text-[9px] text-slate-400 font-mono">[R]</span>
            </div>
            <div className="flex justify-center my-1">
              <TurretSilhouette type="arc" className="w-8 h-8" />
            </div>
            <div>
              <div className={`text-xs font-bold font-mono ${credits < 240 ? 'text-[#ef4444]' : 'text-[#fbbf24]'}`}>
                $240
              </div>
              <div className="text-[9px] text-[#60a5fa] font-mono">14.1 DPS</div>
            </div>
          </button>

          {/* 5. Repair Core */}
          <button
            onClick={onRepairCore}
            disabled={coreLives >= 20 || credits < repairCost}
            className={`w-[110px] h-[116px] p-2 rounded-[6px] border flex flex-col justify-between text-left transition-all ${
              coreLives >= 20 || credits < repairCost
                ? 'bg-[#080d1a]/50 border-slate-800 opacity-35 cursor-not-allowed'
                : 'bg-[#0a0f1d] hover:bg-emerald-950/40 border-emerald-500/40 text-emerald-300'
            }`}>
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-[#10b981] font-sans tracking-[0.08em]">REPAIR</span>
              <Wrench size={12} className="text-[#10b981]" />
            </div>
            <div className="flex justify-center my-1">
              <Heart size={26} className="text-[#10b981] fill-emerald-950/60" />
            </div>
            <div>
              <div className={`text-xs font-bold font-mono ${credits < repairCost ? 'text-[#ef4444]' : 'text-[#fbbf24]'}`}>
                ${repairCost}
              </div>
              <div className="text-[9px] text-[#10b981] font-mono">+1 Life</div>
            </div>
          </button>
        </div>

        {/* PANEL B: COMBAT */}
        <div className="flex items-center gap-2.5 shrink-0 px-2 border-r border-slate-800">
          {/* EMP [1/F] */}
          <button
            onClick={onTriggerEMP}
            disabled={energy < 40}
            className={`w-[115px] h-[116px] p-2.5 rounded-[6px] border flex flex-col justify-between relative overflow-hidden transition-all text-left ${
              energy >= 40
                ? 'bg-[#0a0f1d] hover:bg-cyan-950/60 border-[#00f0ff]/60 text-cyan-200 shadow-[0_0_10px_rgba(0,240,255,0.2)]'
                : 'bg-[#0a0f1d]/50 border-slate-800 text-slate-500 cursor-not-allowed'
            }`}>
            {/* Diagonal striped recharge fill when NRG < 40 */}
            {energy < 40 && (
              <div
                className="absolute inset-0 opacity-15 pointer-events-none"
                style={{
                  backgroundImage:
                    'repeating-linear-gradient(45deg, #00f0ff 0, #00f0ff 8px, transparent 8px, transparent 16px)',
                }}
              />
            )}
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold font-sans tracking-[0.08em] text-[#00f0ff]">EMP</span>
              <span className="text-[9px] text-slate-400 font-mono">[1/F]</span>
            </div>
            <div className="flex justify-center my-1">
              <Zap size={28} className={energy >= 40 ? 'text-[#00f0ff] fill-[#00f0ff]/30' : 'text-slate-600'} />
            </div>
            <div>
              <div className="text-[10px] font-mono text-cyan-300">
                {energy < 40 ? `${energy}/40 NRG` : 'READY (40)'}
              </div>
              <div className="text-[9px] text-slate-400">4s Area Freeze</div>
            </div>
          </button>

          {/* OVERCLOCK [2/V] */}
          <button
            onClick={onTriggerOverclock}
            disabled={energy < 25 || overclockActive}
            className={`w-[115px] h-[116px] p-2.5 rounded-[6px] border flex flex-col justify-between relative overflow-hidden transition-all text-left ${
              overclockActive
                ? 'bg-pink-950/80 border-[#ec4899] text-pink-200 shadow-[0_0_12px_rgba(236,72,153,0.4)]'
                : energy >= 25
                ? 'bg-[#0a0f1d] hover:bg-pink-950/50 border-[#ec4899]/60 text-pink-200'
                : 'bg-[#0a0f1d]/50 border-slate-800 text-slate-500 cursor-not-allowed'
            }`}>
            {/* Striped recharge when NRG < 25 */}
            {energy < 25 && !overclockActive && (
              <div
                className="absolute inset-0 opacity-15 pointer-events-none"
                style={{
                  backgroundImage:
                    'repeating-linear-gradient(45deg, #ec4899 0, #ec4899 8px, transparent 8px, transparent 16px)',
                }}
              />
            )}
            {/* Draining sweep bar along bottom edge during active 10s */}
            {overclockActive && (
              <div
                className="absolute bottom-0 left-0 h-1 bg-[#ec4899] transition-all duration-100"
                style={{width: `${(overclockTimeLeft / 10) * 100}%`}}
              />
            )}
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold font-sans tracking-[0.08em] text-[#ec4899]">OVERCLOCK</span>
              <span className="text-[9px] text-slate-400 font-mono">[2/V]</span>
            </div>
            <div className="flex justify-center my-1">
              <TrendingUp size={28} className={overclockActive ? 'text-white animate-pulse' : energy >= 25 ? 'text-[#ec4899]' : 'text-slate-600'} />
            </div>
            <div>
              <div className="text-[10px] font-mono text-pink-300">
                {overclockActive ? `${Math.ceil(overclockTimeLeft)}s ACTIVE` : energy < 25 ? `${energy}/25 NRG` : 'READY (25)'}
              </div>
              <div className="text-[9px] text-slate-400">2x Fire Rate (10s)</div>
            </div>
          </button>

          {/* START WAVE / STATUS */}
          {isPrepPhase ? (
            <button
              onClick={onStartWave}
              className={`w-[130px] h-[116px] p-2.5 rounded-[6px] border flex flex-col justify-between text-left transition-all ${
                prepTimer < 5
                  ? 'bg-emerald-950/90 border-[#10b981] shadow-[0_0_15px_rgba(16,185,129,0.5)] animate-pulse'
                  : 'bg-emerald-950/70 hover:bg-emerald-900/80 border-[#10b981]/70'
              } text-emerald-200`}>
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-bold font-sans tracking-[0.08em] text-[#10b981]">START WAVE</span>
                <Play size={12} className="fill-current text-[#10b981]" />
              </div>
              <div className="my-1">
                <div className="text-2xl font-black font-mono text-[#10b981] tabular-nums">
                  {Math.ceil(prepTimer)}s
                </div>
                <div className="text-[9px] text-emerald-400/80">Prep Phase</div>
              </div>
              <div className="text-[10px] font-mono font-bold text-amber-300">
                [SPACE +$20]
              </div>
            </button>
          ) : (
            <div className="w-[130px] h-[116px] p-2.5 rounded-[6px] border border-amber-500/50 bg-amber-950/30 flex flex-col justify-between text-left text-amber-300">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-bold font-sans tracking-[0.08em]">ENGAGED</span>
                <Crosshair size={14} className="text-amber-400 animate-spin" style={{animationDuration: '4s'}} />
              </div>
              <div className="my-1">
                <div className="text-xs font-bold text-white font-mono">WAVE {wave}</div>
                <div className="text-[10px] text-amber-400">{enemyCount} Hostiles</div>
              </div>
              <div className="text-[9px] text-slate-400 font-mono">Combat in progress</div>
            </div>
          )}
        </div>

        {/* PANEL C: >_ TACTICAL TERMINAL (Inspector) */}
        <div className="flex-1 min-w-[280px] max-w-[420px] h-[116px] p-2.5 rounded-[6px] bg-[#070b16] border border-cyan-500/30 flex flex-col justify-between text-xs font-mono">
          {selectedTower ? (
            <>
              {/* Header: Unit name & level */}
              <div className="flex items-center justify-between border-b border-slate-800 pb-1">
                <span className="text-[#00f0ff] font-bold font-sans tracking-[0.08em] flex items-center gap-1.5">
                  <TurretSilhouette type={selectedTower.type} className="w-4 h-4" />
                  {selectedTower.type.toUpperCase()} TURRET LV {selectedTower.level}
                </span>
                <span className="text-[10px] text-slate-400">
                  {selectedTower.hardpointId ? 'HARDPOINT' : 'OPEN GRID'}
                </span>
              </div>
              {/* Stat matrix */}
              <div className="grid grid-cols-4 gap-1 text-[10px] py-1 text-slate-300">
                <div>
                  <span className="text-[#94a3b8] block">DPS</span>
                  <span className="text-cyan-300 font-bold font-mono">20.0</span>
                </div>
                <div>
                  <span className="text-[#94a3b8] block">RANGE</span>
                  <span className="text-cyan-300 font-bold font-mono">180</span>
                </div>
                <div>
                  <span className="text-[#94a3b8] block">KILLS</span>
                  <span className="text-slate-100 font-bold font-mono">{selectedTower.kills}</span>
                </div>
                <div>
                  <span className="text-[#94a3b8] block">DEALT</span>
                  <span className="text-slate-100 font-bold font-mono">{Math.round(selectedTower.damageDealt)}</span>
                </div>
              </div>
              {/* Actions */}
              <div className="flex items-center gap-2 pt-1 border-t border-slate-800">
                <button
                  onClick={() => onUpgradeTower(selectedTower)}
                  disabled={selectedTower.level >= 10 || credits < getTowerUpgradeCost(selectedTower.type, selectedTower.level)}
                  className={`flex-1 py-1 rounded-[4px] text-[10px] font-bold font-sans tracking-[0.08em] uppercase transition-colors ${
                    selectedTower.level >= 10
                      ? 'bg-slate-900 text-slate-600 border border-slate-800 cursor-not-allowed'
                      : credits < getTowerUpgradeCost(selectedTower.type, selectedTower.level)
                      ? 'bg-slate-900 text-slate-600 border border-slate-800 cursor-not-allowed'
                      : 'bg-amber-950/80 hover:bg-amber-900 border border-[#fbbf24] text-[#fbbf24]'
                  }`}>
                  {selectedTower.level >= 10 ? 'MAX LV' : `UPGRADE $${getTowerUpgradeCost(selectedTower.type, selectedTower.level)} [U]`}
                </button>
                <button
                  onClick={() => onSellTower(selectedTower)}
                  className="px-3 py-1 rounded-[4px] bg-red-950/80 hover:bg-red-900 border border-red-500/60 text-red-300 text-[10px] font-bold font-sans tracking-[0.08em] uppercase">
                  SELL +${Math.floor(selectedTower.totalInvested * 0.7)} [S]
                </button>
              </div>
            </>
          ) : isCoreSelected ? (
            <>
              {/* Core Inspector */}
              <div className="flex items-center justify-between border-b border-slate-800 pb-1">
                <span className="text-[#10b981] font-bold font-sans tracking-[0.08em] flex items-center gap-1.5">
                  <Shield size={14} className="text-[#10b981]" />
                  NEXUS CORE LV {coreTurretLevel}
                </span>
                <span className="text-[10px] text-emerald-400">ZONE 0 SANCTUM</span>
              </div>
              <div className="grid grid-cols-4 gap-1 text-[10px] py-1 text-slate-300">
                <div>
                  <span className="text-[#94a3b8] block">DPS</span>
                  <span className="text-emerald-300 font-bold font-mono">25.0</span>
                </div>
                <div>
                  <span className="text-[#94a3b8] block">RANGE</span>
                  <span className="text-cyan-300 font-bold font-mono">180</span>
                </div>
                <div>
                  <span className="text-[#94a3b8] block">CORE LIVES</span>
                  <span className="text-emerald-400 font-bold font-mono">{coreLives}/20</span>
                </div>
                <div>
                  <span className="text-[#94a3b8] block">GATES</span>
                  <span className="text-cyan-300 font-bold font-mono">6 ONLINE</span>
                </div>
              </div>
              <div className="flex items-center gap-2 pt-1 border-t border-slate-800">
                <button
                  onClick={onUpgradeCore}
                  disabled={coreTurretLevel >= 10 || credits < Math.floor(120 * coreTurretLevel)}
                  className="flex-1 py-1 rounded-[4px] bg-emerald-950/80 hover:bg-emerald-900 border border-emerald-500 text-emerald-300 text-[10px] font-bold font-sans tracking-[0.08em] uppercase transition-colors">
                  {coreTurretLevel >= 10 ? 'MAX TURRET' : `UPGRADE CORE $${Math.floor(120 * coreTurretLevel)} [U]`}
                </button>
                <button
                  onClick={onRepairCore}
                  disabled={coreLives >= 20 || credits < repairCost}
                  className="px-3 py-1 rounded-[4px] bg-amber-950/80 hover:bg-amber-900 border border-amber-500 text-amber-300 text-[10px] font-bold font-sans tracking-[0.08em] uppercase">
                  REPAIR ${repairCost}
                </button>
              </div>
            </>
          ) : selectedHardpoint && !selectedHardpoint.tower ? (
            <>
              {/* Empty Hardpoint Socket Inspector */}
              <div className="flex items-center justify-between border-b border-slate-800 pb-1">
                <span className="text-[#00f0ff] font-bold font-sans tracking-[0.08em] flex items-center gap-1.5">
                  <Target size={14} className="text-[#00f0ff]" />
                  {selectedHardpoint.isCoreHardpoint ? 'CORE SOCKET' : 'MICRO SOCKET'} #{selectedHardpoint.id}
                </span>
                <span className="text-[10px] text-amber-400 font-bold">UNOCCUPIED</span>
              </div>
              <div className="py-1 text-[11px] text-slate-300 leading-relaxed">
                {selectedHardpoint.isCoreHardpoint
                  ? 'Zone 0 Reinforced Hardpoint (+6% Range, +8% Damage, -5% CD). Select a turret below to deploy.'
                  : 'Tactical Micro Socket on defense perimeter. Select a turret below to deploy.'}
              </div>
              <div className="flex items-center justify-between text-[10px] text-[#94a3b8] pt-1 border-t border-slate-800">
                <span className="text-cyan-300 font-mono">STATUS: READY FOR MOUNT</span>
                <button
                  onClick={onDeselect}
                  className="text-slate-400 hover:text-white underline text-[9px]">
                  [DESELECT]
                </button>
              </div>
            </>
          ) : selectedGateIndex !== null ? (
            <>
              {/* Core Gate Inspector */}
              <div className="flex items-center justify-between border-b border-slate-800 pb-1">
                <span className="text-[#10b981] font-bold font-sans tracking-[0.08em] flex items-center gap-1.5">
                  <Shield size={14} className="text-[#10b981]" />
                  GATE G{selectedGateIndex + 1} // AIRLOCK CHOKEPOINT
                </span>
                <span className="text-[10px] text-emerald-300 font-bold">ONLINE</span>
              </div>
              <div className="py-1 text-[11px] text-slate-300 leading-relaxed">
                Zone 0 perimeter airlock funneling hostiles directly toward the Nexus Core. Open cell placement prohibited in Zone 0.
              </div>
              <div className="flex items-center justify-between text-[10px] text-[#94a3b8] pt-1 border-t border-slate-800">
                <span className="text-emerald-400">PERIMETER SECTOR ONLINE</span>
                <button
                  onClick={onDeselect}
                  className="text-slate-400 hover:text-white underline text-[9px]">
                  [DESELECT]
                </button>
              </div>
            </>
          ) : (
            <>
              {/* Ready / Free Cursor / Primed state */}
              <div className="flex items-center justify-between border-b border-slate-800 pb-1">
                <span className="text-[#00f0ff] font-bold font-sans tracking-[0.08em] flex items-center gap-1.5">
                  <Terminal size={14} className="text-[#00f0ff]" />
                  {selectedBuildType === null
                    ? '&gt;_ TACTICAL TERMINAL // SELECT A UNIT OR SOCKET'
                    : `&gt;_ TACTICAL TERMINAL // PRIMED: ${selectedBuildType.toUpperCase()}`}
                </span>
                <span className={`text-[10px] flex items-center gap-1 font-bold ${selectedBuildType === null ? 'text-emerald-400' : 'text-amber-400'}`}>
                  <span className={`w-1.5 h-1.5 rounded-full ${selectedBuildType === null ? 'bg-emerald-400 animate-pulse' : 'bg-amber-400 animate-ping'}`} />
                  {selectedBuildType === null ? 'FREE CURSOR' : 'CONSTRUCT'}
                </span>
              </div>
              <div className="py-1 text-[11px] text-slate-300 leading-relaxed">
                {selectedBuildType === null
                  ? 'Cursor is in free navigation mode. Click any turret, socket, core, or gate to inspect without building.'
                  : `Placement primed: Click an open cell or empty socket to construct ${TOWER_SPECS[selectedBuildType]?.name || selectedBuildType}. [Right-Click or ESC to Cancel]`}
              </div>
              <div className="flex items-center justify-between text-[10px] text-[#94a3b8] pt-1 border-t border-slate-800">
                <span>[Q][W][E][R] Build</span>
                <span>[X/C] Free Cursor</span>
                <span>[U] Upgr</span>
                <span>[S] Sell</span>
              </div>
            </>
          )}
        </div>
      </footer>

      {/* 
        ========================================================================
        SCREENS 03 TO 06: MENU MODAL (880x600, game paused)
        ========================================================================
      */}
      {isMenuOpen && (
        <div className="pointer-events-auto fixed inset-0 z-50 flex items-center justify-center bg-black/85 backdrop-blur-md">
          <div
            className="w-[880px] h-[600px] rounded-[12px] p-6 flex flex-col justify-between text-left text-xs font-mono shadow-[0_0_50px_rgba(0,240,255,0.25)] relative"
            style={{
              backgroundColor: 'rgba(8, 12, 22, 0.96)',
              backdropFilter: 'blur(16px)',
              border: '1px solid rgba(0, 240, 255, 0.5)',
            }}>
            {/* Modal Header */}
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <div className="flex items-center gap-2">
                <div className="w-2.5 h-2.5 rounded-full bg-[#00f0ff] animate-pulse" />
                <h2 className="text-sm font-bold text-[#00f0ff] font-sans tracking-[0.08em]">
                  // SIMULATION PAUSED // SYSTEM TERMINAL // TACTICAL ARCHIVE
                </h2>
              </div>
              <button
                onClick={() => setIsMenuOpen(false)}
                className="px-2.5 py-1 rounded-[4px] bg-slate-900 hover:bg-slate-800 text-slate-300 hover:text-white border border-slate-700 font-sans tracking-[0.08em] text-xs">
                [ESC] ✕
              </button>
            </div>

            {/* Horizontal Segmented Tabs */}
            <div className="flex items-center gap-2 border-b border-slate-800 py-2.5">
              <button
                onClick={() => setMenuTab('directives')}
                className={`px-4 py-1.5 rounded-[6px] font-sans tracking-[0.08em] font-bold text-xs transition-all ${
                  menuTab === 'directives'
                    ? 'bg-cyan-950/80 border border-[#00f0ff] text-[#00f0ff] shadow-[0_0_10px_rgba(0,240,255,0.3)]'
                    : 'bg-slate-900/60 hover:bg-slate-800 text-slate-400 border border-slate-800'
                }`}>
                ◈ DIRECTIVES
              </button>
              <button
                onClick={() => setMenuTab('codex')}
                className={`px-4 py-1.5 rounded-[6px] font-sans tracking-[0.08em] font-bold text-xs transition-all ${
                  menuTab === 'codex'
                    ? 'bg-cyan-950/80 border border-[#00f0ff] text-[#00f0ff] shadow-[0_0_10px_rgba(0,240,255,0.3)]'
                    : 'bg-slate-900/60 hover:bg-slate-800 text-slate-400 border border-slate-800'
                }`}>
                ⬡ CODEX
              </button>
              <button
                onClick={() => setMenuTab('systems')}
                className={`px-4 py-1.5 rounded-[6px] font-sans tracking-[0.08em] font-bold text-xs transition-all ${
                  menuTab === 'systems'
                    ? 'bg-cyan-950/80 border border-[#00f0ff] text-[#00f0ff] shadow-[0_0_10px_rgba(0,240,255,0.3)]'
                    : 'bg-slate-900/60 hover:bg-slate-800 text-slate-400 border border-slate-800'
                }`}>
                ⚙ SYSTEMS
              </button>
              <button
                onClick={() => setMenuTab('reboot')}
                className={`px-4 py-1.5 rounded-[6px] font-sans tracking-[0.08em] font-bold text-xs transition-all ${
                  menuTab === 'reboot'
                    ? 'bg-red-950/80 border border-red-500 text-red-400 shadow-[0_0_10px_rgba(239,68,68,0.3)]'
                    : 'bg-slate-900/60 hover:bg-slate-800 text-slate-400 border border-slate-800'
                }`}>
                ⟲ REBOOT
              </button>
            </div>

            {/* Modal Body: Switch between Screens 03, 04, 05, 06 */}
            <div className="flex-1 overflow-y-auto py-3 pr-1">
              {/* 
                SCREEN 03: DIRECTIVES (Left: 01-06 Rules, Right: Hotkeys + Note)
              */}
              {menuTab === 'directives' && (
                <div className="grid grid-cols-2 gap-6 h-full">
                  {/* Left Column: Core Rules 01-06 */}
                  <div className="space-y-2.5">
                    <span className="text-[11px] text-[#00f0ff] font-sans tracking-[0.08em] font-bold block uppercase border-b border-cyan-900/50 pb-1">
                      CORE RULES &amp; DIRECTIVES
                    </span>
                    <div className="space-y-2 text-[11px] text-slate-300">
                      <div className="p-2 rounded-[6px] bg-[#0c1220] border border-slate-800">
                        <b className="text-emerald-400">01</b> Defend the Nexus Core. Each enemy that reaches it costs one life. Zero lives ends the run.
                      </div>
                      <div className="p-2 rounded-[6px] bg-[#0c1220] border border-slate-800">
                        <b className="text-emerald-400">02</b> Enemies spawn from rift zones and head for the core along designated conduits.
                      </div>
                      <div className="p-2 rounded-[6px] bg-[#0c1220] border border-slate-800">
                        <b className="text-emerald-400">03</b> Build turrets on hardpoints. Kills pay credits back.
                      </div>
                      <div className="p-2 rounded-[6px] bg-[#0c1220] border border-slate-800">
                        <b className="text-emerald-400">04</b> Repair Core restores one life for $100.
                      </div>
                      <div className="p-2 rounded-[6px] bg-[#0c1220] border border-slate-800">
                        <b className="text-emerald-400">05</b> The reactor refills at 3.5 NRG per second. EMP costs 40, Overclock 25.
                      </div>
                      <div className="p-2 rounded-[6px] bg-[#0c1220] border border-slate-800">
                        <b className="text-emerald-400">06</b> Call a wave early for a flat +$20 credit bounty.
                      </div>
                    </div>
                  </div>

                  {/* Right Column: Hotkey Index & Note Banner */}
                  <div className="flex flex-col justify-between space-y-3">
                    <div>
                      <span className="text-[11px] text-[#00f0ff] font-sans tracking-[0.08em] font-bold block uppercase border-b border-cyan-900/50 pb-1 mb-2">
                        HOTKEY INDEX
                      </span>
                      <div className="grid grid-cols-2 gap-2 text-[10.5px]">
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between">
                          <span className="text-[#94a3b8]">[1][F]</span>
                          <span className="text-cyan-300 font-bold">EMP blast</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between">
                          <span className="text-[#94a3b8]">[2][V]</span>
                          <span className="text-pink-300 font-bold">Overclock</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between col-span-2">
                          <span className="text-[#94a3b8]">[SPACE]</span>
                          <span className="text-emerald-300 font-bold">Start wave early (+$20)</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between col-span-2">
                          <span className="text-[#94a3b8]">[Q][W][E][R]</span>
                          <span className="text-slate-200">Laser, Rapid, Railgun, Tesla</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between">
                          <span className="text-[#94a3b8]">[U]</span>
                          <span className="text-amber-300 font-bold">Upgrade selected</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between">
                          <span className="text-[#94a3b8]">[S]</span>
                          <span className="text-red-300 font-bold">Sell selected</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between">
                          <span className="text-[#94a3b8]">[ARROWS]</span>
                          <span className="text-slate-300">Pan map (or drag)</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between">
                          <span className="text-[#94a3b8]">[SCROLL]</span>
                          <span className="text-slate-300">Zoom map</span>
                        </div>
                        <div className="p-1.5 bg-[#0c1220] rounded border border-slate-800 flex justify-between col-span-2">
                          <span className="text-[#94a3b8]">[ESC]</span>
                          <span className="text-slate-300">Menu, back, resume</span>
                        </div>
                      </div>
                    </div>

                    {/* Note Banner */}
                    <div className="p-2.5 rounded-[6px] bg-cyan-950/30 border border-cyan-500/40 text-cyan-300 text-[10.5px] italic">
                      "While paused only ESC works. Every other hotkey is ignored."
                    </div>
                  </div>
                </div>
              )}

              {/* 
                SCREEN 04: CODEX (Sub-filters: Core Command, Turrets, Hostiles)
              */}
              {menuTab === 'codex' && (
                <div className="flex flex-col h-full gap-3">
                  {/* Sub-filter pills */}
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setCodexSubTab('command')}
                      className={`px-3 py-1 rounded-[4px] text-xs font-sans tracking-[0.08em] font-bold ${
                        codexSubTab === 'command'
                          ? 'bg-[#00f0ff] text-black'
                          : 'bg-slate-900 text-slate-400 hover:text-white'
                      }`}>
                      [CORE COMMAND]
                    </button>
                    <button
                      onClick={() => {
                        setCodexSubTab('turrets');
                        setSelectedCodexItem('basic');
                      }}
                      className={`px-3 py-1 rounded-[4px] text-xs font-sans tracking-[0.08em] font-bold ${
                        codexSubTab === 'turrets'
                          ? 'bg-[#00f0ff] text-black'
                          : 'bg-slate-900 text-slate-400 hover:text-white'
                      }`}>
                      [TURRETS]
                    </button>
                    <button
                      onClick={() => {
                        setCodexSubTab('hostiles');
                        setSelectedCodexItem('basic');
                      }}
                      className={`px-3 py-1 rounded-[4px] text-xs font-sans tracking-[0.08em] font-bold ${
                        codexSubTab === 'hostiles'
                          ? 'bg-[#00f0ff] text-black'
                          : 'bg-slate-900 text-slate-400 hover:text-white'
                      }`}>
                      [HOSTILES]
                    </button>
                  </div>

                  {/* Codex Content Grid: Left List, Right Detailed Inspector */}
                  <div className="grid grid-cols-2 gap-4 flex-1">
                    {/* Left: Interactive Card Grid */}
                    <div className="space-y-2 overflow-y-auto max-h-[360px] pr-1">
                      {codexSubTab === 'turrets' &&
                        (['basic', 'rapid', 'sniper', 'arc'] as TowerType[]).map((t) => (
                          <div
                            key={t}
                            onClick={() => setSelectedCodexItem(t)}
                            className={`p-2.5 rounded-[6px] border flex items-center justify-between cursor-pointer transition-colors ${
                              selectedCodexItem === t
                                ? 'bg-cyan-950/80 border-[#00f0ff]'
                                : 'bg-[#0c1220] border-slate-800 hover:border-slate-700'
                            }`}>
                            <div className="flex items-center gap-2.5">
                              <TurretSilhouette type={t} className="w-6 h-6" />
                              <span className="font-bold font-sans tracking-[0.08em] uppercase text-slate-200">
                                {t === 'basic' ? 'Laser Turret' : t === 'rapid' ? 'Rapid Pulse' : t === 'sniper' ? 'Railgun Sniper' : 'Tesla Arc'}
                              </span>
                            </div>
                            <span className="text-amber-400 font-mono text-[11px]">
                              ${t === 'basic' ? 100 : t === 'rapid' ? 130 : t === 'sniper' ? 220 : 240}
                            </span>
                          </div>
                        ))}

                      {codexSubTab === 'hostiles' &&
                        (['basic', 'fast', 'tank', 'splitter', 'bulwark', 'shifter', 'boss'] as EnemyType[]).map((e) => {
                          const isLocked = wave < ENEMY_SPECS[e].unlockWave;
                          return (
                            <div
                              key={e}
                              onClick={() => setSelectedCodexItem(e)}
                              className={`p-2.5 rounded-[6px] border flex items-center justify-between cursor-pointer transition-colors ${
                                selectedCodexItem === e
                                  ? 'bg-red-950/60 border-red-500'
                                  : 'bg-[#0c1220] border-slate-800 hover:border-slate-700'
                              } ${isLocked ? 'opacity-50' : ''}`}>
                              <div className="flex items-center gap-2.5">
                                <EnemySilhouette type={e} className="w-6 h-6" />
                                <span className="font-bold font-sans tracking-[0.08em] uppercase text-slate-200">
                                  {isLocked ? '???' : ENEMY_SPECS[e].name}
                                </span>
                              </div>
                              <span className="text-xs font-mono">
                                {isLocked ? `Unlocks at wave ${ENEMY_SPECS[e].unlockWave}` : `+$${ENEMY_SPECS[e].reward}`}
                              </span>
                            </div>
                          );
                        })}

                      {codexSubTab === 'command' && (
                        <div className="space-y-2">
                          <div className="p-3 bg-[#0c1220] border border-emerald-500/40 rounded-[6px] text-slate-300">
                            <b className="text-emerald-400 text-sm block mb-1">NEXUS CORE MATRIX</b>
                            Fortified center crystal holding 20 Lives. Equipped with automated defense turret (upgradeable to Lv 10).
                          </div>
                          <div className="p-3 bg-[#0c1220] border border-cyan-500/40 rounded-[6px] text-slate-300">
                            <b className="text-[#00f0ff] text-sm block mb-1">6 CORE GATES (G1 - G6)</b>
                            Airlock choke-points flanking the Core. Corridors strictly funnel hostiles through these gates.
                          </div>
                        </div>
                      )}
                    </div>

                    {/* Right: Detailed Inspector Panel with large vector illustration */}
                    <div className="p-4 rounded-[8px] bg-[#070b16] border border-cyan-500/30 flex flex-col justify-between">
                      {codexSubTab === 'turrets' && (
                        <>
                          <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                            <span className="text-base font-bold text-[#00f0ff] font-sans tracking-[0.08em] uppercase">
                              {selectedCodexItem} TURRET
                            </span>
                            <TurretSilhouette type={selectedCodexItem as TowerType} className="w-10 h-10" />
                          </div>
                          <div className="grid grid-cols-3 gap-2 py-3 text-center bg-black/40 rounded-[6px] border border-slate-900">
                            <div>
                              <span className="text-[10px] text-[#94a3b8] block">COST</span>
                              <span className="text-amber-400 font-bold font-mono">
                                ${selectedCodexItem === 'basic' ? 100 : selectedCodexItem === 'rapid' ? 130 : selectedCodexItem === 'sniper' ? 220 : 240}
                              </span>
                            </div>
                            <div>
                              <span className="text-[10px] text-[#94a3b8] block">DPS</span>
                              <span className="text-cyan-300 font-bold font-mono">
                                {selectedCodexItem === 'basic' ? '20.0' : selectedCodexItem === 'rapid' ? '30.0' : selectedCodexItem === 'sniper' ? '36.7' : '14.1'}
                              </span>
                            </div>
                            <div>
                              <span className="text-[10px] text-[#94a3b8] block">RANGE</span>
                              <span className="text-slate-100 font-bold font-mono">
                                {selectedCodexItem === 'sniper' ? '260' : '100'}
                              </span>
                            </div>
                          </div>
                          <div className="text-xs text-slate-300 leading-relaxed">
                            <b className="text-cyan-400 block mb-1">SPECIALIZATION:</b>
                            {selectedCodexItem === 'basic' && 'Continuous coherent Cyan beam. High-frequency thermal burn.'}
                            {selectedCodexItem === 'rapid' && 'Twin amber plasma bolts. Excels at shredding Fast & Mini swarms (+50% bonus).'}
                            {selectedCodexItem === 'sniper' && 'Hypersonic magnetic kinetic slug. Pierces 4 targets with heavy armor punch (+25% vs Tanks/Bosses).'}
                            {selectedCodexItem === 'arc' && 'Discharges chain lightning. Arc towers within 3 tiles link up for up to ×5 network damage!'}
                          </div>
                        </>
                      )}

                      {codexSubTab === 'hostiles' && (
                        <>
                          <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                            <span className="text-base font-bold text-red-400 font-sans tracking-[0.08em] uppercase">
                              {ENEMY_SPECS[selectedCodexItem as EnemyType]?.name || selectedCodexItem}
                            </span>
                            <EnemySilhouette type={selectedCodexItem as EnemyType} className="w-10 h-10" />
                          </div>
                          <div className="grid grid-cols-3 gap-2 py-3 text-center bg-black/40 rounded-[6px] border border-slate-900">
                            <div>
                              <span className="text-[10px] text-[#94a3b8] block">BASE HP</span>
                              <span className="text-white font-bold font-mono">
                                {ENEMY_SPECS[selectedCodexItem as EnemyType]?.hp}
                              </span>
                            </div>
                            <div>
                              <span className="text-[10px] text-[#94a3b8] block">SPEED</span>
                              <span className="text-cyan-300 font-bold font-mono">
                                {ENEMY_SPECS[selectedCodexItem as EnemyType]?.speed}
                              </span>
                            </div>
                            <div>
                              <span className="text-[10px] text-[#94a3b8] block">BOUNTY</span>
                              <span className="text-amber-400 font-bold font-mono">
                                +${ENEMY_SPECS[selectedCodexItem as EnemyType]?.reward}
                              </span>
                            </div>
                          </div>
                          <div className="text-xs text-slate-300 leading-relaxed">
                            <b className="text-red-400 block mb-1">COMBAT PROFILE:</b>
                            {selectedCodexItem === 'bulwark' && 'Taunter. Heavy core armor forces all nearby turrets to prioritize attacking it.'}
                            {selectedCodexItem === 'shifter' && 'Optical Phase Cloaking. Periodically turns invisible and completely untargetable.'}
                            {selectedCodexItem === 'splitter' && 'Splits into 2-3 fast Minis upon destruction.'}
                            {selectedCodexItem === 'boss' && 'Prime Titan. Massive HP pool, breaches cost 3 lives instead of 1.'}
                            {selectedCodexItem !== 'bulwark' && selectedCodexItem !== 'shifter' && selectedCodexItem !== 'splitter' && selectedCodexItem !== 'boss' && 'Standard hostile creep advancing toward the Nexus Core.'}
                          </div>
                        </>
                      )}

                      {codexSubTab === 'command' && (
                        <div className="space-y-3">
                          <h4 className="text-emerald-400 font-bold text-sm">DEFENSE DIRECTIVES</h4>
                          <p className="text-xs text-slate-300 leading-relaxed">
                            Position turrets adjacent to Gate conduits. Prioritize Rapid Pulse for swarms and Railguns for heavy Bulwark taunters.
                          </p>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* 
                SCREEN 05: SYSTEMS (Audio Matrix, Visual/Perf, Accessibility)
              */}
              {menuTab === 'systems' && (
                <div className="space-y-4">
                  {/* 01 // AUDIO MATRIX */}
                  <div className="p-3 bg-[#0c1220] rounded-[6px] border border-slate-800 space-y-2">
                    <div className="flex items-center justify-between border-b border-slate-800 pb-1">
                      <span className="text-xs font-bold text-[#00f0ff] font-sans tracking-[0.08em] block uppercase">
                        01 // AUDIO MATRIX &amp; DYNAMIC SOUNDTRACK
                      </span>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={onToggleMusic}
                          className={`px-2 py-0.5 rounded text-[10px] font-bold border ${
                            isMusicMuted
                              ? 'bg-red-950/80 border-red-500 text-red-300'
                              : 'bg-cyan-950/80 border-cyan-500 text-cyan-300'
                          }`}>
                          {isMusicMuted ? 'BGM MUTED' : 'BGM ON'}
                        </button>
                        <button
                          onClick={onToggleMute}
                          className={`px-2 py-0.5 rounded text-[10px] font-bold border ${
                            isMuted
                              ? 'bg-red-950/80 border-red-500 text-red-300'
                              : 'bg-emerald-950/80 border-emerald-500 text-emerald-300'
                          }`}>
                          {isMuted ? 'SFX MUTED' : 'SFX ON'}
                        </button>
                      </div>
                    </div>
                    <div className="space-y-2">
                      {/* Active Dynamic Soundtrack Indicator */}
                      <div className="flex items-center justify-between text-xs py-1 px-2 rounded bg-black/40 border border-slate-800/80">
                        <span className="text-slate-400">ACTIVE SOUNDTRACK</span>
                        <span className="font-bold text-xs uppercase px-2 py-0.5 rounded bg-cyan-950 border border-cyan-500/40 text-cyan-300 flex items-center gap-1.5">
                          <Volume2 size={12} className="text-[#00f0ff]" />
                          {currentTrack === 'boss'
                            ? '⚠ BOSS CLASH (APEX TITAN)'
                            : currentTrack === 'mutation'
                            ? '⚡ MUTATION SURGE'
                            : 'TACTICAL SYNTH (STANDARD)'}
                        </span>
                      </div>
                      {/* Master Volume */}
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-slate-300">MASTER VOLUME</span>
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => setMasterVolume((v) => Math.max(0, v - 1))}
                            className="w-6 h-6 rounded bg-slate-900 hover:bg-slate-800 border border-slate-700 flex items-center justify-center">
                            <Minus size={12} />
                          </button>
                          {/* 10-block illuminated meter */}
                          <div className="flex items-center gap-1">
                            {Array.from({length: 10}).map((_, i) => (
                              <div
                                key={i}
                                className={`w-2 h-4 rounded-[1px] ${
                                  i < masterVolume ? 'bg-[#00f0ff]' : 'bg-slate-800'
                                }`}
                              />
                            ))}
                          </div>
                          <button
                            onClick={() => setMasterVolume((v) => Math.min(10, v + 1))}
                            className="w-6 h-6 rounded bg-slate-900 hover:bg-slate-800 border border-slate-700 flex items-center justify-center">
                            <Plus size={12} />
                          </button>
                        </div>
                      </div>

                      {/* SFX Volume */}
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-slate-300">SFX EFFECTS</span>
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => setSfxVolume((v) => Math.max(0, v - 1))}
                            className="w-6 h-6 rounded bg-slate-900 hover:bg-slate-800 border border-slate-700 flex items-center justify-center">
                            <Minus size={12} />
                          </button>
                          <div className="flex items-center gap-1">
                            {Array.from({length: 10}).map((_, i) => (
                              <div
                                key={i}
                                className={`w-2 h-4 rounded-[1px] ${
                                  i < sfxVolume ? 'bg-[#10b981]' : 'bg-slate-800'
                                }`}
                              />
                            ))}
                          </div>
                          <button
                            onClick={() => setSfxVolume((v) => Math.min(10, v + 1))}
                            className="w-6 h-6 rounded bg-slate-900 hover:bg-slate-800 border border-slate-700 flex items-center justify-center">
                            <Plus size={12} />
                          </button>
                        </div>
                      </div>

                      {/* Threat Track / Synth Music */}
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-slate-300">THREAT TRACK (BGM)</span>
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => setThreatVolume((v) => Math.max(0, v - 1))}
                            className="w-6 h-6 rounded bg-slate-900 hover:bg-slate-800 border border-slate-700 flex items-center justify-center">
                            <Minus size={12} />
                          </button>
                          <div className="flex items-center gap-1">
                            {Array.from({length: 10}).map((_, i) => (
                              <div
                                key={i}
                                className={`w-2 h-4 rounded-[1px] ${
                                  i < threatVolume ? 'bg-[#ec4899]' : 'bg-slate-800'
                                }`}
                              />
                            ))}
                          </div>
                          <button
                            onClick={() => setThreatVolume((v) => Math.min(10, v + 1))}
                            className="w-6 h-6 rounded bg-slate-900 hover:bg-slate-800 border border-slate-700 flex items-center justify-center">
                            <Plus size={12} />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* 02 // VISUAL & PERFORMANCE */}
                  <div className="p-3 bg-[#0c1220] rounded-[6px] border border-slate-800 space-y-2">
                    <span className="text-xs font-bold text-[#00f0ff] font-sans tracking-[0.08em] block uppercase">
                      02 // VISUAL &amp; PERFORMANCE
                    </span>
                    <div className="grid grid-cols-3 gap-3 text-xs">
                      <div>
                        <span className="text-[#94a3b8] block mb-1">PARTICLE DENSITY</span>
                        <div className="flex items-center gap-1">
                          {(['LOW', 'MED', 'HIGH'] as const).map((p) => (
                            <button
                              key={p}
                              onClick={() => setParticleDensity(p)}
                              className={`px-2 py-1 rounded text-[10px] font-bold ${
                                particleDensity === p
                                  ? 'bg-[#00f0ff] text-black'
                                  : 'bg-slate-900 text-slate-400'
                              }`}>
                              [{p}]
                            </button>
                          ))}
                        </div>
                      </div>

                      <div>
                        <span className="text-[#94a3b8] block mb-1">TELEMETRY OVERLAY</span>
                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => setTelemetryOverlay(true)}
                            className={`px-2 py-1 rounded text-[10px] font-bold ${
                              telemetryOverlay ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                            }`}>
                            [ONLINE]
                          </button>
                          <button
                            onClick={() => setTelemetryOverlay(false)}
                            className={`px-2 py-1 rounded text-[10px] font-bold ${
                              !telemetryOverlay ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                            }`}>
                            [OFFLINE]
                          </button>
                        </div>
                      </div>

                      <div>
                        <span className="text-[#94a3b8] block mb-1">UI SCALE</span>
                        <div className="flex items-center gap-1">
                          {(['80%', '100%', '120%'] as const).map((s) => (
                            <button
                              key={s}
                              onClick={() => setUiScale(s)}
                              className={`px-2 py-1 rounded text-[10px] font-bold ${
                                uiScale === s ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                              }`}>
                              [{s}]
                            </button>
                          ))}
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* 03 // ACCESSIBILITY */}
                  <div className="p-3 bg-[#0c1220] rounded-[6px] border border-slate-800 space-y-2">
                    <span className="text-xs font-bold text-[#00f0ff] font-sans tracking-[0.08em] block uppercase">
                      03 // ACCESSIBILITY
                    </span>
                    <div className="grid grid-cols-2 gap-4 text-xs">
                      <div className="flex items-center justify-between">
                        <span className="text-slate-300">REDUCED MOTION</span>
                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => setReducedMotion(true)}
                            className={`px-2 py-1 rounded text-[10px] font-bold ${
                              reducedMotion ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                            }`}>
                            [ONLINE]
                          </button>
                          <button
                            onClick={() => setReducedMotion(false)}
                            className={`px-2 py-1 rounded text-[10px] font-bold ${
                              !reducedMotion ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                            }`}>
                            [OFFLINE]
                          </button>
                        </div>
                      </div>

                      <div className={`flex items-center justify-between ${reducedMotion ? 'opacity-40' : ''}`}>
                        <span className="text-slate-300">SCREEN SHAKE</span>
                        <div className="flex items-center gap-1">
                          <button
                            disabled={reducedMotion}
                            onClick={() => setScreenShake(true)}
                            className={`px-2 py-1 rounded text-[10px] font-bold ${
                              screenShake && !reducedMotion ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                            }`}>
                            [ONLINE]
                          </button>
                          <button
                            disabled={reducedMotion}
                            onClick={() => setScreenShake(false)}
                            className={`px-2 py-1 rounded text-[10px] font-bold ${
                              !screenShake || reducedMotion ? 'bg-[#00f0ff] text-black' : 'bg-slate-900 text-slate-400'
                            }`}>
                            [OFFLINE]
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* 
                SCREEN 06: REBOOT (Step 1 & Step 2)
              */}
              {menuTab === 'reboot' && (
                <div className="flex flex-col items-center justify-center h-full p-4 text-center">
                  {rebootStep === 1 ? (
                    <div className="space-y-4 max-w-md">
                      <div className="w-14 h-14 rounded-full bg-red-950/60 border border-red-500/60 flex items-center justify-center mx-auto text-red-400">
                        <RotateCw size={24} />
                      </div>
                      <h3 className="text-lg font-bold text-white font-sans tracking-[0.08em]">
                        SIMULATION REBOOT INITIATION
                      </h3>
                      <p className="text-xs text-slate-400 leading-relaxed">
                        Rebooting will wipe active sector placement and begin a clean defense simulation run from Wave 1.
                      </p>
                      <button
                        onClick={() => setRebootStep(2)}
                        className="px-6 py-2.5 rounded-[6px] border-2 border-red-500 text-red-400 hover:bg-red-950/60 font-sans tracking-[0.08em] font-bold text-xs uppercase transition-all shadow-[0_0_15px_rgba(239,68,68,0.2)]">
                        REBOOT NEXUS CORE
                      </button>
                    </div>
                  ) : (
                    /* Step 2: Warning confirmation card */
                    <div className="w-full max-w-md p-5 rounded-[12px] bg-red-950/40 border border-red-500 space-y-4 shadow-[0_0_30px_rgba(239,68,68,0.3)]">
                      <div className="flex items-center justify-center gap-2 text-red-400 font-bold font-sans tracking-[0.08em] text-sm">
                        <AlertTriangle size={18} />
                        ⚠ REBOOT NEXUS CORE? STEP 2 / 2
                      </div>
                      <p className="text-xs text-slate-200">
                        "All active progress and credits will be lost."
                      </p>
                      {/* Run summary */}
                      <div className="grid grid-cols-3 gap-2 py-2.5 bg-black/60 rounded border border-red-900/60 text-center font-mono">
                        <div>
                          <span className="text-[10px] text-[#94a3b8] block">WAVE</span>
                          <span className="text-white font-bold text-sm">{wave}</span>
                        </div>
                        <div>
                          <span className="text-[10px] text-[#94a3b8] block">SCORE</span>
                          <span className="text-amber-400 font-bold text-sm">{score.toLocaleString()}</span>
                        </div>
                        <div>
                          <span className="text-[10px] text-[#94a3b8] block">CREDITS</span>
                          <span className="text-emerald-400 font-bold text-sm">${credits}</span>
                        </div>
                      </div>
                      {/* Action buttons */}
                      <div className="flex items-center gap-3 pt-2">
                        <button
                          onClick={() => setRebootStep(1)}
                          className="flex-1 py-2 rounded-[6px] bg-slate-900 hover:bg-slate-800 border border-slate-700 text-slate-300 font-sans tracking-[0.08em] text-xs font-bold uppercase">
                          [CANCEL ESC]
                        </button>
                        <button
                          onClick={() => {
                            setIsMenuOpen(false);
                            setRebootStep(1);
                            onRebootGame();
                          }}
                          className="flex-1 py-2 rounded-[6px] bg-red-600 hover:bg-red-500 text-white font-sans tracking-[0.08em] text-xs font-bold uppercase shadow-[0_0_15px_rgba(239,68,68,0.5)]">
                          [⟲ CONFIRM REBOOT]
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div className="flex items-center justify-between border-t border-slate-800 pt-3 text-xs">
              <span className="text-slate-500 italic">"Settings save automatically"</span>
              <button
                onClick={() => setIsMenuOpen(false)}
                className="px-5 py-2 rounded-[6px] bg-[#00f0ff] hover:bg-cyan-300 text-black font-sans tracking-[0.08em] font-bold text-xs flex items-center gap-1.5 transition-all shadow-[0_0_15px_rgba(0,240,255,0.3)]">
                <Play size={13} className="fill-black" />
                ▶ RESUME DEFENSE [ESC]
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
