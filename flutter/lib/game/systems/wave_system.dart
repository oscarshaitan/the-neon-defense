import 'dart:math';
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

  final _rng = Random();

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

    // Build spawn queue — matches JS startWave() exactly
    final wave = g.state.wave.value;
    final count = 5 + (wave * 2.5).floor();
    for (int i = 0; i < count; i++) {
      EnemyType type;
      final r = _rng.nextDouble();

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
        final chance = _rng.nextDouble();
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
      final idx = _rng.nextInt(spawnQueue.length + 1);
      spawnQueue.insert(idx, EnemyType.boss);
    }

    // Surprise boss after wave 50 (JS: 25% chance)
    if (wave > 50 && wave % 5 == 0 && wave % 10 != 0) {
      if (_rng.nextDouble() < 0.25) {
        final idx = _rng.nextInt(spawnQueue.length + 1);
        spawnQueue.insert(idx, EnemyType.boss);
      }
    }

    totalEnemies = spawnQueue.length;
  }

  void _endWave() {
    final g = gameWorld.game;
    g.state.isWaveActive.value = false;
    g.state.wave.value++;
    startPrepPhase();
  }

  void _spawnNext() {
    if (spawnQueue.isEmpty || rifts.isEmpty) return;
    final type = spawnQueue.removeAt(0);
    final rift = rifts[_rng.nextInt(rifts.length)];
    final def = kEnemies[type]!;
    final g = gameWorld.game;

    // Scale HP by wave
    final scaledHp = def.hp * (1.0 + g.state.wave.value * 0.4);

    final enemy = Enemy(
      type: type,
      hp: scaledHp,
      speed: def.speed,
      color: def.color,
      reward: def.reward,
      width: def.width,
      path: rift.points,
      riftLevel: rift.level,
      spatialGrid: gameWorld.spatialGrid,
    );
    gameWorld.add(enemy);
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
      } else {
        break; // couldn't generate more
      }
    }
  }
}
