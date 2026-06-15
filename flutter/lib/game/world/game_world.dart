import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../neon_defense_game.dart';
import '../config/constants.dart';
import 'tile_grid.dart';
import 'hardpoint_manager.dart';
import 'rift_path_renderer.dart';
import 'no_build_overlay.dart';
import 'arc_tower_links.dart';
import '../systems/pathfinding/rift_generator.dart';
import '../systems/wave_system.dart';
import '../systems/spatial_grid.dart';
import '../systems/ability_system.dart';
import '../systems/placement_system.dart' show PlacementSystem;
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
  static const int noBuildOverlay = 4; // under rifts (JS draws it pre-rift loop)
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

  /// Inter-tower arc network (JS arcTowerLinks): rebuilt lazily when towers
  /// change. Each link's strength = max network bonus of its endpoints.
  final List<({Tower a, Tower b, int strength})> arcTowerLinks = [];
  bool _arcNetworkDirty = true;

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
      NoBuildOverlay(waveSystem, coreBase)
        ..priority = RenderLayers.noBuildOverlay,
      RiftPathRenderer(waveSystem)..priority = RenderLayers.riftPaths,
      ArcTowerLinkRenderer(this)..priority = RenderLayers.arcLinks,
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
    refreshArcNetwork(); // dirty-gated; recomputes only when towers change
    super.updateTree(dt);

    // JS update() ends with AudioEngine.updateMusic(): threat track while a
    // boss/mutant is alive, else the wave-indexed melody.
    if (game.state.frameCount % 30 == 0) {
      final hasThreat = game.entities.enemies
          .any((e) => e.type == EnemyType.boss || e.isMutant);
      game.audio.updateMusic(
          wave: game.state.wave.value, hasThreat: hasThreat);
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void startPrepPhase() => waveSystem.startPrepPhase();

  void activateAbility(AbilityType type) => abilitySystem.startTargeting(type);

  void markArcNetworkDirty() => _arcNetworkDirty = true;

  /// JS refreshArcTowerNetwork (05_loop.js:1198): link cardinally aligned arc
  /// towers 1-3 cells apart, find connected components via DFS, and grant each
  /// member a bonus = component size (capped). Dirty-gated — only runs when
  /// towers are added/removed.
  void refreshArcNetwork() {
    if (!_arcNetworkDirty) return;
    _arcNetworkDirty = false;
    arcTowerLinks.clear();

    final arcTowers = [
      for (final t in game.entities.towers)
        if (t.type == TowerType.arc) t,
    ];
    for (final t in arcTowers) {
      t.arcNetworkBonus = 0;
    }
    if (arcTowers.isEmpty) return;

    final adjacency = {for (final t in arcTowers) t: <Tower>[]};
    for (var i = 0; i < arcTowers.length; i++) {
      for (var j = i + 1; j < arcTowers.length; j++) {
        final a = arcTowers[i];
        final b = arcTowers[j];
        if (!_isArcLinkPair(a, b)) continue;
        adjacency[a]!.add(b);
        adjacency[b]!.add(a);
        arcTowerLinks.add((a: a, b: b, strength: 1));
      }
    }

    final visited = <Tower>{};
    for (final t in arcTowers) {
      if (visited.contains(t)) continue;
      final stack = <Tower>[t];
      final component = <Tower>[];
      visited.add(t);
      while (stack.isNotEmpty) {
        final node = stack.removeLast();
        component.add(node);
        for (final next in adjacency[node]!) {
          if (visited.add(next)) stack.add(next);
        }
      }
      final bonus = component.length.clamp(1, kArcMaxBonus);
      for (final node in component) {
        node.arcNetworkBonus = bonus;
      }
    }

    for (var i = 0; i < arcTowerLinks.length; i++) {
      final l = arcTowerLinks[i];
      final s = (l.a.arcNetworkBonus > l.b.arcNetworkBonus
              ? l.a.arcNetworkBonus
              : l.b.arcNetworkBonus)
          .clamp(1, kArcMaxBonus);
      arcTowerLinks[i] = (a: l.a, b: l.b, strength: s);
    }
  }

  bool _isArcLinkPair(Tower a, Tower b) {
    final ac = (a.position.x / kGridSize).floor();
    final ar = (a.position.y / kGridSize).floor();
    final bc = (b.position.x / kGridSize).floor();
    final br = (b.position.y / kGridSize).floor();
    final dc = (ac - bc).abs();
    final dr = (ar - br).abs();
    final spacing = dc + dr;
    final aligned = (dc == 0 && dr > 0) || (dr == 0 && dc > 0);
    if (!aligned) return false;
    return spacing >= kArcMinLinkSpacingCells &&
        spacing <= kArcMaxLinkSpacingCells;
  }

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
        if (PlacementSystem.segmentBoxHit(
            t.position, pathPoints[j], pathPoints[j + 1], tolerance)) {
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
    markArcNetworkDirty();
  }

  // ---------------------------------------------------------------------------
  // Debug / command center (JS debug functions; parity with the Godot edition)
  // ---------------------------------------------------------------------------

  void debugAddMoney() {
    game.state.money.value += 1000000;
    game.saveSystem.save();
  }

  /// JS debugSpawn: spawn one enemy of a specific type on a random rift.
  void debugSpawn(EnemyType type) {
    final rifts = waveSystem.rifts;
    if (rifts.isEmpty) return;
    final rift = rifts[waveSystem.rng.nextInt(rifts.length)];
    final def = kEnemies[type]!;
    var hp = def.hp * (1.0 + game.state.wave.value * 0.4);
    if (rift.level > 1) hp *= 1 + (rift.level - 1) * 0.5;
    add(Enemy(
      type: type,
      hp: hp,
      speed: def.speed,
      color: def.color,
      reward: def.reward,
      width: def.width,
      path: rift.points,
      riftLevel: rift.level,
      spatialGrid: spatialGrid,
    ));
    game.state.isWaveActive.value = true; // ensure systems process it
  }

  /// JS debugCreateRift: force-generate one extra rift (async in Flutter).
  Future<void> debugCreateRift() async {
    final rift = await riftGenerator.generateRift(
      existingPaths: waveSystem.rifts,
      wave: game.state.wave.value,
    );
    if (rift == null) return;
    waveSystem.rifts.add(rift);
    destroyTowersOnPath(rift.points);
    game.audio.playBuild();
  }

  /// JS debugLevelUpRift: bump a random rift's tier with a flash.
  void debugLevelUpRift() {
    final rifts = waveSystem.rifts;
    if (rifts.isEmpty) return;
    final rift = rifts[waveSystem.rng.nextInt(rifts.length)];
    rift.level++;
    if (rift.points.isNotEmpty) {
      final s = rift.points.first;
      particles.createParticles(s.x, s.y, const Color(0xFFFF00AC), 30);
      lights.emit(x: s.x, y: s.y, radius: 200, color: const Color(0xFFFF00AC));
    }
    game.audio.playBuild();
  }

  /// JS debugUpgradeAllTowers: add N upgrade levels to every tower for free.
  /// Reuses Tower.upgrade() (which clamps range to kMaxTowerRange and does not
  /// touch money), so range stays capped — never infinite.
  void debugUpgradeAllTowers(int levels) {
    for (final t in game.entities.towers) {
      for (var i = 0; i < levels; i++) {
        t.upgrade();
      }
      particles.createParticles(
          t.position.x, t.position.y, const Color(0xFF00FF41), 8);
    }
    // Re-select the current tower so the selection panel shows new stats.
    final sel = game.selection.selectedTower;
    if (sel != null) game.selection.selectTower(sel);
    game.saveSystem.save();
  }

  void toggleNoBuildOverlay() {
    game.state.noBuildOverlay.value = !game.state.noBuildOverlay.value;
  }

  /// Lightweight bulk placement (no per-tower charge UI/sfx/select). Returns
  /// false if the tile is invalid. Cost is still deducted for consistency.
  bool _stressBuild(Vector2 worldPos, TowerType type) {
    final v = game.placement.validate(worldPos, type);
    if (!v.valid) return false;
    final hp = v.hardpoint;
    if (hp != null && hp.occupied) return false;
    hp?.occupied = true;
    game.state.money.value -= kTowers[type]!.cost;
    add(Tower(
        position: v.snap.clone(),
        type: type,
        spatialGrid: spatialGrid,
        hardpoint: hp));
    return true;
  }

  /// Debug: synthetic worst-case level for human perf evaluation — maxed base
  /// (1000 lives), ~20 level-1 rifts, a dense mix of every tower type around
  /// the roads/core (with a contiguous arc block that forms a connected
  /// network), and 100 mixed enemies. Mirrors the Godot/JS stress test.
  Future<void> debugStressTest() async {
    game.state.money.value = 10000000;
    game.state.lives.value = 1000;
    coreBase.level = 10;

    var attempts = 0;
    while (waveSystem.rifts.length < 20 && attempts < 80) {
      await debugCreateRift();
      attempts++;
    }
    for (final r in waveSystem.rifts) {
      r.level = 1;
      r.mutation = null;
    }

    final coreCol = worldCols ~/ 2;
    final coreRow = worldRows ~/ 2;
    Vector2 cellCenter(int col, int row) =>
        Vector2((col + 0.5) * kGridSize, (row + 0.5) * kGridSize);
    bool inBounds(int col, int row) =>
        col >= 1 && row >= 1 && col < worldCols - 1 && row < worldRows - 1;

    var placed = 0;
    // Connected arc cluster hugging the core (contiguous -> links), close to
    // where the rifts converge so the towers are actually in the fight.
    for (var dr = 3; dr <= 7; dr++) {
      for (var dc = 3; dc <= 7; dc++) {
        final col = coreCol + dc, row = coreRow + dr;
        if (inBounds(col, row) &&
            _stressBuild(cellCenter(col, row), TowerType.arc)) {
          placed++;
        }
      }
    }
    // Pack the other tower types into a tight ring AROUND the core (all valid
    // tiles within 8 cells) so every rift's final approach runs a gauntlet.
    const others = [TowerType.basic, TowerType.rapid, TowerType.sniper];
    for (var dr = -8; dr <= 8 && placed < 200; dr++) {
      for (var dc = -8; dc <= 8 && placed < 200; dc++) {
        if (dr == 0 && dc == 0) continue; // leave the core cell for the base
        if (dr >= 3 && dr <= 7 && dc >= 3 && dc <= 7) continue;
        final col = coreCol + dc, row = coreRow + dr;
        if (inBounds(col, row) &&
            _stressBuild(cellCenter(col, row),
                others[(dr.abs() + dc.abs()) % others.length])) {
          placed++;
        }
      }
    }
    markArcNetworkDirty();

    const etypes = [
      EnemyType.basic,
      EnemyType.fast,
      EnemyType.tank,
      EnemyType.splitter,
      EnemyType.bulwark,
      EnemyType.shifter,
      EnemyType.mini,
      EnemyType.boss,
    ];
    for (var i = 0; i < 100; i++) {
      debugSpawn(etypes[i % etypes.length]);
    }
    game.state.isWaveActive.value = true;
    game.state.showToast('STRESS: $placed towers / 100 enemies / '
        '${waveSystem.rifts.length} rifts');
    game.saveSystem.save();
  }

  /// Must only be called while gameplay is halted (game over, pause-menu
  /// reset, or save load) with isWaveActive already false: the registry and
  /// spatial grid are cleared synchronously here, while Flame drains the
  /// component-removal queue a frame later — wave-end checks running in
  /// that window would see an empty registry.
  void reset() {
    removeWhere((c) => c is Tower || c is Enemy || c is Projectile);
    game.entities.clear();
    arcTowerLinks.clear();
    _arcNetworkDirty = true;
    for (final hp in hardpointManager.hardpoints) {
      hp.occupied = false;
    }
    coreBase.level = 0;
    waveSystem.reset();
    spatialGrid.clear();
    abilitySystem.cancelTargeting();
  }
}
