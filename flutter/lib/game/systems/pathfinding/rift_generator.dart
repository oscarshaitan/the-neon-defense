import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../world/hardpoint_manager.dart';
import 'a_star.dart';

/// A rift mutation — lasts one wave, applied to all enemies spawning from
/// the mutated rift (JS generateMutation, 03_abilities.js:903-929).
class Mutation {
  final String key;
  final String name;
  final int colorValue; // ARGB int so it survives isolate/save round-trips
  final double hpMulti;
  final double speedMulti;
  final double rewardMulti;

  const Mutation({
    required this.key,
    required this.name,
    required this.colorValue,
    required this.hpMulti,
    required this.speedMulti,
    required this.rewardMulti,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'color': colorValue,
        'hpMulti': hpMulti,
        'speedMulti': speedMulti,
        'rewardMulti': rewardMulti,
      };

  static Mutation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return Mutation(
      key: json['key'] as String,
      name: json['name'] as String,
      colorValue: json['color'] as int,
      hpMulti: (json['hpMulti'] as num).toDouble(),
      speedMulti: (json['speedMulti'] as num).toDouble(),
      rewardMulti: (json['rewardMulti'] as num).toDouble(),
    );
  }
}

/// JS mutation profiles (03_abilities.js:908-914).
const List<Mutation> kMutationProfiles = [
  Mutation(key: 'CRIMSON', name: 'CRIMSON', colorValue: 0xFFFF0033, hpMulti: 1.6, speedMulti: 1.2, rewardMulti: 2.0),
  Mutation(key: 'VOID', name: 'VOID', colorValue: 0xFFAA00FF, hpMulti: 1.4, speedMulti: 1.5, rewardMulti: 2.5),
  Mutation(key: 'TITAN', name: 'TITAN', colorValue: 0xFF00FFAA, hpMulti: 3.0, speedMulti: 0.7, rewardMulti: 3.0),
  Mutation(key: 'PHASE', name: 'PHASE', colorValue: 0xFFFFFFFF, hpMulti: 1.2, speedMulti: 2.0, rewardMulti: 1.5),
  Mutation(key: 'NEON', name: 'NEON', colorValue: 0xFFFCEE0A, hpMulti: 1.8, speedMulti: 1.3, rewardMulti: 2.0),
];

/// A generated rift path: world-space waypoints from spawn to core.
class RiftPath {
  final List<Vector2> points;
  int level; // tier 1+
  final int zone; // orbital zone of the spawn point
  Mutation? mutation;

  RiftPath({required this.points, this.level = 1, this.zone = 1, this.mutation});
}

// ---------------------------------------------------------------------------
// Isolate params/result — plain serializable types only.
// ---------------------------------------------------------------------------

class _RiftParams {
  final int cols;
  final int rows;
  final int coreC;
  final int coreR;
  final int zone0Radius;
  final List<List<int>> hardpointCells; // [c, r]
  final List<List<int>> coreHardpointCells; // [c, r] — for gap sectors
  // Existing paths: cells flattened per path + zone per path.
  final List<List<List<int>>> pathCells; // path -> [c, r] list
  final List<int> pathZones;
  final int wave;
  final bool initial; // first rift uses JS calculatePath rules
  final int seed;

  const _RiftParams({
    required this.cols,
    required this.rows,
    required this.coreC,
    required this.coreR,
    required this.zone0Radius,
    required this.hardpointCells,
    required this.coreHardpointCells,
    required this.pathCells,
    required this.pathZones,
    required this.wave,
    required this.initial,
    required this.seed,
  });
}

class _RiftResult {
  final List<List<int>> points; // [c, r]
  final int zone;
  const _RiftResult(this.points, this.zone);
}

// ---------------------------------------------------------------------------
// Gap sector helpers (JS 01_init.js:734-807)
// ---------------------------------------------------------------------------

double _normalizeAngle(double angle) {
  const twoPi = pi * 2;
  var a = angle % twoPi;
  if (a < 0) a += twoPi;
  return a;
}

class _GapSector {
  final int index;
  final double startAngle;
  final double endAngle;
  final double centerAngle;
  const _GapSector(this.index, this.startAngle, this.endAngle, this.centerAngle);
}

