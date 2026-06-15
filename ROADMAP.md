# The Neon Defense — Roadmap

This roadmap tracks practical priorities for gameplay quality, balance stability, and long-term replayability.

## Guiding Priorities

1. Keep the game readable under pressure.
2. Preserve tactical freedom as waves and paths scale.
3. Expand strategic depth without increasing UI friction.
4. Prioritize systems that improve replay value over one-off content.

---

## Current State (2026-06)

The game ships as three editions (JS reference, Flutter, Godot) at behavioral
parity. Foundational UX and tooling are largely in place; the open frontier is
**strategic depth and late-game solvability**, not feature parity.

- ✅ Shipped: tutorial + hints, Wave Intelligence, quality governor, the Arc
  tower + inter-tower network, a developer **command center** (credits, spawn,
  rifts, wave jumps, bulk upgrade, no-build overlay) and a one-tap **STRESS
  TEST** level — a first step toward Milestone G's balance-testing tooling.
- ⏳ Not yet started: the Tech Tree (E), the Disruptor tower + modifiers (D2/D3),
  late-game core-area solvability (C), and a between-runs progression/meta loop.

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

- [~] Deterministic simulation mode for balance testing — partial: the command-center **STRESS TEST** builds a fixed worst-case scenario, and the Godot headless smoke test exercises a full wave. Still missing: seeded determinism + an automated multi-wave sim.
- [ ] Add debug replay snapshots for difficult-wave diagnosis
- [ ] Add metric logger for wave clear rates by segment (loss-wave, loss-reason, tower-usage distribution)
- [ ] Add lightweight balancing checklist before each release

---

## What's Really Missing — Priority View

An opinionated read on the highest-leverage gaps, in order. The editions are at
parity and the moment-to-moment loop is solid; what's missing is **reasons to
keep playing and reasons to build differently**.

1. **A reason to play again (meta/progression).** The biggest gap. Today every
   run starts identical and nothing carries over — it's one endless score
   attack. The Tech Tree (Milestone E) with a between-runs research currency and
   a pre-run loadout is the single highest-leverage addition for retention. Even
   a thin v1 (one branch + research points) changes "play once" into "plan a build."

2. **Late-game core-area solvability (Milestone C).** The most likely *unfair*
   loss today is geometric: as rift count rises, buildable tiles near the core
   vanish and the loss becomes a lockout, not a decision. The **Core Exclusion
   Ring** (reserve a minimum buildable ring) is the most concrete fix and should
   come before more content. The new STRESS TEST makes this easy to reproduce.

3. **A real fourth role / fix tower-role compression (Milestone D).** Only four
   towers, and one of them (Rapid) is effectively dominated (see the balance
   analysis). The Disruptor (utility/Expose) adds the missing "support" axis;
   equally important is giving Rapid a genuine niche so all four are picked.

4. **Telemetry + a deterministic sim (Milestone G).** Nothing here can be tuned
   confidently without data: loss-wave, loss-reason, and tower-usage
   distribution. This is cheap to add (the STRESS TEST and headless smoke test
   are the seed) and unblocks every balance decision below.

5. **Difficulty/accessibility options.** A single fixed curve excludes both
   newer and expert players — an assist ruleset and/or challenge presets
   (Milestone F) widen the audience for little cost.

Lower priority until the above land: modifier chips, synergy tags, seasonal
modifiers, and the deferred Mortar/Prism towers — all add surface area before
the core depth and fairness problems are solved.

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

Last updated: 2026-06-15
