import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neon_defense/game/neon_defense_game.dart';
import 'package:neon_defense/main.dart';

/// Renders every menu/overlay at a small landscape phone size and a desktop
/// size and fails on any layout exception (RenderFlex overflow throws in
/// tests). This is the automated "all menus and buttons render fine" gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<NeonDefenseGame> pumpGame(WidgetTester tester, Size size) async {
    // Muted so no FlameAudio call reaches the (absent) platform plugins.
    SharedPreferences.setMockInitialValues({
      'neonAudioSettings': '{"music":0.5,"sfx":0.7,"muted":true}',
    });
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.reset);

    final game = NeonDefenseGame();
    await tester.pumpWidget(MaterialApp(
      home: GameWidget<NeonDefenseGame>(
        game: game,
        overlayBuilderMap: NeonDefenseApp.overlayBuilders(),
        initialActiveOverlays: const ['startScreen'],
      ),
    ));
    // The onLoad chain does real async work (asset fetches, prefs) that the
    // fake-async test zone never services on its own; interleave real-async
    // windows with pumped frames, bounded so a regression fails fast instead
    // of hanging the suite.
    var loaded = false;
    for (var i = 0; i < 400 && !loaded; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
      loaded = game.isLoaded && game.gameWorld.isLoaded;
    }
    expect(loaded, isTrue, reason: 'game/world onLoad did not finish');
    await tester.pump(const Duration(milliseconds: 50));
    return game;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// Disposes the widget tree so periodic HUD timers are cancelled before
  /// the framework's pending-timer check. The leading pump lets one-shot
  /// timers (deferred save write, toasts) fire first.
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  for (final size in const [Size(640, 360), Size(1280, 800)]) {
    group('menus render at ${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('start screen', (tester) async {
        await pumpGame(tester, size);
        expect(find.text('THE NEON DEFENSE'), findsOneWidget);
        expect(find.text('INITIATE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      testWidgets('HUD + tower bar + abilities', (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        game.tutorial.skip(); // HUD without the tutorial dialog
        await settle(tester);
        expect(find.text('START WAVE'), findsOneWidget);
        expect(find.text('BASIC'), findsOneWidget);
        expect(find.text('ARC'), findsOneWidget);
        expect(find.textContaining('EMP'), findsWidgets);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      testWidgets('tutorial overlay (modal step)', (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        await settle(tester);
        expect(find.text('INCOMING TRANSMISSION'), findsOneWidget);
        expect(find.text('UNDERSTOOD'), findsOneWidget);
        expect(find.text('SKIP'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      testWidgets('pause menu with sound + quality controls', (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        game.tutorial.skip();
        await settle(tester);
        game.togglePause();
        await settle(tester);
        expect(find.text('PAUSED'), findsOneWidget);
        expect(find.text('RESUME'), findsOneWidget);
        expect(find.text('SAVE'), findsOneWidget);
        expect(find.text('RESET'), findsOneWidget);
        expect(find.text('AUTO'), findsOneWidget);
        expect(find.textContaining('SOUND:'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      testWidgets('wave intel panel', (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        game.tutorial.skip();
        await settle(tester);
        game.state.waveIntelOpen.value = true;
        await settle(tester);
        expect(find.textContaining('INTEL'), findsOneWidget);
        expect(find.text('THREAT'), findsOneWidget);
        expect(find.text('EXPECTED HOSTILES'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      testWidgets('selection panel (base variant)', (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        game.tutorial.skip();
        await settle(tester);
        game.selection.selectBase();
        await settle(tester);
        expect(find.text('HOME BASE'), findsOneWidget);
        expect(find.textContaining('REPAIR'), findsOneWidget);
        expect(find.textContaining('INSTALL TURRET'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      testWidgets('game over screen', (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        game.tutorial.skip();
        await settle(tester);
        game.gameOver();
        await settle(tester);
        expect(find.text('SYSTEM FAILURE'), findsOneWidget);
        expect(find.text('REBOOT SYSTEM'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });

      // Regression: a 32-bit shift overflow in the rift seed made
      // generateRift throw on the web target, silently producing a wave with
      // zero rifts (and therefore zero enemies). Prep must end with at least
      // one rift so spawning can happen. See rift_generator.dart seed bound.
      testWidgets('prep phase generates rifts so enemies can spawn',
          (tester) async {
        final game = await pumpGame(tester, size);
        game.startGame();
        game.tutorial.skip();
        // generateRift runs via compute() (async); service real-async windows
        // until rifts appear, bounded so a regression fails fast.
        var hasRift = false;
        for (var i = 0; i < 200 && !hasRift; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)));
          await tester.pump(const Duration(milliseconds: 16));
          hasRift = game.gameWorld.waveSystem.rifts.isNotEmpty;
        }
        expect(hasRift, isTrue,
            reason: 'prep phase produced no rifts — enemies cannot spawn');
        expect(tester.takeException(), isNull);
        await cleanup(tester);
      });
    });
  }
}
