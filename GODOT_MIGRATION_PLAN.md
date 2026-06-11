# Godot Plan — The Neon Defense in Godot 4.x (GDScript, web + mobile)

Goal: rebuild the game in Godot 4.x with GDScript, primary target HTML5 (like the JS version) plus Android/iOS. The single source of truth for all mechanics, numbers, and feel is the JS code in `js/scripts/` (`00_core.js` constants/audio, `01_init.js` input/camera/hardpoints, `03_abilities.js` abilities/waves/save, `04_tutorial.js` tutorial/build flow, `05_loop.js` main loop, `06_render.js` rendering/VFX, `workers/path_worker.js` async A*).

## B0. Project setup (S)

- New `godot/` directory at repo root, Godot **4.3+**, GDScript, **Compatibility renderer** (required for stable HTML5 export and best mobile reach).
- Export presets from day one: Web (HTML5), Android, iOS. CI check that the web export builds.
- Folder layout mirroring the game's systems:
  ```
  godot/
    project.godot
    scenes/          # main.tscn, game.tscn, ui/*.tscn
    scripts/
      core/          # constants.gd, game_state.gd, save_system.gd
      entities/      # tower.gd, enemy.gd, projectile.gd, core_base.gd
      systems/       # wave_system.gd, ability_system.gd, pathfinding/, spatial_grid.gd
      vfx/           # particles, arc lightning, light sources, screen shake
      audio/         # procedural music player
    ui/              # HUD scenes + scripts
    assets/          # Orbitron font, icons
  ```
- Port all constants from `js/scripts/00_core.js` into `scripts/core/constants.gd` verbatim (tower stats, enemy stats, colors, GRID_SIZE=40, world 140×90, zone radii, quality profiles). This file is the parity contract.

## B1. Architecture mapping (JS concept → Godot equivalent)

