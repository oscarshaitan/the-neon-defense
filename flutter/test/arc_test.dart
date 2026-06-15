import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neon_defense/game/config/constants.dart';
import 'package:neon_defense/game/entities/towers/tower.dart';
import 'package:neon_defense/game/neon_defense_game.dart';
import 'package:neon_defense/main.dart';

/// Regression: the Flutter arc tower previously fired a plain projectile and
/// never built the inter-tower network (arcNetworkBonus stayed 0, no arc was
/// rendered). These tests lock in the network computation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<NeonDefenseGame> pumpGame(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'neonAudioSettings': '{"music":0.5,"sfx":0.7,"muted":true}',
    });
    const size = Size(1280, 800);
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
    var loaded = false;
    for (var i = 0; i < 400 && !loaded; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
      loaded = game.isLoaded && game.gameWorld.isLoaded;
    }
    expect(loaded, isTrue, reason: 'game/world onLoad did not finish');
    return game;
  }

  testWidgets('cardinally aligned arc towers link into one component',
      (tester) async {
    final game = await pumpGame(tester);
    game.startGame();
    game.tutorial.skip();
    await tester.pump(const Duration(milliseconds: 16));

    // Three arc towers on a horizontal line, 2 cells apart (within the 1-3
    // link spacing). Added directly so placement validation is irrelevant.
    Tower arcAt(int col, int row) => Tower(
          position: Vector2(col * kGridSize + kGridSize / 2,
              row * kGridSize + kGridSize / 2),
          type: TowerType.arc,
          spatialGrid: game.gameWorld.spatialGrid,
        );
    final t1 = arcAt(10, 10);
    final t2 = arcAt(12, 10);
    final t3 = arcAt(14, 10);
    await game.gameWorld.addAll([t1, t2, t3]);
    // Let onMount register them in the entity registry.
    await tester.pump(const Duration(milliseconds: 16));

    game.gameWorld.markArcNetworkDirty();
    game.gameWorld.refreshArcNetwork();

    expect(game.gameWorld.arcTowerLinks.length, greaterThanOrEqualTo(2),
        reason: 'adjacent arc towers should form links');
    expect(t1.arcNetworkBonus, 3, reason: 'component of 3 grants bonus 3');
    expect(t2.arcNetworkBonus, 3);
    expect(t3.arcNetworkBonus, 3);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('stress test builds a dense level with a connected arc network',
      (tester) async {
    final game = await pumpGame(tester);
    game.startGame();
    game.tutorial.skip();
    await tester.pump(const Duration(milliseconds: 16));

    // Async (awaits rift generation via compute); run on the real event loop.
    await tester.runAsync(() => game.gameWorld.debugStressTest());
    // Pump so the bulk-added towers mount and the network refreshes.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(game.gameWorld.waveSystem.rifts.length, greaterThanOrEqualTo(15));
    expect(game.entities.towers.length, greaterThanOrEqualTo(40));
    final arcTowers =
        game.entities.towers.where((t) => t.type == TowerType.arc).length;
    expect(arcTowers, greaterThan(0));
    expect(game.gameWorld.arcTowerLinks, isNotEmpty,
        reason: 'the arc block should form a connected network');
    expect(game.entities.enemies.length, greaterThan(0));
    expect(game.state.lives.value, 1000);
    expect(game.gameWorld.coreBase.level, 10);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a lone arc tower has bonus 1 and no links', (tester) async {
    final game = await pumpGame(tester);
    game.startGame();
    game.tutorial.skip();
    await tester.pump(const Duration(milliseconds: 16));

    final lone = Tower(
      position: Vector2(20 * kGridSize, 20 * kGridSize),
      type: TowerType.arc,
      spatialGrid: game.gameWorld.spatialGrid,
    );
    await game.gameWorld.add(lone);
    await tester.pump(const Duration(milliseconds: 16));

    game.gameWorld.markArcNetworkDirty();
    game.gameWorld.refreshArcNetwork();

    expect(game.gameWorld.arcTowerLinks, isEmpty);
    expect(lone.arcNetworkBonus, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