List<_GapSector> _getCoreGapSectors(
    List<List<int>> coreSlots, int coreC, int coreR) {
  final angles = coreSlots
      .map((hp) =>
          _normalizeAngle(atan2((hp[1] - coreR).toDouble(), (hp[0] - coreC).toDouble())))
      .toList()
    ..sort();
  if (angles.length < 2) return [];

  final sectors = <_GapSector>[];
  for (var i = 0; i < angles.length; i++) {
    final startAngle = angles[i];
    var endAngle = angles[(i + 1) % angles.length];
    if (endAngle <= startAngle) endAngle += pi * 2;
    sectors.add(_GapSector(
        i, startAngle, endAngle, _normalizeAngle((startAngle + endAngle) / 2)));
  }
  return sectors;
}

int? _getCoreGapIndexForCell(
    int c, int r, int coreC, int coreR, List<_GapSector> gapSectors) {
  if (gapSectors.isEmpty) return null;
  if (c == coreC && r == coreR) return null;

  final angle = _normalizeAngle(atan2((r - coreR).toDouble(), (c - coreC).toDouble()));
  for (final sector in gapSectors) {
    var testAngle = angle;
    if (testAngle < sector.startAngle) testAngle += pi * 2;
    if (testAngle >= sector.startAngle && testAngle < sector.endAngle) {
      return sector.index;
    }
  }
  return gapSectors[0].index;
}

int? _getCoreEntryGapFromPath(List<List<int>> pathCells, int coreC, int coreR,
    List<_GapSector> gapSectors, int zone0Radius) {
  if (pathCells.length < 2 || gapSectors.isEmpty) return null;

  List<int>? entryCell;
  for (var i = 1; i < pathCells.length; i++) {
    final prev = pathCells[i - 1];
    final curr = pathCells[i];
    final prevDist = sqrt(
        (pow(prev[0] - coreC, 2) + pow(prev[1] - coreR, 2)).toDouble());
    final currDist = sqrt(
        (pow(curr[0] - coreC, 2) + pow(curr[1] - coreR, 2)).toDouble());
    if (prevDist >= zone0Radius && currDist < zone0Radius) {
      entryCell = prev;
      break;
    }
  }
  entryCell ??= pathCells[pathCells.length - 2];
  return _getCoreGapIndexForCell(
      entryCell[0], entryCell[1], coreC, coreR, gapSectors);
}

