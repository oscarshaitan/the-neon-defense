/**
 * The Neon Defense - Game Logic
 */

// --- Constants & Config ---
const GRID_SIZE = 40;
const CANVAS_BG = '#050510';
const DEBUG_UNLOCK_KEY = 'neonDefenseDebugUnlocked';
const PERFORMANCE_MODE_KEY = 'neonDefensePerformanceMode';
const ZONE0_RADIUS_CELLS = 6;
const WORLD_MIN_COLS = 140;
const WORLD_MIN_ROWS = 90;
const WORLD_VIEW_MARGIN_COLS = 12;
const WORLD_VIEW_MARGIN_ROWS = 10;
const WORLD_CONTENT_MARGIN_COLS = 14;
const WORLD_CONTENT_MARGIN_ROWS = 14;
const PATHING_RULES = {
    coreRepulsionRadius: 9,          // Grid cells
    coreRepulsionStrength: 14,       // Extra path cost near core
    nearCoreStraightRadius: 8,       // Grid cells
    nearCoreTurnPenaltyBoost: 18,    // Extra turn penalty near core
    mergeMinCoreDistance: 7          // Prefer merges away from core center
};
const HARDPOINT_RULES = {
    slotSnapRadius: GRID_SIZE * 0.45,
    core: {
        count: 6,
        radiusCells: ZONE0_RADIUS_CELLS,
        damageMult: 1.08,
        rangeMult: 1.06,
        cooldownMult: 0.95,
        sizeScale: 1.0
    },
    microRings: [
        { count: 10, radiusCells: 13, angleOffset: Math.PI / 10 },
        { count: 14, radiusCells: 17, angleOffset: 0 }
    ],
    micro: {
        damageMult: 0.82,
        rangeMult: 0.86,
        cooldownMult: 1.12,
        sizeScale: 0.78
    }
};

const TOWERS = {
    basic: { cost: 50, range: 100, damage: 10, cooldown: 30, color: '#00f3ff', type: 'basic' },
    rapid: { cost: 120, range: 80, damage: 4, cooldown: 10, color: '#fcee0a', type: 'rapid' },
    sniper: { cost: 200, range: 250, damage: 50, cooldown: 90, color: '#ff00ac', type: 'sniper' },
    arc: { cost: 180, range: 100, damage: 8, cooldown: 34, color: '#7cd7ff', type: 'arc' }
};
// Hard cap on tower range to prevent spatial-grid query loops from scaling with level.
// At cellSize=200, a range of 800 needs cr=4 → (2*4+1)²=81 cell sweeps — well within budget.
const MAX_TOWER_RANGE = 800;

const ARC_TOWER_RULES = {
    // Temporary perf test switch: disables Arc-specific calculations and VFX.
    // Set to false to restore full Arc mechanics.
    disableCalculationsForPerfTest: false,
    minLinkSpacingCells: 1,
    maxLinkSpacingCells: 3,
    maxBonus: 5,
    staticThreshold: 100,
    stunFrames: 30, // 0.5s at 60 FPS
    baseChainTargets: 3,
    chainRange: GRID_SIZE * 4,
    bounceDamageMult: 0.7,
    maxLightningBursts: 180,
    lowAnimationMode: true
};

// qualityFloor: 0=HIGH, 1=MED, 2=LOW — the minimum profile the governor can run.
// Migrates old 'on'/'off' values from the boolean era.
(function () {
    const stored = localStorage.getItem(PERFORMANCE_MODE_KEY);
    let floor = 0;
    if (stored === '1') floor = 1;
    else if (stored === '2') floor = 2;
    else if (stored === 'on') floor = 1;   // legacy
    // 'off', '0', null → 0
    window._initialQualityFloor = floor;
}());

const PERFORMANCE_RULES = {
    qualityFloor: window._initialQualityFloor,
    enabled: window._initialQualityFloor > 0,   // kept for backward compat with game logic
    autoDropEnabled: localStorage.getItem('neonAutoDropEnabled') !== 'false',
    staticLabelNearCursorRadius: 95,
    statusHalfRateEnemyThreshold: 26,
    staticHitParticleScale: 0.45,
    staticStunParticleCount: 2,
    staticStunTrailInterval: 20
};
ARC_TOWER_RULES.lowAnimationMode = PERFORMANCE_RULES.enabled;

