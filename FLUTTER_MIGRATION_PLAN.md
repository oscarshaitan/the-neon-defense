# Flutter Migration Plan — JS → Flutter parity (refactor existing port)

Goal: bring `flutter/` to behavioral and "feel" parity with the JS game in `js/`. The JS version is the reference spec — every number, formula, and visual detail below points at the exact source of truth. The approach is to **refactor and extend the existing Flame port**, not rewrite it.

## Verified gap summary

Code-level comparison confirmed gaps beyond the obvious missing features:

1. **Placement model is wrong, not just incomplete.** Flutter `GameWorld.placeTower()` only allows hardpoint slots. JS allows any empty grid tile via tap-empty-tile → buildTarget → build panel → `buildTower()` with `isValidPlacement()` (path collision, occupancy, cost) — `js/scripts/04_tutorial.js:1019-1129`, `01_init.js:280-453`.
2. **Targeting mismatch.** JS targets the *nearest* enemy with bulwark taunt priority and invisible shifters excluded (`05_loop.js:592-624, 1351-1397`); Flutter sorts by path progress and ignores taunt/invisibility (`tower.dart:88-94`).
3. **Frozen ×1.2 damage bonus missing** (`05_loop.js:1484`).
4. **Base turret diverges**: JS cooldown `max(8, 35 - level*5)`, projectile speed 12; Flutter uses a fixed 60-frame cooldown, speed 7. Base selection/repair/upgrade UI is absent. JS quirks to replicate exactly (they are the played behavior): `upgradeBase()` increments level **twice**, `repairBase()` adds **+2 lives** (`00_core.js:499-535`).
5. **Enemy shapes**: Flutter renders all enemies as circles; JS has per-type silhouettes (tank=square, fast=kite, boss=hexagon, splitter=triangle), elite diamond markers, HP bars only when damaged (`06_render.js:405-530`).
6. **Rift generation is a placeholder**: Flutter picks random map-edge starts; JS uses orbital-zone shells, merge-vs-direct missions, zone-0 commitment, core repulsion, and destroys overlapping non-hardpoint towers with 70% refund (`04_tutorial.js:128-635`, `workers/path_worker.js`). The initial rift starts ≥10 cells from center, not at a map edge.
7. **Energy**: JS has no passive regen (+1 per kill only); delete Flutter's unused `kEnergyRegenPerFrame`. Hotkeys 1/2/u/delete are missing.

## Phase A1 — Architectural refactor (L) — prerequisite for everything else

No behavior change; restructuring so later phases land cleanly.

- **Typed `GameState`**: new `flutter/lib/game/state/game_state.dart` holding money, lives, wave, energy, isWaveActive, prepTimer, totalKills, playerName, gamePhase as `ValueNotifier`s. `NeonDefenseGame` owns one `GameState`; delete the loose fields in `neon_defense_game.dart:20-27`. Replace every `(game as dynamic)` cast (e.g. `enemy.dart:111-128`) with typed `HasGameReference<NeonDefenseGame>` → `game.state`.
- **Entity registries**: new `flutter/lib/game/state/entity_registry.dart` with explicit `List<Tower>/List<Enemy>/List<Projectile>` registered in `onMount`/`onRemove`; replaces all `children.whereType<T>()` scans (`wave_system.dart:179-181`, `ability_system.dart:76,92`, `game_world.dart:206`). Mirrors the JS module arrays (`00_core.js:236-243`).
- **Unified input routing**: remove `TapCallbacks` from `Tower`; resolve all taps in one `flutter/lib/game/input/input_router.dart` mirroring JS `handleClick()` priority (`01_init.js:280-432`): ability targeting → tower hit (<20 units) → rift spawn (<30) → base (<30) → build-target select → deselect. New `selection_state.dart` (selectedTower/Rift/Base, buildTarget, selectedTowerType, targetingAbility — mutually exclusive ChangeNotifier). Port the 8-px drag-vs-tap threshold (`01_init.js:76-128`).
- **HUD decoupling**: replace the per-frame `Ticker → setState` in `main.dart` with `ValueListenableBuilder`s; one low-rate ticker (~6 frames, JS `UI_SYNC_INTERVAL_FRAMES`) only for countdown/enemy-count text.
- **Frame counter + render order**: global `frameCount` on a fixed 60 Hz accumulator so JS frame-based numbers transfer 1:1 (pulses key off `sin(frameCount*0.1)`). Make `GameWorld` render order explicit via Flame `priority`, matching the JS `draw()` order (`06_render.js:86-798`): grid → paths → base → hardpoints → towers → arc links → enemies → projectiles → bursts → particles → overlays → lights → ghost preview.

