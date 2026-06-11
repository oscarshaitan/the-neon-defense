import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import 'config/constants.dart';
import 'world/game_world.dart';
import 'camera/game_camera.dart';
import 'audio/audio_manager.dart';
import 'input/input_router.dart';
import 'state/entity_registry.dart';
import 'state/game_state.dart';
import 'state/selection_state.dart';
import 'systems/save_system.dart';

class NeonDefenseGame extends FlameGame
    with ScaleDetector, HasKeyboardHandlerComponents, TapCallbacks {
  late GameWorld gameWorld;
  late GameCamera gameCamera;
  final AudioManager audio = AudioManager();
  late SaveSystem saveSystem;
  late InputRouter inputRouter;

  final GameState state = GameState();
  final SelectionState selection = SelectionState();
  final EntityRegistry entities = EntityRegistry();

  // Fixed 60 Hz logic stepping so JS frame-based numbers (cooldowns in
  // frames, spawn every 60 frames, stun 30 frames) transfer 1:1 regardless
  // of display refresh rate.
  static const double _step = 1 / 60;
  static const int _maxStepsPerFrame = 4;
  double _accumulator = 0;

  @override
  Color backgroundColor() => kColorBg;

  @override
  Future<void> onLoad() async {
    gameCamera = GameCamera(this);
    gameWorld = GameWorld(this);
    inputRouter = InputRouter(this);

    saveSystem = SaveSystem(this);
    await audio.init();
    camera = gameCamera.cameraComponent;
    world.add(gameWorld);
  }

  @override
  void update(double dt) {
    if (state.isPlaying) {
      gameWorld.qualityGovernor.recordFrameMs(dt * 1000);
    }

    _accumulator += dt;
    var steps = 0;
    while (_accumulator >= _step && steps < _maxStepsPerFrame) {
      super.update(_step);
      _accumulator -= _step;
      steps++;
    }
    // Drop time we can't catch up on (avoids spiral of death after jank).
    if (_accumulator >= _step) _accumulator = 0;
  }

  @override
  void onTapDown(TapDownEvent event) {
    final worldPos = gameCamera.screenToWorld(event.canvasPosition);
    inputRouter.handleTap(worldPos);
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    gameCamera.onScaleUpdate(info);
  }

  @override
  void onScaleEnd(ScaleEndInfo info) {
    gameCamera.onScaleEnd(info);
  }

  // Keyboard hotkeys handled at Flutter widget level (see main.dart FocusNode)
  void handleKeyDown(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.keyQ:
        selection.selectTowerType(TowerType.basic);
        break;
      case LogicalKeyboardKey.keyW:
        selection.selectTowerType(TowerType.rapid);
        break;
      case LogicalKeyboardKey.keyE:
        selection.selectTowerType(TowerType.sniper);
        break;
      case LogicalKeyboardKey.keyR:
        selection.selectTowerType(TowerType.arc);
        break;
      case LogicalKeyboardKey.escape:
        selection.clear();
        break;
      default:
        break;
    }
  }

  void togglePause() {
    if (state.phase.value != GamePhase.playing) return;
    state.isPaused.value = !state.isPaused.value;
    if (state.isPaused.value) {
      overlays.add('pauseMenu');
    } else {
      overlays.remove('pauseMenu');
    }
  }

  void startGame() {
    state.phase.value = GamePhase.playing;
    overlays.remove('startScreen');
    overlays.add('hud');
    gameWorld.startPrepPhase();
  }

  void gameOver() {
    state.phase.value = GamePhase.gameover;
    overlays.remove('hud');
    overlays.add('gameOverScreen');
  }

  void resetGame() {
    state.reset();
    state.phase.value = GamePhase.playing;
    selection.clear();
    overlays.remove('gameOverScreen');
    overlays.add('hud');
    gameWorld.reset();
    gameWorld.startPrepPhase();
  }
}
