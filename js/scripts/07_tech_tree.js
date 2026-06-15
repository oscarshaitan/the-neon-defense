/**
 * The Neon Defense - Tech Tree (Milestone E)
 *
 * Strategy/progression layer ported from the Godot edition (scripts/tech_tree.gd,
 * the reference/spec). Research Points (RP) and unlocked nodes are PERSISTENT
 * across runs (localStorage key `neonDefenseTech`, SEPARATE from the per-run
 * `neonDefenseSave`). Node effects accumulate into `TECH.fx` and are read live by
 * gameplay; start-of-run bonuses (credits/lives/energy) apply when a fresh run
 * begins (see resetGameLogic / _applyTechRunBonuses).
 */

const TECH = {
    SAVE_KEY: 'neonDefenseTech',

    // Control-branch frost tuning.
    CHILL_FRAMES: 120,   // Cryo Conductors chill duration (2s @ 60Hz)
    CHILL_SLOW: 0.5,     // chilled enemies move at 50% speed
    // Offense capstone execution.
    EXECUTE_THRESHOLD: 0.15,
    EXECUTE_BONUS: 2.0,
    // Core capstone restore.
    LAST_STAND_LIVES: 5,

    BRANCHES: ['OFFENSE', 'CONTROL', 'ECONOMY', 'CORE'],

    // Node graph. tier 1-3 are the lane, tier 4 is the capstone. `prereq` is the
    // node id that must be unlocked first ('' = always available). `fx` lists the
    // effect contributions accumulated into `fx` (see _apply).
    NODES: [
        // --- OFFENSE ---
        { id: 'off_1', branch: 'OFFENSE', tier: 1, cost: 2, prereq: '',
            name: 'FOCUSED OPTICS', desc: '+8% tower damage', fx: { dmg_mult: 1.08 } },
        { id: 'off_2', branch: 'OFFENSE', tier: 2, cost: 3, prereq: 'off_1',
            name: 'OVERCHARGED ROUNDS', desc: '+12% tower damage', fx: { dmg_mult: 1.12 } },
        { id: 'off_3', branch: 'OFFENSE', tier: 3, cost: 4, prereq: 'off_2',
            name: 'EXTENDED BARRELS', desc: '+12% tower range', fx: { range_mult: 1.12 } },
        { id: 'off_4', branch: 'OFFENSE', tier: 4, cost: 6, prereq: 'off_3',
            name: 'EXECUTIONER', desc: 'Enemies below 15% HP take double damage',
            fx: { execute: true } },
        // --- CONTROL (frost package) ---
        { id: 'con_1', branch: 'CONTROL', tier: 1, cost: 2, prereq: '',
            name: 'CRYO CONDUCTORS', desc: 'Arc attacks chill enemies (slow)',
            fx: { arc_chill: true } },
        { id: 'con_2', branch: 'CONTROL', tier: 2, cost: 3, prereq: 'con_1',
            name: 'CRYO EMP', desc: 'EMP freeze lasts 50% longer', fx: { emp_freeze_mult: 1.5 } },
        { id: 'con_3', branch: 'CONTROL', tier: 3, cost: 4, prereq: 'con_2',
            name: 'THERMAL WEAKNESS', desc: 'Chilled/frozen enemies take +25% damage',
            fx: { thermal_mult: 1.25 } },
        { id: 'con_4', branch: 'CONTROL', tier: 4, cost: 6, prereq: 'con_3',
            name: 'DEEP FREEZE PROTOCOL', desc: 'EMP blast radius +50%',
            fx: { emp_radius_mult: 1.5 } },
        // --- ECONOMY ---
        { id: 'eco_1', branch: 'ECONOMY', tier: 1, cost: 2, prereq: '',
            name: 'SALVAGE ROUTINES', desc: '+15% credits from kills', fx: { reward_mult: 1.15 } },
        { id: 'eco_2', branch: 'ECONOMY', tier: 2, cost: 3, prereq: 'eco_1',
            name: 'BULK DISCOUNT', desc: 'Tower upgrades cost 20% less',
            fx: { upgrade_cost_mult: 0.8 } },
        { id: 'eco_3', branch: 'ECONOMY', tier: 3, cost: 4, prereq: 'eco_2',
            name: 'WAR CHEST', desc: 'Start each run with +150 credits', fx: { start_money: 150 } },
        { id: 'eco_4', branch: 'ECONOMY', tier: 4, cost: 6, prereq: 'eco_3',
            name: 'LIQUIDATION', desc: 'Selling towers refunds 100%', fx: { sell_refund: 1.0 } },
        // --- CORE SYSTEMS ---
        { id: 'core_1', branch: 'CORE', tier: 1, cost: 2, prereq: '',
            name: 'REINFORCED PLATING', desc: 'Start each run with +5 lives', fx: { start_lives: 5 } },
        { id: 'core_2', branch: 'CORE', tier: 2, cost: 3, prereq: 'core_1',
            name: 'FIELD REPAIRS', desc: 'Base repairs cost 30% less', fx: { repair_cost_mult: 0.7 } },
        { id: 'core_3', branch: 'CORE', tier: 3, cost: 4, prereq: 'core_2',
            name: 'EMERGENCY CAPACITORS', desc: 'Start each run with +30 energy',
            fx: { start_energy: 30 } },
        { id: 'core_4', branch: 'CORE', tier: 4, cost: 6, prereq: 'core_3',
            name: 'LAST STAND PROTOCOL',
            desc: 'Once per run, survive a fatal breach (restore 5 lives)', fx: { last_stand: true } }
    ],

    rp: 0,
    unlocked: {},   // id -> true
    fx: {},         // accumulated live effects (see _defaultFx)

    // ---------------------------------------------------------------------
    // Effect accumulation
    // ---------------------------------------------------------------------

    _defaultFx() {
        return {
            dmg_mult: 1, range_mult: 1, reward_mult: 1, upgrade_cost_mult: 1,
            repair_cost_mult: 1, emp_freeze_mult: 1, emp_radius_mult: 1,
            thermal_mult: 1, sell_refund: 0.7,
            start_money: 0, start_lives: 0, start_energy: 0,
            arc_chill: false, execute: false, last_stand: false
        };
    },

    _apply(f, key, value) {
        if (typeof value === 'boolean') {
            f[key] = f[key] || value;
        } else if (key === 'sell_refund') {
            f[key] = Math.max(f[key], value); // best refund wins
        } else if (key.startsWith('start_')) {
            f[key] = f[key] + value;
        } else { // multiplicative (*_mult)
            f[key] = f[key] * value;
        }
    },

    recompute() {
        const f = this._defaultFx();
        for (const node of this.NODES) {
            if (this.unlocked[node.id]) {
                for (const key in node.fx) {
                    this._apply(f, key, node.fx[key]);
                }
            }
        }
        this.fx = f;
    },

    // ---------------------------------------------------------------------
    // Node queries / unlocking
    // ---------------------------------------------------------------------

    nodeById(id) {
        for (const node of this.NODES) {
            if (node.id === id) return node;
        }
        return null;
    },

    isUnlocked(id) {
        return !!this.unlocked[id];
    },

    prereqMet(node) {
        return node.prereq === '' || !!this.unlocked[node.prereq];
    },

    canUnlock(node) {
        return !this.isUnlocked(node.id) && this.prereqMet(node) && this.rp >= node.cost;
    },

    unlock(id) {
        const node = this.nodeById(id);
        if (!node || !this.canUnlock(node)) return false;
        this.rp -= node.cost;
        this.unlocked[id] = true;
        this.recompute();
        this.save();
        return true;
    },

    nodesInBranch(branch) {
        return this.NODES.filter(n => n.branch === branch);
    },

    // ---------------------------------------------------------------------
    // Research Points
    // ---------------------------------------------------------------------

    // Awarded when a wave is cleared; scales gently with depth.
    awardWave(clearedWave) {
        const gain = 1 + Math.floor(clearedWave / 10);
        this.rp += gain;
        this.save();
        return gain;
    },

    grantRp(amount) {
        this.rp += amount;
        this.save();
    },

    // Debug/respec: wipe all progression.
    resetProgress() {
        this.rp = 0;
        this.unlocked = {};
        this.recompute();
        this.save();
    },

    // ---------------------------------------------------------------------
    // Persistence (separate from the per-run save so it carries across runs)
    // ---------------------------------------------------------------------

    save() {
        try {
            localStorage.setItem(this.SAVE_KEY, JSON.stringify({
                rp: this.rp,
                unlocked: Object.keys(this.unlocked)
            }));
        } catch (_) { /* storage unavailable */ }
    },

    load() {
        let raw = null;
        try {
            raw = localStorage.getItem(this.SAVE_KEY);
        } catch (_) {
            return;
        }
        if (!raw) return;
        let data;
        try {
            data = JSON.parse(raw);
        } catch (_) {
            return;
        }
        if (!data || typeof data !== 'object') return;
        this.rp = Math.floor(Number(data.rp) || 0);
        this.unlocked = {};
        const list = Array.isArray(data.unlocked) ? data.unlocked : [];
        for (const id of list) {
            if (this.nodeById(String(id))) this.unlocked[String(id)] = true;
        }
    }
};

