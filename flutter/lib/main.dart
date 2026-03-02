import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/neon_defense_game.dart';
import 'ui/screens/start_screen.dart';
import 'ui/screens/game_over_screen.dart';
import 'ui/hud/stats_bar.dart';
import 'ui/hud/tower_bar.dart';
import 'ui/hud/abilities_bar.dart';
import 'ui/panels/selection_panel.dart';
import 'ui/panels/pause_menu.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const NeonDefenseApp());
}

class NeonDefenseApp extends StatelessWidget {
  const NeonDefenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Neon Defense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const _GamePage(),
    );
  }
}

class _GamePage extends StatefulWidget {
  const _GamePage();

  @override
  State<_GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<_GamePage> {
  late final NeonDefenseGame _game;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _game = NeonDefenseGame();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyP ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _togglePause();
      } else {
        _game.handleKeyDown(event.logicalKey);
      }
    }
  }

  void _togglePause() {
    if (_game.gameState != 'playing') return;
    _game.isPaused = !_game.isPaused;
    if (_game.isPaused) {
      _game.overlays.add('pauseMenu');
    } else {
      _game.overlays.remove('pauseMenu');
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GameWidget<NeonDefenseGame>(
        game: _game,
        overlayBuilderMap: {
          'startScreen': (_, game) => StartScreen(game: game),
          'gameOverScreen': (_, game) => GameOverScreen(game: game),
          'hud': (_, game) => _HudLayer(game: game),
          'pauseMenu': (_, game) => PauseMenu(game: game),
        },
        initialActiveOverlays: const ['startScreen'],
      ),
    );
  }
}

class _HudLayer extends StatelessWidget {
  final NeonDefenseGame game;
  const _HudLayer({required this.game});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StatsBar(game: game),
        TowerBar(game: game),
        AbilitiesBar(game: game),
        SelectionPanel(game: game),
        // Pause button (top-right)
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () {
                  game.isPaused = !game.isPaused;
                  if (game.isPaused) {
                    game.overlays.add('pauseMenu');
                  } else {
                    game.overlays.remove('pauseMenu');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xE6050510),
                    border: Border.all(color: const Color(0x6000F3FF), width: 1),
                  ),
                  child: const Text(
                    'II',
                    style: TextStyle(
                      color: Color(0xFF00F3FF),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
