# The Neon Defense

**https://oscarshaitan.github.io/the-neon-defense/**

A neon-styled tower defense game — defend the core crystal against escalating Rift waves, elite enemy mutations, and high-pressure late-game scenarios.

| Version | Platform | Status |
|---|---|---|
| **JavaScript** | Web (HTML5 Canvas) | Live — reference implementation |
| **Flutter** | Web · Android · iOS | Live — full parity with the JS edition |
| **Godot** | Web · Android · iOS | Live — Godot 4.3, GL Compatibility renderer |

---

## Gameplay

### Combat Loop
- Four tower classes: **Basic**, **Rapid**, **Sniper**, **Arc**
- Hardpoint placement system — core ring (damage/range bonuses) and micro rings
- Tower upgrades, sell flow, and base crystal upgrades
- Arc tower network links with static charge accumulation

### Rift & Wave System
- Multi-path Rift spawning with A* pathfinding
- Rift tier progression and orbital zone biasing
- Mutation profiles that alter enemy stats and rewards mid-wave
- Wave Intelligence panel for threat visibility

### Enemies
- **Basic** · **Fast** · **Tank** · **Boss**
- **Splitter** — splits into minions on death
- **Bulwark** — high armor, slow
- **Shifter** — intermittently invisible

### Commander Abilities
- **EMP Burst** — freezes all enemies in a radius (energy cost: 40)
- **Overclock** — doubles fire rate on a single tower (energy cost: 25)
- Energy economy tied to kills — +1 energy per kill, capped at 100 (no passive regeneration)

---

## Controls

### Desktop (all versions)
| Input | Action |
|---|---|
| Left click / Tap | Select · place · interact |
| Drag | Pan camera |
| Scroll / Pinch | Zoom — 0.1×–1.0× (Godot 0.1×–2.0×) |
| `Q` `W` `E` `R` | Select tower type |
| `1` `2` | Ability targeting |
| `U` | Upgrade selected tower |
| `Del` / `Bksp` | Sell selected tower |
| `F` / `G` | Repair base / install·upgrade turret (Godot; hold to repeat) |
| `Esc` / `P` | Pause |

All three editions show a live **FPS counter** in the stats bar (Godot/Flutter hide it on very narrow phone widths).

### Mobile / Touch
- Tower bar and ability slots are always visible as tap targets
- Pinch to zoom, drag to pan
- Recenter button (bottom-right) snaps camera back to core

---

## Developer Command Center

All three editions ship a SHA-256-gated **command center** — a developer debug
panel inside the pause menu (the JS panel is in the pause overlay). Unlock it
with the access code, then use:

- **+1M credits**
- **Spawn** any enemy type (basic / fast / tank / splitter / bulwark / shifter / boss)
- **Rifts** — create a new rift, level up a rift, rebuild rift topology
- **Wave jumps** — +1 / +5 / +10 waves (skipped waves are simulated for correct pacing)
- **Bulk upgrade** — `+5 / +10 / +25 LVL` to every tower at once (range stays clamped to the 800 cap — never infinite)
- **Toggle overlay** — the spatial-zoning / no-build debug overlay
- **STRESS TEST** — builds a synthetic worst-case level for performance evaluation: maxed base turret + 1000 lives, ~20 level-1 rifts, a dense ring of every tower type packed around the core (including a connected arc cluster), and 100 mixed enemies

The unlock state persists (localStorage / `shared_preferences` / a `user://` marker).

---

## Run Locally

### JavaScript version

```bash
# Serve from the js/ folder, or the repo root:
python -m http.server 8000
# then open http://localhost:8000/js/
```

Or open `js/index.html` directly in a browser.

### Flutter version

```bash
cd flutter
flutter pub get
flutter run -d chrome
```

Build for web (the deployed build uses a relative base href so it works from any subpath):

```bash
flutter build web
# then set <base href="./"> in build/web/index.html
```

### Godot version

Open `godot/project.godot` in Godot 4.3+ and press Run, or from the command line:

```bash
godot --path godot
```

Export for web (requires the 4.3 web export templates):

```bash
godot --headless --path godot --export-release "Web" build/web/index.html
```

Headless gameplay smoke test (boots the real scene, plays a wave, checks invariants):

```bash
cd godot && godot --headless -s tool/headless_smoke.gd
```

---

## Project Structure

