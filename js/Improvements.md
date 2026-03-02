# Performance Improvements Roadmap

Scales:
- Complexity: `1` (low) to `5` (high)
- Expected Gain: `1` (small) to `5` (large)

## Ranked Ideas (Complexity First, Then Gain)

| Rank | Idea | Complexity | Gain | Status | Notes |
|---|---|---:|---:|:---:|---|
| 1 | Add frame-time budgets and profiling checkpoints by subsystem | 1 | 5 | ✅ | Baseline required to validate all other optimizations |
| 2 | Render culling by viewport for non-critical visuals | 1 | 4 | ✅ | Render only in-view visuals while keeping gameplay simulation global |
| 3 | Throttle UI/DOM writes and update only when values change | 1 | 3 | ✅ | Reduces layout/reflow and DOM churn |
| 4 | Gate expensive text rendering to "needed" cases only | 1 | 3 | ✅ | Status labels only near cursor/selection |
| 5 | Pre-warm/pre-size object pools at wave start | 1 | 2 | ✅ | Pool exhaustion fallback `{}` eliminated; pools filled at init |
| 6 | Cap particles/lights/bursts per frame with priority | 2 | 5 | ✅ | Stabilizes frame-time under heavy combat |
| 7 | Object pooling for particles/projectiles/lights | 2 | 4 | ✅ | Reduces garbage-collection spikes |
| 8 | Dynamic quality governor based on frame-time | 2 | 4 | ✅ | Auto scales visuals under load; +/- stepper UI with auto-drop toast |
| 9 | Cache/reuse radial gradients for light sources | 2 | 4 | ✅ | Pre-baked to offscreen canvas per `(color, radius)`; `drawImage` per frame |
| 10 | Stagger low-priority visual updates across frames | 2 | 3 | ✅ | Smooths frame spikes |
| 11 | Replace repeated scans with cached sets/lists | 2 | 3 | ✅ | Reduces repeated O(n) filtering work |
| 12 | Spatial hash/grid broad-phase for targeting and chain lookups | 3 | 5 | ✅ | `ENEMY_SPATIAL_GRID` (cellSize=200); tower targeting, arc bounce, base turret |
| 13 | Cache arc lightning trig / static geometry draw primitives | 3 | 3 | ✅ | `_arcSegCache` typed arrays; only sin/cos per frame; burst.geom pre-baked |
| 14 | Batch render operations by style/material | 3 | 3 | ✅ | Projectiles, enemies (4-pass), particles (alpha×color quantization), arc links (pre-bucketed by intensity, 1 traversal instead of 10N) all batched |
| 15 | Eliminate `globalCompositeOperation: 'screen'` from hot paths | 2 | 4 | ✅ | Removed from arc links, arc bursts, and dynamic lighting; GPU read-back eliminated |
| 16 | Remove hit particles; skip full-HP health bars; pre-bake boss hexagon | 1 | 3 | ✅ | Arc hit particles removed; health bars only on damaged enemies; boss hex uses lookup table |
| 17 | Move path/rift generation and wave precompute to Web Worker | 4 | 4 | ✅ | `scripts/workers/path_worker.js`; batch protocol; main thread applies side-effects after `path_ready` messages |
| 18 | Move save/telemetry post-processing off main thread | 4 | 2 | ✅ | `requestIdleCallback` with 5 s timeout fallback; snapshot taken sync, stringify+write deferred |
| 19 | OffscreenCanvas rendering pipeline in worker | 5 | 4 | ⏸ | Deferred: requires ~50–100 KB/frame serialization at 60 fps (3–6 MB/s) — too costly without ECS first |
| 20 | Data-oriented entity architecture (ECS/typed arrays) | 5 | 5 | ⏸ | Deferred: full rewrite; existing object pools already mitigate GC at current entity scale |

---

## Phase A — Complexity 1 ✅ Done

