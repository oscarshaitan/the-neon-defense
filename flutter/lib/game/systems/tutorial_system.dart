import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../neon_defense_game.dart';

const _kTutorialCompleteKey = 'neonDefenseTutorialComplete';

/// Tutorial flow — port of JS 04_tutorial.js:1-126.
/// Steps 0-1 pause the game behind a modal dialog; steps 2-4 unpause and
/// advance on gameplay events (build-target select, successful build,
/// wave start). SKIP is offered only on step 0.
class TutorialSystem extends ChangeNotifier {
  final NeonDefenseGame game;
  TutorialSystem(this.game);

  bool active = false;
  bool completed = false;
  int step = 0;

  static const List<String> stepTexts = [
    'Welcome, Commander. Our sector is under threat. We need to establish '
        'a defense perimeter immediately.',
    'Command protocol loaded. You will now place your first defense node.',
    'First, select a tactical position. Hardpoint: fixed anchor slot with '
        'placement bonuses. Soft point: any normal empty grid tile without '
        'slot bonuses. Now TAP AN EMPTY SQUARE near the Core to target it.',
    'Position locked. Now, CHOOSE A TOWER TYPE from the deployment panel '
        'below.',
    'Defense initialized. When you\'re ready to engage the enemy, click '
        'START WAVE.',
  ];

  String get currentText => stepTexts[step.clamp(0, stepTexts.length - 1)];

  /// Steps 0-1 are modal (game paused, button-advanced); 2-4 pass input
  /// through to the game.
  bool get isModalStep => step <= 1;
  bool get canSkip => step == 0;

  Future<void> loadCompletionFlag() async {
    final prefs = await SharedPreferences.getInstance();
    completed = prefs.getString(_kTutorialCompleteKey) == 'true';
  }

  void maybeStart() {
    if (completed || active) return;
    active = true;
    step = 0;
    game.state.isPaused.value = true;
    notifyListeners();
  }

  void next() {
    if (!active) return;
    step++;
    if (step > 4) {
      _finish();
      return;
    }
    game.state.isPaused.value = isModalStep;
    notifyListeners();
  }

  void skip() {
    if (!active) return;
    _finish();
  }

  void _finish() {
    active = false;
    game.state.isPaused.value = false;
    completed = true;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_kTutorialCompleteKey, 'true'));
    notifyListeners();
    game.hints.showNext();
  }

  // Gameplay-event hooks (JS advance triggers).
  void onBuildTargetSelected() {
    if (active && step == 2) next();
  }

  void onTowerBuilt() {
    if (active && step == 3) next();
  }

  void onWaveStarted() {
    if (active && step == 4) next();
  }
}
