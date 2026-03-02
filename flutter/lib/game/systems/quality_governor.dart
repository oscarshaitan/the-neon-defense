import 'package:flame/components.dart';

import '../config/constants.dart';
import '../vfx/particle_system.dart';
import '../vfx/arc_lightning.dart';
import '../vfx/light_source.dart';

/// Tracks EMA frame time and auto-downgrades/upgrades the quality profile.
/// Mirrors the JS quality governor logic exactly.
class QualityGovernor extends Component {
  final ParticleSystem particles;
  final ArcLightning arcLightning;
  final LightSourceSystem lights;

  QualityProfile currentProfile = QualityProfile.high;

  double _emaFrameMs = 16.0;
  int _downgradeCounter = 0;
  int _upgradeCounter = 0;

  // Notifier so UI can reflect current profile
  QualityProfile get profile => currentProfile;

  QualityGovernor({
    required this.particles,
    required this.arcLightning,
    required this.lights,
  });

  void recordFrameMs(double frameMs) {
    // EMA update
    _emaFrameMs = _emaFrameMs * 0.9 + frameMs * 0.1;

    final shouldDowngrade = frameMs > kQualityDowngradeFrameMs ||
        _emaFrameMs > kQualityDowngradeEmaMs;
    final shouldUpgrade = frameMs < kQualityUpgradeFrameMs &&
        _emaFrameMs < kQualityUpgradeEmaMs;

    if (shouldDowngrade) {
      _upgradeCounter = 0;
      _downgradeCounter++;
      if (_downgradeCounter >= kQualityDowngradeWindow) {
        _downgradeCounter = 0;
        _tryDowngrade();
      }
    } else if (shouldUpgrade) {
      _downgradeCounter = 0;
      _upgradeCounter++;
      if (_upgradeCounter >= kQualityUpgradeWindow) {
        _upgradeCounter = 0;
        _tryUpgrade();
      }
    } else {
      _downgradeCounter = 0;
      _upgradeCounter = 0;
    }
  }

  void _tryDowngrade() {
    switch (currentProfile) {
      case QualityProfile.high:
        _applyProfile(QualityProfile.balanced);
        break;
      case QualityProfile.balanced:
        _applyProfile(QualityProfile.low);
        break;
      case QualityProfile.low:
        break;
    }
  }

  void _tryUpgrade() {
    switch (currentProfile) {
      case QualityProfile.low:
        _applyProfile(QualityProfile.balanced);
        break;
      case QualityProfile.balanced:
        _applyProfile(QualityProfile.high);
        break;
      case QualityProfile.high:
        break;
    }
  }

  void _applyProfile(QualityProfile profile) {
    currentProfile = profile;
    particles.setProfile(profile);
    arcLightning.setProfile(profile);
    lights.setProfile(profile);
  }
}