```
the-neon-defense/
  index.html                  — Landing page (links to all three versions)
  js/                         — JavaScript edition
    index.html
    scripts/
      00_core.js              — Constants, tower/arc/quality/pathing config
      01_init.js              — Canvas setup, input, camera, hardpoints
      02_game_control.js      — Placement, selection, build UI
      03_abilities.js         — EMP/Overclock, save/load, path worker
      04_tutorial.js          — Tutorial flow, path generation
      05_loop.js              — Main game loop, wave/enemy logic
      06_render.js            — All rendering (enemies, towers, VFX, UI)
      workers/
        path_worker.js        — Web Worker: async rift path generation
    styles/
      00_base_ui.css
      01_abilities_debug.css
      02_tutorial_and_responsive.css
    manual.html
    technical_docs.html
  flutter/                    — Flutter/Flame edition
    lib/
      main.dart               — App entry, GameWidget, HUD overlay layer
      game/
        neon_defense_game.dart
        config/
          constants.dart      — All game constants (mirrors JS 00_core.js)
        world/
          game_world.dart     — World component, entity managers, arc network
          tile_grid.dart      — Grid rendering (infinite, white lines)
          hardpoint_manager.dart
          arc_tower_links.dart  — Inter-tower arc link rendering
          no_build_overlay.dart — Command-center spatial-zoning overlay
        entities/
          towers/tower.dart
          enemies/enemy.dart
          projectiles/projectile.dart
          base/core_base.dart
        systems/
          pathfinding/
            a_star.dart
            rift_generator.dart
          wave_system.dart
          spatial_grid.dart
          ability_system.dart
          quality_governor.dart
        vfx/
          particle_system.dart
          arc_lightning.dart
          light_source.dart
        camera/game_camera.dart
      ui/
        hud/
          stats_bar.dart      — Full-width stats (wave, lives, credits, enemies)
          tower_bar.dart      — Tower selector with shaped icons
          abilities_bar.dart  — EMP / Overclock slots + vertical energy bar
        panels/
          selection_panel.dart
          pause_menu.dart
        screens/
          start_screen.dart
          game_over_screen.dart
    assets/
      fonts/Orbitron.ttf      — Bundled locally (no CDN dependency)
      audio/                  — Pre-rendered music loops + SFX (see tool/render_audio.py)
      images/
    pubspec.yaml
  godot/                      — Godot 4.3 edition
    project.godot             — Autoloads (State, AudioEngine), GL Compatibility
    scenes/main.tscn
    scripts/
      constants.gd            — All game constants (mirrors JS 00_core.js)
      game_state.gd           — Autoload: money/lives/wave/energy + signals
      world.gd                — Simulation: enemies, towers, projectiles, abilities
      pathfinding.gd          — A* + orbital-zone rift generation
      wave_intel.gd           — Wave Intelligence predictions
      save_system.gd          — user:// JSON save (same schema as JS localStorage)
      tutorial.gd / hints.gd
      audio_engine.gd         — Procedural music/SFX synthesized to AudioStreamWAV
      render_layers.gd        — Cached static layers + per-frame dynamic layer
      main.gd / hud.gd        — Fixed-step loop, input, all UI built in code
    tool/headless_smoke.gd    — Headless gameplay smoke test (CI-gateable)
    export_presets.cfg        — Web export (no-threads, GitHub Pages compatible)
    build/web/                — Committed web export served by GitHub Pages
```

---

## Technology

### JavaScript Edition
- HTML5 Canvas API
- Vanilla JavaScript (ES6+)
- CSS3
- Web Audio API (procedural soundtrack)
- Web Workers (async rift path generation, off main thread)
- Local Storage (save/load)

### Flutter Edition
- Flutter 3.x + Dart
- [Flame](https://flame-engine.org/) game engine (v1.x)
- CanvasKit web renderer (Skia/WASM, the default web renderer)
- `compute()` for rift path generation (parallel isolate on mobile, sync on web)
- SharedPreferences (save/load)
- Pre-rendered audio assets (generated by `flutter/tool/render_audio.py` from the JS synth spec)
- Orbitron font bundled locally

### Godot Edition
- Godot 4.3, GDScript, GL Compatibility renderer (stable HTML5 + widest mobile reach)
- Retained-mode 2D: static layers cached and redrawn only on change, one dynamic layer per frame
- Fixed 60 Hz logic stepping so JS frame-based numbers transfer 1:1
- Web export built without thread support (no COOP/COEP headers needed on GitHub Pages)
- Procedural audio synthesized at load into `AudioStreamWAV` (same note tables as the JS Web Audio engine)
- `user://save.json` with the same schema as the JS localStorage save

---

## Documentation

- Player manual: `js/manual.html`
- Technical reference: `js/technical_docs.html`
- Feature roadmap: `ROADMAP.md`
- Balance analysis: `GAME_BALANCE_ANALYSIS.md`
- Flutter parity migration plan: `FLUTTER_MIGRATION_PLAN.md`
- Godot migration plan: `GODOT_MIGRATION_PLAN.md`
- Performance/optimization log: `Improvements.md`
