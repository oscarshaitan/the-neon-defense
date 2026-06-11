import 'dart:math';
import 'dart:ui' show Color;
import 'package:flame/components.dart';

import '../config/constants.dart';
import '../world/game_world.dart';
import '../entities/enemies/enemy.dart';
import 'pathfinding/rift_generator.dart';

class WaveSystem extends Component with HasGameReference {
  final GameWorld gameWorld;

  final List<RiftPath> rifts = [];
  final List<EnemyType> spawnQueue = [];

  double prepTimer = 0;
  bool isPrepPhase = false;
  int spawnTimer = 0;
  int totalEnemies = 0;
  int enemiesSpawned = 0;

  /// Actual composition of the running wave (JS currentWaveDistribution).
  Map<EnemyType, int>? currentWaveDistribution;

  final rng = Random();

  WaveSystem(this.gameWorld);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void startPrepPhase() {
    isPrepPhase = true;
    prepTimer = kPrepTimerSeconds.toDouble();
    _generateMissingRifts();
  }

  void skipPrep() {
    if (isPrepPhase) prepTimer = 0;
  }

  void reset() {
    rifts.clear();
    spawnQueue.clear();
    isPrepPhase = false;
    prepTimer = 0;
    spawnTimer = 0;
    enemiesSpawned = 0;
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  @override
  void update(double dt) {
    // Pause/phase gating is centralized in GameWorld.updateTree.
    final g = gameWorld.game;

    if (isPrepPhase) {
      prepTimer -= dt;
      if (prepTimer <= 0) {
        _startWave();
      }
      return;
    }

    if (g.state.isWaveActive.value) {
      spawnTimer++;
      if (spawnTimer >= kSpawnIntervalFrames && spawnQueue.isNotEmpty) {
        spawnTimer = 0;
        _spawnNext();
      }

      // Wave end: no enemies left and queue empty
      if (spawnQueue.isEmpty && _noEnemiesAlive()) {
        _endWave();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _startWave() {
    isPrepPhase = false;
    final g = gameWorld.game;
    g.state.isWaveActive.value = true;
    spawnQueue.clear();
    spawnTimer = 0;
    enemiesSpawned = 0;

    final wave = g.state.wave.value;

    // Clear temporal mutations — unlike rift tiers, mutations only last
    // for the wave they occur in (JS startWave, 03_abilities.js:819-821).
    for (final r in rifts) {
      r.mutation = null;
    }

    // Rift upgrades (post wave 50) — PERMANENT: 10% chance per rift.
    if (wave > 50) {
      for (final r in rifts) {
        if (rng.nextDouble() < 0.10) r.level++;
      }
    }

    // Mutation event every 20 waves (JS generateMutation).
    if (wave % 20 == 0 && rifts.isNotEmpty) {
      final target = rifts[rng.nextInt(rifts.length)];
      target.mutation = kMutationProfiles[rng.nextInt(kMutationProfiles.length)];
      g.audio.playHit(); // JS mutation alert sound
    }

    // Build spawn queue — matches JS startWave() exactly
    final count = 5 + (wave * 2.5).floor();
    for (int i = 0; i < count; i++) {
      EnemyType type;
      final r = rng.nextDouble();

      if (wave < 3) {
        type = EnemyType.basic;
      } else if (wave < 5) {
        type = r < 0.3 ? EnemyType.fast : EnemyType.basic;
      } else if (wave < 10) {
        if (wave % 5 == 0 && i < 2) {
          type = EnemyType.tank;
        } else if (r < 0.2) {
          type = EnemyType.fast;
        } else if (r < 0.25) {
          type = EnemyType.tank;
        } else {
          type = EnemyType.basic;
        }
      } else {
        final chance = rng.nextDouble();
        if (chance < 0.08 && wave >= 30) {
          type = EnemyType.shifter;
        } else if (chance < 0.15 && wave >= 20) {
          type = EnemyType.bulwark;
        } else if (chance < 0.30 && wave >= 15) {
          type = EnemyType.splitter;
        } else if (chance < 0.50) {
          type = EnemyType.fast;
        } else if (chance < 0.70) {
          type = EnemyType.tank;
        } else {
          type = EnemyType.basic;
        }
      }
      spawnQueue.add(type);
    }

    // Boss wave: insert boss at random queue position (JS: wave % 10 === 0)
    if (wave % 10 == 0) {
      final idx = rng.nextInt(spawnQueue.length + 1);
      spawnQueue.insert(idx, EnemyType.boss);
    }

    // Surprise boss after wave 50 (JS: 25% chance)
    if (wave > 50 && wave % 5 == 0 && wave % 10 != 0) {
      if (rng.nextDouble() < 0.25) {
        final idx = rng.nextInt(spawnQueue.length + 1);
        spawnQueue.insert(idx, EnemyType.boss);
        g.audio.playHit(); // JS surprise-boss alert
      }
    }

    totalEnemies = spawnQueue.length;
    currentWaveDistribution = <EnemyType, int>{};
    for (final t in spawnQueue) {
      currentWaveDistribution![t] = (currentWaveDistribution![t] ?? 0) + 1;
    }
    g.audio.playBuild(); // JS plays 'build' on wave start
    g.saveSystem.save(); // JS saves on wave start
    g.tutorial.onWaveStarted();
    g.hints.maybeShowCameraHint();
  }

  void _endWave() {
    final g = gameWorld.game;
    g.state.isWaveActive.value = false;
    g.state.wave.value++;
    startPrepPhase();
    g.saveSystem.save(); // JS saves on wave completion
  }

  /// JS spawnEnemy (05_loop.js:812-873): wave HP scaling, then rift tier
  /// scaling, then mutation multipliers.
  void _spawnNext() {
    if (spawnQueue.isEmpty || rifts.isEmpty) return;
    final type = spawnQueue.removeAt(0);
    final rift = rifts[rng.nextInt(rifts.length)];
    final def = kEnemies[type]!;
    final g = gameWorld.game;
    final riftLevel = rift.level;
    final mutation = rift.mutation;

    var hp = def.hp * (1.0 + g.state.wave.value * 0.4);
    var speed = def.speed;
    var reward = def.reward;
    var color = def.color;
    var isMutant = false;

    // Rift tier (elite scaling): +50% HP, +15% speed, +50% reward per level.
    if (riftLevel > 1) {
      hp *= 1 + (riftLevel - 1) * 0.5;
      speed *= 1 + (riftLevel - 1) * 0.15;
      reward = (reward * (1 + (riftLevel - 1) * 0.5)).floorToDouble();
    }

    // Rift mutation (lasts this wave only).
    if (mutation != null) {
      hp *= mutation.hpMulti;
      speed *= mutation.speedMulti;
      reward = (reward * mutation.rewardMulti).floorToDouble();
      color = Color(mutation.colorValue);
      isMutant = true;
    }

    final enemy = Enemy(
      type: type,
      hp: hp,
      speed: speed,
      color: color,
      reward: reward,
      width: def.width,
      path: rift.points,
      riftLevel: riftLevel,
      isMutant: isMutant,
      mutationKey: mutation?.key,
      spatialGrid: gameWorld.spatialGrid,
    );
    gameWorld.add(enemy);
    // JS: boss spawns flash a big orange light (r150 #ff8800).
    if (type == EnemyType.boss) {
      gameWorld.lights.emit(
          x: enemy.position.x,
          y: enemy.position.y,
          radius: 150,
          color: const Color(0xFFFF8800));
    }
    enemiesSpawned++;
  }

  bool _noEnemiesAlive() {
    return gameWorld.game.entities.enemies.isEmpty;
  }

Future<void> _generateMissingRifts() async {
    // Wave 1: 1 rift; +1 every 10 waves to wave 50; +1 every 5 waves after
    final wave = gameWorld.game.state.wave.value;
    int targetRifts;
    if (wave <= 50) {
      targetRifts = 1 + (wave - 1) ~/ 10;
    } else {
      targetRifts = 6 + (wave - 51) ~/ 5;
    }
    targetRifts = targetRifts.clamp(1, 20);

    while (rifts.length < targetRifts) {
      final rift = await gameWorld.riftGenerator.generateRift(
        existingPaths: rifts,
        wave: wave,
      );
      if (rift != null) {
        rifts.add(rift);
        // New rifts destroy overlapping non-hardpoint towers (70% refund).
        gameWorld.destroyTowersOnPath(rift.points);
      } else {
        break; // couldn't generate more
      }
    }
  }
}