const _DETAIL_NAMES = ['HIGH', 'MED', 'LOW'];

function updatePerformanceUI() {
    const labelEl = document.getElementById('details-label');
    const minusBtn = document.getElementById('details-btn-minus');
    const plusBtn = document.getElementById('details-btn-plus');
    const autoBtn = document.getElementById('auto-drop-btn');
    if (!labelEl) return;
    // Always reflect the actual running profile so auto-drops are visible in the menu.
    const actualIdx = (typeof QUALITY_GOVERNOR !== 'undefined')
        ? Math.max(0, Math.min(2, QUALITY_GOVERNOR.profileIndex))
        : PERFORMANCE_RULES.qualityFloor;
    labelEl.textContent = _DETAIL_NAMES[actualIdx] || 'HIGH';
    if (minusBtn) minusBtn.disabled = actualIdx >= 2;
    if (plusBtn)  plusBtn.disabled  = actualIdx <= 0;
    if (autoBtn) {
        const on = PERFORMANCE_RULES.autoDropEnabled;
        autoBtn.textContent = on ? 'AUTO: ON' : 'AUTO: OFF';
        autoBtn.classList.toggle('auto-drop-off', !on);
    }
}

// delta = +1 → improve quality (go to HIGH), delta = -1 → reduce quality (go to LOW)
window.adjustDetails = function (delta) {
    const actualIdx = (typeof QUALITY_GOVERNOR !== 'undefined')
        ? Math.max(0, Math.min(2, QUALITY_GOVERNOR.profileIndex))
        : PERFORMANCE_RULES.qualityFloor;
    const newIdx = Math.max(0, Math.min(2, actualIdx - delta));
    if (newIdx === actualIdx) return;
    PERFORMANCE_RULES.qualityFloor = newIdx;
    PERFORMANCE_RULES.enabled = newIdx > 0;
    ARC_TOWER_RULES.lowAnimationMode = PERFORMANCE_RULES.enabled;
    localStorage.setItem(PERFORMANCE_MODE_KEY, String(newIdx));
    if (typeof refreshQualitySettings === 'function') refreshQualitySettings();
    updatePerformanceUI();
};

window.toggleAutoDrop = function () {
    PERFORMANCE_RULES.autoDropEnabled = !PERFORMANCE_RULES.autoDropEnabled;
    localStorage.setItem('neonAutoDropEnabled', String(PERFORMANCE_RULES.autoDropEnabled));
    updatePerformanceUI();
};

// Kept for any legacy callers
window.togglePerformanceMode = function () {
    window.adjustDetails(PERFORMANCE_RULES.qualityFloor > 0 ? 1 : -1);
};

let _toastTimer = null;
window.showQualityToast = function (msg) {
    const el = document.getElementById('quality-toast');
    if (!el) return;
    el.textContent = msg;
    el.classList.remove('hidden');
    el.classList.add('visible');
    if (_toastTimer) clearTimeout(_toastTimer);
    _toastTimer = setTimeout(() => {
        el.classList.remove('visible');
        setTimeout(() => el.classList.add('hidden'), 350);
    }, 2800);
};

window.toggleNoBuildOverlay = function () {
    showNoBuildOverlay = !showNoBuildOverlay;
    updateUI();
}

window.addDebugMoney = function () {
    money += 1000000;
    updateUI();
    saveGame();
}

function setCommandCenterAccess(unlocked, persist = false) {
    const securityPanel = document.getElementById('debug-security');
    const commandCenter = document.getElementById('command-center');
    if (!securityPanel || !commandCenter) return;

    securityPanel.classList.toggle('hidden', unlocked);
    commandCenter.classList.toggle('hidden', !unlocked);

    if (persist) {
        if (unlocked) {
            localStorage.setItem(DEBUG_UNLOCK_KEY, 'true');
        } else {
            localStorage.removeItem(DEBUG_UNLOCK_KEY);
        }
    }
}

