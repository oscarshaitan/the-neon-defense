import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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

class _HudLayer extends StatefulWidget {
  final NeonDefenseGame game;
  const _HudLayer({required this.game});

  @override
  State<_HudLayer> createState() => _HudLayerState();
}

class _HudLayerState extends State<_HudLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() {}));
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Stack(
      children: [
        StatsBar(game: game),
        TowerBar(game: game),
        AbilitiesBar(game: game),
        SelectionPanel(game: game, selectedTower: game.selectedTower),
        // Recenter button — bottom-right circle, matches JS #recenter-btn
        SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20, right: 20),
              child: GestureDetector(
                onTap: () => game.gameCamera.resetCamera(),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xB3000000),
                    border: Border.all(
                        color: const Color(0xFF00F3FF), width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x8800F3FF), blurRadius: 15),
                    ],
                  ),
                  child: const Icon(Icons.my_location,
                      color: Color(0xFF00F3FF), size: 24),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
