import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../neon_defense_game.dart';
import '../config/constants.dart';
import 'tile_grid.dart';
import 'hardpoint_manager.dart';
import 'rift_path_renderer.dart';
import '../systems/pathfinding/rift_generator.dart';
import '../systems/wave_system.dart';
import '../systems/spatial_grid.dart';
import '../systems/ability_system.dart';
import '../systems/quality_governor.dart';
import '../vfx/particle_system.dart';
import '../vfx/arc_lightning.dart';
import '../vfx/light_source.dart';
import '../vfx/placement_preview.dart';
import '../entities/towers/tower.dart';
import '../entities/enemies/enemy.dart';
import '../entities/projectiles/projectile.dart';
import '../entities/base/core_base.dart';

/// Explicit render layer order, matching the JS draw() pipeline
/// (06_render.js:86-798): grid -> rift paths -> base -> hardpoints ->
/// towers -> arc links -> enemies -> projectiles -> particles ->
/// ability overlays -> lights. Entities set their own priority from these.
class RenderLayers {
  static const int grid = 0;
  static const int riftPaths = 5;
  static const int base = 10;
  static const int hardpoints = 15;
  static const int towers = 20;
  static const int arcLinks = 25;
  static const int enemies = 30;
  static const int projectiles = 35;
  static const int particles = 45;
  static const int abilityOverlays = 55;
  static const int lights = 60;
  static const int placementPreview = 65;
}

class GameWorld extends Component with HasGameReference<NeonDefenseGame> {
  late TileGrid tileGrid;
  late HardpointManager hardpointManager;
  late RiftGenerator riftGenerator;
  late WaveSystem waveSystem;
  late SpatialGrid spatialGrid;
  late AbilitySystem abilitySystem;
  late ParticleSystem particles;
  late ArcLightning arcLightning;
  late LightSourceSystem lights;
  late QualityGovernor qualityGovernor;
  late CoreBase coreBase;

  final int worldCols;
  final int worldRows;

  GameWorld(NeonDefenseGame game)
      : worldCols = kWorldMinCols,
        worldRows = kWorldMinRows,
        super();

  @override
  Future<void> onLoad() async {
    spatialGrid = SpatialGrid();
    tileGrid = TileGrid(worldCols, worldRows)..priority = RenderLayers.grid;
    hardpointManager = HardpointManager(worldCols, worldRows)
      ..priority = RenderLayers.hardpoints;
    riftGenerator = RiftGenerator(worldCols, worldRows, hardpointManager);
    waveSystem = WaveSystem(this);
    abilitySystem = AbilitySystem(this)
      ..priority = RenderLayers.abilityOverlays;
    particles = ParticleSystem()..priority = RenderLayers.particles;
    arcLightning = ArcLightning()..priority = RenderLayers.arcLinks;
    lights = LightSourceSystem()..priority = RenderLayers.lights;
    qualityGovernor = QualityGovernor(
      particles: particles,
      arcLightning: arcLightning,
      lights: lights,
    );
    coreBase = CoreBase(
      worldCenter: Vector2(worldCols * kGridSize / 2, worldRows * kGridSize / 2),
      spatialGrid: spatialGrid,
    )..priority = RenderLayers.base;

    await addAll([
      tileGrid,
      RiftPathRenderer(waveSystem)..priority = RenderLayers.riftPaths,
      hardpointManager,
      coreBase,
      waveSystem,
      abilitySystem,
      lights,
      arcLightning,
      particles,
      qualityGovernor,
      PlacementPreview()..priority = RenderLayers.placementPreview,
    ]);
  }

  /// Central pause/phase gate: no child logic runs unless playing,
  /// matching the JS loop which skips update() entirely when paused.
  /// Rendering continues; component add/remove queues are processed at
  /// the game root, so lifecycle is unaffected.
  @override
  void updateTree(double dt) {
    if (!game.state.isPlaying) return;
    game.state.frameCount++;
    super.updateTree(dt);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void startPrepPhase() => waveSystem.startPrepPhase();

  void activateAbility(AbilityType type) => abilitySystem.startTargeting(type);

  /// JS spawnSubUnits (05_loop.js:875-905): a dying splitter releases
  /// 2-3 minis that inherit its path, progress, tier, and mutation.
  void spawnMinis(Enemy parentEnemy) {
    final rng = waveSystem.rng;
    final miniCount = 2 + rng.nextInt(2);
    final miniDef = kEnemies[EnemyType.mini]!;

    for (var i = 0; i < miniCount; i++) {
      final offset = Vector2(
        (rng.nextDouble() - 0.5) * 20,
        (rng.nextDouble() - 0.5) * 20,
      );
      add(Enemy(
        type: EnemyType.mini,
        hp: parentEnemy.maxHp * 0.2,
        speed: parentEnemy.speed * 1.5,
        color: parentEnemy.color,
        reward: miniDef.reward,
        width: miniDef.width,
        path: parentEnemy.path,
        riftLevel: parentEnemy.riftLevel,
        isMutant: parentEnemy.isMutant,
        mutationKey: parentEnemy.mutationKey,
        spatialGrid: spatialGrid,
        spawnPos: parentEnemy.position + offset,
        startPathIndex: parentEnemy.pathIndex,
      ));
    }
  }

  /// JS generateNewPath tower destruction (04_tutorial.js:609-632): a new
  /// rift destroys overlapping non-hardpoint towers with a 70% refund.
  void destroyTowersOnPath(List<Vector2> pathPoints) {
    final tolerance = kGridSize / 2;
    final doomed = <Tower>[];
    for (final t in game.entities.towers) {
      if (t.hardpoint != null) continue;
      for (var j = 0; j < pathPoints.length - 1; j++) {
        final p1 = pathPoints[j];
        final p2 = pathPoints[j + 1];
        var hit = false;
        if ((p1.y - p2.y).abs() < 1) {
          // Horizontal
          hit = (t.position.y - p1.y).abs() < tolerance &&
              t.position.x >= (p1.x < p2.x ? p1.x : p2.x) - tolerance &&
              t.position.x <= (p1.x > p2.x ? p1.x : p2.x) + tolerance;
        } else {
          // Vertical
          hit = (t.position.x - p1.x).abs() < tolerance &&
              t.position.y >= (p1.y < p2.y ? p1.y : p2.y) - tolerance &&
              t.position.y <= (p1.y > p2.y ? p1.y : p2.y) + tolerance;
        }
        if (hit) {
          doomed.add(t);
          break;
        }
      }
    }
    for (final t in doomed) {
      game.state.money.value +=
          (t.baseCost * t.level * 0.7).floorToDouble();
      particles.createParticles(
          t.position.x, t.position.y, const Color(0xFFFFFFFF), 10);
      removeTower(t);
    }
  }

  void removeTower(Tower t) {
    t.hardpoint?.occupied = false;
    if (game.selection.selectedTower == t) {
      game.selection.selectTower(null);
    }
    t.removeFromParent();
  }

  void reset() {
    removeWhere((c) => c is Tower || c is Enemy || c is Projectile);
    game.entities.clear();
    for (final hp in hardpointManager.hardpoints) {
      hp.occupied = false;
    }
    coreBase.level = 0;
    waveSystem.reset();
    spatialGrid.clear();
    abilitySystem.cancelTargeting();
  }
}
