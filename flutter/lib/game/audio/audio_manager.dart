import 'dart:convert';

import 'package:flame_audio/flame_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAudioSettingsKey = 'neonAudioSettings';

/// Audio with JS AudioEngine semantics (00_core.js:406-705), playing
/// pre-rendered loops of the same procedural patterns (tool/render_audio.py):
/// - music: threat loop while a boss/mutant is alive, else the wave-indexed
///   normal loop ((wave-1) % 15)
/// - SFX: shoot / explosion / hit / build
/// - master mute + music/sfx volumes persisted like JS neonAudioSettings
class AudioManager {
  double _musicVolume = 0.5; // JS musicVol default
  double _sfxVolume = 0.7; // JS sfxVol default
  bool _muted = false;

  String? _currentTrack;

  bool get muted => _muted;
  double get musicVolume => _musicVolume;
  double get sfxVolume => _sfxVolume;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    await _loadSettings();
    try {
      await FlameAudio.audioCache.loadAll([
        'shoot.wav',
        'explosion.wav',
        'hit.wav',
        'build.wav',
      ]);
    } catch (_) {
      // Assets missing — keep silent.
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAudioSettingsKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _musicVolume = (data['music'] as num?)?.toDouble() ?? 0.5;
      _sfxVolume = (data['sfx'] as num?)?.toDouble() ?? 0.7;
      _muted = data['muted'] as bool? ?? false;
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kAudioSettingsKey,
        jsonEncode({'music': _musicVolume, 'sfx': _sfxVolume, 'muted': _muted}),
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Music — JS updateMusic
  // ---------------------------------------------------------------------------

  /// Call regularly with current wave + threat presence; switches tracks
  /// only when the target changes (JS updateMusic).
  void updateMusic({required int wave, required bool hasThreat}) {
    final track = hasThreat
        ? 'music_threat.wav'
        : 'music_normal_${(((wave - 1) % 15) + 1).toString().padLeft(2, '0')}.wav';
    if (track == _currentTrack) return;
    _currentTrack = track;
    if (_muted) return;
    try {
      FlameAudio.bgm.play(track, volume: _musicVolume);
    } catch (_) {}
  }

  void pauseMusic() {
    try {
      FlameAudio.bgm.pause();
    } catch (_) {}
  }

  void resumeMusic() {
    if (_muted || _currentTrack == null) return;
    try {
      FlameAudio.bgm.resume();
    } catch (_) {}
  }

  void stopMusic() {
    _currentTrack = null;
    try {
      FlameAudio.bgm.stop();
    } catch (_) {}
  }

  void setMusicVolume(double v) {
    _musicVolume = v.clamp(0.0, 1.0);
    try {
      FlameAudio.bgm.audioPlayer.setVolume(_musicVolume);
    } catch (_) {}
    _saveSettings();
  }

  // ---------------------------------------------------------------------------
  // SFX — JS playSFX types
  // ---------------------------------------------------------------------------

  void playShoot() => _playSfx('shoot.wav');
  void playExplosion() => _playSfx('explosion.wav');
  void playHit() => _playSfx('hit.wav');
  void playBuild() => _playSfx('build.wav');

  void _playSfx(String file) {
    if (_muted) return;
    try {
      FlameAudio.play(file, volume: _sfxVolume);
    } catch (_) {}
  }

  void setSfxVolume(double v) {
    _sfxVolume = v.clamp(0.0, 1.0);
    _saveSettings();
  }

  // ---------------------------------------------------------------------------
  // Mute
  // ---------------------------------------------------------------------------

  bool toggleMute() {
    _muted = !_muted;
    if (_muted) {
      try {
        FlameAudio.bgm.pause();
      } catch (_) {}
    } else {
      resumeMusic();
    }
    _saveSettings();
    return _muted;
  }
}
