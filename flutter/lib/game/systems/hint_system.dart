import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../neon_defense_game.dart';
import '../state/game_state.dart';

const _kHintsKey = 'neonDefenseOnboardingHints';
const _kHintsVersionKey = 'neonDefenseOnboardingHintsVersion';
const _kHintsVersion = 3;

/// Onboarding hint queue — port of JS 00_core.js:299-397.
/// Versioned seen-keys map; a single hint shows for 3.6 s (+220 ms fade),
/// suppressed while paused or during the tutorial.
class HintSystem extends ChangeNotifier {
  final NeonDefenseGame game;
  HintSystem(this.game);

  Map<String, bool> _seen = {};
  final List<({String key, String text})> _queue = [];
  final Set<String> _queuedKeys = {};
  String? activeHint;
  Timer? _hideTimer;

  Future<void> loadSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = int.tryParse(
            prefs.getString(_kHintsVersionKey) ?? '0') ??
        0;
    if (savedVersion != _kHintsVersion) {
      _seen = {};
      await prefs.setString(_kHintsVersionKey, '$_kHintsVersion');
      await prefs.setString(_kHintsKey, jsonEncode(_seen));
      return;
    }
    try {
      final stored =
          jsonDecode(prefs.getString(_kHintsKey) ?? '{}') as Map<String, dynamic>;
      _seen = stored.map((k, v) => MapEntry(k, v == true));
    } catch (_) {
      _seen = {};
    }
  }

  void _saveSeen() {
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_kHintsKey, jsonEncode(_seen)));
  }

  bool get _canShow =>
      game.state.phase.value == GamePhase.playing &&
      !game.tutorial.active &&
      !game.state.isPaused.value;

  void queue(String key, String text) {
    if (_seen[key] == true || _queuedKeys.contains(key)) return;
    _queuedKeys.add(key);
    _queue.add((key: key, text: text));
    showNext();
  }

  void showNext() {
    if (activeHint != null || _queue.isEmpty || !_canShow) return;
    final next = _queue.removeAt(0);
    _queuedKeys.remove(next.key);
    _seen[next.key] = true;
    _saveSeen();

    activeHint = next.text;
    notifyListeners();

    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3600 + 220), () {
      activeHint = null;
      notifyListeners();
      showNext();
    });
  }

  // JS hint triggers.
  void maybeShowAbilityHint() =>
      queue('ability_ready', 'Ability ready: press 1/2 or tap an ability icon.');
  void maybeShowCameraHint() => queue('camera_controls',
      'Camera controls: drag to pan, pinch/wheel to zoom, recenter to reset.');
  void maybeShowRiftHint() =>
      queue('rift_intel', 'Tap rifts to view threat multipliers and sector intel.');
  void maybeShowTowerHint() => queue('tower_intel',
      'Tower intel: tap a placed tower to inspect stats, then upgrade or sell.');
}