window.unlockDebug = async function () {
    const input = document.getElementById('debug-pass').value;
    const msgUint8 = new TextEncoder().encode(input);
    const hashBuffer = await crypto.subtle.digest('SHA-256', msgUint8);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    // Salted/Persistent protection check
    if (hashHex === '73ceb15f18bb0a313c8880abe54bf61a529dd8f1e75b084dd39926a1518d3d2f') {
        setCommandCenterAccess(true, true);
    } else {
        // Feedback on failure
        const btn = document.querySelector('#debug-security button');
        const oldText = btn.innerText;
        btn.innerText = "ACCESS DENIED";
        btn.style.borderColor = "#ff0000";
        setTimeout(() => {
            btn.innerText = oldText;
            btn.style.borderColor = "";
        }, 1000);
    }
}

const ENEMIES = {
    basic: { hp: 30, speed: 1.5, color: '#ff0000', reward: 10, width: 20 },
    fast: { hp: 20, speed: 2.5, color: '#ffff00', reward: 15, width: 16 },
    tank: { hp: 100, speed: 0.8, color: '#ff00ff', reward: 30, width: 24 },
    boss: { hp: 500, speed: 0.5, color: '#ff8800', reward: 200, width: 40 },
    splitter: { hp: 80, speed: 1.2, color: '#00ff41', reward: 40, width: 28, type: 'splitter' },
    mini: { hp: 20, speed: 2.0, color: '#00ff41', reward: 5, width: 12, type: 'mini' },
    bulwark: { hp: 350, speed: 0.6, color: '#fcee0a', reward: 60, width: 32, type: 'bulwark' },
    shifter: { hp: 60, speed: 1.5, color: '#ff00ac', reward: 60, width: 20, type: 'shifter' }
};

// --- Game State ---
let canvas, ctx;
let width, height;
let worldCols = WORLD_MIN_COLS;
let worldRows = WORLD_MIN_ROWS;
let lastTime = 0;
let gameState = 'start'; // start, playing, gameover
let wave = 1;
let money = 115;
let lives = 20;

let selectedTowerType = null; // null means we might be selecting an existing tower
let selectedPlacedTower = null; // Reference to a placed tower object
let selectedRift = null; // Reference to a placed tower object
let buildTarget = null; // {x, y} for empty tile selection

let towers = [];
let enemies = [];
let projectiles = [];
let particles = [];
let paths = []; // Array of arrays of points
let hardpoints = [];
let arcTowerLinks = []; // {a, b, strength}
let arcLightningBursts = []; // transient lightning segments
let arcNetworkDirty = true;
let activeStaticStatusCount = 0;

function markArcNetworkDirty() {
    arcNetworkDirty = true;
}

let spawnQueue = []; // New: Array of enemy types to spawn
let spawnTimer = 0;
let waveTimer = 0;
let currentEnemyType = 'basic'; // kept for potential legacy checks but main logic uses queue

// --- Camera State ---
let camera = { x: 0, y: 0, zoom: 1 };
let isDragging = false;
let lastMouseX = 0;
let lastMouseY = 0;

// --- New State for Hover ---
let mouseX = 0;
let mouseY = 0;
let isHovering = false;

// --- VFX State ---
let shakeAmount = 0;
let lightSources = []; // {x, y, radius, color, life}

function startShake(amt) {
    shakeAmount = Math.max(shakeAmount, amt);
}

// --- Wave State ---
let isWaveActive = false;
let totalKills = { basic: 0, fast: 0, tank: 0, boss: 0, splitter: 0, mini: 0, bulwark: 0, shifter: 0 };
let currentWaveTotalEnemies = 0;
let currentWaveDistribution = null;
let pendingRiftGenerations = 0;

