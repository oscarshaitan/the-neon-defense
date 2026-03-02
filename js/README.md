# The Neon Defense

The Neon Defense is a fast, neon-styled HTML5 tower defense game built with Canvas and vanilla JavaScript.
You defend the core against escalating waves, expanding Rift networks, elite path mutations, and high-pressure late game scenarios.

## Current Status

- Single-player endless defense
- Desktop and mobile touch support
- Camera pan and zoom (0.1× min to 1.0× max)
- Auto-save with manual force-save option
- Interactive onboarding tutorial
- Inline gameplay hints
- Dynamic quality governor (HIGH/MED/LOW stepper with auto-drop toast)

## Core Features

### Combat Loop
- Four tower classes: Basic, Rapid, Sniper, Arc
- Tower upgrades and sell flow
- Base upgrades and life repair
- Enemy variety including Boss, Splitter, Bulwark, and Shifter behaviors

### Balance Direction (Planned)
- Next tower target: **Disruptor** (utility support, Expose + stealth reveal)
- Frost mechanics are planned as a **Tech Tree Control branch** unlock path
- Mortar and Prism are currently deferred pending telemetry after Tech Tree v1

### Rift and Wave Systems
- Multi-path Rift spawning
- Rift tier progression after high waves
- Mutation profiles that temporarily alter enemy stats/rewards
- Wave Intelligence panel for threat visibility

### Commander Tools
- Active abilities: EMP and Overclock
- Energy economy tied to kills
- Pause menu controls for save/audio/debug

### Presentation
- Neon UI with animated effects
- Dynamic VFX (particles, flashes, pulses)
- Procedural Web Audio soundtrack
- Dynamic quality governor with +/- stepper (HIGH/MED/LOW) and auto-drop toast

## Controls

### Desktop
- Left click: select/interact/place
- Drag: pan camera
- Mouse wheel: zoom
- `Q` / `W` / `E` / `R`: select tower type
- `1` / `2`: ability targeting
- `U`: upgrade selected tower
- `Delete` / `Backspace`: sell selected tower
- `Esc`: deselect or pause
- `GAME DETAILS −/+`: cycle quality preset (HIGH/MED/LOW)

### Touch
- Tap: select/interact
- Drag: pan camera
- Pinch: zoom

## Run Locally

1. Open `index.html` directly, or serve the folder:

```bash
python -m http.server 8000
```

2. Open `http://localhost:8000`.

## Project Structure

```text
the-neon-defense/
  index.html
  scripts/
    00_core.js          — constants, tower/arc/quality/pathing config
    01_init.js          — canvas setup, input, camera, hardpoints, path helpers
    02_game_control.js  — placement, selection, build UI
    03_abilities.js     — EMP/Overclock, save/load, path worker management
    04_tutorial.js      — tutorial flow, generateNewPath(), findPathOnGrid()
    05_loop.js          — main game loop, spatial grid, wave/enemy logic
    06_render.js        — all rendering (enemies, towers, VFX, UI), resetCamera()
    workers/
      path_worker.js    — Web Worker: async rift/path generation (off main thread)
  styles/
    00_base_ui.css
    01_abilities_debug.css
    02_tutorial_and_responsive.css
  manual.html
  technical_docs.html
  ROADMAP.md
  GAME_BALANCE_ANALYSIS.md
  Improvements.md
```

## Documentation

- Player Manual: `manual.html`
- Technical Docs: `technical_docs.html`
- Product and feature planning: `ROADMAP.md`
- Design and balance critique: `GAME_BALANCE_ANALYSIS.md`

## Technology

- HTML5 Canvas
- Vanilla JavaScript (ES6+)
- CSS3
- Web Audio API
- Web Workers (async rift path generation)
- Local Storage

## Notes

- This project is framework-free by design.
- Gameplay logic is split across `scripts/*.js`.
- Visual identity and layout behavior are split across `styles/*.css`.
