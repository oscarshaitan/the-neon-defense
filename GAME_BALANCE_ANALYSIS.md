# The Neon Defense: Mechanics and Balance Analysis

This document reviews likely gameplay risks and proposes design-level solutions.
It is intentionally focused on design suggestions, not code changes.

## Scope

- Core game idea and loop risks
- Mechanical risks by game phase
- Difficulty curve review (early, mid, late)
- New tower mechanics and modifier ideas
- Tech Tree strategy layer proposal

---

## 0. Observed Imbalances (current numbers)

Grounded in the live constants (`js/scripts/00_core.js`), mirrored 1:1 in the
Flutter and Godot editions. These are concrete, measurable issues — not just
risks.

### Tower value table

| Tower | Cost | Dmg | Cooldown | DPS¹ | DPS / credit | Range | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| Basic | 50 | 10 | 30f (0.5s) | 20.0 | **0.40** | 100 | best raw efficiency |
| Rapid | 120 | 4 | 10f (0.17s) | 24.0 | 0.20 | 80 | — |
| Sniper | 200 | 50 | 90f (1.5s) | 33.3 | 0.17 | 250 | boss killer; poor vs swarms |
| Arc | 180 | 8 | 34f (0.57s) | 14.1² | 0.08² | 100 | AoE chain + stun; scales ×1–5 with network |

¹ single-target DPS at level 1. ² Arc also hits up to 3 bounce targets at 0.7×
and applies static charge (stun at threshold); its network bonus (component
size, capped 5) multiplies static charge — so its *effective* AoE/control value
is far above the single-target number.

**Problem 1 — Rapid is dominated by Basic.** Rapid costs 2.4× a Basic for half
the DPS/credit (0.20 vs 0.40) *and* shorter range (80 vs 100). Its only edge is
+4 raw single-target DPS in one footprint — a weak niche that rarely justifies
the price. Two Basics (100 credits) out-DPS one Rapid (120) with more coverage.
There is currently **no scenario where Rapid is the correct pick**.

**Problem 2 — linear enemy HP vs multiplicative tower scaling.** Enemy HP grows
*linearly*: `hp = base × (1 + wave × 0.4)` (basic = 330 HP at wave 25), then
×`(1 + 0.5·(tier−1))` per rift tier and ×mutation (TITAN = ×3). Tower output
grows *multiplicatively* via upgrades (×1.2 dmg/level). The curves cross: early
on, fresh towers fall behind (you *must* upgrade or leak); late, a well-upgraded
field snowballs past the linear threat. The result is a curve that feels either
punishing or trivial, rarely tuned — exactly the "economy/scaling volatility"
risk in §2–3, now quantified.

**Problem 3 — range stops being a lever.** The 800 cap is reached by a Sniper in
~12–13 upgrades (`250 × 1.1ⁿ`), after which range is a non-choice and only
damage matters.

**Problem 4 — Arc network is now a live dominance candidate.** With the
inter-tower network implemented across all editions, a cardinally aligned line
of Arc towers reaches the ×5 bonus, turning Arc into a high-value AoE+stun
anchor. Worth watching against the "single-combo domination" guardrail — the
STRESS TEST builds exactly this configuration for inspection.

### What's needed to improve balance

1. **Give Rapid a real identity** (highest priority — it's a dominated pick, not
   a design trade-off). Options: a small splash radius (anti-swarm), an
   anti-fast bonus, a much lower cost, or a far higher fire rate. Any one makes
   the 4-tower roster a real choice.
2. **Reconcile the HP/damage curves.** Either bend enemy HP super-linear past a
   threshold *and* soften tower upgrade growth (additive past N levels), so
   neither side runs away. Tune against measured clear-rates, not by feel.
3. **Add anti-stack guardrails** (diminishing returns for repeated same-type
   towers; Arc-network bonus softening) so Basic-spam and Arc-line-spam aren't
   strictly optimal — see §2 "soft anti-stack balancing."
4. **Scale a survival/utility lever with path count**, not just enemy HP, to fix
   the late-game geometric losses (Roadmap Milestone C).
5. **Instrument before tuning.** None of the above can be set confidently
   without loss-wave / loss-reason / tower-usage telemetry. The STRESS TEST and
   headless smoke test are the seed for a deterministic balance sim (Roadmap G).
6. **Smooth reward spikes** from mutated elites (NEON = ×3 reward) per §3A.

---

## 1. Core Idea Risk Review

### Strong Points
- Distinct visual identity and readable neon language
- Good tactical variety from Rift tiers, mutations, and enemy archetypes
- Fast action loop with meaningful micro decisions (targeting, ability timing, placement)

### Potential Weak Points
- High complexity growth can outpace player readability after many paths spawn
- If spatial constraints become too strict, losses feel predetermined
- Strategy expression can collapse into one or two dominant late-game patterns

### Design Goal

Late-game losses should come from tactical or economic mistakes, not map geometry lockout.

---

## 2. Difficulty Curve Analysis

## Early Game (Waves 1-15)

