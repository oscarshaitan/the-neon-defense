# The Neon Defense — Flutter Edition

A Flutter/Flame port of [the original JS game](../js/), targeting web (CanvasKit), Android, and iOS from a single codebase.

**Status: at parity with the JS implementation** (migration phases A1–A7 complete; the per-phase plan was retired — its history is in git). The JS game remains the reference spec; every number, formula, and visual detail is traced to its JS source in code comments.

---

## Parity highlights

### Architecture (Phase A1)
- Typed `GameState` (ValueNotifier-backed) — no `dynamic` casts anywhere
- `EntityRegistry` with explicit tower/enemy/projectile lists (mirrors the JS module arrays)
- `InputRouter` resolving all taps with the JS `handleClick()` priority order
- Fixed 60 Hz logic stepping so JS frame-based numbers transfer 1:1 at any refresh rate
- Explicit `RenderLayers` priorities matching the JS `draw()` pipeline
- Central pause gating; HUD updates at the JS UI sync interval

### Gameplay (Phase A2)
- Full rift-generation port: orbital zone shells, merge-vs-direct missions, core gap sectors, zone-0 commitment, core repulsion + near-core turn penalties, relaxation retries; new rifts destroy overlapping non-hardpoint towers (70% refund)
- Free-tile placement with the JS build-target flow (tap tile → pick type); hardpoints are always-buildable anchors with stat multipliers
- Targeting: nearest-first with bulwark taunt priority; invisible shifters untargetable
- Splitters burst into 2–3 minis inheriting path progress, tier, and mutation
- Mutations (CRIMSON/VOID/TITAN/PHASE/NEON) applied to stats and colors, cleared each wave; rifts evolve permanently past wave 50
- Base turret with exact JS numbers, repair (+2 lives) and upgrade (+2 levels) quirks replicated
- Frozen ×1.2 damage, overclock cdRate, projectile speeds 10/12

### Game feel (Phase A3)
- Screen shake, per-type enemy silhouettes, elite markers, damage-only HP bars
- JS tower shapes/sizes, level pips (diamond per 5 + dot per 1), selection rings
- Base hex shields + orbiting drones; rift tier/mutation styling with spawn pulses
- Build-target brackets + ghost preview with validity colors
- JS particle semantics (3×3 rects, alpha-quantized batching) with every JS effect call site
- Quality governor toasts + HIGH/MED/LOW/AUTO controls

### Persistence (Phase A4)
- Save schema mirrors JS `neonDefenseSave` field-for-field
- Autosave cadence (120-frame min gap / 360 max delay) + immediate saves on the JS triggers
- CONTINUE / NEW GAME start screen; mid-wave loads demote to a 5 s prep

### Audio (Phase A5)
- The JS procedural patterns pre-rendered to WAV by `tool/render_audio.py` (15 wave-indexed loops + threat loop + 4 SFX)
- Threat track while a boss/mutant is alive; throttled shoot SFX; persisted volumes/mute

### Onboarding (Phase A6)
- 5-step tutorial with typewriter dialogs and gameplay-gated advancement
- Versioned onboarding hints (ability/camera/rift/tower)
- Wave Intelligence panel: predicted/live distribution, threat tags, mutation readiness
- Hotkeys: Q/W/E/R build, 1/2 abilities, U upgrade, Del sell, Esc two-stage, P pause

---

## Run

```bash
flutter pub get
flutter run -d chrome
```

Build for web:

```bash
flutter build web --base-href /the-neon-defense/flutter/
```

> **CanvasKit is required.** The HTML renderer does not produce game-quality Canvas output.

Regenerate audio assets after changing the JS patterns:

```bash
python3 tool/render_audio.py
```

Tests (tower economy, mutations, placement snapping, Wave Intel math):

```bash
flutter test
```

---

## Architecture