// Apply Tech Tree start-of-run bonuses (credits/lives/energy) to the fresh
// default state of a new run. Analogous to Godot main.gd _apply_tech_run_bonuses.
function _applyTechRunBonuses() {
    money += TECH.fx.start_money;
    lives += TECH.fx.start_lives;
    energy += TECH.fx.start_energy;
}

// Load + recompute on script load.
TECH.load();
TECH.recompute();

window.TECH = TECH;

// ---------------------------------------------------------------------------
// Tech Tree UI overlay
// ---------------------------------------------------------------------------

function _techBranchColor(branch) {
    switch (branch) {
        case 'OFFENSE': return '#ff00ac';
        case 'CONTROL': return '#00f3ff';
        case 'ECONOMY': return '#fcee0a';
        case 'CORE': return '#00ff41';
        default: return '#00f3ff';
    }
}

function _renderTechNodeCard(node) {
    const unlocked = TECH.isUnlocked(node.id);
    const prereqOk = TECH.prereqMet(node);
    const affordable = TECH.rp >= node.cost;

    let stateClass = 'locked';
    if (unlocked) stateClass = 'acquired';
    else if (prereqOk) stateClass = 'unlockable';

    let footer;
    if (unlocked) {
        footer = `<div class="tech-node-status acquired">ACQUIRED</div>`;
    } else if (!prereqOk) {
        footer = `<div class="tech-node-status locked">LOCKED &middot; ${node.cost} RP</div>`;
    } else {
        const disabled = affordable ? '' : 'disabled';
        footer = `<button class="tech-unlock-btn ${affordable ? '' : 'unaffordable'}" ${disabled}
            onclick="unlockTechNode('${node.id}')">UNLOCK &middot; ${node.cost} RP</button>`;
    }

    return `<div class="tech-node ${stateClass}">
        <div class="tech-node-name">${node.name}</div>
        <div class="tech-node-desc">${node.desc}</div>
        ${footer}
    </div>`;
}

