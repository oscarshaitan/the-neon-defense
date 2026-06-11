import 'dart:math';

/// Faithful port of the JS grid pathfinder `findPathOnGrid`
/// (04_tutorial.js:637-766). Plain Dart (no Flutter imports) so it can run
/// inside compute().

class Cell {
  final int c;
  final int r;
  const Cell(this.c, this.r);

  @override
  bool operator ==(Object other) => other is Cell && other.c == c && other.r == r;

  @override
  int get hashCode => c * 100003 + r;

  @override
  String toString() => '($c, $r)';
}

/// JS PATHING_RULES (00_core.js:17-23).
class PathingRules {
  static const double coreRepulsionRadius = 9; // grid cells
  static const double coreRepulsionStrength = 14; // extra path cost near core
  static const double nearCoreStraightRadius = 8; // grid cells
  static const double nearCoreTurnPenaltyBoost = 18; // extra turn cost near core
  static const double mergeMinCoreDistance = 7; // prefer merges away from core
}

class _Node {
  final int c;
  final int r;
  double g;
  final double h;
  double f;
  _Node? parent;
  int? dc;
  int? dr;
  bool enteredZone0;

  _Node({
    required this.c,
    required this.r,
    required this.g,
    required this.h,
    required this.f,
    this.parent,
    this.dc,
    this.dr,
    required this.enteredZone0,
  });
}

bool isCellInsideZone0(int c, int r, int coreC, int coreR, int zone0Radius) {
  final dx = c - coreC;
  final dy = r - coreR;
  return sqrt((dx * dx + dy * dy).toDouble()) < zone0Radius;
}

double coreRepulsionPenalty(int c, int r, int coreC, int coreR) {
  final dx = c - coreC;
  final dy = r - coreR;
  final distToCore = sqrt((dx * dx + dy * dy).toDouble());
  if (distToCore >= PathingRules.coreRepulsionRadius) return 0;
  final t = 1 - (distToCore / PathingRules.coreRepulsionRadius);
  return PathingRules.coreRepulsionStrength * t * t;
}

/// Returns path as grid cells from start to end inclusive, or null.
/// [allowedObstacleKeys] are obstacle cells that may still be entered
/// (merge points). Once a route enters zone 0 it cannot step back outside.
List<Cell>? findPathOnGrid({
  required Cell start,
  required Cell end,
  required int cols,
  required int rows,
  required Set<Cell> obstacles,
  Set<Cell>? allowedObstacles,
  Cell? coreNode,
  bool lockZone0AfterEntry = false,
  int zone0Radius = 6,
}) {
  final allowed = allowedObstacles ?? const <Cell>{};
  final lock = lockZone0AfterEntry && coreNode != null;
  final startsInsideZone0 = lock &&
      isCellInsideZone0(start.c, start.r, coreNode.c, coreNode.r, zone0Radius);

  bool isInCurrentBranch(_Node? node, int c, int r) {
    var cursor = node;
    while (cursor != null) {
      if (cursor.c == c && cursor.r == r) return true;
      cursor = cursor.parent;
    }
    return false;
  }

  double heuristic(int c, int r) =>
      ((c - end.c).abs() + (r - end.r).abs()).toDouble();

  final openSet = <_Node>[
    _Node(
      c: start.c,
      r: start.r,
      g: 0,
      h: heuristic(start.c, start.r),
      f: heuristic(start.c, start.r),
      enteredZone0: startsInsideZone0,
    ),
  ];
  final closedSet = <String, double>{};

  while (openSet.isNotEmpty) {
    var bestIndex = 0;
    for (var i = 1; i < openSet.length; i++) {
      if (openSet[i].f < openSet[bestIndex].f) bestIndex = i;
    }
    final current = openSet.removeAt(bestIndex);

    if (current.c == end.c && current.r == end.r) {
      final pathCells = <Cell>[];
      final uniqueCells = <Cell>{};
      _Node? temp = current;
      while (temp != null) {
        final cell = Cell(temp.c, temp.r);
        if (uniqueCells.contains(cell)) return null;
        uniqueCells.add(cell);
        pathCells.insert(0, cell);
        temp = temp.parent;
      }
      return pathCells;
    }

    closedSet['${current.c},${current.r},${current.enteredZone0 ? 1 : 0}'] =
        current.g;

    const dirs = [(0, -1), (1, 0), (0, 1), (-1, 0)];
    for (final (dc, dr) in dirs) {
      final nc = current.c + dc;
      final nr = current.r + dr;
      if (nc < 0 || nc >= cols || nr < 0 || nr >= rows) continue;

      final nCell = Cell(nc, nr);
      // Hard block occupied tiles; merge allowed only at approved cells.
      if (obstacles.contains(nCell) && !allowed.contains(nCell)) continue;
      // Prevent branch loops/folding over itself while searching.
      if (isInCurrentBranch(current, nc, nr)) continue;

      final nextInsideZone0 = lock &&
          isCellInsideZone0(nc, nr, coreNode.c, coreNode.r, zone0Radius);
      final nextEnteredZone0 =
          lock ? (current.enteredZone0 || nextInsideZone0) : false;
      // Once route enters Zone 0, it cannot step back outside.
      if (lock && current.enteredZone0 && !nextInsideZone0) continue;

      var cost = 1.0;
      final isTurning =
          current.dc != null && (current.dc != dc || current.dr != dr);
      if (isTurning) {
        cost += 5; // JS baseline turn penalty
      }

      final distToCore = sqrt(
          (pow(nc - end.c, 2) + pow(nr - end.r, 2)).toDouble());
      if (isTurning && distToCore < PathingRules.nearCoreStraightRadius) {
        final turnBias = 1 - (distToCore / PathingRules.nearCoreStraightRadius);
        cost += PathingRules.nearCoreTurnPenaltyBoost * turnBias;
      }
      cost += coreRepulsionPenalty(nc, nr, end.c, end.r);

      final g = current.g + cost;
      final stateKey = '$nc,$nr,${nextEnteredZone0 ? 1 : 0}';
      final closedG = closedSet[stateKey];
      if (closedG != null && closedG <= g) continue;

      var inOpen = false;
      for (final node in openSet) {
        if (node.c == nc &&
            node.r == nr &&
            node.enteredZone0 == nextEnteredZone0) {
          if (node.g > g) {
            node.g = g;
            node.f = g + node.h;
            node.parent = current;
            node.dc = dc;
            node.dr = dr;
            node.enteredZone0 = nextEnteredZone0;
          }
          inOpen = true;
          break;
        }
      }

      if (!inOpen) {
        final h = heuristic(nc, nr);
        openSet.add(_Node(
          c: nc,
          r: nr,
          g: g,
          h: h,
          f: g + h,
          parent: current,
          dc: dc,
          dr: dr,
          enteredZone0: nextEnteredZone0,
        ));
      }
    }
  }
  return null;
}
