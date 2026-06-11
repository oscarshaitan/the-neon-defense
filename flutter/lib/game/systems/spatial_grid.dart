import 'package:flame/components.dart';

import '../config/constants.dart';
import '../entities/enemies/enemy.dart';

const double _cellSize = 200.0;

/// Enemy spatial hash (JS ENEMY_SPATIAL_GRID, 200-unit cells) with a taunter
/// (bulwark) sub-index. Invisible shifters are excluded from queries, matching
/// the JS targetable cache (05_loop.js:592-624).
class SpatialGrid {
  final Map<int, List<Enemy>> _cells = {};
  final Map<int, List<Enemy>> _taunterCells = {};

  void clear() {
    _cells.clear();
    _taunterCells.clear();
  }

  int _key(int cx, int cy) => cx * 100000 + cy;

  void insert(Enemy enemy) {
    final key = _cellKey(enemy.position);
    _cells.putIfAbsent(key, () => []).add(enemy);
    if (enemy.type == EnemyType.bulwark) {
      _taunterCells.putIfAbsent(key, () => []).add(enemy);
    }
  }

  void remove(Enemy enemy) {
    final key = _cellKey(enemy.position);
    _cells[key]?.remove(enemy);
    if (enemy.type == EnemyType.bulwark) {
      _taunterCells[key]?.remove(enemy);
    }
  }

  void update(Enemy enemy, Vector2 oldPos) {
    final oldKey = _cellKey(oldPos);
    final newKey = _cellKey(enemy.position);
    if (oldKey != newKey) {
      _cells[oldKey]?.remove(enemy);
      _cells.putIfAbsent(newKey, () => []).add(enemy);
      if (enemy.type == EnemyType.bulwark) {
        _taunterCells[oldKey]?.remove(enemy);
        _taunterCells.putIfAbsent(newKey, () => []).add(enemy);
      }
    }
  }

  List<Enemy> queryRadius(Vector2 center, double radius) =>
      _query(_cells, center, radius);

  /// Bulwarks only — towers check these first (taunt priority).
  List<Enemy> queryTaunters(Vector2 center, double radius) =>
      _query(_taunterCells, center, radius);

  List<Enemy> _query(
      Map<int, List<Enemy>> cells, Vector2 center, double radius) {
    final result = <Enemy>[];
    final minCx = ((center.x - radius) / _cellSize).floor();
    final maxCx = ((center.x + radius) / _cellSize).floor();
    final minCy = ((center.y - radius) / _cellSize).floor();
    final maxCy = ((center.y + radius) / _cellSize).floor();
    final r2 = radius * radius;

    for (int cx = minCx; cx <= maxCx; cx++) {
      for (int cy = minCy; cy <= maxCy; cy++) {
        final cell = cells[_key(cx, cy)];
        if (cell == null) continue;
        for (final enemy in cell) {
          if (enemy.isDead) continue;
          if (enemy.isInvisible) continue; // JS excludes from targetable cache
          if (enemy.position.distanceToSquared(center) <= r2) {
            result.add(enemy);
          }
        }
      }
    }
    return result;
  }

  int _cellKey(Vector2 pos) {
    final cx = (pos.x / _cellSize).floor();
    final cy = (pos.y / _cellSize).floor();
    return _key(cx, cy);
  }
}