bool _pathRespectsZone0Commitment(List<Cell> cells, int coreC, int coreR,
    int zone0Radius, int startIndex) {
  var enteredZone0 = false;
  for (var i = max(0, startIndex); i < cells.length; i++) {
    final inside =
        isCellInsideZone0(cells[i].c, cells[i].r, coreC, coreR, zone0Radius);
    if (inside) {
      enteredZone0 = true;
    } else if (enteredZone0) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Isolate entry point
// ---------------------------------------------------------------------------

_RiftResult? _generateRiftIsolate(_RiftParams p) {
  final rng = Random(p.seed);
  if (p.initial) return _generateInitialRift(p, rng);

  // JS generateNewPath retries internally with relaxedLevel 0 -> 2.
  for (var relaxedLevel = 0; relaxedLevel <= 2; relaxedLevel++) {
    final result = _generateNewPath(p, rng, relaxedLevel);
    if (result != null) return result;
  }
  return null;
}

/// Port of JS calculatePath (01_init.js:829-910): the initial rift starts at
/// a random cell >= 10 cells from the core, not on a hardpoint.
_RiftResult? _generateInitialRift(_RiftParams p, Random rng) {
  final hardpointSet = {
    for (final hp in p.hardpointCells) Cell(hp[0], hp[1]),
  };

  int startC = 0, startR = 0;
  var validStart = false;
  for (var attempts = 0; attempts < 100 && !validStart; attempts++) {
    startC = rng.nextInt(p.cols);
    startR = rng.nextInt(p.rows);
    final dist = sqrt(
        (pow(startC - p.coreC, 2) + pow(startR - p.coreR, 2)).toDouble());
    if (dist >= 10 &&
        (startC != p.coreC || startR != p.coreR) &&
        !hardpointSet.contains(Cell(startC, startR))) {
      validStart = true;
    }
  }
  if (!validStart) {
    startC = 0;
    startR = 0;
  }

  final path = findPathOnGrid(
    start: Cell(startC, startR),
    end: Cell(p.coreC, p.coreR),
    cols: p.cols,
    rows: p.rows,
    obstacles: hardpointSet,
    coreNode: Cell(p.coreC, p.coreR),
    lockZone0AfterEntry: true,
    zone0Radius: p.zone0Radius,
  );

  if (path != null && path.isNotEmpty) {
    final startDist = sqrt(
        (pow(startC - p.coreC, 2) + pow(startR - p.coreR, 2)).toDouble());
    final zone = max(1,
        min(15, ((startDist - p.zone0Radius) / 3).floor() + 1));
    return _RiftResult(path.map((c) => [c.c, c.r]).toList(), zone);
  }

  // Fallback manual L-shaped path (JS fallbackPath).
  return _RiftResult([
    [startC, startR],
    [p.coreC, startR],
    [p.coreC, p.coreR],
  ], 1);
}

/// Port of JS generateNewPath (04_tutorial.js:128-635), minus the
/// aggressive-placement debug mode. One relaxation attempt per call.
_RiftResult? _generateNewPath(_RiftParams p, Random rng, int relaxedLevel) {
  final cols = p.cols, rows = p.rows;
  final centerC = p.coreC, centerR = p.coreR;
  final endNode = Cell(centerC, centerR);
  final zone0 = p.zone0Radius;

  final hardpointSet = {
    for (final hp in p.hardpointCells) Cell(hp[0], hp[1]),
  };
  bool isGridNearHardpoint(int c, int r, double radiusCells) {
    if (radiusCells <= 0) return hardpointSet.contains(Cell(c, r));
    for (final hp in p.hardpointCells) {
      final d = sqrt((pow(c - hp[0], 2) + pow(r - hp[1], 2)).toDouble());
      if (d <= radiusCells) return true;
    }
    return false;
  }

  final pathCellSets = <Set<Cell>>[
    for (final path in p.pathCells) {for (final pt in path) Cell(pt[0], pt[1])},
  ];
  bool isLocationOnPath(int c, int r) {
    final cell = Cell(c, r);
    for (final s in pathCellSets) {
      if (s.contains(cell)) return true;
    }
    return false;
  }

  // --- 1. Pick best candidate start (wave-biased orbital zoning) ---
  final cornerDistances = [
    sqrt((pow(centerC, 2) + pow(centerR, 2)).toDouble()),
    sqrt((pow(cols - 1 - centerC, 2) + pow(centerR, 2)).toDouble()),
    sqrt((pow(centerC, 2) + pow(rows - 1 - centerR, 2)).toDouble()),
    sqrt((pow(cols - 1 - centerC, 2) + pow(rows - 1 - centerR, 2)).toDouble()),
  ];
  final maxRadiusByMap = cornerDistances.reduce(max);
  final mapZoneCap = max(3, ((maxRadiusByMap - zone0) / 3).floor());
  final maxZone = max(3, min(15, mapZoneCap));
  const orbitalDensity = 0.62; // softer 2n^2-inspired shell capacity
  int shellCapacity(int zone) =>
      max(1, ((2 * zone * zone) * orbitalDensity).round());

  final riftLoadTarget =
      max(p.pathCells.length + 1, _expectedRiftCountByWave(p.wave));
  final zoneCounts = List<int>.filled(maxZone + 1, 0);
  for (final z in p.pathZones) {
    zoneCounts[max(1, min(maxZone, z))]++;
  }

  var targetZone = 1;
  var cumulativeCapacity = 0;
  for (var z = 1; z <= maxZone; z++) {
    cumulativeCapacity += shellCapacity(z);
    targetZone = z;
    if (cumulativeCapacity >= riftLoadTarget) break;
  }

  final desiredZoneCounts = List<int>.filled(maxZone + 1, 0);
  var remainingDesired = riftLoadTarget;
  for (var z = 1; z <= targetZone && remainingDesired > 0; z++) {
    final desired = min(shellCapacity(z), remainingDesired);
    desiredZoneCounts[z] = desired;
    remainingDesired -= desired;
  }

  final baseMinRiftSpacing = p.wave < 120
      ? 0.95
      : (p.wave < 300 ? 0.85 : (p.wave < 700 ? 0.75 : 0.65));
  final minRiftSpacing = max(0.2, baseMinRiftSpacing - (relaxedLevel * 0.35));
  final candidateAttempts =
      min(960, 180 + (p.wave ~/ 8) + (relaxedLevel * 260));

  // Keep minimum tactical presence in inner shells.
  final innerZoneTargets = <int, int>{
    1: riftLoadTarget >= 8 ? 2 : 1,
    2: riftLoadTarget >= 16 ? 2 : 0,
    3: riftLoadTarget >= 24 ? 2 : 0,
  };
  int? forcedZone;
  var strongestDeficit = 0;
  final searchZoneLimit = min(maxZone, targetZone + 1);
  for (var z = 1; z <= searchZoneLimit; z++) {
    final desired = max(innerZoneTargets[z] ?? 0, desiredZoneCounts[z]);
    final deficit = desired - zoneCounts[z];
    if (deficit > strongestDeficit) {
      strongestDeficit = deficit;
      forcedZone = z;
    }
  }

  final zoneOrder = <int>[];
  if (forcedZone != null) zoneOrder.add(forcedZone);
  final weightedZones = <({int z, double score})>[];
  for (var z = 1; z <= searchZoneLimit; z++) {
    if (z == forcedZone) continue;
    final distanceFromTarget = (z - targetZone).abs();
    final desired = max(innerZoneTargets[z] ?? 0, desiredZoneCounts[z]);
    final deficit = max(0, desired - zoneCounts[z]);
    final deficitBias =
        deficit > 0 ? -min(2.8, 0.85 + deficit * 0.55) : 0.0;
    final innerBias = z <= 3 ? -0.25 : 0.0;
    final randomness = rng.nextDouble() * 1.1;
    weightedZones.add((
      z: z,
      score: (distanceFromTarget * 0.75) + randomness + innerBias + deficitBias,
    ));
  }
  weightedZones.sort((a, b) => a.score.compareTo(b.score));
  zoneOrder.addAll(weightedZones.map((e) => e.z));

  Cell? bestStartNode;
  var foundZone = -1;
  for (final zoneIndex in zoneOrder) {
    final zoneCapacity =
        max(innerZoneTargets[zoneIndex] ?? 0, shellCapacity(zoneIndex));
    final relaxedExtraCapacity =
        relaxedLevel == 0 ? 4 : (relaxedLevel == 1 ? 10 : 20);
    if (zoneCounts[zoneIndex] >= zoneCapacity + relaxedExtraCapacity) continue;

    final innerR = zone0 + (zoneIndex - 1) * 3;
    final outerR = zone0 + zoneIndex * 3;
    final zoneCandidates = <({int c, int r, double minDist})>[];

    for (var i = 0; i < candidateAttempts; i++) {
      final angle = rng.nextDouble() * pi * 2;
      final dist = innerR + rng.nextDouble() * (outerR - innerR);
      final c = (centerC + cos(angle) * dist).round();
      final r = (centerR + sin(angle) * dist).round();

      if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
      if (isLocationOnPath(c, r)) continue;
      if (isGridNearHardpoint(c, r, 0)) continue;

      var minDist = double.infinity;
      var meetsGlobalSpacing = true;
      if (p.pathCells.isEmpty) {
        minDist = sqrt((pow(c - centerC, 2) + pow(r - centerR, 2)).toDouble());
      } else {
        outer:
        for (final path in p.pathCells) {
          for (final pt in path) {
            final d = sqrt(
                (pow(c - pt[0], 2) + pow(r - pt[1], 2)).toDouble());
            if (d < minDist) minDist = d;
            if (minRiftSpacing > 0 && d < minRiftSpacing) {
              meetsGlobalSpacing = false;
              break outer;
            }
          }
        }
      }
      if (!meetsGlobalSpacing) continue;
      zoneCandidates.add((c: c, r: r, minDist: minDist));
    }

    if (zoneCandidates.isNotEmpty) {
      zoneCandidates.sort((a, b) => b.minDist.compareTo(a.minDist));
      final topSlice = zoneCandidates.sublist(0, min(zoneCandidates.length, 16));
      final pickIndex = (pow(rng.nextDouble(), 1.15) * topSlice.length).floor();
      final picked = topSlice[max(0, min(topSlice.length - 1, pickIndex))];
      bestStartNode = Cell(picked.c, picked.r);
      foundZone = zoneIndex;
      break;
    }
  }

  if (bestStartNode == null && relaxedLevel >= 2) {
    // Emergency fallback for ultra-late map saturation.
    for (var i = 0; i < 1200; i++) {
      final angle = rng.nextDouble() * pi * 2;
      final dist = 10 + rng.nextDouble() * 48;
      final c = (centerC + cos(angle) * dist).round();
      final r = (centerR + sin(angle) * dist).round();
      if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
      if (isLocationOnPath(c, r)) continue;
      if (isGridNearHardpoint(c, r, 0.5)) continue;
      bestStartNode = Cell(c, r);
      foundZone = max(1, min(maxZone, ((dist - zone0) / 3).floor() + 1));
      break;
    }
  }
  if (bestStartNode == null) return null;
  final startNode = bestStartNode;

  // --- 2/3. Target selection (merge or base) + path generation ---
  final obstacles = <Cell>{};
  for (final s in pathCellSets) {
    obstacles.addAll(s);
  }
  obstacles.addAll(hardpointSet);

  bool hasOpenApproach(int c, int r) {
    const dirs = [(0, -1), (1, 0), (0, 1), (-1, 0)];
    for (final (dc, dr) in dirs) {
      final nc = c + dc, nr = r + dr;
      if (nc < 0 || nc >= cols || nr < 0 || nr >= rows) continue;
      if (!obstacles.contains(Cell(nc, nr))) return true;
    }
    return false;
  }

  final coreGapSectors =
      _getCoreGapSectors(p.coreHardpointCells, centerC, centerR);
  final pathGapByIndex = <int?>[];
  final gapUsage = <int, int>{};
  for (final path in p.pathCells) {
    final gap =
        _getCoreEntryGapFromPath(path, centerC, centerR, coreGapSectors, zone0);
    pathGapByIndex.add(gap);
    if (gap != null) gapUsage[gap] = (gapUsage[gap] ?? 0) + 1;
  }
  final startGap = _getCoreGapIndexForCell(
      startNode.c, startNode.r, centerC, centerR, coreGapSectors);
  final startGapUsage = startGap == null ? 0 : (gapUsage[startGap] ?? 0);
  final mustMergeBeforeZone0 = startGap != null && startGapUsage > 0;

  final uncoveredGaps =
      coreGapSectors.where((g) => (gapUsage[g.index] ?? 0) == 0).length;
  final baseDirectProb = 0.5 / (foundZone * foundZone);
  final gapCoverageBoost =
      uncoveredGaps > 0 ? min(0.45, uncoveredGaps * 0.08) : 0.0;
  final directProb =
      mustMergeBeforeZone0 ? 0.0 : min(0.8, baseDirectProb + gapCoverageBoost);
  final isDirectMission = rng.nextDouble() < directProb;

  final minExpansionDist = max(3, 6 - (relaxedLevel * 2));
  List<({int c, int r, int pathIndex, int pointIndex, double score})>
      collectMergeTargets(bool enforceCoreDistance,
          {int? requiredGap, int? preferredGap, bool requireOutsideZone0 = false}) {
    final candidates =
        <({int c, int r, int pathIndex, int pointIndex, double score})>[];
    for (var i = 0; i < p.pathCells.length; i++) {
      final path = p.pathCells[i];
      final pathGap = pathGapByIndex[i];
      if (requiredGap != null && pathGap != requiredGap) continue;
      for (var j = 0; j < path.length; j++) {
        final pc = path[j][0], pr = path[j][1];

        final dToSpawn = sqrt(
            (pow(startNode.c - pc, 2) + pow(startNode.r - pr, 2)).toDouble());
        if (dToSpawn < minExpansionDist) continue;

        final dToCore =
            sqrt((pow(pc - centerC, 2) + pow(pr - centerR, 2)).toDouble());
        if (requireOutsideZone0 && dToCore < zone0) continue;
        if (enforceCoreDistance &&
            dToCore < PathingRules.mergeMinCoreDistance) {
          continue;
        }
        if (isGridNearHardpoint(pc, pr, 0)) continue;
        if (relaxedLevel == 0 && !hasOpenApproach(pc, pr)) continue;

        var score = dToSpawn + rng.nextDouble() * 0.9;
        if (preferredGap != null && pathGap != preferredGap) score += 4.5;
        if (!_pathRespectsZone0Commitment(
            [for (final pt in path) Cell(pt[0], pt[1])],
            centerC,
            centerR,
            zone0,
            j)) {
          continue;
        }
        candidates.add((c: pc, r: pr, pathIndex: i, pointIndex: j, score: score));
      }
    }
    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates.sublist(0, min(candidates.length, 240));
  }

  List<Cell>? newPathCells;
  var mergePathIndex = -1;
  var mergePointIndex = -1;

  if (!isDirectMission) {
    var mergeCandidates =
        <({int c, int r, int pathIndex, int pointIndex, double score})>[];
    if (mustMergeBeforeZone0) {
      mergeCandidates = collectMergeTargets(true,
          requiredGap: startGap, requireOutsideZone0: true);
      if (mergeCandidates.isEmpty) {
        mergeCandidates = collectMergeTargets(false,
            requiredGap: startGap, requireOutsideZone0: true);
      }
    } else {
      mergeCandidates = collectMergeTargets(true, preferredGap: startGap);
      if (mergeCandidates.isEmpty) {
        mergeCandidates = collectMergeTargets(false, preferredGap: startGap);
      }
    }

    final mergePathAttempts = min(
        relaxedLevel == 0 ? 100 : (relaxedLevel == 1 ? 180 : 260),
        mergeCandidates.length);
    for (var i = 0; i < mergePathAttempts; i++) {
      final candidate = mergeCandidates[i];
      final attemptPath = findPathOnGrid(
        start: startNode,
        end: Cell(candidate.c, candidate.r),
        cols: cols,
        rows: rows,
        obstacles: obstacles,
        allowedObstacles: {Cell(candidate.c, candidate.r)},
        coreNode: endNode,
        lockZone0AfterEntry: true,
        zone0Radius: zone0,
      );
      if (attemptPath == null) continue;

      newPathCells = attemptPath;
      mergePathIndex = candidate.pathIndex;
      mergePointIndex = candidate.pointIndex;
      break;
    }
  }

  if (newPathCells == null && mustMergeBeforeZone0) {
    return null; // retried at the next relaxation level by the caller
  }

  if (newPathCells == null) {
    // Direct mission or fallback: create/extend trunks through hardpoint gaps.
    final coreEntryCandidates = coreGapSectors
        .map((sector) => (
              gapIndex: sector.index,
              c: (endNode.c + cos(sector.centerAngle) * max(1, zone0 - 1))
                  .round(),
              r: (endNode.r + sin(sector.centerAngle) * max(1, zone0 - 1))
                  .round(),
            ))
        .where((t) =>
            t.c >= 0 &&
            t.c < cols &&
            t.r >= 0 &&
            t.r < rows &&
            !isGridNearHardpoint(t.c, t.r, 0))
        .toList();

    final rankedEntries = coreEntryCandidates
        .map((t) => (
              gapIndex: t.gapIndex,
              c: t.c,
              r: t.r,
              usage: gapUsage[t.gapIndex] ?? 0,
              startGapMatch:
                  startGap != null && t.gapIndex == startGap ? 1 : 0,
              blocked: obstacles.contains(Cell(t.c, t.r)) ? 1 : 0,
              jitter: rng.nextDouble() * 0.25,
            ))
        .toList()
      ..sort((a, b) {
        if (a.startGapMatch != b.startGapMatch) {
          return b.startGapMatch - a.startGapMatch;
        }
        if (a.usage != b.usage) return a.usage - b.usage;
        if (a.blocked != b.blocked) return a.blocked - b.blocked;
        return a.jitter.compareTo(b.jitter);
      });

    final preferredEntry = rankedEntries.isNotEmpty ? rankedEntries[0] : null;
    final directTarget = preferredEntry != null
        ? Cell(preferredEntry.c, preferredEntry.r)
        : endNode;
    final localAllowed = <Cell>{};
    if (preferredEntry != null && preferredEntry.blocked == 1) {
      localAllowed.add(Cell(preferredEntry.c, preferredEntry.r));
    }
    localAllowed.add(endNode);

    newPathCells = findPathOnGrid(
      start: startNode,
      end: directTarget,
      cols: cols,
      rows: rows,
      obstacles: obstacles,
      allowedObstacles: localAllowed,
      coreNode: endNode,
      lockZone0AfterEntry: true,
      zone0Radius: zone0,
    );
    if (newPathCells != null && directTarget != endNode) {
      final last = newPathCells.last;
      if (last != endNode) {
        final bridgeAllowed = {...localAllowed, last};
        final bridgePath = findPathOnGrid(
          start: last,
          end: endNode,
          cols: cols,
          rows: rows,
          obstacles: obstacles,
          allowedObstacles: bridgeAllowed,
          coreNode: endNode,
          lockZone0AfterEntry: true,
          zone0Radius: zone0,
        );
        if (bridgePath != null && bridgePath.length > 1) {
          newPathCells.addAll(bridgePath.sublist(1));
        } else {
          newPathCells = null;
        }
      }
    }
    mergePathIndex = -1;
    mergePointIndex = -1;
  }

  if (newPathCells == null) return null;

  if (mergePathIndex != -1) {
    final targetPath = p.pathCells[mergePathIndex];
    for (var j = mergePointIndex + 1; j < targetPath.length; j++) {
      newPathCells.add(Cell(targetPath[j][0], targetPath[j][1]));
    }
  }

  if (!_pathRespectsZone0Commitment(newPathCells, centerC, centerR, zone0, 0)) {
    return null;
  }

  // Safety guard: don't commit paths that overlap themselves.
  final seenCells = <Cell>{};
  for (final cell in newPathCells) {
    if (!seenCells.add(cell)) return null;
  }

  return _RiftResult(
      newPathCells.map((c) => [c.c, c.r]).toList(), foundZone);
}

/// JS getExpectedRiftCountByWave (03_abilities.js:754-764).
int _expectedRiftCountByWave(int currentWave) {
  var scheduled = 0;
  for (var w = 2; w <= currentWave; w++) {
    if (w <= 50) {
      if ((w - 1) % 10 == 0) scheduled++;
    } else {
      if ((w - 1) % 5 == 0) scheduled++;
    }
  }
  return 1 + scheduled;
}

// ---------------------------------------------------------------------------
// Main-thread API
// ---------------------------------------------------------------------------

class RiftGenerator {
  final int worldCols;
  final int worldRows;
  final HardpointManager hardpointManager;
  final _rng = Random();

  RiftGenerator(this.worldCols, this.worldRows, this.hardpointManager);

  int get _coreC => worldCols ~/ 2;
  int get _coreR => worldRows ~/ 2;

  Future<RiftPath?> generateRift({
    required List<RiftPath> existingPaths,
    required int wave,
  }) async {
    final hardpointCells = [
      for (final hp in hardpointManager.hardpoints) [hp.col, hp.row],
    ];
    final coreHardpointCells = [
      for (final hp in hardpointManager.hardpoints)
        if (hp.type == HardpointType.core) [hp.col, hp.row],
    ];

    final params = _RiftParams(
      cols: worldCols,
      rows: worldRows,
      coreC: _coreC,
      coreR: _coreR,
      zone0Radius: kZone0RadiusCells,
      hardpointCells: hardpointCells,
      coreHardpointCells: coreHardpointCells,
      pathCells: [
        for (final path in existingPaths)
          [
            for (final pt in path.points)
              [(pt.x / kGridSize).floor(), (pt.y / kGridSize).floor()],
          ],
      ],
      pathZones: [for (final path in existingPaths) path.zone],
      wave: wave,
      initial: existingPaths.isEmpty,
      // NOTE: must stay <= 2^31-1. On the web/JS target bitwise shifts are
      // 32-bit, so `1 << 32` overflows to 0 and `nextInt(0)` throws a
      // RangeError — which silently aborted rift generation (no enemies ever
      // spawned). `0x7FFFFFFF` is a portable positive max across web and VM.
      seed: _rng.nextInt(0x7FFFFFFF),
    );

    // compute() = isolate on mobile, sync on web (both compile correctly)
    final result = await compute(_generateRiftIsolate, params);
    if (result == null) return null;

    final points = result.points
        .map((p) => Vector2(
              p[0] * kGridSize + kGridSize / 2,
              p[1] * kGridSize + kGridSize / 2,
            ))
        .toList();

    return RiftPath(points: points, zone: result.zone);
  }
}
