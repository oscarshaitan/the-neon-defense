import 'dart:ui';

import 'package:flame/components.dart';

import '../neon_defense_game.dart';
import '../config/constants.dart';
import 'tile_grid.dart';
import 'hardpoint_manager.dart';
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
import '../entities/base/core_base.dart';

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

  TowerType? selectedTowerType;

  final int worldCols;
  final int worldRows;

  GameWorld(NeonDefenseGame game)
      : worldCols = kWorldMinCols,
        worldRows = kWorldMinRows,
        super();

  @override
  Future<void> onLoad() async {
    spatialGrid = SpatialGrid();
    tileGrid = TileGrid(worldCols, worldRows);
    hardpointManager = HardpointManager(worldCols, worldRows);
    riftGenerator = RiftGenerator(worldCols, worldRows, hardpointManager);
    waveSystem = WaveSystem(this);
    abilitySystem = AbilitySystem(this);
    particles = ParticleSystem();
    arcLightning = ArcLightning();
    lights = LightSourceSystem();
    qualityGovernor = QualityGovernor(
      particles: particles,
      arcLightning: arcLightning,
      lights: lights,
    );
    coreBase = CoreBase(
      worldCenter: Vector2(worldCols * kGridSize / 2, worldRows * kGridSize / 2),
      spatialGrid: spatialGrid,
    );

    await addAll([
      tileGrid,
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

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    // Draw paths BEFORE children so towers/enemies render on top
    _renderRiftPaths(canvas);
    super.render(canvas);
  }

  void _renderRiftPaths(Canvas canvas) {
    for (final rift in waveSystem.rifts) {
      if (rift.points.length < 2) continue;

      final pathObj = Path();
      pathObj.moveTo(rift.points.first.x, rift.points.first.y);
      for (int i = 1; i < rift.points.length; i++) {
        pathObj.lineTo(rift.points[i].x, rift.points[i].y);
      }

      // 1. Wide glow background — matches JS lineWidth = GRID_SIZE * 0.8
      canvas.drawPath(
        pathObj,
        Paint()
          ..color = const Color(0x0D00F3FF) // rgba(0,243,255,0.05)
          ..strokeWidth = kGridSize * 0.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // 2. Thin dashed center line — matches JS lineWidth=2, setLineDash([10,10])
      _drawDashed(
        canvas,
        pathObj,
        Paint()
          ..color = const Color(0xFF00F3FF)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
        10,
        10,
      );

      // 3. Spawn circle at path start — matches JS arc(20), inner black arc(10)
      final spawn = rift.points.first;
      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        20,
        Paint()
          ..color = const Color(0xFFFF4444)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        20,
        Paint()
          ..color = const Color(0xFFFF4444)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        10,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      bool drawing = true;
      while (dist < metric.length) {
        final len = drawing ? dash : gap;
        final end = (dist + len).clamp(0.0, metric.length);
        if (drawing) canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += len;
        drawing = !drawing;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void selectTowerType(TowerType type) => selectedTowerType = type;

  void deselect() => selectedTowerType = null;

  void startPrepPhase() => waveSystem.startPrepPhase();

  void activateAbility(AbilityType type) => abilitySystem.startTargeting(type);

  void placeTower(Vector2 worldPos) {
    if (selectedTowerType == null) return;
    final type = selectedTowerType!;
    final cost = kTowers[type]!.cost;
    if (game.money < cost) return;

    final hp = hardpointManager.getNearestSnap(worldPos);
    if (hp != null && hp.occupied) return;

    final placePos = hp?.worldPos.clone() ?? worldPos;
    if (hp != null) hp.occupied = true;

    game.money -= cost;
    final tower = Tower(
      position: placePos,
      type: type,
      spatialGrid: spatialGrid,
      hardpoint: hp,
    );
    add(tower);
    selectedTowerType = null;
  }

  void removeTower(Tower t) {
    t.hardpoint?.occupied = false;
    game.selectTower(null);
    t.removeFromParent();
  }

  void reset() {
    removeWhere((c) => c is Tower || c is Enemy);
    for (final hp in hardpointManager.hardpoints) {
      hp.occupied = false;
    }
    coreBase.level = 0;
    waveSystem.reset();
    spatialGrid.clear();
    abilitySystem.cancelTargeting();
    selectedTowerType = null;
  }
}
