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
import 'ui/overlays/tutorial_overlay.dart';
import 'ui/panels/selection_panel.dart';
import 'ui/panels/pause_menu.dart';
import 'ui/panels/wave_intel_panel.dart';

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
      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        _game.togglePause();
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _game.handleEscape(); // two-stage: deselect, then pause
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
/// Transient toast for quality-governor notifications
/// (JS showQualityToast). Hiding is managed by GameState.showToast so
/// widget rebuilds can't re-arm the timer.
class _QualityToast extends StatelessWidget {
  final NeonDefenseGame game;
  const _QualityToast({required this.game});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: game.state.toast,
      builder: (_, message, child) {
        if (message == null) return const SizedBox.shrink();
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 64),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xE6050510),
                border:
                    Border.all(color: const Color(0xFFFCEE0A), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 10,
                  color: Color(0xFFFCEE0A),
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Single-line onboarding hint (JS inline-hint): 3.6 s display.
class _HintBanner extends StatelessWidget {
  final NeonDefenseGame game;
  const _HintBanner({required this.game});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.hints,
      builder: (_, child) {
        final hint = game.hints.activeHint;
        if (hint == null) return const SizedBox.shrink();
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 116),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xE6050510),
                border: Border.all(color: const Color(0x8800F3FF), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                hint,
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 9,
                  color: Color(0xCCE6FCFF),
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

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
        WaveIntelPanel(game: game),
        _QualityToast(game: game),
        _HintBanner(game: game),
        // The panel shows money/lives-dependent costs and affordances, so it
        // listens to those notifiers directly rather than relying on the
        // low-rate HUD timer.
        ListenableBuilder(
          listenable: Listenable.merge(
              [game.selection, game.state.money, game.state.lives]),
          builder: (_, child) => SelectionPanel(game: game),
        ),
        TutorialOverlay(game: game),
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
