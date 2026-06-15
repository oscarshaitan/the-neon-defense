# Cross-Edition Learnings & Comparison

Engineering notes from building and maintaining **The Neon Defense** as three
parallel editions — a JavaScript reference and Flutter/Godot ports that must
stay at behavioral parity. The JS edition is the single source of truth; every
number and formula in the ports is traced back to it.

This document captures what actually broke, why, and the patterns worth
remembering — drawn from the code and commit history, not theory.

---

## 1. The three editions at a glance

| Concern | JavaScript (reference) | Flutter / Flame | Godot 4.3 |
|---|---|---|---|
| State | Module-global `let`s (`00_core.js`) | Typed `GameState` (`ValueNotifier`) | `State` autoload + change signals |
| Rendering | Canvas2D immediate draw loop | Flame components, `RenderLayers` priorities | `Node2D._draw()` — static layers cached, one dynamic layer per frame |
| Frame loop | `requestAnimationFrame` @ 60fps | Fixed 60 Hz accumulator (`_step = 1/60`) | Fixed 60 Hz accumulator (`FIXED_STEP`) |
| Why fixed-step | n/a (native 60) | JS numbers are frame-based (cooldowns, stun=30f); fixed-step makes them transfer 1:1 at any refresh rate | same |
| Pathfinding | Web Worker A* (off main thread) | `compute()` — isolate on mobile, **synchronous on web** | Synchronous GDScript (fast enough; web export is single-threaded) |
| Save | `localStorage` | `shared_preferences` | `user://save.json` — **same schema** |
| Audio | Web Audio synthesis | Pre-rendered WAV (offline render of the JS synth) | Synthesized to `AudioStreamWAV` at load |
| Zoom | wheel, 0.1×–1.0× | wheel + pinch, 0.1×–1.0× | wheel + pinch, **0.1×–2.0×** (wider viewport baseline) |
| Deploy | static files | `flutter build web` from source in CI | **committed** `build/web/` binary export |

The logic ported cleanly. **Almost every bug was in the seams** — coordinate
conventions, render origins, platform int/async semantics, and input — not in
the game rules.

---

## 2. Coordinate & rendering conventions are where ports drift

The single biggest bug cluster. Three distinct instances, same theme:

- **Flame's render canvas origin is the component's top-left, not its center**
  — even with `Anchor.center`. Shapes authored around `(0,0)=center` (as the JS
  draw functions are) ended up half a size up-left. Towers landed exactly on the
  grid intersection; enemies drew above the rift line. Fix: `canvas.translate(size/2)`
  at the top of each `render()`. (`tower.dart`, `enemy.dart`, `core_base.dart`,
  `projectile.dart`)
- **`worldCols * kGridSize / 2` is a grid line for an even world width**, but
  hardpoints and rift termini use the cell *center* (`col*kGridSize + kGridSize/2`).
  The core base sat half a cell off, on the intersection. (`game_world.dart`)
- **Godot 2D `_draw()` is immediate-mode.** Static layers cache (redraw only on
  signal — genuinely free), but the dynamic layer re-runs every draw call every
  frame. With no viewport culling, every off-screen entity still cost a draw —
  the real cause of "Godot perf is bad." The JS edition culls via
  `isWorldPointVisible`; Godot didn't. (`render_layers.gd`)

**Takeaway:** when porting a canvas game, audit the render origin and
cell-center-vs-grid-line conventions *first*, and replicate the reference's
culling — that's where visual drift and perf gaps hide.

---

## 3. Platform / engine gotchas that tests don't catch

| Edition | Gotcha | Symptom | Fix |
|---|---|---|---|
| Flutter (web) | `1 << 32` overflows to `0` on the JS target (32-bit shifts); native VM does not | `Random.nextInt(0)` threw, rift gen silently aborted → **no enemies ever spawned**, but VM tests passed | Use a portable bound (`0x7FFFFFFF`); surface the swallowed async error |
| Flutter | No `Material`/`Scaffold` ancestor → WidgetsApp's error `DefaultTextStyle` (yellow **double underline**) | Every overlay `Text` had an underline | Wrap `GameWidget` in a transparent `Material` |
| Flutter / Flame | `add()` / `remove()` are **deferred** to the next tick | Reading `entities.towers` right after adding gave a stale set (arc network saw 0 towers) | Mark state dirty in `onMount`/`onRemove`, not at the call site |
| Flutter (web/desktop) | `ScaleDetector` is pinch-only | **No zoom at all** with a mouse | Add `ScrollDetector` wheel zoom |
| Godot | `emulate_touch_from_mouse` + `emulate_mouse_from_touch` both on → duplicate events | Taps could leak past a button and deselect/close panels | Disable mouse→touch; guard world taps against HUD rects |
| Godot | Ships a **committed binary** web export | Source edits don't deploy until re-exported | Re-export `build/web/` on every Godot change |

