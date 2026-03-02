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
    final worldW = kWorldMinCols * kGridSize;
    final worldH = kWorldMinRows * kGridSize;
    _zoom = 1.0;
    cameraComponent.viewfinder.zoom = _zoom;
    cameraComponent.viewfinder.position = Vector2(
      worldW / 2 - game.size.x / 2,
      worldH / 2 - game.size.y / 2,
    );
  }

  void resetCamera() => _centerOnCore();

  double get zoom => _zoom;
}
