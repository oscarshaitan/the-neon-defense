import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../entities/towers/tower.dart';
import '../neon_defense_game.dart';
import '../world/hardpoint_manager.dart';

class PlacementValidation {
  final bool valid;
  final String? reason; // 'cost' | 'path' | 'tower'
  final Vector2 snap;
  final Hardpoint? hardpoint;
  const PlacementValidation({
    required this.valid,
    this.reason,
    required this.snap,
    this.hardpoint,
  });
}

/// Free-tile tower placement, mirroring JS isValidPlacement/buildTower
/// (04_tutorial.js:1019-1129). Any empty grid tile is buildable; hardpoints
/// are always-buildable anchors even where a path overlaps, and grant their
/// stat multipliers.
class PlacementSystem {
  final NeonDefenseGame game;
  PlacementSystem(this.game);

  /// JS snapToGrid: cell center of the tile containing (x, y).
  static Vector2 snapToGrid(Vector2 worldPos) => Vector2(
        (worldPos.x / kGridSize).floor() * kGridSize + kGridSize / 2,
        (worldPos.y / kGridSize).floor() * kGridSize + kGridSize / 2,
      );

  /// Hardpoint within the JS slot snap radius (GRID_SIZE * 0.45) of the
  /// snapped position.
  Hardpoint? hardpointAt(Vector2 snap) {
    Hardpoint? best;
    var bestDist = kHardpointSnapRadius;
    for (final hp in game.gameWorld.hardpointManager.hardpoints) {
      final d = hp.worldPos.distanceTo(snap);
      if (d < bestDist) {
        bestDist = d;
        best = hp;
      }
    }
    return best;
  }

  PlacementValidation validate(Vector2 worldPos, TowerType type) {
    final snap = snapToGrid(worldPos);
    final hardpoint = hardpointAt(snap);

    if (game.state.money.value < kTowers[type]!.cost) {
      return PlacementValidation(
          valid: false, reason: 'cost', snap: snap, hardpoint: hardpoint);
    }

    // Path collision via segment box check — skipped on hardpoints.
    if (hardpoint == null && _intersectsAnyPath(snap, kGridSize / 2)) {
      return PlacementValidation(
          valid: false, reason: 'path', snap: snap, hardpoint: hardpoint);
    }

    // Tower collision (grid-based equality).
    for (final t in game.entities.towers) {
      if ((t.position.x - snap.x).abs() < 1 &&
          (t.position.y - snap.y).abs() < 1) {
        return PlacementValidation(
            valid: false, reason: 'tower', snap: snap, hardpoint: hardpoint);
      }
    }

    return PlacementValidation(valid: true, snap: snap, hardpoint: hardpoint);
  }

  bool _intersectsAnyPath(Vector2 snap, double tolerance) {
    for (final rift in game.gameWorld.waveSystem.rifts) {
      final pts = rift.points;
      for (var i = 0; i < pts.length - 1; i++) {
        final p1 = pts[i];
        final p2 = pts[i + 1];
        if ((p1.y - p2.y).abs() < 1) {
          // Horizontal segment
          if ((snap.y - p1.y).abs() < tolerance &&
              snap.x >= (p1.x < p2.x ? p1.x : p2.x) - tolerance &&
              snap.x <= (p1.x > p2.x ? p1.x : p2.x) + tolerance) {
            return true;
          }
        } else {
          // Vertical segment
          if ((snap.x - p1.x).abs() < tolerance &&
              snap.y >= (p1.y < p2.y ? p1.y : p2.y) - tolerance &&
              snap.y <= (p1.y > p2.y ? p1.y : p2.y) + tolerance) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// JS buildTower: validates, charges, places, and keeps the new tower
  /// selected for instant upgrades.
  Tower? buildTower(Vector2 worldPos, TowerType type) {
    final validation = validate(worldPos, type);
    if (!validation.valid) {
      // JS buildTower: red burst on path/tower collisions.
      if (validation.reason == 'path' || validation.reason == 'tower') {
        game.gameWorld.particles.createParticles(
            validation.snap.x, validation.snap.y, const Color(0xFFFF0000), 5);
      }
      return null;
    }

    final hp = validation.hardpoint;
    if (hp != null && hp.occupied) return null;
    hp?.occupied = true;

    game.state.money.value -= kTowers[type]!.cost;
    final tower = Tower(
      position: validation.snap.clone(),
      type: type,
      spatialGrid: game.gameWorld.spatialGrid,
      hardpoint: hp,
    );
    game.gameWorld.add(tower);

    game.gameWorld.particles.createParticles(
        validation.snap.x, validation.snap.y, kTowers[type]!.color, 5);

    // Quick flow: keep the newly built tower selected (JS selectPlacedTower).
    game.selection.selectTower(tower);
    game.audio.playBuild();
    game.saveSystem.save(); // JS saves on build
    game.tutorial.onTowerBuilt();
    return tower;
  }

  /// True if the snapped tile can be picked as a build target
  /// (JS handleClick occupied checks, 01_init.js:390-414).
  bool isTileFree(Vector2 snap) {
    for (final t in game.entities.towers) {
      if ((t.position.x - snap.x).abs() < 1 &&
          (t.position.y - snap.y).abs() < 1) {
        return false;
      }
    }
    // Path cells block build-target selection unless on a hardpoint.
    if (hardpointAt(snap) == null) {
      final snapC = (snap.x / kGridSize).floor();
      final snapR = (snap.y / kGridSize).floor();
      for (final rift in game.gameWorld.waveSystem.rifts) {
        for (final p in rift.points) {
          if ((p.x / kGridSize).floor() == snapC &&
              (p.y / kGridSize).floor() == snapR) {
            return false;
          }
        }
      }
    }
    return true;
  }
}
