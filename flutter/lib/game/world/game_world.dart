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

  void placeTower(Vector2 worldPos) {
    final type = game.selection.selectedTowerType;
    if (type == null) return;
    final cost = kTowers[type]!.cost;
    if (game.state.money.value < cost) return;

    final hp = hardpointManager.getNearestSnap(worldPos);
    if (hp == null) return;
    if (hp.occupied) return;

    hp.occupied = true;
    final placePos = hp.worldPos.clone();

    game.state.money.value -= cost;
    final tower = Tower(
      position: placePos,
      type: type,
      spatialGrid: spatialGrid,
      hardpoint: hp,
    );
    add(tower);
    game.selection.selectTowerType(null);
  }

  void removeTower(Tower t) {
    t.hardpoint?.occupied = false;
    game.selection.selectTower(null);
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
