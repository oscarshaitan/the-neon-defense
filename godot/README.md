# The Neon Defense — Godot Edition

A Godot 4.3 rebuild of [the original JS game](../js/), targeting web (HTML5), Android, and iOS from a single project.

**Status: behavioral parity with the JS implementation** (per [GODOT_MIGRATION_PLAN.md](../GODOT_MIGRATION_PLAN.md)). The JS game remains the reference spec; every number, formula, and visual detail is traced to its JS source in code comments.

---

## Architecture

| JS concept | Godot mapping |
|---|---|
| Global mutable state | `State` autoload (`scripts/game_state.gd`) with change signals |
| Canvas 2D draw loop | Layered `Node2D._draw()`: grid and static world layers are cached and redrawn only on change signals; one dynamic layer redraws per frame (`scripts/render_layers.gd`) |
| Entity arrays | Lightweight `RefCounted` inner classes (`Enemy`/`Tower`/`Projectile` in `scripts/world.gd`) — no per-entity nodes, batched drawing per layer |
| `requestAnimationFrame` @ 60fps | Fixed 60 Hz logic accumulator in `scripts/main.gd` so JS frame-based numbers (cooldowns, timers, speeds) transfer 1:1 at any refresh rate |
| Web Worker A* | Synchronous generation in `scripts/pathfinding.gd` — fast enough in GDScript, and the web export is built without threads (no COOP/COEP headers needed on GitHub Pages) |
| Spatial hash (200-unit cells) | 1:1 port inside `world.gd` (towers never use physics queries; targeting matches JS exactly, including the taunter sub-index and invisible-shifter exclusion) |
| `localStorage` save | `user://save.json` via `FileAccess` + `JSON`, **same schema** as the JS save, with the JS deferred-write coalescing (50 ms) |
| Web Audio synthesis | `scripts/audio_engine.gd` synthesizes the same square-lead/triangle-bass note tables into `AudioStreamWAV` at load — 15 wave-indexed loops + threat loop + 4 SFX, zero audio assets |
| CSS HUD | All UI built in code in `scripts/hud.gd` (start/game-over screens, stats bar, tower bar, abilities + energy, selection panel variants, pause menu, Wave Intel, tutorial, hints, toasts) |

## Parity highlights

- Full rift-generation port: orbital zone shells, merge-vs-direct missions, core gap sectors, zone-0 commitment, core repulsion + near-core turn penalties, relaxation retries; new rifts destroy overlapping non-hardpoint towers (70% refund)
- Free-tile placement with the JS build-target flow; hardpoint stat multipliers (core ×1.08 dmg / ×1.06 range / ×0.95 cd; micro ×0.82 / ×0.86 / ×1.12)
- Splitter minis, mutations (CRIMSON/VOID/TITAN/PHASE/NEON), rift tier scaling, post-wave-50 evolution
- Base turret with the JS quirks preserved (upgrade +2 levels, repair +2 lives)
- Energy: +1 per kill only, capped at 100 — no passive regeneration
- EMP / Overclock abilities, frozen ×1.2 damage, overclock cdRate 2
- Arc-tower lightning network: cardinally aligned arc towers 1–3 cells apart link into connected components; each member's bonus = component size (capped 5), driving stronger static charge and brighter bolts, with the JS dot→dash→solid link rendering
- Command center: SHA-256-gated developer panel in the pause menu — credits, enemy spawns, wave jumps, rift create/level/rebuild, no-build overlay, `+5/+10/+25 LVL` bulk upgrade (range stays clamped to the 800 cap), and a **STRESS TEST** level builder (maxed base, ~20 rifts, a dense ring of every tower type around the core incl. a connected arc cluster, 100 mixed enemies)
- FPS counter in the stats bar; `F` repair base / `G` install·upgrade turret hotkeys (hold to repeat)
- Quality governor (EMA frame time, auto up/downgrade, toast, manual override in pause menu)
- Tutorial (5 steps, typewriter), versioned hints, Wave Intelligence panel with the exact `distributeByWeights` largest-remainder math

### Rendering
- Viewport culling on the dynamic layer: off-screen enemies/projectiles/particles/lights/towers/arc-bursts are skipped (the JS edition culls the same way; Godot 2D `_draw` is immediate mode, so this matters)
- Towers carry a persistent soft glow (stamped from a cached radial light texture) plus the muzzle flash on fire, matching the JS/Flutter look
- Near-black clear color (`C.COL_BG`) and a 0.1×–2.0× zoom range (the 1280×720 viewport frames more world at zoom 1 than the JS/Flutter canvases)

## Run

Open `project.godot` in Godot 4.3+ and press Run, or:

```bash
godot --path . 
```

## Test

A headless gameplay smoke test boots the real main scene, generates a rift, builds towers, fast-forwards through a wave, fires an EMP, and round-trips a save (~25 checks). Exits non-zero on failure, so it can gate CI:

```bash
godot --headless -s tool/headless_smoke.gd
```

## Export (web)

Requires the Godot 4.3 web export templates. The preset is configured with `thread_support=false` so the build runs on plain static hosting (GitHub Pages) without cross-origin isolation headers.

```bash
godot --headless --export-release "Web" build/web/index.html
```

The committed `build/web/` is what GitHub Pages serves at `/godot/build/web/`.

## Compatibility notes

- Written against **Godot 4.3** — avoid 4.4+ APIs (e.g. `Dictionary.get_or_add()`); the smoke test would have caught that one, and did.
- GL Compatibility renderer for the widest web/mobile reach; glow is drawn with layered translucent shapes rather than a WorldEnvironment so the look matches the JS canvas version on every backend.
