import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../entities/towers/tower.dart';

/// Single source of truth for what the player has selected.
/// States are mutually exclusive, mirroring JS handleClick()
/// (01_init.js): selecting a tower clears the build type and vice versa.
class SelectionState extends ChangeNotifier {
  Tower? _selectedTower;
  TowerType? _selectedTowerType;

  Tower? get selectedTower => _selectedTower;
  TowerType? get selectedTowerType => _selectedTowerType;

  void selectTower(Tower? tower) {
    _selectedTower?.isSelected = false;
    _selectedTower = tower;
    tower?.isSelected = true;
    if (tower != null) _selectedTowerType = null;
    notifyListeners();
  }

  void selectTowerType(TowerType? type) {
    _selectedTower?.isSelected = false;
    _selectedTower = null;
    _selectedTowerType = type;
    notifyListeners();
  }

  void clear() {
    _selectedTower?.isSelected = false;
    _selectedTower = null;
    _selectedTowerType = null;
    notifyListeners();
  }
}