**Verify**: `flutter analyze && flutter run -d chrome`; game plays identically to the current build; `grep -rn "as dynamic" lib/` is empty.

## Phase A2 — Core gameplay parity (L)

- **Free-tile placement + validation** (`04_tutorial.js:1019-1129` → new `placement_system.dart`): snap to 40-px grid; reject occupied/path-overlap (hardpoints always buildable); hardpoint multipliers (core dmg×1.08/range×1.06/cd×0.95; micro ×0.82/×0.86/×1.12, scale 0.78; cooldown floor 4); range cap 800; after build the new tower stays selected.
- **Targeting fix**: nearest-first with bulwark-taunt priority; add a taunter sub-index to `spatial_grid.dart` (JS `taunterCells`); exclude invisible enemies at cache-build time. Same for `CoreBase`.
- **Splitter/mini** (`05_loop.js:875-905`): on splitter death spawn 2–3 minis at ±10, `maxHp = parent×0.2`, `speed = parent×1.5`, inherit path/pathIndex/riftLevel/mutation/color; reward 5. Via `GameWorld.spawnMinis(parent)` callback.
- **Rift tier + mutation stat application** (`05_loop.js:812-873`): `hp = base*(1+wave*0.4)`, tier `hp ×= 1+(lvl-1)*0.5`, `speed ×= 1+(lvl-1)*0.15`, `reward = floor(reward*(1+(lvl-1)*0.5))`; then mutation multipliers + color + isMutant. Boss spawn adds a light source (150, `#ff8800`).
- **Mutations + rift evolution** (`03_abilities.js:808-929`): mutations last one wave; `wave % 20 == 0` mutates one random rift from the 5 profiles (CRIMSON/VOID/TITAN/PHASE/NEON with exact multipliers); `wave > 50`: 10%/wave permanent rift level++. Extend `RiftPath` with a full `Mutation` object (the key alone is insufficient for save/render).
- **Combat details**: frozen ×1.2 damage; kill = +1 energy (cap 100) + reward + totalKills++; Overclock = cooldown decrements 2×/frame (not halved maxCooldown); projectile speed 10 (towers) / 12 (base).
- **Base turret + interaction** (`00_core.js:499-535`): damage `20+(level-1)*10`, range `150+(level-1)*30`, cooldown `max(8, 35-level*5)`, cap level 10; repair cost `lives<20 ? 50 : 50+(lives-20+1)*25` (+2 lives); upgrade cost `200*(level+1)` (+2 levels, JS quirk); enemy reaching core → lives--, shake(20), hit SFX.
- **Rift generator parity** — the largest single item. Rewrite `rift_generator.dart` + `a_star.dart` against `04_tutorial.js:128-766` + `workers/path_worker.js`: orbital zone shells (`zone = floor((dist-6)/3)+1`, capacity `round(2z²·0.62)`), merge-vs-direct probability `0.5/zone²`, zone-0 commitment, core repulsion (radius 9, strength 14, quadratic), turn penalty 5 (+up to 18 near core), relaxed-level retries; destroy overlapping non-hardpoint towers with `floor(cost*level*0.7)` refund + white particles. Keep `compute()` execution.

