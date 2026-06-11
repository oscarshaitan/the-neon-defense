import 'package:flutter/foundation.dart';

import '../config/constants.dart';

enum GamePhase { start, playing, gameover }

/// Typed, observable game state. Mirrors the JS module globals
/// (00_core.js: money, lives, energy, wave, isWaveActive, gameState).
/// HUD widgets subscribe to individual notifiers instead of polling.
class GameState {
  final ValueNotifier<double> money = ValueNotifier(kStartingMoney);
  final ValueNotifier<int> lives = ValueNotifier(kStartingLives);
  final ValueNotifier<double> energy = ValueNotifier(kStartingEnergy);
  final ValueNotifier<int> wave = ValueNotifier(1);
  final ValueNotifier<bool> isWaveActive = ValueNotifier(false);
  final ValueNotifier<bool> isPaused = ValueNotifier(false);
  final ValueNotifier<GamePhase> phase = ValueNotifier(GamePhase.start);

  final Map<EnemyType, int> totalKills = {};

  String? playerName;

  /// Fixed-step frame counter — JS effects key off `frameCount`
  /// (e.g. spawn pulses use sin(frameCount * 0.1)). Incremented once per
  /// 60 Hz logic step while playing, frozen on pause like the JS loop.
  int frameCount = 0;

  /// Screen shake (JS startShake/decay, 00_core.js:268-273): new impulses
  /// keep the larger amount; decays x0.9 per render frame.
  double shakeAmount = 0;

  /// Transient HUD toast (quality governor notifications).
  final ValueNotifier<String?> toast = ValueNotifier(null);

  void startShake(double amount) {
    if (amount > shakeAmount) shakeAmount = amount;
  }

  double get maxEnergy => kMaxEnergy;

  bool get isPlaying => phase.value == GamePhase.playing && !isPaused.value;

  void addEnergy(double amount) {
    energy.value = (energy.value + amount).clamp(0.0, kMaxEnergy);
  }

  void recordKill(EnemyType type) {
    totalKills[type] = (totalKills[type] ?? 0) + 1;
  }

  void reset() {
    money.value = kStartingMoney;
    lives.value = kStartingLives;
    energy.value = kStartingEnergy;
    wave.value = 1;
    isWaveActive.value = false;
    isPaused.value = false;
    totalKills.clear();
    frameCount = 0;
    shakeAmount = 0;
  }
}
