import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../world/hardpoint_manager.dart';
import 'a_star.dart';

/// A generated rift path: list of world-space waypoints from spawn to core.
class RiftPath {
  final List<Vector2> points;
  int level; // tier 1+
  String? mutationKey;

  RiftPath({required this.points, this.level = 1, this.mutationKey});
}

/// Params passed into compute() — must be serializable (plain Dart types).
class _RiftParams {
  final int cols;
  final int rows;
  final int coreCenterCol;
  final int coreCenterRow;
  final int zone0RadiusCells;
  final Set<String> occupiedCells; // "col,row" strings
  final int wave;

  const _RiftParams({
    required this.cols,
    required this.rows,
    required this.coreCenterCol,
    required this.coreCenterRow,
    required this.zone0RadiusCells,
    required this.occupiedCells,
    required this.wave,
  });
}

/// Top-level function required by compute()
List<Map<String, int>>? _generateRiftIsolate(_RiftParams params) {
  final rng = Random();
  final obstacles = params.occupiedCells
      .map((s) {
        final parts = s.split(',');
        return GridPoint(int.parse(parts[0]), int.parse(parts[1]));
      })
      .toSet();

  // Pick a random edge start point (biased away from core)
  GridPoint? start;
  for (int attempt = 0; attempt < 20; attempt++) {
    final side = rng.nextInt(4);
    late int col, row;
    switch (side) {
      case 0: col = rng.nextInt(params.cols); row = 0; break;
      case 1: col = rng.nextInt(params.cols); row = params.rows - 1; break;
      case 2: col = 0; row = rng.nextInt(params.rows); break;
      default: col = params.cols - 1; row = rng.nextInt(params.rows); break;
    }
    final distToCore = sqrt(
        pow(col - params.coreCenterCol, 2) + pow(row - params.coreCenterRow, 2));
    if (distToCore > 30) {
      start = GridPoint(col, row);
      break;
    }
  }
  if (start == null) return null;

  final end = GridPoint(params.coreCenterCol, params.coreCenterRow);

  final result = findPath(
    start: start,
    end: end,
    cols: params.cols,
    rows: params.rows,
    obstacles: obstacles,
    zone0RadiusCells: params.zone0RadiusCells,
    coreCenterCol: params.coreCenterCol,
    coreCenterRow: params.coreCenterRow,
  );

  if (!result.found || result.path.length < 10) return null;

  return result.path
      .map((p) => {'col': p.col, 'row': p.row})
      .toList();
}

class RiftGenerator {
  final int worldCols;
  final int worldRows;
  final HardpointManager hardpointManager;

  RiftGenerator(this.worldCols, this.worldRows, this.hardpointManager);

  int get _coreCenterCol => worldCols ~/ 2;
  int get _coreCenterRow => worldRows ~/ 2;

  Future<RiftPath?> generateRift({
    required List<RiftPath> existingPaths,
    required int wave,
  }) async {
    // Build occupied cells from hardpoints (can't path through them)
    final occupied = <String>{};
    for (final hp in hardpointManager.hardpoints) {
      occupied.add('${hp.col},${hp.row}');
    }

    final params = _RiftParams(
      cols: worldCols,
      rows: worldRows,
      coreCenterCol: _coreCenterCol,
      coreCenterRow: _coreCenterRow,
      zone0RadiusCells: kZone0RadiusCells,
      occupiedCells: occupied,
      wave: wave,
    );

    // compute() = Isolate on mobile, sync on web (both compile correctly)
    final rawPath = await compute(_generateRiftIsolate, params);
    if (rawPath == null) return null;

    final points = rawPath
        .map((p) => Vector2(
              p['col']! * kGridSize + kGridSize / 2,
              p['row']! * kGridSize + kGridSize / 2,
            ))
        .toList();

    return RiftPath(points: points);
  }
}