function _renderTechBranchColumn(branch) {
    const color = _techBranchColor(branch);
    let cards = '';
    for (const node of TECH.nodesInBranch(branch)) {
        cards += _renderTechNodeCard(node);
    }
    return `<div class="tech-branch" style="--branch-color: ${color};">
        <div class="tech-branch-head">${branch}</div>
        ${cards}
    </div>`;
}

function renderTechTree() {
    const screen = document.getElementById('tech-tree-screen');
    if (!screen) return;
    const rpEl = document.getElementById('tech-rp-balance');
    if (rpEl) rpEl.textContent = `RESEARCH: ${TECH.rp} RP`;
    const body = document.getElementById('tech-tree-branches');
    if (!body) return;
    let html = '';
    for (const branch of TECH.BRANCHES) {
        html += _renderTechBranchColumn(branch);
    }
    body.innerHTML = html;
}

window.openTechTree = function () {
    const screen = document.getElementById('tech-tree-screen');
    if (!screen) return;
    renderTechTree();
    screen.classList.remove('hidden');
};

window.closeTechTree = function () {
    const screen = document.getElementById('tech-tree-screen');
    if (screen) screen.classList.add('hidden');
};

window.unlockTechNode = function (id) {
    if (TECH.unlock(id)) {
        if (typeof AudioEngine !== 'undefined' && AudioEngine.playSFX) {
            AudioEngine.playSFX('build');
        }
        renderTechTree();
    }
};
