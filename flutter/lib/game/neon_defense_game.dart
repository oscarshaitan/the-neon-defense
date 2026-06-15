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
import 'systems/ability_system.dart';
import 'systems/hint_system.dart';
import 'systems/placement_system.dart';
import 'systems/save_system.dart';
import 'systems/tech_tree.dart';
import 'systems/tutorial_system.dart';

class NeonDefenseGame extends FlameGame
    with
        ScaleDetector,
        ScrollDetector,
        HasKeyboardHandlerComponents,
        TapCallbacks {
  late GameWorld gameWorld;
  late GameCamera gameCamera;
  final AudioManager audio = AudioManager();
  late SaveSystem saveSystem;
  late InputRouter inputRouter;
  late PlacementSystem placement;
  late TutorialSystem tutorial;
  late HintSystem hints;

  /// Tech Tree progression layer (RP + unlocked nodes), persisted in a store
  /// separate from the per-run save so it carries across runs.
  final TechTree tech = TechTree();

  /// Once-per-run flag for the CORE capstone (Last Stand Protocol). Reset on
  /// every fresh run (start/reset/continue).
  bool lastStandUsed = false;

  final GameState state = GameState();
  final SelectionState selection = SelectionState();
  final EntityRegistry entities = EntityRegistry();

  /// Smoothed frames-per-second for the HUD counter (EMA of 1/dt), matching
  /// the JS HUD's fps-display and the Godot FPS readout.
  double fps = 0;

  // JS playShootSFX throttle (05_loop.js:691-700): min interval by quality.
  int _lastShootSfxFrame = -1000000;

  void playShootSfx() {
    final minInterval = switch (gameWorld.qualityGovernor.currentProfile) {
      QualityProfile.high => 1,
      QualityProfile.balanced => 2,
      QualityProfile.low => 3,
    };
    if (state.frameCount - _lastShootSfxFrame < minInterval) return;
    _lastShootSfxFrame = state.frameCount;
    audio.playShoot();
  }

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
    tutorial = TutorialSystem(this);
    hints = HintSystem(this);
    await tutorial.loadCompletionFlag();
    await hints.loadSeen();
    await tech.load(); // persistent tech progression (separate store)
    state.playerName = await saveSystem.loadPlayerName();
    await audio.init();
    camera = gameCamera.cameraComponent;
    world.add(gameWorld);
  }

  @override
  void update(double dt) {
    if (dt > 0) {
      final inst = 1 / dt;
      fps = fps == 0 ? inst : fps * 0.9 + inst * 0.1;
    }

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
  void onScroll(PointerScrollInfo info) {
    final dy = info.scrollDelta.global.y;
    if (dy == 0) return;
    // Wheel up (negative dy) zooms in; matches the JS wheel zoom.
    gameCamera.zoomBy(dy < 0 ? 1.1 : 1 / 1.1, info.eventPosition.global);
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
      case LogicalKeyboardKey.digit1:
        gameWorld.activateAbility(AbilityType.emp);
        break;
      case LogicalKeyboardKey.digit2:
        gameWorld.activateAbility(AbilityType.overclock);
        break;
      case LogicalKeyboardKey.keyU:
        upgradeSelectedTower();
        break;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        sellSelectedTower();
        break;
      default:
        break;
    }
  }

  /// Esc is two-stage like JS: first clears any selection, then pauses.
  void handleEscape() {
    if (selection.selectedTower != null ||
        selection.selectedRift != null ||
        selection.selectedBase ||
        selection.buildTarget != null ||
        selection.selectedTowerType != null ||
        gameWorld.abilitySystem.isTargeting) {
      gameWorld.abilitySystem.cancelTargeting();
      selection.clear();
      return;
    }
    togglePause();
  }

  void upgradeSelectedTower() {
    final tower = selection.selectedTower;
    if (tower == null) return;
    if (state.money.value < tower.upgradeCost) return;
    state.money.value -= tower.upgradeCost;
    tower.upgrade();
    gameWorld.particles.createParticles(
        tower.position.x, tower.position.y, const Color(0xFF00FF41), 15);
    saveSystem.save(); // JS saves on upgrade
  }

  void sellSelectedTower() {
    final tower = selection.selectedTower;
    if (tower == null) return;
    state.money.value += tower.sellValue;
    gameWorld.particles.createParticles(
        tower.position.x, tower.position.y, const Color(0xFFFFFFFF), 10);
    gameWorld.removeTower(tower);
    saveSystem.save(); // JS saves on sell
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

  /// Which overlay to restore when the Tech Tree screen closes (start screen
  /// or pause menu). Null when the Tech Tree isn't open.
  String? _techReturnOverlay;

  /// Open the Tech Tree overlay from [fromOverlay] (e.g. 'startScreen' or
  /// 'pauseMenu'); that overlay is hidden and restored on close.
  void openTechTree(String fromOverlay) {
    _techReturnOverlay = fromOverlay;
    overlays.remove(fromOverlay);
    overlays.add('techTree');
  }

  void closeTechTree() {
    overlays.remove('techTree');
    final back = _techReturnOverlay;
    _techReturnOverlay = null;
    if (back != null) overlays.add(back);
  }

  void togglePause() {
    if (state.phase.value != GamePhase.playing) return;
    state.isPaused.value = !state.isPaused.value;
    if (state.isPaused.value) {
      overlays.add('pauseMenu');
      audio.pauseMusic();
    } else {
      overlays.remove('pauseMenu');
      audio.resumeMusic();
    }
  }

  void startGame() {
    _applyTechRunBonuses();
    state.phase.value = GamePhase.playing;
    overlays.remove('startScreen');
    overlays.add('hud');
    gameWorld.startPrepPhase();
    tutorial.maybeStart();
  }

  /// Tech Tree start-of-run bonuses (credits/lives/energy). Applied to the
  /// fresh default state of a new run — never on the save-load path. Also
  /// re-arms the once-per-run Last Stand capstone.
  void _applyTechRunBonuses() {
    state.money.value += tech.fx.startMoney;
    state.lives.value += tech.fx.startLives;
    state.energy.value += tech.fx.startEnergy;
    lastStandUsed = false;
  }

  /// CONTINUE from the start screen: restore the save, then enter a prep
  /// phase (JS loadGame).
  Future<void> continueGame() async {
    final loaded = await saveSystem.load();
    if (!loaded) {
      startGame();
      return;
    }
    lastStandUsed = false; // fresh run; capstone re-armed
    state.phase.value = GamePhase.playing;
    overlays.remove('startScreen');
    overlays.add('hud');
    gameCamera.resetCamera();
  }

  void gameOver() {
    saveSystem.flushQueuedAutoSave(force: true);
    saveSystem.save(); // JS saves on game over
    audio.playHit(); // JS plays 'hit' on system failure
    audio.stopMusic();
    state.phase.value = GamePhase.gameover;
    overlays.remove('hud');
    overlays.add('gameOverScreen');
  }

  void resetGame() {
    state.reset();
    gameWorld.reset();
    _applyTechRunBonuses();
    state.phase.value = GamePhase.playing;
    selection.clear();
    overlays.remove('gameOverScreen');
    overlays.add('hud');
    gameWorld.startPrepPhase();
  }
}
