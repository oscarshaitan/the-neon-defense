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

    await addAll([
      tileGrid,
      hardpointManager,
      waveSystem,
      abilitySystem,
      lights,       // drawn under particles
      arcLightning,
      particles,
      qualityGovernor,
    ]);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void selectTowerType(TowerType type) => selectedTowerType = type;

  void deselect() => selectedTowerType = null;

  void startPrepPhase() => waveSystem.startPrepPhase();

  void activateAbility(AbilityType type) => abilitySystem.startTargeting(type);

  void reset() {
    waveSystem.reset();
    spatialGrid.clear();
    abilitySystem.cancelTargeting();
    selectedTowerType = null;
  }
}