- [x] C1-1 Profiling checkpoints + subsystem frame budgets
- [x] C1-2 Viewport culling for non-critical visuals
- [x] C1-3 UI throttling + update-on-change writes
- [x] C1-4 Expensive text gating to needed context
- [x] C1-5 Pre-warm/pre-size object pools at wave start

## Phase B — Complexity 2 ✅ Done

- [x] C2-6 Cap particles/lights/bursts per frame with priority
- [x] C2-7 Object pooling for particles/projectiles/lights
- [x] C2-8 Dynamic quality governor + +/- stepper UI + auto-drop toast
- [x] C2-10 Stagger low-priority visual updates across frames
- [x] C2-11 Replace repeated scans with cached sets/lists
- [x] C2-9 Cache/reuse radial gradients for light sources

## Phase C — Complexity 3 ✅ Done

- [x] C3-12 Spatial hash/grid broad-phase (targeting + arc bounce + base turret)
- [x] C3-13 Cache arc lightning trig segments; burst.geom pre-baked at creation
- [x] C3-14 Batch render: projectiles by color, enemies 4-pass, particles by alpha×color, arc links pre-bucketed by intensity

## Phase C+ — Post-Phase-C Quick Wins ✅ Done

- [x] Remove `globalCompositeOperation: 'screen'` from arc links (HIGH) — batched by intensity level
- [x] Remove `globalCompositeOperation: 'screen'` from arc bursts (HIGH) — source-over, brighter alpha
- [x] Remove `globalCompositeOperation: 'screen'` from dynamic lights — all GPU read-back eliminated
- [x] Pre-bake boss hexagon offsets (`_HEX_COS`/`_HEX_SIN`) — 0 trig calls per boss per frame
- [x] Skip health bar render for full-HP enemies — eliminates up to 2×N fillRect calls at wave start
- [x] Remove arc static-hit particles — particles only spawn on enemy death

## Phase D — Complexity 4–5 ✅ Done (C4), ⏸ Deferred (C5)

- [x] C4-17 Web Worker for path/rift generation — `path_worker.js` batch protocol; main thread handles side-effects
- [x] C4-18 Deferred save — `requestIdleCallback` defers JSON.stringify + localStorage.setItem off render frame
- [⏸] C5-19 OffscreenCanvas pipeline — deferred: ~50–100 KB/frame serialization too costly without ECS
- [⏸] C5-20 ECS/typed-array architecture — deferred: complete rewrite; pools already handle GC at current scale

---

## Validation Targets

- Median frame-time <= `16.7ms` at target wave density
- 99th percentile frame-time improved by >= `30%` from pre-optimization baseline
- Gameplay parity preserved (no simulation drift from render culling/throttling)

---

## EXTRA CONCERNS

### After-shoot frame spikes — all root causes addressed ✅

| # | Location | Issue | Fix Applied |
|---|---|---|---|
| 1 | `06_render.js` | `createRadialGradient()` per light per frame | ✅ Gradient cache (`getLightGradientTexture`) |
| 2 | `05_loop.js` | Arc bounce O(n) scan per bounce per tower | ✅ Spatial grid (`queryEnemiesInRadius`) |
| 3 | `05_loop.js` | Tower targeting O(towers × enemies) | ✅ Spatial grid (`queryTauntersInRadius` / `queryEnemiesInRadius`) |
| 4 | `05_loop.js` | Arc network rebuild O(n²) when dirty | ⬜ Still O(n²) — low frequency, tolerable |
| 5 | `05_loop.js` | Pool exhaustion → GC on kill bursts | ✅ Pool pre-warmed at init |
| 6 | `06_render.js` | `globalCompositeOperation: 'screen'` everywhere | ✅ Removed from all hot paths |
| 7 | `06_render.js` | Per-enemy shadow + draw in single loop | ✅ Multi-pass batching by color bucket |
| 8 | `06_render.js` | Arc hit particles on every static charge | ✅ Removed; particles only on death |
