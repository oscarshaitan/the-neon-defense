# The Neon Defense — Roadmap

This roadmap tracks practical priorities for gameplay quality, balance stability, and long-term replayability.

## Guiding Priorities

1. Keep the game readable under pressure.
2. Preserve tactical freedom as waves and paths scale.
3. Expand strategic depth without increasing UI friction.
4. Prioritize systems that improve replay value over one-off content.

---

## Milestone A: Stability and UX Foundation

### A1. Input and Interaction Quality
- [x] Tap-vs-drag separation to prevent accidental selection while panning
- [x] Selection dismissal parity (tap same cell, `Esc`, ability selection)
- [ ] Add optional interaction sensitivity sliders (tap/drag thresholds)

### A2. Onboarding and Hinting
- [x] First-run tutorial flow
- [x] Inline hints for camera/rift/ability/tower intel
- [ ] Add optional "Hints: On/Off" toggle in pause menu
- [ ] Add "Replay onboarding" from settings without full reset

### A3. Save/Profile Reliability
- [x] One-time name capture with local persistence
- [x] Tutorial and hint state persistence
- [ ] Profile panel: highest wave, average run length, total kills by class

---

## Milestone B: Balance and Difficulty Curve

### B1. Early Game (Waves 1-15)
- [ ] Reduce dead-time in early prep by adaptive countdown scaling
- [ ] Improve tutorial-to-live transition pacing
- [ ] Add one low-risk economic decision in first 10 waves

### B2. Mid Game (Waves 16-50)
- [ ] Introduce composition checks that force mixed tower investment
- [ ] Increase telegraphing for priority enemies and mutations
- [ ] Add clearer threat tags in Wave Intelligence panel

### B3. Late Game (50+)
- [ ] Solve core-adjacent tile starvation when path count rises
- [ ] Add anti-snowball safeguards for path density and overlap pressure
- [ ] Add optional "Late Game Assist Ruleset" preset for accessibility

---

## Milestone C: Pathing and Core-Area Design

Focus: keep late game solvable while preserving tension.

### Candidate Solutions to Prototype
- [ ] Core Exclusion Ring: reserve minimum buildable ring around core
- [ ] Soft Path Repulsion near core: raise path cost in protected cells
- [ ] Dynamic reroute budget: only allow N high-proximity paths near center
- [ ] Core Hardpoint Nodes: fixed build anchors that never become blocked
- [ ] Emergency Core Modules unlocked at wave thresholds

### Validation Criteria
- [ ] At least 3 viable build tiles remain near core at late-game target wave
- [ ] No single mutation/profile makes all core-adjacent decisions invalid
- [ ] Late wave loss reason is tactical, not geometric lockout

---

## Milestone D: Tower and Buildcraft Expansion

### D1. New Tower Concepts
- [x] Arc Tower: chain lightning with diminishing jumps
- [ ] Disruptor Tower: utility support that applies Expose and brief stealth reveal
- [ ] Re-evaluate Siege Mortar after Tech Tree telemetry (deferred)
- [ ] Re-evaluate Prism Tower after Tech Tree telemetry (deferred)

### D2. Modifier System
- [ ] Prefix/suffix tower mods (example: Focused, Volatile, Stable)
- [ ] Socket-style mod chips earned from milestone waves
- [ ] Tradeoff balancing (power gain vs cost/cooldown/coverage)

### D3. Synergy Rules
- [ ] Cross-tower combo tags (example: Shock + Wet, Mark + Crit)
- [ ] Diminishing returns guardrails to prevent single-combo domination

---

## Milestone E: Tech Tree Strategy Layer

Goal: custom strategy progression that changes decision-making each run.

### E1. Tech Tree Foundations
- [ ] Add Research Currency (earned via wave milestones/objectives)
- [ ] Add Branches: Offense, Control, Economy, Core Systems
- [ ] Add prereq graph and unlock dependencies

### E2. Build Identity
- [ ] Pre-run loadout page for selected branch route
- [ ] In-run tactical unlock choices at milestone waves
- [ ] Respec tokens with limits to avoid build trivialization

### E3. Balance Guardrails
- [ ] Node power budget caps by tier
- [ ] Mutual-exclusion nodes for strong archetype divergence
- [ ] Telemetry for dominant node paths and abandonment rates

### E4. Frost Control Package (First Branch Lane)
- [ ] Cryo Conductors: Arc attacks apply Chill stacks
- [ ] Cryo EMP: EMP leaves short chill field
- [ ] Thermal Weakness: chilled targets take extra incoming damage
- [ ] Icebreak: bonus hit damage against frozen targets
- [ ] Deep Freeze Protocol capstone with freeze-immunity guardrail

---

## Milestone F: Content and Replayability

- [ ] New enemy archetypes tied to specific counterplay skills
- [ ] Variant Rift events with explicit risk-reward decisions
- [ ] Challenge presets (Time Pressure, Sparse Build, Elite Storm)
- [ ] Seasonal objective modifiers

---

## Milestone G: Production and Tooling

- [ ] Add deterministic simulation mode for balance testing
- [ ] Add debug replay snapshots for difficult-wave diagnosis
- [ ] Add metric logger for wave clear rates by segment
- [ ] Add lightweight balancing checklist before each release

---

## Release Order (Recommended)

1. Milestone B + C (difficulty and late-path solvability)
2. Milestone E (tech tree strategy layer, Frost Control package first)
3. Milestone D (Disruptor tower and modifiers)
4. Milestone F (content replay loops)
5. Milestone G (tooling hardening in parallel)

---

## Success Metrics

- Late-game fairness: average "unavoidable geometry loss" reports trend to near zero
- Build diversity: no single tower composition exceeds 45% high-wave usage
- Engagement: increased run completion into mid game and late game
- Tech tree adoption: players maintain multiple distinct strategy paths

---

Last updated: 2026-02-12
