import 'package:flame_audio/flame_audio.dart';

/// Wraps flame_audio for music and SFX.
/// All methods are safe to call before assets are loaded — they no-op silently.
class AudioManager {
  double _musicVolume = 0.5;
  double _sfxVolume = 0.8;
  bool _muted = false;

  bool get muted => _muted;
  double get musicVolume => _musicVolume;
  double get sfxVolume => _sfxVolume;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    // Pre-cache SFX so first play has no latency.
    // Files must exist in assets/audio/ — silently skip missing ones.
    await _safeCache('shoot.wav');
    await _safeCache('hit.wav');
    await _safeCache('emp.wav');
    await _safeCache('wave_start.wav');
    await _safeCache('game_over.wav');
  }

  Future<void> _safeCache(String file) async {
    try {
      await FlameAudio.audioCache.load(file);
    } catch (_) {
      // Asset not yet provided — skip
    }
  }

  // ---------------------------------------------------------------------------
  // Music
  // ---------------------------------------------------------------------------

  Future<void> playMusic(String file) async {
    if (_muted) return;
    try {
      await FlameAudio.bgm.play(file, volume: _musicVolume);
    } catch (_) {}
  }

  void stopMusic() {
    try {
      FlameAudio.bgm.stop();
    } catch (_) {}
  }

  void setMusicVolume(double v) {
    _musicVolume = v.clamp(0.0, 1.0);
    FlameAudio.bgm.audioPlayer.setVolume(_musicVolume);
  }

  // ---------------------------------------------------------------------------
  // SFX
  // ---------------------------------------------------------------------------

  void playShoot() => _playSfx('shoot.wav');
  void playHit()   => _playSfx('hit.wav');
  void playEmp()   => _playSfx('emp.wav');
  void playWaveStart() => _playSfx('wave_start.wav');
  void playGameOver()  => _playSfx('game_over.wav');

  void _playSfx(String file) {
    if (_muted) return;
    try {
      FlameAudio.play(file, volume: _sfxVolume);
    } catch (_) {}
  }

  void setSfxVolume(double v) => _sfxVolume = v.clamp(0.0, 1.0);

  // ---------------------------------------------------------------------------
  // Mute
  // ---------------------------------------------------------------------------

  void toggleMute() {
    _muted = !_muted;
    if (_muted) {
      stopMusic();
    }
  }
}