**Verify**: side-by-side vs JS (`python3 -m http.server` in `js/`): splitters split at wave 15+; wave-20 mutation colors propagate; bulwarks soak targeting; shifters blink untargetable; a new rift at wave 11 spawns mid-ring and sometimes merges. Unit tests: `distributeByWeights`, upgrade/sell math, mini inheritance.

## Phase A3 — Game feel & VFX parity (L) — the core complaint

Reference `06_render.js` throughout. A3a–d can be pulled forward right after A1 for a fast "feels right" milestone.

- **Screen shake** (`00_core.js:268-273`): `shake = max(shake, amt)`, ×0.9/frame, offset ±shake/2 on camera; amt 20 on life loss.
- **Enemy silhouettes + status rings**: type shapes, glow via `MaskFilter.blur`, elite diamond when riftLevel>1, HP bar 20×3 only when damaged, shifter alpha 0.2, frozen cyan ring + frost fill, static-charge dashed rotating ring, overclock pulse ring.
- **Spawn pulses + rift styling**: pulse `1+sin(frameCount*0.1)*0.2`; tier-2+ rifts pink `#ff00ac` at 1.5× size; mutation rifts use the mutation color; dashed lines `[10,10]`; level pips.
- **Ghost preview + build target**: pulsing corner brackets, range circle green/red dashed `[5,5]`, 50%-alpha ghost, hardpoint scale preview — new `vfx/placement_preview.dart` reading `SelectionState`.
- **Tower/base visuals**: exact JS sizes (basic 26×26, rapid r13, sniper d15, arc hex r14 + core dot), level pips (diamond per 5 + dot per 1); base rotating hex shield layers, orbiting triangle drones (two orbits r32/r45), pulsing core.
- **Selection panel** floats next to the selected world object (clamped to screen), three variants: Tower (arc link/static/chain rows), Rift Intel (tier + multipliers + mutation banner), Base (repair/upgrade buttons). Needs `GameCamera.worldToScreen`. Rework `ui/panels/selection_panel.dart`.
- **Effects on every event**: map all JS `createParticles`/`addLightSource` call sites (kill, muzzle, upgrade, sell, build, invalid, repair, EMP, overclock) with the priority + spawn-budget semantics from `05_loop.js:17-115, 296-486`.
- **Quality toast + details menu**: surface the governor ("AUTO: DETAILS → MED" toast, HIGH/MED/LOW ± and AUTO toggle in the pause menu).
- **Palette/font audit**: bg `#050510`, cyan `#00f3ff`, pink `#ff00ac`, green `#00ff41`, yellow `#fcee0a`, grid `rgba(255,255,255,0.08)`, Orbitron everywhere.

**Verify**: screenshot A/B at fixed moments (fresh game, wave-10 boss, arc network, build mode) — visually indistinguishable.

## Phase A4 — Save/load parity + start screen (M)

- Mirror the JS schema exactly (`03_abilities.js:264-296`): money, lives, wave, isWaveActive, prepTimer, spawnQueue, paths (points/level/zone/mutation object), towers (full per-tower fields incl. hardpointId/Type/Scale), baseLevel, baseCooldown, energy, playerName, totalKills, pendingRiftGenerations, worldCols/Rows. Rewrite `save_system.dart` snapshot/apply (currently saves only 5 fields).
- Load semantics (`03_abilities.js:298-392`): rebuild hardpoints, clear transients, mid-wave loads demote to prep with `prepTimer = 5`.
- Autosave cadence (`05_loop.js:8-14, 668-689`): queue on kill, min 120-frame gap / 360-frame max delay; immediate save on wave start/complete, build, upgrade, sell, game over.
- Start screen: SAVE DATA FOUND → CONTINUE / NEW GAME; pause menu gains Save/Quit + volume/details rows.

