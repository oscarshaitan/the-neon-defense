import 'dart:async';

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
        _game.togglePause();
      } else {
        _game.handleKeyDown(event.logicalKey);
      }
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

/// HUD container. Stat widgets subscribe to GameState notifiers; data that
/// has no notifier (prep countdown, enemy count, ability cooldowns) is
/// refreshed by a single low-rate timer (~6 frames, matching the JS
/// UI_SYNC_INTERVAL_FRAMES) instead of a per-frame setState ticker.
class _HudLayer extends StatefulWidget {
  final NeonDefenseGame game;
  const _HudLayer({required this.game});

  @override
  State<_HudLayer> createState() => _HudLayerState();
}

class _HudLayerState extends State<_HudLayer> {
  Timer? _uiSync;

  @override
  void initState() {
    super.initState();
    _uiSync = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _uiSync?.cancel();
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
        ListenableBuilder(
          listenable: game.selection,
          builder: (_, child) => SelectionPanel(game: game),
        ),
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
