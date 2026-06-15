import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../neon_defense_game.dart';
import '../config/constants.dart';

class GameCamera {
  final NeonDefenseGame game;
  late CameraComponent cameraComponent;

  double _zoom = 1.0;
  static const double _minZoom = 0.1;
  static const double _maxZoom = 1.0;

  bool _isScaling = false;
  final _shakeRng = Random();
  final Vector2 _shakeApplied = Vector2.zero();

  GameCamera(this.game) {
    cameraComponent = CameraComponent(world: game.world)
      ..viewfinder.anchor = Anchor.topLeft;
    _centerOnCore();
  }

  // ---------------------------------------------------------------------------
  // ScaleDetector callbacks (handles both pan and pinch)
  // ---------------------------------------------------------------------------

  void onScaleUpdate(ScaleUpdateInfo info) {
    final scale = info.scale.global.x;

    if ((scale - 1.0).abs() > 0.01) {
      // Pinch zoom
      _isScaling = true;
      final worldPosBefore = _screenToWorld(info.eventPosition.global);
      _zoom = (_zoom * scale).clamp(_minZoom, _maxZoom);
      cameraComponent.viewfinder.zoom = _zoom;
      // Zoom toward cursor: shift camera so world pos stays under finger
      final worldPosAfter = _screenToWorld(info.eventPosition.global);
      final delta = worldPosBefore - worldPosAfter;
      cameraComponent.viewfinder.position += delta;
    } else if (!_isScaling) {
      // Pan
      final delta = info.delta.global / _zoom;
      cameraComponent.viewfinder.position -= delta;
    }
  }

  void onScaleEnd(ScaleEndInfo info) {
    _isScaling = false;
  }

  /// Mouse-wheel / trackpad zoom toward [screenPos] (web + desktop, which have
  /// no pinch gesture). Mirrors the JS wheel zoom.
  void zoomBy(double factor, Vector2 screenPos) {
    final worldBefore = _screenToWorld(screenPos);
    _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom);
    cameraComponent.viewfinder.zoom = _zoom;
    final worldAfter = _screenToWorld(screenPos);
    cameraComponent.viewfinder.position += worldBefore - worldAfter;
  }

  /// JS draw() applies a random +-shake/2 screen-space jitter each frame
  /// (06_render.js:100-102). Implemented as a transient viewfinder offset.
  void applyShake(double amount) {
    cameraComponent.viewfinder.position -= _shakeApplied;
    if (amount > 0) {
      _shakeApplied.setValues(
        (_shakeRng.nextDouble() - 0.5) * amount / _zoom,
        (_shakeRng.nextDouble() - 0.5) * amount / _zoom,
      );
      cameraComponent.viewfinder.position += _shakeApplied;
    } else {
      _shakeApplied.setZero();
    }
  }

  // ---------------------------------------------------------------------------
  // Coordinate helpers
  // ---------------------------------------------------------------------------

  Vector2 _screenToWorld(Vector2 screenPos) {
    return (screenPos / _zoom) + cameraComponent.viewfinder.position;
  }

  Vector2 screenToWorld(Vector2 screenPos) => _screenToWorld(screenPos);

  // ---------------------------------------------------------------------------
  // Reset: center on core (world center = (worldCols/2 * kGridSize, worldRows/2 * kGridSize))
  // ---------------------------------------------------------------------------

  void _centerOnCore() {
    // Centre on the core CELL centre (matches CoreBase), not the grid line.
    final coreX = (kWorldMinCols ~/ 2) * kGridSize + kGridSize / 2;
    final coreY = (kWorldMinRows ~/ 2) * kGridSize + kGridSize / 2;
    _zoom = 1.0;
    cameraComponent.viewfinder.zoom = _zoom;
    cameraComponent.viewfinder.position = Vector2(
      coreX - game.size.x / 2,
      coreY - game.size.y / 2,
    );
  }

  void resetCamera() => _centerOnCore();

  double get zoom => _zoom;
}
