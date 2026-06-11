import 'package:flutter/material.dart';

import '../../game/config/constants.dart' show TowerType;
import '../../game/entities/towers/tower.dart';
import '../../game/neon_defense_game.dart';
import '../../game/systems/pathfinding/rift_generator.dart';

/// Selection panel with three variants matching JS updateSelectionUI
/// (04_tutorial.js): Tower info, Rift intel, and Base/HOME.
class SelectionPanel extends StatelessWidget {
  final NeonDefenseGame game;
  const SelectionPanel({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final selection = game.selection;
    final Widget? body;
    if (selection.selectedTower != null) {
      body = _towerBody(selection.selectedTower!);
    } else if (selection.selectedRift != null) {
      body = _riftBody(selection.selectedRift!);
    } else if (selection.selectedBase) {
      body = _baseBody();
    } else {
      body = null;
    }
    if (body == null) return const SizedBox.shrink();

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20, left: 10),
          padding: const EdgeInsets.all(14),
          width: 200,
          decoration: BoxDecoration(
            color: const Color(0xF0050510),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xB3FF00AC), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x5200F3FF), blurRadius: 16),
              BoxShadow(
                  color: Color(0x0AFF00AC),
                  blurRadius: 14,
                  spreadRadius: -2),
            ],
          ),
          child: body,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tower variant
  // ---------------------------------------------------------------------------

  Widget _towerBody(Tower tower) {
    final canUpgrade = game.state.money.value >= tower.upgradeCost;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('TOWER INFO'),
        const SizedBox(height: 8),
        _row('TYPE', tower.type.name.toUpperCase()),
        _row('LEVEL', '${tower.level}'),
        _row('DMG', tower.damage.toStringAsFixed(1)),
        _row('RNG', tower.range.toStringAsFixed(0)),
        if (tower.type == TowerType.arc)
          _row('ARC BONUS', '+${tower.arcNetworkBonus}'),
        if (tower.hardpoint != null)
          _row('MOUNT', tower.hardpoint!.type.name.toUpperCase()),
        const SizedBox(height: 10),
        _actionBtn(
          'UPGRADE  \$${tower.upgradeCost.toInt()}',
          canUpgrade ? const Color(0xFF00FF41) : const Color(0x44FFFFFF),
          canUpgrade ? () => _upgrade(tower) : null,
        ),
        const SizedBox(height: 6),
        _actionBtn(
          'SELL  \$${tower.sellValue.toInt()}',
          const Color(0xFFFF4444),
          () => _sell(tower),
        ),
        const SizedBox(height: 6),
        _closeBtn(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Rift intel variant
  // ---------------------------------------------------------------------------

  Widget _riftBody(RiftPath rift) {
    final level = rift.level;
    final hpMult = 1 + (level - 1) * 0.5;
    final speedMult = 1 + (level - 1) * 0.15;
    final mutation = rift.mutation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('RIFT INTEL'),
        const SizedBox(height: 8),
        _row('TIER', '$level'),
        _row('ZONE', '${rift.zone}'),
        _row('HP MULT', 'x${hpMult.toStringAsFixed(2)}'),
        _row('SPD MULT', 'x${speedMult.toStringAsFixed(2)}'),
        if (mutation != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '!! ${mutation.name} MUTATION !!',
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(mutation.colorValue),
              ),
            ),
          ),
        const SizedBox(height: 10),
        _closeBtn(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Base / HOME variant
  // ---------------------------------------------------------------------------

  Widget _baseBody() {
    final base = game.gameWorld.coreBase;
    final money = game.state.money.value;
    final canRepair = money >= base.repairCost;
    final canUpgrade = base.canUpgrade && money >= base.upgradeCost;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('HOME BASE'),
        const SizedBox(height: 8),
        _row('TURRET LVL', '${base.level}'),
        _row('LIVES', '${game.state.lives.value}'),
        if (base.level > 0) ...[
          _row('DMG', base.currentDamage.toStringAsFixed(0)),
          _row('RNG', base.currentRange.toStringAsFixed(0)),
        ],
        const SizedBox(height: 10),
        _actionBtn(
          'REPAIR  \$${base.repairCost.toInt()}',
          canRepair ? const Color(0xFF00FF41) : const Color(0x44FFFFFF),
          canRepair ? () => base.repair() : null,
        ),
        const SizedBox(height: 6),
        if (base.canUpgrade)
          _actionBtn(
            '${base.level == 0 ? 'INSTALL' : 'UPGRADE'} TURRET  \$${base.upgradeCost.toInt()}',
            canUpgrade ? const Color(0xFF00F3FF) : const Color(0x44FFFFFF),
            canUpgrade ? () => base.upgrade() : null,
          )
        else
          const Text(
            'MAX LEVEL',
            style: TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 9,
              color: Color(0x66FFFFFF),
            ),
          ),
        const SizedBox(height: 6),
        _closeBtn(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared pieces
  // ---------------------------------------------------------------------------

  Widget _header(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 11,
        color: Color(0xFFFF00AC),
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  Widget _closeBtn() => _actionBtn(
      'CLOSE', const Color(0x66FFFFFF), () => game.selection.clear());

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Color(0xAAFFFFFF),
              )),
          Text(value,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Color(0xFFFFFFFF),
                fontWeight: FontWeight.bold,
              )),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x80000000),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
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

  void _upgrade(Tower tower) {
    if (game.state.money.value < tower.upgradeCost) return;
    game.state.money.value -= tower.upgradeCost;
    tower.upgrade();
    game.gameWorld.particles.createParticles(
        tower.position.x, tower.position.y, const Color(0xFF00FF41), 15);
    game.saveSystem.save(); // JS saves on upgrade
  }

  void _sell(Tower tower) {
    game.state.money.value += tower.sellValue;
    game.gameWorld.particles.createParticles(
        tower.position.x, tower.position.y, const Color(0xFFFFFFFF), 10);
    game.gameWorld.removeTower(tower);
    game.saveSystem.save(); // JS saves on sell
  }
}