### Risks
- Slow onboarding creates downtime before meaningful choices
- Low enemy pressure can hide weak build habits
- New players may not understand value of path intel and ability timing

### Suggestions
- Add one guaranteed "teaching wave" for each major enemy behavior
- Slightly shorten first prep timers after first successful placements
- Add one visible objective prompt: "Scan one Rift before wave 5"

## Mid Game (Waves 16-50)

### Risks
- Build variety can narrow if one tower route dominates value-per-credit
- Mutation spikes may feel random if threat telegraphing is weak
- Players may overinvest in local fixes and miss scaling needs

### Suggestions
- Expand Wave Intelligence with explicit counter-hint tags
- Add soft anti-stack balancing (diminishing returns for repeated same-type towers)
- Add side-objective rewards for varied composition

## Late Game (50+)

### Risks
- Path proliferation compresses buildable space near core
- Visual and decision overload during multi-path synchronized pressure
- Extreme stat scaling can invalidate tactical play windows

### Suggestions
- Introduce survival tools that scale with path count, not only enemy HP
- Keep reaction windows by capping simultaneous high-impact effects per interval

---

## 3. Potential Flaws in Current Mechanics and Fix Directions

## A. Economy Volatility

### Risk
- Reward spikes from mutated elites can create runaway power.

### Suggestion
- Add reward smoothing bands:
  - cap short-interval reward variance
  - convert excess spike rewards into delayed payout buffer

## B. Tower Role Compression

### Risk
- One or two towers may outperform all others in late scenarios.

### Suggestion
- Add role-specific scaling vectors:
  - anti-swarm, anti-armor, anti-speed, utility-control
- Add enemy defenses that specifically test each vector

## C. Ability Timing Dominance

### Risk
- If abilities become mandatory at strict intervals, skill expression narrows.

### Suggestion
- Add alternate counterplay windows:
  - positioning routes
  - pre-wave planning effects
  - passive node choices in tech tree

---

## 4. New Tower Direction (Locked for Next Iteration)

This section reflects the current product direction.

### Direction Decisions

- Next tower to add: **Disruptor Tower** (utility support).
- **Siege Mortar** and **Prism Tower** are deferred.
- **Frost is no longer planned as a standalone tower** in this phase.
- Frost mechanics move into the Tech Tree as a Control branch unlock path.

### Disruptor Tower (Next Addition)

Role: utility amplifier that increases team damage reliability without replacing Arc.

Design intent:
- Applies `Expose` debuff: enemies take bonus damage from all towers.
- Provides brief stealth reveal pulse on hit (small radius around target).
- Low personal DPS, high strategic value in mixed compositions.

Balance goals:
- Should improve mixed builds, not mono-tower spam.
- Must not outperform Arc/Sniper as direct boss killer.
- Must have visible payoff in Wave Intelligence and selection panel stats.

### Frost as Tech Package (Not a Tower)

Frost becomes a branch-defined utility suite that upgrades existing systems.

Control branch Frost package:
1. `Cryo Conductors`: Arc hits apply Chill stacks.
2. `Cryo EMP`: EMP leaves a short chill field after detonation.
3. `Thermal Weakness`: chilled targets take bonus incoming damage.
4. `Icebreak`: bonus hit damage against frozen targets.
5. `Deep Freeze Protocol` (capstone): Chill threshold triggers short freeze.

Guardrails for freeze gameplay:
- Bosses receive reduced freeze duration.
- Freeze immunity window after each freeze proc.
- Chill decays when not refreshed.
- Optional proc-rate cap in extreme density scenarios.

---

## 5. Tech Tree v1 Definition

Goal: let players express run identity through planned progression choices.

### Branches (v1)

1. Offense
- Projectile damage shaping
- Penetration / execution style effects

2. Control
- Debuff amplification
- Frost package (defined above)

3. Economy
- Credit smoothing
- Upgrade/sell economy efficiency

4. Core Systems
- Core durability
- Emergency defensive tools

### Suggested Node Budget

- v1 target: **12-16 nodes total**
- 3 tiers per branch
- 1 capstone per branch
- mutual exclusions on high-impact nodes

### Unlock Flow

- Research Points earned from:
  - wave milestones
  - challenge objectives
  - no-leak bonuses
- Spend points:
  - pre-run loadout configuration
  - limited in-run checkpoints

### Anti-Dominance Rules

- Effect-family stacking caps
- Diminishing returns for repeated archetype picks
- Cross-branch prerequisites for top-tier nodes

---

## 6. Practical Balancing Roadmap (Recommended)

1. Ship Tech Tree framework (research currency, graph, UI shell).
2. Ship Control branch Frost package as first complete branch lane.
3. Add Disruptor Tower with synergy telemetry hooks.
4. Gather telemetry:
- average loss wave
- loss reason tags
- tower usage distribution
- tech path pick rates
5. Re-evaluate deferred towers (Mortar/Prism) only after telemetry review.

---

## 7. Final Design Principle

If the game gets harder while giving fewer meaningful options, frustration rises.
If the game gets harder while giving deeper strategic tools, mastery rises.

The Neon Defense should target the second path.