// --- Player Profile & Stats ---
let playerName = localStorage.getItem('neonDefensePlayerName') || null;
let prepTimer = 30; // seconds
let frameCount = 0;
let energy = 0;
const maxEnergy = 100;
let targetingAbility = null; // 'emp' or null
let abilities = {
    emp: { cost: 40, radius: 120, duration: 5 * 60, cooldown: 0, maxCooldown: 15 }, // duration in frames
    overclock: { cost: 25, duration: 10 * 60, cooldown: 0, maxCooldown: 10 } // duration in frames
};


let isPaused = false;
let showNoBuildOverlay = false;
let selectedZone = -1; // -1 means no zone highlighted

// --- Tutorial State ---
let tutorialActive = false;
let tutorialStep = 0;
let completedTutorial = localStorage.getItem('neonDefenseTutorialComplete') === 'true';
const tutorialSeenKey = 'neonDefenseTutorialSeen';
const onboardingHintKey = 'neonDefenseOnboardingHints';
const onboardingHintVersionKey = 'neonDefenseOnboardingHintsVersion';
const onboardingHintVersion = 3;
let onboardingHintsSeen = {};
let hintQueue = [];
let hintQueuedKeys = new Set();
let hintActive = false;
let hintHideTimer = null;
let hintResetTimer = null;

try {
    const savedVersion = Number(localStorage.getItem(onboardingHintVersionKey) || '0');
    if (savedVersion !== onboardingHintVersion) {
        onboardingHintsSeen = {};
        localStorage.setItem(onboardingHintVersionKey, String(onboardingHintVersion));
        localStorage.setItem(onboardingHintKey, JSON.stringify(onboardingHintsSeen));
    } else {
        const storedHints = JSON.parse(localStorage.getItem(onboardingHintKey) || '{}');
        if (storedHints && typeof storedHints === 'object') onboardingHintsSeen = storedHints;
    }
} catch (_) {
    onboardingHintsSeen = {};
    localStorage.setItem(onboardingHintVersionKey, String(onboardingHintVersion));
    localStorage.setItem(onboardingHintKey, JSON.stringify(onboardingHintsSeen));
}

function saveOnboardingHints() {
    localStorage.setItem(onboardingHintKey, JSON.stringify(onboardingHintsSeen));
}

function canShowInlineHints() {
    return gameState === 'playing' && !tutorialActive && !isPaused;
}

function showNextHint() {
    if (hintActive || hintQueue.length === 0) return;
    if (!canShowInlineHints()) return;

    const hintEl = document.getElementById('inline-hint');
    if (!hintEl) return;

    const next = hintQueue.shift();
    hintQueuedKeys.delete(next.key);
    onboardingHintsSeen[next.key] = true;
    saveOnboardingHints();

    hintActive = true;
    hintEl.textContent = next.text;
    hintEl.classList.remove('hidden');
    void hintEl.offsetWidth;
    hintEl.classList.add('visible');

    clearTimeout(hintHideTimer);
    clearTimeout(hintResetTimer);

    hintHideTimer = setTimeout(() => {
        hintEl.classList.remove('visible');
        hintResetTimer = setTimeout(() => {
            hintEl.classList.add('hidden');
            hintActive = false;
            showNextHint();
        }, 220);
    }, next.duration || 3600);
}

function queueOnboardingHint(key, text, duration = 3600) {
    if (!key || onboardingHintsSeen[key] || hintQueuedKeys.has(key)) return;
    hintQueuedKeys.add(key);
    hintQueue.push({ key, text, duration });
    showNextHint();
}

function maybeShowAbilityHint() {
    if (gameState !== 'playing') return;
    const abilityReady = Object.values(abilities).some(a => energy >= a.cost && a.cooldown <= 0);
    if (abilityReady) {
        queueOnboardingHint('ability_ready', 'Ability ready: press 1/2 or tap an ability icon.');
    }
}

function maybeShowCameraHint() {
    if (gameState !== 'playing') return;
    queueOnboardingHint('camera_controls', 'Camera controls: drag to pan, pinch/wheel to zoom, recenter to reset.');
}

