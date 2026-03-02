import 'package:flame/components.dart';

import '../entities/enemies/enemy.dart';

const double _cellSize = 200.0;

class SpatialGrid {
  final Map<int, List<Enemy>> _cells = {};

  void clear() => _cells.clear();

  int _key(int cx, int cy) => cx * 100000 + cy;

  void insert(Enemy enemy) {
    final key = _cellKey(enemy.position);
    _cells.putIfAbsent(key, () => []).add(enemy);
  }

  void remove(Enemy enemy) {
    final key = _cellKey(enemy.position);
    _cells[key]?.remove(enemy);
  }

  void update(Enemy enemy, Vector2 oldPos) {
    final oldKey = _cellKey(oldPos);
    final newKey = _cellKey(enemy.position);
    if (oldKey != newKey) {
      _cells[oldKey]?.remove(enemy);
      _cells.putIfAbsent(newKey, () => []).add(enemy);
    }
  }

  List<Enemy> queryRadius(Vector2 center, double radius) {
    final result = <Enemy>[];
    final minCx = ((center.x - radius) / _cellSize).floor();
    final maxCx = ((center.x + radius) / _cellSize).floor();
    final minCy = ((center.y - radius) / _cellSize).floor();
    final maxCy = ((center.y + radius) / _cellSize).floor();
    final r2 = radius * radius;

    for (int cx = minCx; cx <= maxCx; cx++) {
      for (int cy = minCy; cy <= maxCy; cy++) {
        final cell = _cells[_key(cx, cy)];
        if (cell == null) continue;
        for (final enemy in cell) {
          if (enemy.isDead) continue;
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
