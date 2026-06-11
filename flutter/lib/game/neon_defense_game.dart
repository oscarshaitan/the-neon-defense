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
import 'systems/placement_system.dart';
import 'systems/save_system.dart';

class NeonDefenseGame extends FlameGame
    with ScaleDetector, HasKeyboardHandlerComponents, TapCallbacks {
  late GameWorld gameWorld;
  late GameCamera gameCamera;
  final AudioManager audio = AudioManager();
  late SaveSystem saveSystem;
  late InputRouter inputRouter;
  late PlacementSystem placement;

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
    placement = PlacementSystem(this);

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

    // Screen shake decays per render frame (JS draw()).
    if (state.shakeAmount > 0) {
      state.shakeAmount *= 0.9;
      if (state.shakeAmount < 0.1) state.shakeAmount = 0;
    }
    gameCamera.applyShake(state.shakeAmount);

    _accumulator += dt;
    var steps = 0;
    while (_accumulator >= _step && steps < _maxStepsPerFrame) {
      super.update(_step);
      _accumulator -= _step;
      steps++;
    }
    // Drop time we can't catch up on (avoids spiral of death after jank).
    if (_accumulator >= _step) _accumulator = 0;

    if (state.isPlaying) saveSystem.flushQueuedAutoSave();
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
        chooseTowerType(TowerType.basic);
        break;
      case LogicalKeyboardKey.keyW:
        chooseTowerType(TowerType.rapid);
        break;
      case LogicalKeyboardKey.keyE:
        chooseTowerType(TowerType.sniper);
        break;
      case LogicalKeyboardKey.keyR:
        chooseTowerType(TowerType.arc);
        break;
      case LogicalKeyboardKey.escape:
        selection.clear();
        break;
      default:
        break;
    }
  }

  /// JS window.selectTower (04_tutorial.js:768-786): with a build target
  /// chosen, picking a tower type builds there immediately; otherwise it
  /// just arms the type.
  void chooseTowerType(TowerType type) {
    final target = selection.buildTarget;
    if (target != null) {
      placement.buildTower(target, type);
      return;
    }
    selection.selectTowerType(type);
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

  /// CONTINUE from the start screen: restore the save, then enter a prep
  /// phase (JS loadGame).
  Future<void> continueGame() async {
    final loaded = await saveSystem.load();
    if (!loaded) {
      startGame();
      return;
    }
    state.phase.value = GamePhase.playing;
    overlays.remove('startScreen');
    overlays.add('hud');
    gameCamera.resetCamera();
  }

  void gameOver() {
    saveSystem.flushQueuedAutoSave(force: true);
    saveSystem.save(); // JS saves on game over
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
