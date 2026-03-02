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
    final g = gameWorld.game;
    if (g.gameState != 'playing' || g.isPaused) return;

    if (isPrepPhase) {
      prepTimer -= dt;
      if (prepTimer <= 0) {
        _startWave();
      }
      return;
    }

    if (g.isWaveActive) {
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
    g.isWaveActive = true;
    spawnQueue.clear();
    spawnTimer = 0;
    enemiesSpawned = 0;

    // Build spawn queue
    final count = 5 + (g.wave * 2.5).floor();
    totalEnemies = count;
    for (int i = 0; i < count; i++) {
      spawnQueue.add(_pickEnemyType(g.wave));
    }
  }

  void _endWave() {
    final g = gameWorld.game;
    g.isWaveActive = false;
    g.wave++;
    startPrepPhase();
  }

  void _spawnNext() {
    if (spawnQueue.isEmpty || rifts.isEmpty) return;
    final type = spawnQueue.removeAt(0);
    final rift = rifts[_rng.nextInt(rifts.length)];
    final def = kEnemies[type]!;
    final g = gameWorld.game;

    // Scale HP by wave
    final scaledHp = def.hp * (1.0 + g.wave * 0.4);

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
    return gameWorld.children.whereType<Enemy>().isEmpty;
  }

  EnemyType _pickEnemyType(int wave) {
    // Distribution shifts by wave — matches JS logic
    final roll = _rng.nextDouble();
    if (wave >= 30 && roll < 0.08) return EnemyType.shifter;
    if (wave >= 20 && roll < 0.10) return EnemyType.bulwark;
    if (wave >= 15 && roll < 0.12) return EnemyType.splitter;
    if (wave % 10 == 0 && roll < 0.05) return EnemyType.boss;
    if (wave >= 5 && roll < 0.15) return EnemyType.tank;
    if (wave >= 3 && roll < 0.25) return EnemyType.fast;
    return EnemyType.basic;
  }

  Future<void> _generateMissingRifts() async {
    // Wave 1: 1 rift; +1 every 10 waves to wave 50; +1 every 5 waves after
    final g = gameWorld.game;
    int targetRifts;
    if (g.wave <= 50) {
      targetRifts = 1 + (g.wave - 1) ~/ 10;
    } else {
      targetRifts = 6 + (g.wave - 51) ~/ 5;
    }
    targetRifts = targetRifts.clamp(1, 20);

    while (rifts.length < targetRifts) {
      final rift = await gameWorld.riftGenerator.generateRift(
        existingPaths: rifts,
        wave: g.wave,
      );
      if (rift != null) {
        rifts.add(rift);
      } else {
        break; // couldn't generate more
      }
    }
  }
}
