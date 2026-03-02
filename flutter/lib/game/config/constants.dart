import 'dart:ui';

// ---------------------------------------------------------------------------
// Grid & world
// ---------------------------------------------------------------------------
const double kGridSize = 40.0;
const int kZone0RadiusCells = 6;
const int kWorldMinCols = 140;
const int kWorldMinRows = 90;

// ---------------------------------------------------------------------------
// Tower definitions
// ---------------------------------------------------------------------------
enum TowerType { basic, rapid, sniper, arc }

class TowerDef {
  final TowerType type;
  final double cost;
  final double range;
  final double damage;
  final int cooldown; // frames
  final Color color;
  const TowerDef({
    required this.type,
    required this.cost,
    required this.range,
    required this.damage,
    required this.cooldown,
    required this.color,
  });
}

const Map<TowerType, TowerDef> kTowers = {
  TowerType.basic: TowerDef(
    type: TowerType.basic,
    cost: 50,
    range: 100,
    damage: 10,
    cooldown: 30,
    color: Color(0xFF00F3FF), // neon blue
  ),
  TowerType.rapid: TowerDef(
    type: TowerType.rapid,
    cost: 120,
    range: 80,
    damage: 4,
    cooldown: 10,
    color: Color(0xFFFCEE0A), // neon yellow
  ),
  TowerType.sniper: TowerDef(
    type: TowerType.sniper,
    cost: 200,
    range: 250,
    damage: 50,
    cooldown: 90,
    color: Color(0xFFFF00AC), // neon pink
  ),
  TowerType.arc: TowerDef(
    type: TowerType.arc,
    cost: 180,
    range: 100,
    damage: 8,
    cooldown: 34,
    color: Color(0xFF7CD7FF), // light blue
  ),
};

// ---------------------------------------------------------------------------
// Enemy definitions
// ---------------------------------------------------------------------------
enum EnemyType { basic, fast, tank, boss, splitter, mini, bulwark, shifter }

class EnemyDef {
  final EnemyType type;
  final double hp;
  final double speed; // world units / frame
  final Color color;
  final double reward;
  final double width;
  const EnemyDef({
    required this.type,
    required this.hp,
    required this.speed,
    required this.color,
    required this.reward,
    required this.width,
  });
}

const Map<EnemyType, EnemyDef> kEnemies = {
  EnemyType.basic: EnemyDef(
    type: EnemyType.basic,
    hp: 30,
    speed: 1.5,
    color: Color(0xFFFF4444),
    reward: 10,
    width: 18,
  ),
  EnemyType.fast: EnemyDef(
    type: EnemyType.fast,
    hp: 20,
    speed: 2.5,
    color: Color(0xFFFCEE0A),
    reward: 15,
    width: 14,
  ),
  EnemyType.tank: EnemyDef(
    type: EnemyType.tank,
    hp: 100,
    speed: 0.8,
    color: Color(0xFFFF00AC),
    reward: 30,
    width: 26,
  ),
  EnemyType.boss: EnemyDef(
    type: EnemyType.boss,
    hp: 500,
    speed: 0.5,
    color: Color(0xFFFF8C00),
    reward: 200,
    width: 36,
  ),
  EnemyType.splitter: EnemyDef(
    type: EnemyType.splitter,
    hp: 80,
    speed: 1.2,
    color: Color(0xFF00FF41),
    reward: 40,
    width: 22,
  ),
  EnemyType.mini: EnemyDef(
    type: EnemyType.mini,
    hp: 20,
    speed: 2.0,
    color: Color(0xFF00FF41),
    reward: 5,
    width: 12,
  ),
  EnemyType.bulwark: EnemyDef(
    type: EnemyType.bulwark,
    hp: 350,
    speed: 0.6,
    color: Color(0xFFFCEE0A),
    reward: 60,
    width: 30,
  ),
  EnemyType.shifter: EnemyDef(
    type: EnemyType.shifter,
    hp: 60,
    speed: 1.5,
    color: Color(0xFFFF00AC),
    reward: 60,
    width: 18,
  ),
};

// ---------------------------------------------------------------------------
// Arc tower rules
// ---------------------------------------------------------------------------
const double kArcChainRange = 160.0;
const int kArcBaseChainTargets = 3;
const double kArcBounceDamageMult = 0.7;
const double kArcStaticThreshold = 100.0;
const int kArcStunFrames = 30;
const int kArcMinLinkSpacingCells = 1;
const int kArcMaxLinkSpacingCells = 3;

// ---------------------------------------------------------------------------
// Hardpoint rules
// ---------------------------------------------------------------------------
const double kHardpointSnapRadius = 18.0;

// Core ring
const int kCoreHardpointCount = 6;
const int kCoreHardpointRadiusCells = 6;
const double kCoreDamageMult = 1.08;
const double kCoreRangeMult = 1.06;
const double kCoreCooldownMult = 0.95;
const double kCoreScaleMult = 1.08;

// Micro rings
const List<({int count, int radiusCells, double angleOffset})> kMicroRings = [
  (count: 10, radiusCells: 13, angleOffset: 0.3141592653589793), // π/10
  (count: 14, radiusCells: 17, angleOffset: 0.0),
];
const double kMicroDamageMult = 0.82;
const double kMicroRangeMult = 0.86;
const double kMicroCooldownMult = 1.12;
const double kMicroScaleMult = 0.78;

// ---------------------------------------------------------------------------
// Economy
// ---------------------------------------------------------------------------
const double kStartingMoney = 100.0;
const int kStartingLives = 20;
const double kStartingEnergy = 0.0;
const double kMaxEnergy = 100.0;
const double kEnergyRegenPerFrame = 0.05;

// ---------------------------------------------------------------------------
// Abilities
// ---------------------------------------------------------------------------
const double kEmpCost = 40.0;
const double kEmpRadius = 120.0;
const int kEmpDurationFrames = 300; // 5s @ 60fps
const int kEmpMaxCooldown = 15;

const double kOverclockCost = 25.0;
const int kOverclockDurationFrames = 600; // 10s @ 60fps
const int kOverclockMaxCooldown = 10;

// ---------------------------------------------------------------------------
// Wave
// ---------------------------------------------------------------------------
const int kPrepTimerSeconds = 30;
const int kSpawnIntervalFrames = 60; // 1 enemy/s

// ---------------------------------------------------------------------------
// Performance profiles
// ---------------------------------------------------------------------------
enum QualityProfile { high, balanced, low }

const Map<QualityProfile, ({int maxParticles, int maxLights, int maxArcBursts})>
    kQualityProfiles = {
  QualityProfile.high: (maxParticles: 900, maxLights: 140, maxArcBursts: 180),
  QualityProfile.balanced: (
    maxParticles: 620,
    maxLights: 90,
    maxArcBursts: 140
  ),
  QualityProfile.low: (maxParticles: 420, maxLights: 65, maxArcBursts: 96),
};

const double kQualityDowngradeFrameMs = 22.0;
const double kQualityDowngradeEmaMs = 19.5;
const double kQualityUpgradeFrameMs = 15.8;
const double kQualityUpgradeEmaMs = 15.3;
const int kQualityDowngradeWindow = 45; // frames
const int kQualityUpgradeWindow = 240; // frames

// ---------------------------------------------------------------------------
// Neon color palette
// ---------------------------------------------------------------------------
const Color kColorBg = Color(0xFF050510);
const Color kColorNeonBlue = Color(0xFF00F3FF);
const Color kColorNeonPink = Color(0xFFFF00AC);
const Color kColorNeonGreen = Color(0xFF00FF41);
const Color kColorNeonYellow = Color(0xFFFCEE0A);
