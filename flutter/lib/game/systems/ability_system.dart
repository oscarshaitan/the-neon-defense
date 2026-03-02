import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';
import '../entities/enemies/enemy.dart';
import '../entities/towers/tower.dart';
import '../world/game_world.dart';

enum AbilityType { emp, overclock }

enum AbilityState { ready, targeting, active, cooldown }

class AbilitySystem extends Component {
  final GameWorld gameWorld;

  // EMP
  AbilityState empState = AbilityState.ready;
  int empCooldownTimer = 0;

  // Overclock
  AbilityState overclockState = AbilityState.ready;
  int overclockCooldownTimer = 0;

  // Targeting
  AbilityType? targetingAbility;
  Vector2? targetingPos; // world position of cursor/tap during targeting

  // Cooldown tick: decrements every 60 frames
  int _cooldownTick = 0;

  AbilitySystem(this.gameWorld);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  bool get isTargeting => targetingAbility != null;

  void startTargeting(AbilityType type) {
    final g = gameWorld.game;
    if (type == AbilityType.emp) {
      if (empState != AbilityState.ready) return;
      if (g.energy < kEmpCost) return;
    } else {
      if (overclockState != AbilityState.ready) return;
      if (g.energy < kOverclockCost) return;
    }
    targetingAbility = type;
  }

  void cancelTargeting() {
    targetingAbility = null;
    targetingPos = null;
  }

  /// Called when the player confirms the ability target (tap on world).
  void useAbility(Vector2 worldPos) {
    if (targetingAbility == null) return;
    final type = targetingAbility!;
    targetingAbility = null;
    targetingPos = null;

    if (type == AbilityType.emp) {
      _fireEmp(worldPos);
    } else {
      _fireOverclock(worldPos);
    }
  }

  void _fireEmp(Vector2 worldPos) {
    final g = gameWorld.game;
    g.energy -= kEmpCost;
    empState = AbilityState.active;

    // Freeze all enemies in radius
    for (final enemy in gameWorld.children.whereType<Enemy>()) {
      if (enemy.position.distanceTo(worldPos) <= kEmpRadius) {
        enemy.freeze(kEmpDurationFrames);
      }
    }

    empCooldownTimer = kEmpMaxCooldown;
    empState = AbilityState.cooldown;
  }

  void _fireOverclock(Vector2 worldPos) {
    final g = gameWorld.game;

    // Find nearest tower to tap position
    Tower? nearest;
    double nearestDist = 80.0; // max snap distance
    for (final tower in gameWorld.children.whereType<Tower>()) {
      final d = tower.position.distanceTo(worldPos);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = tower;
      }
    }
    if (nearest == null) {
      cancelTargeting();
      return;
    }

    g.energy -= kOverclockCost;
    nearest.overclocked = true;
    nearest.overclockTimer = kOverclockDurationFrames;

    overclockCooldownTimer = kOverclockMaxCooldown;
    overclockState = AbilityState.cooldown;
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  @override
  void update(double dt) {
    final g = gameWorld.game;
    if (g.gameState != 'playing' || g.isPaused) return;

    // Energy: JS gives +1 per kill only (no passive regen). See enemy.dart _die().

    // Cooldown tick (decrements every 60 frames)
    _cooldownTick++;
    if (_cooldownTick >= 60) {
      _cooldownTick = 0;
      if (empCooldownTimer > 0) {
        empCooldownTimer--;
        if (empCooldownTimer == 0) empState = AbilityState.ready;
      }
      if (overclockCooldownTimer > 0) {
        overclockCooldownTimer--;
        if (overclockCooldownTimer == 0) overclockState = AbilityState.ready;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rendering: targeting overlays drawn in world space
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    if (targetingAbility == null || targetingPos == null) return;

    if (targetingAbility == AbilityType.emp) {
      _renderEmpOverlay(canvas, targetingPos!);
    } else {
      _renderOverclockOverlay(canvas, targetingPos!);
    }
  }

  void _renderEmpOverlay(Canvas canvas, Vector2 pos) {
    // Radius circle
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      kEmpRadius,
      Paint()
        ..color = const Color(0x3300F3FF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      kEmpRadius,
      Paint()
        ..color = const Color(0xCC00F3FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Crosshair
    const crossSize = 12.0;
    final paint = Paint()
      ..color = const Color(0xCC00F3FF)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(pos.x - crossSize, pos.y),
      Offset(pos.x + crossSize, pos.y),
      paint,
    );
    canvas.drawLine(
      Offset(pos.x, pos.y - crossSize),
      Offset(pos.x, pos.y + crossSize),
      paint,
    );
  }

  void _renderOverclockOverlay(Canvas canvas, Vector2 pos) {
    // Pulsing ring to indicate tower targeting
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      32,
      Paint()
        ..color = const Color(0x44FCEE0A)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      32,
      Paint()
        ..color = const Color(0xCCFCEE0A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // ---------------------------------------------------------------------------
  // Status helpers for UI
  // ---------------------------------------------------------------------------

  double get empCooldownFraction =>
      empState == AbilityState.cooldown
          ? empCooldownTimer / kEmpMaxCooldown
          : 0.0;

  double get overclockCooldownFraction =>
      overclockState == AbilityState.cooldown
          ? overclockCooldownTimer / kOverclockMaxCooldown
          : 0.0;

  bool get empReady =>
      empState == AbilityState.ready && gameWorld.game.energy >= kEmpCost;

  bool get overclockReady =>
      overclockState == AbilityState.ready &&
      gameWorld.game.energy >= kOverclockCost;
}
