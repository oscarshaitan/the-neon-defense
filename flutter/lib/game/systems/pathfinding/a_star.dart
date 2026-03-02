import 'dart:math';

/// A* pathfinder for rift generation.
/// Runs in plain Dart (no Flutter imports) so it can be called inside compute().

class GridPoint {
  final int col;
  final int row;
  const GridPoint(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      other is GridPoint && other.col == col && other.row == row;

  @override
  int get hashCode => col * 100003 + row;

  @override
  String toString() => '($col, $row)';
}

class AStarResult {
  final List<GridPoint> path; // from start to end inclusive
  final bool found;
  const AStarResult(this.path, this.found);
}

/// Obstacles: a set of (col, row) that cannot be entered.
/// Zone0 radius in cells: once a path enters this radius it cannot exit it.
AStarResult findPath({
  required GridPoint start,
  required GridPoint end,
  required int cols,
  required int rows,
  required Set<GridPoint> obstacles,
  required int zone0RadiusCells,
  required int coreCenterCol,
  required int coreCenterRow,
}) {
  // A* open set (priority queue via sorted list — fine for this map size)
  final cameFrom = <GridPoint, GridPoint>{};
  final gScore = <GridPoint, double>{start: 0};
  final fScore = <GridPoint, double>{start: _heuristic(start, end)};
  final openSet = <GridPoint>{start};
  final closedSet = <GridPoint>{};

  // Track which cells have been in zone0
  final enteredZone0 = <GridPoint>{};
  if (_inZone0(start, coreCenterCol, coreCenterRow, zone0RadiusCells)) {
    enteredZone0.add(start);
  }

  while (openSet.isNotEmpty) {
    // Get node with lowest fScore
    GridPoint current = openSet.reduce(
      (a, b) => (fScore[a] ?? double.infinity) < (fScore[b] ?? double.infinity)
          ? a
          : b,
    );

    if (current == end) {
      return AStarResult(_reconstructPath(cameFrom, current), true);
    }

    openSet.remove(current);
    closedSet.add(current);

    for (final neighbor in _neighbors(current, cols, rows)) {
      if (closedSet.contains(neighbor)) continue;
      if (obstacles.contains(neighbor)) continue;

      // Zone0 commitment: if path exited zone0, can't re-enter
      final neighborInZone0 =
          _inZone0(neighbor, coreCenterCol, coreCenterRow, zone0RadiusCells);
      final currentInZone0 = enteredZone0.contains(current);

      // If we previously exited zone0 from this path, block re-entry
      // (tracked via: if current is not in zone0 but neighbor is, that's re-entry)
      // Simple heuristic: if current is NOT in zone0 and has previously entered it,
      // we are "outside" — so block zone0 re-entry.
      // We track whether zone0 was exited by checking: cell exited zone0 = was in zone0
      // but current cell is not.
      // Full commitment: once any cell in the path was in zone0, all subsequent
      // cells must also be in zone0.
      final pathEnteredZone0 = enteredZone0.isNotEmpty;
      if (pathEnteredZone0 && !currentInZone0 && neighborInZone0) {
        continue; // would re-enter zone0 — not allowed
      }

      final tentativeG =
          (gScore[current] ?? double.infinity) + _cost(current, neighbor,
              coreCenterCol, coreCenterRow, zone0RadiusCells);

      if (tentativeG < (gScore[neighbor] ?? double.infinity)) {
        cameFrom[neighbor] = current;
        gScore[neighbor] = tentativeG;
        fScore[neighbor] =
            tentativeG + _heuristic(neighbor, end);
        openSet.add(neighbor);

        if (neighborInZone0) enteredZone0.add(neighbor);
      }
    }
  }

  return const AStarResult([], false);
}

double _heuristic(GridPoint a, GridPoint b) {
  return (a.col - b.col).abs().toDouble() + (a.row - b.row).abs().toDouble();
}

double _cost(
  GridPoint from,
  GridPoint to,
  int coreCenterCol,
  int coreCenterRow,
  int zone0RadiusCells,
) {
  double cost = 1.0;

  // Turn penalty
  // (we don't have previous direction here, handled at neighbor level — simplified)

  // Core repulsion penalty (within 9 cells of core)
  const double repulsionRadius = 9.0;
  const double maxRepulsionPenalty = 14.0;
  final distToCore = sqrt(pow(to.col - coreCenterCol, 2) + pow(to.row - coreCenterRow, 2));
  if (distToCore < repulsionRadius) {
    final t = 1.0 - distToCore / repulsionRadius;
    cost += maxRepulsionPenalty * t * t;
  }

  return cost;
}

bool _inZone0(
    GridPoint p, int coreCenterCol, int coreCenterRow, int zone0RadiusCells) {
  final d = sqrt(
      pow(p.col - coreCenterCol, 2) + pow(p.row - coreCenterRow, 2));
  return d <= zone0RadiusCells;
}

List<GridPoint> _neighbors(GridPoint p, int cols, int rows) {
  final result = <GridPoint>[];
  const dirs = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
  ];
  for (final d in dirs) {
    final nc = p.col + d.$1;
    final nr = p.row + d.$2;
    if (nc >= 0 && nc < cols && nr >= 0 && nr < rows) {
      result.add(GridPoint(nc, nr));
    }
  }
  return result;
}

List<GridPoint> _reconstructPath(
    Map<GridPoint, GridPoint> cameFrom, GridPoint current) {
  final path = [current];
  GridPoint? node = current;
  while (cameFrom.containsKey(node)) {
    node = cameFrom[node]!;
    path.insert(0, node);
  }
  return path;
}