function maybeShowRiftHint() {
    if (gameState !== 'playing') return;
    queueOnboardingHint('rift_intel', 'Tap rifts to view threat multipliers and sector intel.');
}

function maybeShowTowerHint() {
    if (gameState !== 'playing') return;
    queueOnboardingHint('tower_intel', 'Tower intel: tap a placed tower to inspect stats, then upgrade or sell.');
}

// --- Base State ---
let baseLevel = 0; // 0 = No turret, 1+ = Turret active
let baseCooldown = 0;
let baseRange = 150;
let baseDamage = 20;
let selectedBase = false; // Selection state

// --- Audio Engine ---
const AudioEngine = {
    ctx: null,
    masterGain: null,
    musicGain: null,
    sfxGain: null,
    isMuted: false,
    musicVol: 0.5,
    sfxVol: 0.7,
    currentMusic: null,
    musicType: 'none',
    musicStep: 0,

    // Frequencies
    notes: {
        C2: 65.41, G2: 98.00, A2: 110.00, F2: 87.31,
        C3: 130.81, Eb3: 155.56, Gb3: 185.00, G3: 196.00, Bb3: 233.08,
        C4: 261.63, D4: 293.66, E4: 329.63, F4: 349.23, G4: 392.00, A4: 440.00, B4: 493.88,
        C5: 523.25, D5: 587.33, Eb5: 622.25, E5: 659.25, F5: 698.46, Gb5: 739.99, G5: 783.99
    },

    melodies: {
        normal: [
            { // 01: Original High-Tech
                lead: ['C4', 'E4', 'G4', 0, 'F4', 'A4', 'C5', 0, 'G4', 'B4', 'D5', 0, 'C5', 'G4', 'E4', 'D4'],
                bass: ['C2', 0, 'G2', 'C2', 'F2', 0, 'C3', 'F2', 'G2', 0, 'D3', 'G2', 'C2', 'G2', 'E2', 'D2']
            },
            { // 02: Aeolian Chill
                lead: ['A4', 'C5', 'E5', 0, 'F4', 'A4', 'C5', 0, 'C4', 'E4', 'G4', 0, 'G4', 'B4', 'D5', 0],
                bass: ['A2', 0, 'E2', 'A2', 'F2', 0, 'C3', 'F2', 'C2', 0, 'G2', 'C2', 'G2', 0, 'D3', 'G2']
            },
            { // 03: Dorian Tech
                lead: ['D4', 'F4', 'A4', 'C5', 'G4', 'Bb4', 'D5', 0, 'F4', 'A4', 'C5', 0, 'C4', 'E4', 'G4', 0],
                bass: ['D2', 0, 'A2', 'D2', 'G2', 0, 'D3', 'G2', 'F2', 0, 'C3', 'F2', 'C2', 0, 'G2', 'C2']
            },
            { // 04: Phrygian Edge
                lead: ['E4', 'F4', 'G4', 0, 'F4', 'G4', 'A4', 0, 'G4', 'Ab4', 'C5', 0, 'Eb5', 'D5', 'C5', 'Bb4'],
                bass: ['E2', 0, 'B2', 'E2', 'F2', 0, 'C3', 'F2', 'G2', 0, 'D3', 'G2', 'Ab2', 0, 'Eb3', 'Ab2']
            },
            { // 05: Pentatonic Pulse
                lead: ['C4', 'D4', 'E4', 'G4', 'A4', 'G4', 'E4', 'D4', 'C5', 'A4', 'G4', 'E4', 'D4', 'C4', 'D4', 'E4'],
                bass: ['C2', 'C2', 'G2', 'G2', 'A2', 'A2', 'F2', 'F2', 'C2', 'C2', 'G2', 'G2', 'A2', 'A2', 'F2', 'F2']
            },
            { // 06: Lydian Dream
                lead: ['C4', 'E4', 'G4', 'B4', 'D5', 'B4', 'G4', 'E4', 'F4', 'A4', 'C5', 'E5', 'D5', 'C5', 'A4', 'F4'],
                bass: ['C2', 0, 'G2', 'C2', 'D2', 0, 'A2', 'D2', 'F2', 0, 'C3', 'F2', 'G2', 0, 'D3', 'G2']
            },
            { // 07: Mixolydian Groove
                lead: ['G4', 'B4', 'D5', 'F5', 'E5', 'C5', 'B4', 'G4', 'A4', 'C5', 'E5', 'G4', 'F4', 'D4', 'B3', 'G3'],
                bass: ['G2', 0, 'D3', 'G2', 'F2', 0, 'C3', 'F2', 'C2', 0, 'G2', 'C2', 'Bb2', 0, 'F2', 'Bb2']
            },
            { // 08: Chromatic Tension
                lead: ['C4', 'Db4', 'D4', 'Eb4', 'E4', 'Eb4', 'D4', 'Db4', 'C4', 'G3', 'C4', 'Db4', 'D4', 'A3', 'D4', 'Eb4'],
                bass: ['C2', 'Db2', 'D2', 'Eb2', 'E2', 'Eb2', 'D2', 'Db2', 'C2', 'G1', 'C2', 'Db2', 'D2', 'A1', 'D2', 'Eb2']
            },
            { // 09: Arp Madness
                lead: ['C4', 'G4', 'C5', 'G4', 'E4', 'B4', 'E5', 'B4', 'F4', 'C5', 'F5', 'C5', 'G4', 'D5', 'G5', 'D5'],
                bass: ['C2', 0, 0, 0, 'E2', 0, 0, 0, 'F2', 0, 0, 0, 'G2', 0, 0, 0]
            },
            { // 10: Syncopated Flow
                lead: [0, 'C4', 0, 'E4', 'G4', 0, 'F4', 0, 0, 'A4', 0, 'C5', 'G4', 0, 'D5', 0],
                bass: ['C2', 0, 'G2', 0, 'C2', 0, 'F2', 0, 'F2', 0, 'C3', 0, 'G2', 0, 'D3', 0]
            },
            { // 11: Minor Gravity
                lead: ['G4', 'Bb4', 'D5', 'Eb5', 'D5', 'Bb4', 'G4', 'F4', 'G4', 'D4', 'G4', 'Bb4', 'C5', 'Bb4', 'A4', 'F4'],
                bass: ['G2', 0, 'D3', 'G2', 'Eb2', 0, 'Bb2', 'Eb2', 'C2', 0, 'G2', 'C2', 'F2', 0, 'C3', 'F2']
            },
            { // 12: Cyber Funk
                lead: ['C4', 0, 'C4', 'Eb4', 0, 'F4', 'Gb4', 'G4', 0, 'Bb4', 0, 'C5', 0, 'G4', 'Eb4', 'C4'],
                bass: ['C2', 'C2', 0, 'Eb2', 'Eb2', 0, 'F2', 'G2', 'C2', 'C2', 0, 'Bb1', 'Bb1', 0, 'G1', 'F1']
            },
            { // 13: Neon Echo
                lead: ['C5', 0, 'G4', 0, 'E4', 0, 'C4', 0, 'D5', 0, 'A4', 0, 'F4', 0, 'D4', 0],
                bass: ['C2', 'G2', 'C3', 'G2', 'A2', 'E3', 'A3', 'E3', 'F2', 'C3', 'F3', 'C3', 'G2', 'D3', 'G3', 'D3']
            },
            { // 14: Dark Wave
                lead: ['A3', 'C4', 'E4', 'A4', 'G4', 'E4', 'C4', 'B3', 'F3', 'A3', 'C4', 'F4', 'E4', 'C4', 'A3', 'G3'],
                bass: ['A1', 'A1', 'E2', 'E2', 'G1', 'G1', 'D2', 'D2', 'F1', 'F1', 'C2', 'C2', 'E1', 'E1', 'B1', 'B1']
            },
            { // 15: Final Stand
                lead: ['E4', 'E4', 'G4', 'A4', 'B4', 'B4', 'D5', 'E5', 'D5', 'D5', 'B4', 'A4', 'G4', 'G4', 'E4', 'D4'],
                bass: ['E2', 'E2', 'G2', 'G2', 'A2', 'A2', 'B2', 'B2', 'D3', 'D3', 'B2', 'B2', 'A2', 'A2', 'G2', 'F2']
            }
        ],
        threat: {
            lead: ['C5', 'Eb5', 'G5', 'Eb5', 'Gb5', 'Eb5', 'C5', 'Bb4', 'C5', 'Eb5', 'Gb5', 'Eb5', 'F5', 'Eb5', 'D5', 'Bb4'],
            bass: ['C2', 0, 'C2', 0, 'Eb2', 0, 'Eb2', 0, 'Gb2', 0, 'Gb2', 0, 'G2', 0, 'G2', 0]
        }
    },

    init() {
        if (this.ctx) {
            if (this.ctx.state === 'suspended') this.ctx.resume();
            return;
        }
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();

        this.masterGain = this.ctx.createGain();
        this.masterGain.connect(this.ctx.destination);

        this.musicGain = this.ctx.createGain();
        this.musicGain.gain.setValueAtTime(this.musicVol, this.ctx.currentTime);
        this.musicGain.connect(this.masterGain);

        this.sfxGain = this.ctx.createGain();
        this.sfxGain.gain.setValueAtTime(this.sfxVol, this.ctx.currentTime);
        this.sfxGain.connect(this.masterGain);
    },

    setVolume(type, val) {
        this.init();
        const v = parseFloat(val);
        if (type === 'music') {
            this.musicVol = v;
            if (this.musicGain) this.musicGain.gain.setTargetAtTime(v, this.ctx.currentTime, 0.1);
        } else if (type === 'sfx') {
            this.sfxVol = v;
            if (this.sfxGain) this.sfxGain.gain.setTargetAtTime(v, this.ctx.currentTime, 0.1);
        }
        localStorage.setItem('neonAudioSettings', JSON.stringify({
            music: this.musicVol,
            sfx: this.sfxVol,
            muted: this.isMuted
        }));
    },

    loadSettings() {
        const saved = localStorage.getItem('neonAudioSettings');
        if (saved) {
            const data = JSON.parse(saved);
            this.musicVol = data.music ?? 0.5;
            this.sfxVol = data.sfx ?? 0.7;
            this.isMuted = data.muted ?? false; // Load mute state
        }
    },

    toggleMute() {
        this.isMuted = !this.isMuted;
        if (this.masterGain) {
            this.masterGain.gain.setTargetAtTime(this.isMuted ? 0 : 1, this.ctx.currentTime, 0.1);
        }
        // Save mute state
        localStorage.setItem('neonAudioSettings', JSON.stringify({
            music: this.musicVol,
            sfx: this.sfxVol,
            muted: this.isMuted
        }));
        return this.isMuted;
    },

    updateSoundUI() {
        const text = `SOUND: ${this.isMuted ? 'OFF' : 'ON'}`;
        if (document.getElementById('mute-btn-hud')) document.getElementById('mute-btn-hud').innerText = text;
        if (document.getElementById('mute-btn-pause')) document.getElementById('mute-btn-pause').innerText = text;
        if (document.getElementById('master-mute-btn')) document.getElementById('master-mute-btn').innerText = text;
    },

    playSFX(type) {
        if (!this.ctx || this.isMuted) return;
        if (this.ctx.state === 'suspended') this.ctx.resume();

        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();
        osc.connect(gain);
        gain.connect(this.sfxGain);

        const now = this.ctx.currentTime;
        switch (type) {
            case 'shoot':
                osc.type = 'square';
                osc.frequency.setValueAtTime(400, now);
                osc.frequency.exponentialRampToValueAtTime(100, now + 0.1);
                gain.gain.setValueAtTime(0.05, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.1);
                osc.start(now);
                osc.stop(now + 0.1);
                break;
            case 'explosion':
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(100, now);
                osc.frequency.exponentialRampToValueAtTime(10, now + 0.3);
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.linearRampToValueAtTime(0, now + 0.3);
                osc.start(now);
                osc.stop(now + 0.3);
                break;
            case 'hit':
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(150, now);
                osc.frequency.linearRampToValueAtTime(50, now + 0.2);
                gain.gain.setValueAtTime(0.2, now);
                gain.gain.linearRampToValueAtTime(0, now + 0.2);
                osc.start(now);
                osc.stop(now + 0.2);
                break;
            case 'build':
                osc.type = 'sine';
                osc.frequency.setValueAtTime(200, now);
                osc.frequency.exponentialRampToValueAtTime(800, now + 0.2);
                gain.gain.setValueAtTime(0.05, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
                osc.start(now);
                osc.stop(now + 0.2);
                break;
        }
    },

    updateMusic() {
        if (!this.ctx) return;
        if (this.ctx.state === 'suspended') this.ctx.resume();

        const hasThreat = (typeof getCachedThreatPresence === 'function')
            ? getCachedThreatPresence()
            : enemies.some(e => e.type === 'boss' || e.isMutant);
        const targetType = hasThreat ? 'threat' : 'normal';

        // Calculate which normal melody to use based on wave
        const normalMelodyIndex = (wave - 1) % this.melodies.normal.length;

        // Check if we need to change music
        // Change if: type changes OR (type is normal AND wave-index changes)
        if (this.musicType === targetType) {
            if (targetType === 'threat') return; // Threat stays threat
            if (this.currentNormalIndex === normalMelodyIndex) return; // Normal stays same wave melody
        }

        this.musicType = targetType;
        this.currentNormalIndex = normalMelodyIndex;
        this.musicStep = 0;

        if (this.currentMusic) clearInterval(this.currentMusic);

        const stepTime = targetType === 'threat' ? 0.125 : 0.2; // 16th note equivalent
        const melody = targetType === 'threat' ? this.melodies.threat : this.melodies.normal[normalMelodyIndex];

        this.currentMusic = setInterval(() => {
            if (this.isMuted || gameState !== 'playing') return;

            const step = this.musicStep % 16;
            this.musicStep++;

            // Play Bass
            const bassNote = melody.bass[step];
            if (bassNote) {
                this.playNote(this.notes[bassNote] || 60, 'triangle', 0.1, stepTime * 0.9);
            }

            // Play Lead
            const leadNote = melody.lead[step];
            if (leadNote) {
                // Chance for arpeggio on threat
                if (targetType === 'threat' && step % 4 === 0) {
                    this.playArp(this.notes[leadNote], 'square', 0.05, stepTime * 0.8);
                } else {
                    this.playNote(this.notes[leadNote], 'square', 0.05, stepTime * 0.7);
                }
            }
        }, stepTime * 1000);
    },

    playNote(freq, type, vol, duration) {
        if (!this.ctx) return;
        const osc = this.ctx.createOscillator();
        const g = this.ctx.createGain();
        osc.type = type;
        osc.frequency.setValueAtTime(freq, this.ctx.currentTime);
        osc.connect(g);
        g.connect(this.musicGain);

        g.gain.setValueAtTime(vol, this.ctx.currentTime);
        g.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + duration);

        osc.start();
        osc.stop(this.ctx.currentTime + duration);
    },

    playArp(baseFreq, type, vol, duration) {
        if (!this.ctx) return;
        const osc = this.ctx.createOscillator();
        const g = this.ctx.createGain();
        osc.type = type;

        const now = this.ctx.currentTime;
        const arpSpeed = 0.05;
        // Major arpeggio logic (root, 3rd, 5th)
        osc.frequency.setValueAtTime(baseFreq, now);
        osc.frequency.setValueAtTime(baseFreq * 1.25, now + arpSpeed);
        osc.frequency.setValueAtTime(baseFreq * 1.5, now + arpSpeed * 2);
        osc.frequency.setValueAtTime(baseFreq * 2, now + arpSpeed * 3);

        osc.connect(g);
        g.connect(this.musicGain);

        g.gain.setValueAtTime(vol, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + duration);

        osc.start();
        osc.stop(now + duration);
    }
};

