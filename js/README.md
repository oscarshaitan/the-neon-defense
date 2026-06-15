# The Neon Defense — JavaScript Edition

The original, fully shipped version of the game. Built with vanilla JS, HTML5 Canvas, and Web Audio.

**[Play live on GitHub Pages](https://oscarshaitan.github.io/the-neon-defense/)**

---

## Status: Complete

All core gameplay systems are implemented and live.

---

## What's In

### Game World
- Infinite canvas grid with camera pan and zoom (0.1× – 1.0×)
- Core crystal — green diamond at world center
- Hardpoint ring system — core ring (6 slots, damage/range bonus) and two micro rings (10 + 14 slots)
- Rift paths generated off-thread via Web Worker (A* with zone-0 commitment, orbital biasing, anti-overlap)

### Towers
- **Basic** — all-round square tower
- **Rapid** — fast-firing circle
- **Sniper** — long-range diamond
- **Arc** — electric relay hexagon; forms network links with adjacent Arc towers, accumulates static charge that stuns enemies

### Enemies
- **Basic** — standard
- **Fast** — high speed, low HP
- **Tank** — slow, high HP
- **Boss** — large, orange hexagon
- **Splitter** — splits into Minis on death
- **Mini** — spawned by Splitter
- **Bulwark** — high armor octagon
- **Shifter** — intermittently invisible
- **Healer** — restores HP to nearby enemies
- **Mutant** — white diamond, inherits mutation bonuses

### Wave & Rift System
- 30-second prep phase between waves, skippable
- Enemy scaling: `hp = type.hp × (1 + wave × 0.4)` × rift tier × mutation multipliers
- Rift count increases every 10 waves (up to wave 50), then every 5
- Mutation events on certain waves: stat bonuses + color change + reward boost
- Wave Intelligence panel — shows threat level, mutations, enemy distribution preview

### Abilities
- **EMP Burst** — freezes all enemies within radius 120 for 5 seconds (energy cost: 40)
- **Overclock** — doubles fire rate of one tower for 10 seconds (energy cost: 25)
- Energy is earned +1 per kill, capped at 100 (no passive regeneration)

### Developer Command Center
- SHA-256-gated debug panel in the pause overlay: +1M credits, spawn any enemy, create/level/rebuild rifts, +1/+5/+10 wave jumps, no-build overlay toggle
- `+5/+10/+25 LVL` bulk tower upgrade (range stays clamped to the 800 cap)
- **STRESS TEST** — synthetic worst-case level for perf evaluation (maxed base + 1000 lives, ~20 rifts, a dense ring of every tower type around the core incl. a connected arc cluster, 100 mixed enemies)
- Live FPS readout in the stats bar

### VFX & Presentation
- Particle system with object pooling, alpha-quantized color batching
- Arc lightning — jittered segments, branching forks, 5 intensity levels
- Light source system — cached gradient textures, per-frame fade
- Screen shake on high-impact events
- Procedural Web Audio soundtrack + SFX

### Quality Governor
- HIGH / BALANCED / LOW profiles (particle cap, lightning intensity, light count)
- Manual `−/+` stepper in stats bar
- Auto-downgrade on EMA frame time above 22ms, auto-upgrade below 15.8ms
- Toast notification on auto-adjust

### Save / Load
- Auto-save every wave to Local Storage
- Force-save button in pause menu
- Saves: towers, paths, enemies, wave, money, lives, energy, base level

### Accessibility & Controls
- Desktop: mouse click/drag/scroll, keyboard shortcuts (Q/W/E/R, 1/2, U, Del, Esc)
- Mobile: touch tap, drag pan, pinch zoom, on-screen tower bar and ability slots
- Full responsive layout with safe-area support

---

## Run Locally

```bash
# From the repo root:
python -m http.server 8000
# Open http://localhost:8000/js/
```

Or double-click `index.html` (works without a server for most features; Web Workers require a server).

---

## File Map

```
js/
  index.html                    — Game shell, UI layer, all overlays
  scripts/
    00_core.js                  — Constants (GRID_SIZE, tower/enemy/arc configs)
    01_init.js                  — Canvas setup, camera, input, hardpoints
    02_game_control.js          — Tower placement, selection, upgrade, sell, base
    03_abilities.js             — EMP/Overclock, save/load, Web Worker management
    04_tutorial.js              — Onboarding tutorial flow + path generation entry
    05_loop.js                  — Main game loop, wave spawning, enemy AI, spatial grid
    06_render.js                — All canvas rendering (grid, paths, entities, VFX, UI)
    workers/
      path_worker.js            — Web Worker: A* rift generation off main thread
  styles/
    00_base_ui.css              — Stats bar, tower bar, selection panel, screens
    01_abilities_debug.css      — Abilities bar, energy bar, debug overlay
    02_tutorial_and_responsive.css — Tutorial steps, mobile breakpoints
  manual.html                   — In-game player manual
  technical_docs.html           — Architecture and system reference
```

---

## Technology

- HTML5 Canvas API
- Vanilla JavaScript (ES6+, no build step, no dependencies)
- CSS3 with custom properties
- Web Audio API — procedural soundtrack and SFX
- Web Workers — async rift path generation off main thread
- Local Storage — save/load snapshots

---

## Planned (Roadmap)

- **Disruptor tower** — utility support, Expose + stealth reveal
- **Tech Tree** — unlockable upgrade paths (Frost branch, Control branch)
- Mortar and Prism towers — deferred pending telemetry after Tech Tree v1