```
lib/
  main.dart                     — App entry, GameWidget, HUD stack (notifier-driven)
  game/
    neon_defense_game.dart      — FlameGame root, fixed-step loop, hotkeys
    config/constants.dart       — All game constants (mirrors JS 00_core.js)
    state/
      game_state.dart           — Typed observable game state
      selection_state.dart      — Mutually exclusive selection states
      entity_registry.dart      — Explicit entity lists
    input/input_router.dart     — JS handleClick() priority order
    world/
      game_world.dart           — RenderLayers, pause gate, entity API, arc network + debug ops
      rift_path_renderer.dart   — Rift styling layer
      tile_grid.dart            — Infinite-looking grid
      hardpoint_manager.dart    — Core + micro ring hardpoints
      arc_tower_links.dart      — Inter-tower arc link rendering
      no_build_overlay.dart     — Command-center spatial-zoning overlay
    entities/
      towers/tower.dart         — Taunt-aware targeting, overclock cdRate
      enemies/enemy.dart        — Silhouettes, status effects, splitter death
      projectiles/projectile.dart
      base/core_base.dart       — Turret, repair/upgrade, shields + drones
    systems/
      pathfinding/
        a_star.dart             — Faithful findPathOnGrid port
        rift_generator.dart     — Mission logic port (compute() isolate)
      placement_system.dart     — Free-tile placement + validation
      wave_system.dart          — Waves, mutations, rift evolution
      wave_intel.dart           — distributeByWeights + intel report (pure)
      tutorial_system.dart      — 5-step tutorial state machine
      hint_system.dart          — Versioned onboarding hints
      spatial_grid.dart         — 200-unit cells + taunter sub-index
      ability_system.dart       — EMP + Overclock
      quality_governor.dart     — EMA frame time -> profile + toasts
      save_system.dart          — JS-schema save/load + autosave cadence
    vfx/
      particle_system.dart      — JS createParticles semantics
      render_utils.dart         — drawTowerShape, drawLevelPips, dashes
      placement_preview.dart    — Build-target brackets + ghost
      arc_lightning.dart, light_source.dart
    audio/audio_manager.dart    — Pre-rendered loop selection + SFX
    camera/game_camera.dart     — Pan/zoom + screen shake
  ui/
    hud/                        — stats bar (Wave Intel toggle), tower bar, abilities bar
    panels/                     — selection (tower/rift/base), pause, wave intel
    overlays/tutorial_overlay.dart
    screens/                    — start (CONTINUE/NEW GAME), game over
tool/
  render_audio.py               — Offline renderer for the JS procedural audio
```

---

### Arc network, dev tools & polish (Phase A7)
- Arc tower fires the JS instant-chain (target hit → static charge/stun → bounces to nearby enemies) and renders the bolt; cardinally aligned arc towers 1–3 cells apart link into connected components (bonus = component size, capped 5) drawn by `ArcTowerLinkRenderer`
- SHA-256-gated **command center** in the pause menu (access code shared with JS/Godot): +1M credits, spawn any enemy, create/level/rebuild rifts, +1/+5/+10 wave jumps, `+5/+10/+25 LVL` bulk upgrade, no-build overlay toggle, and a **STRESS TEST** level builder
- **FPS counter** in the stats bar (EMA of frame time); hidden on narrow phone widths so the bar never overflows
- Mouse-wheel / trackpad zoom toward the cursor (web + desktop, which have no pinch)
- In-world sprites centered on their cell (Flame's render origin is top-left); core base sits on the cell center, not the grid line

## Known gaps vs JS

- World bounds are fixed at 140×90 (the JS `expandWorldBounds` growth isn't ported)
- The selection panel is docked bottom-left rather than floating next to the selected object

## Dependencies

```yaml
flame: ^1.35.1           # Game engine
flame_audio: ^2.x        # Pre-rendered music loops + SFX
shared_preferences: ^2.x # Save/load + settings persistence + command-center unlock
crypto: ^3.x             # SHA-256 for the command-center access gate
google_fonts: ^8.x       # Kept as dep; Orbitron is bundled in assets/fonts/
```
