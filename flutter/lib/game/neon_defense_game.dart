import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import 'config/constants.dart';
import 'world/game_world.dart';
import 'camera/game_camera.dart';
import 'audio/audio_manager.dart';
import 'entities/towers/tower.dart';
import 'systems/save_system.dart';

class NeonDefenseGame extends FlameGame
    with ScaleDetector, HasKeyboardHandlerComponents, TapCallbacks {
  late GameWorld gameWorld;
  late GameCamera gameCamera;
  final AudioManager audio = AudioManager();
  late SaveSystem saveSystem;

  // --- Game state ---
  double money = kStartingMoney;
  int lives = kStartingLives;
  double energy = kStartingEnergy;
  double get maxEnergy => kMaxEnergy;
  int wave = 1;
  bool isWaveActive = false;
  bool isPaused = false;
  String gameState = 'start'; // 'start' | 'playing' | 'gameover'

  Tower? selectedTower;

  void selectTower(Tower? tower) {
    selectedTower?.isSelected = false;
    selectedTower = tower;
    tower?.isSelected = true;
    if (tower != null) gameWorld.selectedTowerType = null;
  }

  @override
  Color backgroundColor() => kColorBg;

  @override
  Future<void> onLoad() async {
    gameCamera = GameCamera(this);
    gameWorld = GameWorld(this);

    saveSystem = SaveSystem(this);
    await audio.init();
    camera = gameCamera.cameraComponent;
    world.add(gameWorld);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameState == 'playing' && !isPaused) {
      gameWorld.qualityGovernor.recordFrameMs(dt * 1000);
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (gameState != 'playing' || isPaused) return;
    final worldPos = gameCamera.screenToWorld(event.canvasPosition);
    final ability = gameWorld.abilitySystem;
    if (ability.isTargeting) {
      ability.useAbility(worldPos);
    } else if (gameWorld.selectedTowerType != null) {
      gameWorld.placeTower(worldPos);
    } else {
      selectTower(null);
    }
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
        gameWorld.selectTowerType(TowerType.basic);
        break;
      case LogicalKeyboardKey.keyW:
        gameWorld.selectTowerType(TowerType.rapid);
        break;
      case LogicalKeyboardKey.keyE:
        gameWorld.selectTowerType(TowerType.sniper);
        break;
      case LogicalKeyboardKey.keyR:
        gameWorld.selectTowerType(TowerType.arc);
        break;
      case LogicalKeyboardKey.escape:
        gameWorld.deselect();
        break;
      default:
        break;
    }
  }

  void startGame() {
    gameState = 'playing';
    overlays.remove('startScreen');
    overlays.add('hud');
    gameWorld.startPrepPhase();
  }

  void gameOver() {
    gameState = 'gameover';
    overlays.remove('hud');
    overlays.add('gameOverScreen');
  }

  void resetGame() {
    money = kStartingMoney;
    lives = kStartingLives;
    energy = kStartingEnergy;
    wave = 1;
    isWaveActive = false;
    isPaused = false;
    gameState = 'playing';
    selectTower(null);
    overlays.remove('gameOverScreen');
    overlays.add('hud');
    gameWorld.reset();
    gameWorld.startPrepPhase();
  }
}
