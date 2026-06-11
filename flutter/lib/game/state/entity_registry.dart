import '../entities/enemies/enemy.dart';
import '../entities/projectiles/projectile.dart';
import '../entities/towers/tower.dart';

/// Explicit entity lists, mirroring the JS module arrays
/// (00_core.js: towers, enemies, projectiles). Entities self-register in
/// onMount/onRemove; systems iterate these instead of scanning the
/// component tree with `children.whereType<T>()`.
class EntityRegistry {
  final List<Tower> towers = [];
  final List<Enemy> enemies = [];
  final List<Projectile> projectiles = [];

  void clear() {
    towers.clear();
    enemies.clear();
    projectiles.clear();
  }
}
