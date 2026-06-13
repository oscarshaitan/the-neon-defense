import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../game/config/constants.dart';
import '../../game/neon_defense_game.dart';

class PauseMenu extends StatefulWidget {
  final NeonDefenseGame game;
  const PauseMenu({super.key, required this.game});

  @override
  State<PauseMenu> createState() => _PauseMenuState();
}

class _PauseMenuState extends State<PauseMenu> {
  NeonDefenseGame get game => widget.game;

  // Command center: SHA-256-gated developer tools (parity with JS/Godot).
  // Hash of the access code "Testing123!" — identical to the JS/Godot gate.
  static const _debugHash =
      '73ceb15f18bb0a313c8880abe54bf61a529dd8f1e75b084dd39926a1518d3d2f';
  static const _debugUnlockKey = 'neonDefenseDebugUnlocked';
  static const _pink = Color(0xFFFF00AC);
  static const _yellow = Color(0xFFFCEE0A);

  final TextEditingController _passController = TextEditingController();
  bool _debugUnlocked = false;
  bool _accessDenied = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (p.getBool(_debugUnlockKey) == true && mounted) {
        setState(() => _debugUnlocked = true);
      }
    });
  }

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    final hash = sha256.convert(utf8.encode(_passController.text)).toString();
    if (hash == _debugHash) {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_debugUnlockKey, true);
      if (mounted) setState(() => _debugUnlocked = true);
    } else {
      if (!mounted) return;
      setState(() => _accessDenied = true);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _accessDenied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xCC050510),
      body: Center(
        // Scrollable so the full menu stays reachable on short landscape
        // phone viewports.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PAUSED',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF00F3FF),
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 24),
              _menuBtn('RESUME', const Color(0xFF00F3FF), game.togglePause),
              const SizedBox(height: 10),
              _menuBtn('SAVE', const Color(0xFF00FF41), () {
                game.saveSystem.save();
                game.state.showToast('GAME SAVED');
              }),
              const SizedBox(height: 10),
              _menuBtn('RESET', const Color(0xFFFF00AC), () {
                game.overlays.remove('pauseMenu');
                game.resetGame();
              }),
              const SizedBox(height: 18),
              _soundRow(),
              const SizedBox(height: 12),
              _qualityRow(),
              _commandCenter(),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _soundRow() {
    final audio = game.audio;
    return Column(
      children: [
        _chipBtn(
          'SOUND: ${audio.muted ? 'OFF' : 'ON'}',
          selected: !audio.muted,
          onTap: () => setState(() => audio.toggleMute()),
        ),
        const SizedBox(height: 6),
        _volumeSlider('MUSIC', audio.musicVolume,
            (v) => setState(() => audio.setMusicVolume(v))),
        _volumeSlider('SFX', audio.sfxVolume,
            (v) => setState(() => audio.setSfxVolume(v))),
      ],
    );
  }

  Widget _volumeSlider(
      String label, double value, ValueChanged<double> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 8,
              color: Color(0x8800F3FF),
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(
          width: 140,
          height: 28,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00F3FF),
              inactiveTrackColor: const Color(0x3300F3FF),
              thumbColor: const Color(0xFF00F3FF),
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
        ),
      ],
    );
  }

  Widget _qualityRow() {
    final governor = game.gameWorld.qualityGovernor;
    return Column(
      children: [
        const Text(
          'DETAILS',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 9,
            color: Color(0x8800F3FF),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const [
              (QualityProfile.high, 'HIGH'),
              (QualityProfile.balanced, 'MED'),
              (QualityProfile.low, 'LOW'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _chipBtn(
                  entry.$2,
                  selected: !governor.autoAdjust &&
                      governor.currentProfile == entry.$1,
                  onTap: () =>
                      setState(() => governor.setProfileManually(entry.$1)),
                ),
              ),
            const SizedBox(width: 6),
            _chipBtn(
              'AUTO',
              selected: governor.autoAdjust,
              onTap: () => setState(() {
                governor.autoAdjust = true;
                game.state.showToast('DETAILS: AUTO');
              }),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Command center (JS/Godot parity): SHA-256-gated developer tools
  // ---------------------------------------------------------------------------

  Widget _ccHeader() => const Text(
        'COMMAND CENTER',
        style: TextStyle(
          fontFamily: 'Orbitron',
          fontSize: 10,
          color: _pink,
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _commandCenter() {
    final gw = game.gameWorld;
    if (!_debugUnlocked) {
      return Column(
        children: [
          const SizedBox(height: 18),
          _ccHeader(),
          const SizedBox(height: 6),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _passController,
              obscureText: true,
              textAlign: TextAlign.center,
              onSubmitted: (_) => _tryUnlock(),
              style: const TextStyle(
                  fontFamily: 'Orbitron', fontSize: 11, color: Colors.white),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'ACCESS CODE',
                hintStyle: TextStyle(
                    color: Color(0x66FF00AC),
                    fontFamily: 'Orbitron',
                    fontSize: 10),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _pink)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _pink)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _menuBtn(_accessDenied ? 'ACCESS DENIED' : 'UNLOCK COMMAND CENTER',
              _pink, _tryUnlock),
        ],
      );
    }

    Future<void> refreshAfter(Future<void> Function() op) async {
      await op();
      if (mounted) setState(() {});
    }

    return Column(
      children: [
        const SizedBox(height: 18),
        _ccHeader(),
        const SizedBox(height: 8),
        _menuBtn('+1M CREDITS', _yellow,
            () => setState(() => gw.debugAddMoney())),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
            children: [
          _chipBtn('NEW RIFT',
              selected: false,
              onTap: () => refreshAfter(gw.debugCreateRift)),
          _chipBtn('LEVEL UP RIFT',
              selected: false,
              onTap: () => setState(() => gw.debugLevelUpRift())),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
            children: [
          for (final w in const [(1, '+1 WAVE'), (5, '+5 WAVES'),
              (10, '+10 WAVES')])
            _chipBtn(w.$2,
                selected: false,
                onTap: () =>
                    refreshAfter(() => gw.waveSystem.debugIncreaseWave(w.$1))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
            children: [
          for (final n in const [5, 10, 25])
            _chipBtn('+$n LVL',
                selected: false,
                onTap: () => setState(() => gw.debugUpgradeAllTowers(n))),
        ]),
        const SizedBox(height: 8),
        _menuBtn('REBUILD RIFTS', const Color(0xFF00F3FF),
            () => refreshAfter(gw.waveSystem.debugRebuildRifts)),
        const SizedBox(height: 8),
        _menuBtn('TOGGLE OVERLAY', _pink,
            () => setState(() => gw.toggleNoBuildOverlay())),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
            children: [
          for (final e in const [
            (EnemyType.basic, 'BASIC'),
            (EnemyType.fast, 'FAST'),
            (EnemyType.tank, 'TANK'),
            (EnemyType.splitter, 'SPLIT'),
            (EnemyType.bulwark, 'BULW'),
            (EnemyType.shifter, 'SHIFT'),
            (EnemyType.boss, 'BOSS'),
          ])
            _chipBtn(e.$2,
                selected: false,
                onTap: () => setState(() => gw.debugSpawn(e.$1))),
        ]),
      ],
    );
  }

  Widget _chipBtn(String label,
      {required bool selected, required VoidCallback onTap}) {
    final color =
        selected ? const Color(0xFF00FF41) : const Color(0x8800F3FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
          color: selected ? const Color(0x1A00FF41) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 9,
            color: color,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(String label, Color color, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        minimumSize: const Size(180, 0),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Orbitron',
          fontSize: 13,
          letterSpacing: 3,
        ),
      ),
    );
  }
}