| JS concept | Godot equivalent |
|---|---|
| Global mutable state (`playerMoney`, `lives`, waves) | `game_state.gd` as an **autoload singleton** with signals (`money_changed`, `lives_changed`, `wave_changed`, `energy_changed`) |
| Canvas 2D + manual draw loop | `Node2D` scene tree; custom `_draw()` on dedicated canvas layers for grid/paths/particles (keeps the JS-style batched look rather than per-entity sprites) |
| Entity arrays (enemies, towers, projectiles) | Plain `Array[Enemy]` etc. held by `game.gd`; entities are lightweight `Node2D`s (or RefCounted + one MultiMesh/`_draw` layer for projectiles/particles) |
| requestAnimationFrame loop | `_process(delta)`; convert JS frame-based timings (cooldowns in frames @60fps) to seconds: `seconds = frames / 60.0` — keep one conversion helper so numbers stay traceable to JS |
| Web Worker A* (`path_worker.js`) | `WorkerThreadPool.add_task()` or a `Thread` for rift generation; **on web export use `call_deferred` time-slicing instead** (threads on HTML5 require cross-origin isolation headers — avoid the dependency) |
| Spatial hash (200-unit cells) | Port `spatial_grid` logic 1:1 as `spatial_grid.gd` (don't use Godot physics/Area2D for targeting — keeps behavior identical and cheap) |
| localStorage save | `user://save.json` via `FileAccess` + `JSON` — keep the **same JSON schema** as the JS save so balance/QA can compare states |
| CSS UI panels | Godot `Control` nodes in a `CanvasLayer`: stats bar, tower selector, abilities bar, selection panel, pause menu, Wave Intel, tutorial overlay. Theme with Orbitron + neon palette (`#00f3ff`, `#ff00ac`, `#fcee0a`, `#00ff41`, bg `#050510`) |
| `ctx.shadowBlur` glow | WorldEnvironment **Glow** (2D HDR) on the Compatibility renderer, or additive-blend sprites; pick one early and tune against the JS look |

## B2. Phased build order

**Phase 1 — Core loop skeleton (M)**
Camera (pan/drag, wheel/pinch zoom 0.1–1.0×, recenter), infinite grid `_draw()`, core crystal, hardpoint rings (6 core slots +8% dmg/+6% range, micro rings 10+14 slots, snap radius 18), tower placement/ghost preview, credits/lives in `game_state.gd`. Reference: `01_init.js`, `06_render.js` grid/hardpoint sections.

**Phase 2 — Enemies, paths, waves (L)**
A* rift generation port from `path_worker.js` (including placement relaxation levels and orbital-zone biasing), path-following enemies, all 8 enemy types with exact stats from `00_core.js`, wave distribution math from `03_abilities.js` (`count = 5 + floor(wave × 2.5)`, weight tables per wave threshold, boss every 10 waves), rift tier scaling (+50% HP, +15% speed, +50% reward per tier), **mutation profiles applied** (stats + colors), splitter→2-3 minis on death, shifter phase cycle, bulwark armor/taunt.

**Phase 3 — Combat (M)**
Tower targeting via spatial grid (nearest-first with bulwark taunt priority, invisible shifters excluded), projectiles, upgrade (+20% dmg/+10% range per level, cost `0.5 × base × level`) / sell (70% refund), arc tower network (link adjacency 1–3 cells, charge accumulation, stun at 100), core turret at level > 0, frozen ×1.2 damage bonus.

**Phase 4 — Abilities & economy polish (S)**
EMP (cost 40, radius freeze 5s, cooldown) and Overclock (cost 25, 2× fire rate 10s); +1 energy per kill (no passive regen), cap 100; energy bar UI.

**Phase 5 — VFX & game feel (M)**
Particle pool with quality budgets (HIGH 900 / BALANCED 620 / LOW 420), light sources, arc lightning rendering (sine-wave interpolated segments), screen shake (`max(shake, amt)`, ×0.9/frame), spawn pulses on rifts (`1+sin(frameCount*0.1)*0.2`), glow tuning. Quality governor port: EMA frame-time, auto-downgrade > 22ms / upgrade < 15.8ms, toast notification, manual override in pause menu.

**Phase 6 — UI completeness (M)**
Wave Intel panel (threat level, mutation chance, distribution breakdown via `distributeByWeights`), pause menu (save, manual, volume sliders, quality controls), game over ("SYSTEM FAILURE"), start screen with CONTINUE/NEW GAME based on existing save, tutorial port from `04_tutorial.js` (typewriter dialog, 5 steps with build/wave-gated advancement, hint queue with 3.6s display, versioned hints).

**Phase 7 — Audio (M)**
Godot is a *better* fit than Flutter for the JS procedural audio: use `AudioStreamGenerator` + `AudioStreamGeneratorPlayback` to re-implement the melody/bass synthesis from `00_core.js:406-705` (15 wave-indexed loops + threat loop, square lead + triangle bass, 4 procedural SFX), or pre-render loops to OGG if synthesis on web underperforms. Master/music/SFX buses with sliders, mute persistence.

**Phase 8 — Export & platform polish (S)**
Web export (verify the thread-free pathfinding path), touch input verification (drag thresholds, pinch), responsive UI anchors for phone aspect ratios, save persistence on web (`user://` maps to IndexedDB), itch.io/GitHub Pages deploy of the HTML5 build.

## B3. Godot-specific risks

- **Web threads**: design pathfinding to run time-sliced on the main thread for the HTML5 export from the start (don't bolt it on later).
- **Glow parity**: Compatibility-renderer 2D glow needs HDR 2D enabled; budget a tuning pass against side-by-side JS screenshots.
- **Frame-based → delta-based timing**: the single biggest source of subtle behavior drift; centralize the conversion and spot-check cooldowns/speeds against the JS at 60fps.

## B4. Verification

- Run side-by-side with the JS version (`python3 -m http.server` in `js/`) and compare: wave 1–10 composition, credits after each wave, tower DPS vs a tank enemy, EMP freeze duration, arc stun behavior.
- Scripted parity check: dump game-state JSON at wave end in both versions and diff the economy numbers.
- Export the web build and test on a phone browser (touch + performance with the quality governor).
