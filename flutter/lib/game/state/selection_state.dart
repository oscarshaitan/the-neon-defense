import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../entities/towers/tower.dart';
import '../systems/pathfinding/rift_generator.dart';

/// Single source of truth for what the player has selected.
/// States are mutually exclusive, mirroring the JS selection globals
/// (selectedPlacedTower / selectedRift / selectedBase / buildTarget /
/// selectedTowerType — 01_init.js handleClick + 04_tutorial.js).
class SelectionState extends ChangeNotifier {
  Tower? _selectedTower;
  TowerType? _selectedTowerType;
  RiftPath? _selectedRift;
  bool _selectedBase = false;
  Vector2? _buildTarget;

  Tower? get selectedTower => _selectedTower;
  TowerType? get selectedTowerType => _selectedTowerType;
  RiftPath? get selectedRift => _selectedRift;
  bool get selectedBase => _selectedBase;
  Vector2? get buildTarget => _buildTarget;

  void selectTower(Tower? tower) {
    _clearAll();
    _selectedTower = tower;
    tower?.isSelected = true;
    notifyListeners();
  }

  void selectTowerType(TowerType? type) {
    final keptBuildTarget = _buildTarget;
    _clearAll();
    _buildTarget = keptBuildTarget;
    _selectedTowerType = type;
    notifyListeners();
  }

  void selectRift(RiftPath? rift) {
    _clearAll();
    _selectedRift = rift;
    notifyListeners();
  }

  void selectBase() {
    _clearAll();
    _selectedBase = true;
    notifyListeners();
  }

  /// JS selectBuildTarget (01_init.js:434-453): picking an empty tile
  /// clears every other selection and opens the build panel.
  void selectBuildTarget(Vector2 snap) {
    _clearAll();
    _buildTarget = snap.clone();
    notifyListeners();
  }

  void clear() {
    _clearAll();
    notifyListeners();
  }

  void _clearAll() {
    _selectedTower?.isSelected = false;
    _selectedTower = null;
    _selectedTowerType = null;
    _selectedRift = null;
    _selectedBase = false;
    _buildTarget = null;
  }
}