**Meta-lesson:** the test environment and the shipped target can disagree. The
`1 << 32` bug is the sharpest example — green CI, dead game. Test against the
real target's semantics where it matters.

---

## 4. A green build is not a working feature

The Flutter arc tower **compiled, rendered a tower, and fired** — but it fired a
plain projectile and never produced any arc; the entire chain/network/static
mechanic was a stub (`ArcLightning.emit` was never called). The README even
listed the command center as "not ported" while claiming overall parity.

**Takeaway:** parity claims and passing builds are not evidence of behavior.
Verify the feature actually does the thing — ideally with a test that asserts an
observable outcome (e.g. "the arc network forms links with bonus 3").

---

## 5. Performance: measure before optimizing

When "performance is bad on all" came in, profiling **cleared every recent
feature** — the new arc-network refresh was dirty-gated, the no-build overlay
flag-gated, the FPS counter an EMA. The real costs were pre-existing and
architectural:

- **Godot:** no viewport culling on the dynamic layer (the big one).
- **Flutter:** `Projectile.render` allocated a `Paint` per projectile per frame (GC churn).
- **JS:** the enemy status-VFX loop ran its work before the visibility check.

What was deliberately **not** done: capping JS projectiles — that would drop
gameplay shots, not just VFX. Optimization must not change correctness.

**Takeaway:** the scary-looking new code usually isn't the bottleneck; profile,
then cut the cheapest-to-fix biggest cost.

---

## 6. Synthetic load needs *interaction*, not just entity count

The first stress-test build placed 200 towers — but in a wide band whose far
rows filled first and hit the cap, leaving towers ~22 cells from the core while
enemies converge on it. Result: a packed map with **no combat**. Re-centering
the towers into a tight ring around the core (where the rifts converge) turned
it into real load — verified by kills-per-frame, not tower count.

**Takeaway:** a stress level is only stressful where systems actually interact.
Measure the interaction (kills/frame), not the population.

---

## 7. Verification & tooling discipline

- **Run the real toolchains when you can.** Installing Godot 4.3 and Flutter
  3.38.5 caught regressions reading couldn't: a 640px HUD overflow from the FPS
  counter, stochastic rift counts (4 vs 20 — the generator can fail an attempt),
  and the arc block being crowded out by the placement cap (`arc_towers=0`).
- **Be explicit about verification boundaries.** Godot and Flutter are run here;
  JS is not (`node --check` + reasoning only). Say which is which.
- **Match the SDK constraint.** Flutter 3.35 (Dart 3.9) failed the project's
  `^3.10.4`; 3.38.5 (Dart 3.10.4) was required to even `pub get`.

---

## 8. Bug catalog (this maintenance cycle)

| Symptom | Root cause | Edition | Commit |
|---|---|---|---|
| Game dead on arrival (no enemies) | `nextInt(1 << 32)` → `0` on web → `RangeError` | Flutter | `951ae08` |
| Towers on grid intersections; enemies above the path | Flame render origin is top-left | Flutter | `7680c51` |
| Text has a double underline | No `Material` ancestor | Flutter | `7680c51` |
| Rifts render as bare lines | Single blurred stroke ≠ JS `shadowBlur` halo | Flutter | `7680c51` |
| Arc tower never arcs | Mechanic was a stub | Flutter | `190537c` |
| No zoom on web/desktop | Pinch-only input | Flutter | `3e37f15` |
| Main turret on the intersection | Core positioned on a grid line | Flutter | `3f62928` |
| Arc towers don't connect | Inter-tower network unimplemented | Godot | `951ae08` |
| Weak muzzle flash | Flat discs, slow decay | Godot | `951ae08` |
| No command center | Panel not ported | Godot | `cd043c0` |
| Tapping a panel button closes the menu | Tap leaked to world handler / double emulation | Godot | `59fedc9` |
| Godot perf poor | No viewport culling (immediate-mode draw) | Godot | `4290258` |
| Gray background | Default engine clear color | Godot | `3e37f15` |
| Towers don't glow at rest | No persistent glow layer | Godot | `3e37f15` |
| Can't zoom in as close as others | 1280×720 viewport frames more world | Godot | `3e37f15` |
| Stress towers far from core, no combat | Wide band + cap fill order | all | `f2d9ebc` |

---

## 9. Open / known divergences

- **Godot zoom cap (2.0×) is a heuristic**, not a measured match to the JS/Flutter
  framing — the exact multiplier depends on the runtime viewport ratio.
- **Flutter world bounds fixed at 140×90** — the JS `expandWorldBounds` growth
  isn't ported.
- **Flutter selection panel is docked bottom-left**, not floating next to the
  selected object.
- **Godot must be re-exported** for any script change to reach the deployed build.

---

*See also: `README.md` (overview + controls + command center), the per-edition
`README`s, `GODOT_MIGRATION_PLAN.md` / `FLUTTER_MIGRATION_PLAN.md` (parity
plans), and `Improvements.md` (JS performance log).*