**Verify**: save mid-game, hot-restart, CONTINUE restores everything with 5 s prep; diff a Flutter save JSON against a JS `localStorage` export — keys identical.

## Phase A5 — Audio (M)

JS reference: `AudioEngine` (`00_core.js:406-705`) — 15 wave-indexed 16-step loops + 1 threat loop (boss/mutant), square lead + triangle bass, 4 procedural SFX, volume sliders persisted.

**Approach: pre-render to assets + flame_audio** (already a dependency). A one-off offline render script (Node `OfflineAudioContext` or Python/numpy — the synthesis is just oscillators + exp-decay gains) emits `music_normal_01..15.ogg`, `music_threat.ogg`, and `shoot/explosion/hit/build.wav` (<1 MB total). `audio_manager.dart`: track = threat-present ? threat : `normal[(wave-1) % 15]` with crossfade; port the shoot-SFX throttle by quality profile (`05_loop.js:691-700`); persist volumes/mute. Trade-off: a synthesis package (`flutter_soloud`) would be literal but adds native/web risk for zero audible difference since the loops are deterministic per (wave, threat).

**Verify**: wave 10 flips to the threat track and back; melody changes per wave; mute/volumes persist.

## Phase A6 — Tutorial, hints, Wave Intel, hotkeys (M)

- **Tutorial** (`04_tutorial.js:1-126`): 5 steps; 0–1 paused modal with 20 ms/char typewriter; 2–4 unpaused, advancing on build-target select / successful build / wave start; SKIP only on step 0; persist tutorialComplete. New `ui/overlays/tutorial_overlay.dart` + `systems/tutorial_system.dart` hooked to PlacementSystem/WaveSystem events.
- **Hints** (`00_core.js:299-397`): versioned (v3) seen-keys, single-active queue, 3.6 s + 220 ms fade; keys ability_ready, camera_controls, rift_intel, tower_intel.
- **Wave Intel panel** (`03_abilities.js:68-249`): predicted distribution via `distributeByWeights` (largest-remainder rounding) with the exact weight tables per wave bracket; tags (BOSS, SURPRISE_BOSS, TAUNT, STEALTH, MUT_EVENT, T-tier); threat score → NORMAL/ELEVATED/HIGH/CRITICAL; live distribution mid-wave. New `ui/panels/wave_intel_panel.dart` + a stats-bar toggle.
- **Hotkeys**: 1/2 abilities, u upgrade, delete/backspace sell, esc two-stage (deselect → pause).

**Verify**: a fresh install (cleared prefs) runs the tutorial with JS step gating; Wave Intel predictions equal JS for waves 1–40 (unit-test `distributeByWeights` against JS outputs).

## Phase A7 — Final polish & acceptance (S)

Wave-30+ performance check (governor downgrades, particle budgets); full A/B play-through checklist (waves 1/5/10/15/20/25/30/51+) comparing composition, economy, rift placement character, mutations, audio, feel; `flutter test`, `flutter analyze`, web + one mobile build.

## Effort & ordering

| Phase | Scope | Size |
|---|---|---|
| A1 | Architecture refactor | L |
| A2 | Core gameplay parity (rift gen ~40% of it) | L |
| A3 | Game feel & VFX | L |
| A4 | Save/load + start screen | M |
| A5 | Audio (pre-rendered) | M |
| A6 | Tutorial, hints, Wave Intel | M |
| A7 | Polish & acceptance | S |

A4/A5/A6 are independent after A2 and can be parallelized. For a fast "feels right" milestone, pull A3a–d (shake, silhouettes, spawn pulses, ghost preview) forward right after A1.

**Critical files**: JS reference — `js/scripts/05_loop.js`, `03_abilities.js`, `06_render.js`; Flutter targets — `flutter/lib/game/neon_defense_game.dart`, `flutter/lib/game/world/game_world.dart`, plus the new `state/`, `input/`, and `systems/placement_system.dart` files listed above.
