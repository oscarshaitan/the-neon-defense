// --- Ability System Functions ---

function activateAbility(type) {
    if (gameState !== 'playing' || isPaused) return;
    const ability = abilities[type];

    // Check energy and cooldown
    if (energy < ability.cost || ability.cooldown > 0) {
        AudioEngine.playSFX('error'); // Need to ensure error SFX exists or handle gracefully
        return;
    }

    // Toggle targeting
    if (targetingAbility === type) {
        targetingAbility = null;
    } else {
        targetingAbility = type;
        selectedTowerType = null; // Deselect ghost tower
        selectedPlacedTower = null;
        selectedBase = false;
        selectedRift = null;
        buildTarget = null;
        document.querySelectorAll('.tower-selector').forEach(el => el.classList.remove('selected'));
        document.getElementById('controls-bar')?.classList.add('hidden');
        document.getElementById('selection-panel')?.classList.add('hidden');
    }
    updateUI();
}

function useAbility(type, target) {
    const ability = abilities[type];
    if (energy < ability.cost) return;

    energy -= ability.cost;
    targetingAbility = null;
    ability.cooldown = ability.maxCooldown;

    if (type === 'emp') {
        // EMP Blast at target {x, y}
        createParticles(target.x, target.y, '#00f3ff', 20);
        AudioEngine.playSFX('explosion'); // maybe a 'zap' sfx later

        // Freeze enemies in radius
        enemies.forEach(e => {
            const dist = Math.hypot(e.x - target.x, e.y - target.y);
            if (dist < ability.radius) {
                e.frozen = true;
                e.frozenTimer = ability.duration;
            }
        });
        addLightSource(target.x, target.y, 250, '#00f3ff', 2.0, 2);
    } else if (type === 'overclock') {
        // Overclock a specific tower
        createParticles(target.x, target.y, '#fcee0a', 15);
        AudioEngine.playSFX('repair'); // use repair sfx for buff for now

        target.overclocked = true;
        target.overclockTimer = ability.duration;
        // The boost happens in updateTowers
    }

    updateUI();
}

window.activateAbility = activateAbility;
window.togglePause = togglePause; // Expose togglePause globally

window.toggleWavePanel = function () {
    const panel = document.getElementById('wave-info-panel');
    if (panel.classList.contains('hidden')) {
        updateWavePanel();
        panel.classList.remove('hidden');
    } else {
        panel.classList.add('hidden');
    }
};

function getWaveIntelTags(nextWave, upgradedRiftsCount, mutatedRiftsCount, maxTier) {
    const tags = [];

    if (nextWave % 10 === 0) tags.push({ label: "BOSS", color: "var(--neon-pink)" });
    if (nextWave > 50 && nextWave % 5 === 0 && nextWave % 10 !== 0) tags.push({ label: "SURPRISE_BOSS", color: "#ffcc66" });
    if (nextWave >= 20) tags.push({ label: "TAUNT", color: "#fcee0a" });
    if (nextWave >= 30) tags.push({ label: "STEALTH", color: "#ff66cc" });
    if (nextWave % 20 === 0) tags.push({ label: "MUT_EVENT", color: "#ffffff" });
    if (mutatedRiftsCount > 0) tags.push({ label: `MUTx${mutatedRiftsCount}`, color: "#ffffff" });
    if (upgradedRiftsCount > 0) tags.push({ label: `T${maxTier}`, color: "var(--neon-blue)" });

    return tags;
}

function createEmptyEnemyDistribution() {
    return {
        basic: 0,
        fast: 0,
        tank: 0,
        splitter: 0,
        bulwark: 0,
        shifter: 0,
        boss: 0
    };
}

function getEnemyCountsFromQueue(queue) {
    const dist = createEmptyEnemyDistribution();
    for (const t of queue) {
        const key = (t || '').toLowerCase();
        if (dist[key] !== undefined) dist[key]++;
    }
    return dist;
}

function distributeByWeights(total, weights) {
    const result = {};
    let used = 0;
    const remainders = [];

    for (const w of weights) {
        const raw = total * w.weight;
        const base = Math.floor(raw);
        result[w.type] = base;
        used += base;
        remainders.push({ type: w.type, frac: raw - base });
    }

    let leftover = total - used;
    remainders.sort((a, b) => b.frac - a.frac);
    for (let i = 0; i < leftover; i++) {
        const item = remainders[i % remainders.length];
        result[item.type] = (result[item.type] || 0) + 1;
    }

    return result;
}

function getPredictedWaveDistribution(nextWave) {
    const baseCount = 5 + Math.floor(nextWave * 2.5);
    const dist = createEmptyEnemyDistribution();

    if (nextWave < 3) {
        dist.basic = baseCount;
    } else if (nextWave < 5) {
        const split = distributeByWeights(baseCount, [
            { type: 'basic', weight: 0.7 },
            { type: 'fast', weight: 0.3 }
        ]);
        Object.assign(dist, split);
    } else if (nextWave < 10) {
        const fixedTank = (nextWave % 5 === 0) ? Math.min(2, baseCount) : 0;
        const remaining = baseCount - fixedTank;
        const split = distributeByWeights(remaining, [
            { type: 'basic', weight: 0.75 },
            { type: 'fast', weight: 0.2 },
            { type: 'tank', weight: 0.05 }
        ]);
        Object.assign(dist, split);
        dist.tank += fixedTank;
    } else {
        let weights = [
            { type: 'basic', weight: 0.3 },
            { type: 'fast', weight: 0.5 },
            { type: 'tank', weight: 0.2 }
        ];

        if (nextWave >= 15) {
            weights = [
                { type: 'basic', weight: 0.3 },
                { type: 'fast', weight: 0.2 },
                { type: 'tank', weight: 0.2 },
                { type: 'splitter', weight: 0.3 }
            ];
        }
        if (nextWave >= 20) {
            weights = [
                { type: 'basic', weight: 0.3 },
                { type: 'fast', weight: 0.2 },
                { type: 'tank', weight: 0.2 },
                { type: 'splitter', weight: 0.15 },
                { type: 'bulwark', weight: 0.15 }
            ];
        }
        if (nextWave >= 30) {
            weights = [
                { type: 'basic', weight: 0.3 },
                { type: 'fast', weight: 0.2 },
                { type: 'tank', weight: 0.2 },
                { type: 'splitter', weight: 0.15 },
                { type: 'bulwark', weight: 0.07 },
                { type: 'shifter', weight: 0.08 }
            ];
        }

        const split = distributeByWeights(baseCount, weights);
        Object.assign(dist, split);
    }

    if (nextWave % 10 === 0) dist.boss += 1;
    return dist;
}

function renderEnemyDistributionHTML(distribution) {
    const order = ['basic', 'fast', 'tank', 'splitter', 'bulwark', 'shifter', 'boss'];
    let html = '';
    for (const type of order) {
        const count = distribution[type] || 0;
        if (!count) continue;
        html += `<div class="enemy-count-group" title="${type.toUpperCase()}"><div class="enemy-icon-small icon-${type}"></div>${count}</div>`;
    }
    return html || `<div class="enemy-count-group">No data</div>`;
}

function updateWavePanel() {
    const nextWave = wave;

    // Rift Stats
    const totalRifts = paths.length;
    const upgradedRiftsCount = paths.filter(p => p.level > 1).length;
    const mutatedRiftsCount = paths.filter(p => p.mutation).length;
    const maxTier = paths.reduce((max, p) => Math.max(max, p.level || 1), 1);

    const riftCountEl = document.getElementById('intel-rifts');
    if (riftCountEl) riftCountEl.innerText = totalRifts;

    // Mutation / anomaly readiness
    const mutantChanceEl = document.getElementById('intel-mutant-chance');
    if (nextWave % 20 === 0) {
        mutantChanceEl.innerHTML = `<span style="color: #fff; font-weight: bold;">MUTATION EVENT THIS WAVE</span>`;
    } else if (mutatedRiftsCount > 0) {
        mutantChanceEl.innerHTML = `<span style="color: #fff; font-weight: bold;">${mutatedRiftsCount} ACTIVE MUTATION SECTOR(S)</span>`;
    } else {
        const wavesToMutation = 20 - (nextWave % 20);
        mutantChanceEl.innerText = `Stable | Next mutation check in ${wavesToMutation} wave(s)`;
    }

    const tags = getWaveIntelTags(nextWave, upgradedRiftsCount, mutatedRiftsCount, maxTier);
    const threatScore = tags.length + (nextWave >= 50 ? 1 : 0) + (upgradedRiftsCount > 0 ? 1 : 0);
    const threatTitle = threatScore >= 7 ? "CRITICAL" : (threatScore >= 5 ? "HIGH" : (threatScore >= 3 ? "ELEVATED" : "NORMAL"));
    const threatSpan = document.getElementById('intel-threat');
    threatSpan.innerText = threatTitle;
    threatSpan.style.color = threatTitle === "CRITICAL" ? "var(--neon-pink)" : (threatTitle === "HIGH" ? "#ff7a00" : (threatTitle === "ELEVATED" ? "#ffcc00" : "white"));

    const distributionEl = document.getElementById('intel-distribution');
    if (!distributionEl) return;

    const distribution = (isWaveActive && currentWaveDistribution)
        ? currentWaveDistribution
        : getPredictedWaveDistribution(nextWave);
    distributionEl.innerHTML = renderEnemyDistributionHTML(distribution);
}

window.toggleMute = function () {
    const muted = AudioEngine.toggleMute();
    AudioEngine.updateSoundUI();
};

window.setMusicVolume = function (val) {
    AudioEngine.setVolume('music', val);
};

window.setSFXVolume = function (val) {
    AudioEngine.setVolume('sfx', val);
};

window.saveGame = function () {
    // Snapshot all mutable state before deferring, so the save reflects the
    // moment saveGame() was called even if the idle callback fires later.
    const data = {
        money, lives, wave, isWaveActive, prepTimer, spawnQueue,
        paths: paths.map(p => ({ points: p.points, level: p.level, zone: p.zone, mutation: p.mutation || null })),
        towers: towers.map(t => ({
            type: t.type, x: t.x, y: t.y, level: t.level,
            damage: t.damage, range: t.range, cooldown: t.cooldown, maxCooldown: t.maxCooldown,
            color: t.color, cost: t.cost, totalCost: t.totalCost,
            hardpointId: t.hardpointId || null,
            hardpointType: t.hardpointType || null,
            hardpointScale: t.hardpointScale || 1
        })),
        baseLevel, baseCooldown, energy,
        playerName, totalKills,
        pendingRiftGenerations,
        worldCols,
        worldRows
    };

    // Defer JSON.stringify + localStorage.setItem off the render frame (C4-18).
    // timeout:5000 ensures the write completes within 5 s even under heavy load.
    const doSave = () => {
        localStorage.setItem('neonDefenseSave', JSON.stringify(data));
        console.log("Game Saved");
    };
    if (typeof requestIdleCallback === 'function') {
        requestIdleCallback(doSave, { timeout: 5000 });
    } else {
        doSave();
    }
};

window.loadGame = function () {
    const raw = localStorage.getItem('neonDefenseSave');
    if (!raw) {
        startGame();
        return;
    }

    const data = JSON.parse(raw);
    const hasSavedWorldBounds = Number.isFinite(Number(data.worldCols)) && Number(data.worldCols) > 0
        && Number.isFinite(Number(data.worldRows)) && Number(data.worldRows) > 0;
    if (hasSavedWorldBounds) {
        worldCols = Math.max(WORLD_MIN_COLS, Math.floor(Number(data.worldCols)));
        worldRows = Math.max(WORLD_MIN_ROWS, Math.floor(Number(data.worldRows)));
    }

    money = data.money;
    lives = data.lives;
    wave = data.wave;
    isWaveActive = data.isWaveActive;
    prepTimer = data.prepTimer;
    spawnQueue = data.spawnQueue || []; // Load queue

    if (data.paths) {
        paths = data.paths.map(p => {
            if (Array.isArray(p)) return { points: p, level: 1, mutation: null };
            return p;
        });
    }

    baseLevel = data.baseLevel || 0;
    baseCooldown = data.baseCooldown || 0;
    energy = data.energy || 0;
    playerName = data.playerName || playerName || localStorage.getItem('neonDefensePlayerName') || null;
    if (playerName) localStorage.setItem('neonDefensePlayerName', playerName);
    totalKills = data.totalKills || { basic: 0, fast: 0, tank: 0, boss: 0, splitter: 0, mini: 0, bulwark: 0, shifter: 0 };
    pendingRiftGenerations = data.pendingRiftGenerations || 0;

    // Restore towers
    towers = (data.towers || []).map(t => ({
        ...t,
        arcNetworkBonus: t.arcNetworkBonus || 1,
        arcNetworkSize: t.arcNetworkSize || 1,
        hardpointScale: t.hardpointScale || 1,
        cooldown: t.cooldown || 0,
        maxCooldown: t.maxCooldown || t.cooldown || 30
    }));
    markArcNetworkDirty();

    expandWorldBounds();
    buildHardpoints();

    // Reset transient state
    enemies = [];
    projectiles = [];
    particles = [];
    arcTowerLinks = [];
    arcLightningBursts = [];
    selectedPlacedTower = null;
    selectedTowerType = null;
    selectedBase = false;

    playerName = data.playerName || playerName || localStorage.getItem('neonDefensePlayerName') || null;

    // Hide start screen immediately when loading
    document.getElementById('start-screen').classList.add('hidden');

    if (!playerName) {
        document.getElementById('name-entry-modal').classList.remove('hidden');
        // gameState will be set in savePlayerName
    } else {
        gameState = 'playing';
        AudioEngine.init(); // Init audio on continue click
    }

    // Initialize audio sliders
    if (document.getElementById('music-slider')) document.getElementById('music-slider').value = AudioEngine.musicVol;
    if (document.getElementById('sfx-slider')) document.getElementById('sfx-slider').value = AudioEngine.sfxVol;

    updateUI();
    if (typeof window.resetCamera === 'function') {
        window.resetCamera();
    }
    // If we loaded into an active wave, we might want to just reset to prep phase
    // to avoid "instant death" upon loading or complex enemy state sync
    if (isWaveActive) {
        // Option: Restart the current wave
        isWaveActive = false;
        prepTimer = 5; // Give them 5s to get bearings
        document.getElementById('wave-display').innerText = wave;
        document.getElementById('skip-btn').style.display = 'block';
    } else {
        document.getElementById('skip-btn').style.display = 'block';
    }
    updateUI();
};

function checkPlayerName() {
    if (!playerName) {
        document.getElementById('name-entry-modal').classList.remove('hidden');
    } else {
        startGame();
    }
}

function savePlayerName() {
    const input = document.getElementById('player-name-input').value.trim();
    if (input) {
        playerName = input;
        localStorage.setItem('neonDefensePlayerName', playerName);
        document.getElementById('name-entry-modal').classList.add('hidden');

        const fromStartScreen = !document.getElementById('start-screen').classList.contains('hidden');
        if (fromStartScreen) {
            startGame();
            return;
        }

        gameState = 'playing';
        AudioEngine.init(); // Init audio on name confirm click
        updateUI();
        saveGame();
    }
}

window.checkPlayerName = checkPlayerName;
window.savePlayerName = savePlayerName;

window.shareGame = async function () {
    // Generate Stats Text
    let killSummary = "";
    for (let type in totalKills) {
        if (totalKills[type] > 0) {
            killSummary += `\n- ${type.toUpperCase()}: ${totalKills[type]}`;
        }
    }

    // Count towers by type
    const towerCounts = { basic: 0, rapid: 0, sniper: 0 };
    towers.forEach(t => { if (towerCounts[t.type] !== undefined) towerCounts[t.type]++; });

    const shareText = `[THE NEON DEFENSE — STATUS REPORT]\nCommander: ${playerName || "Unknown"}\nSector reached: WAVE ${wave}\nCredits secured: ${money}\nCommand Center: LEVEL ${baseLevel + 1}\nTowers: Basic(${towerCounts.basic}), Rapid(${towerCounts.rapid}), Sniper(${towerCounts.sniper})\nConfirmed Eliminations: ${killSummary}\n\nJoin the defense!`;

    try {
        // Create an offline canvas to render the full report (Game + UI Overlay)
        const borderPadding = 150;
        const offCanvas = document.createElement('canvas');
        offCanvas.width = canvas.width + (borderPadding * 2);
        offCanvas.height = canvas.height + (borderPadding * 2);
        const octx = offCanvas.getContext('2d');

        // Fill background
        octx.fillStyle = '#050510';
        octx.fillRect(0, 0, offCanvas.width, offCanvas.height);

        // Draw the main game canvas onto the offline canvas with padding
        octx.drawImage(canvas, borderPadding, borderPadding);

        // --- Render HUD Overlay onto the Screenshot ---
        const padding = 20 + borderPadding;
        const bannerHeight = 85;
        const textOffset = 75;

        // Fully opaque banner at the top (no border)
        octx.fillStyle = '#050510';
        octx.fillRect(0, 0, offCanvas.width, bannerHeight + textOffset);

        // Header Text
        octx.fillStyle = '#ff00ac';
        octx.font = 'bold 16px Orbitron, sans-serif';
        octx.textAlign = 'left';
        octx.fillText('THE NEON DEFENSE — COMMANDER REPORT', padding, 25 + textOffset);

        // Commander Name
        octx.fillStyle = '#00f3ff';
        octx.font = 'bold 22px Orbitron, sans-serif';
        octx.fillText(`COMMANDER: ${playerName || "UNIDENTIFIED"}`, padding, 55 + textOffset);

        // Wave & Credits (Right Aligned)
        octx.textAlign = 'right';
        octx.font = 'bold 18px Orbitron, sans-serif';
        octx.fillStyle = '#fcee0a';
        octx.fillText(`WAVE: ${wave}  |  CREDITS: $${money}`, offCanvas.width - padding, 45 + textOffset);

        // --- Render Panels ---
        const panelWidth = 220;

        // 1. ELIMINATIONS PANEL
        const elimHeight = 250;
        octx.fillStyle = 'rgba(5, 5, 16, 0.85)';
        octx.fillRect(offCanvas.width - panelWidth - padding, bannerHeight + padding, panelWidth, elimHeight);
        octx.strokeStyle = '#ff00ac';
        octx.strokeRect(offCanvas.width - panelWidth - padding, bannerHeight + padding, panelWidth, elimHeight);

        octx.textAlign = 'left';
        octx.fillStyle = '#ff00ac';
        octx.font = 'bold 14px Orbitron, sans-serif';
        octx.fillText('ELIMINATIONS', offCanvas.width - panelWidth - padding + 10, bannerHeight + padding + 25);

        let y = bannerHeight + padding + 55;
        for (let type in totalKills) {
            if (totalKills[type] > 0 || ['basic', 'fast', 'tank'].includes(type)) {
                // Draw Tiny Enemy Icon
                const color = ENEMIES[type].color;
                octx.fillStyle = color;
                octx.shadowBlur = 5;
                octx.shadowColor = color;

                const ix = offCanvas.width - panelWidth - padding + 20;
                const iy = y - 5;
                octx.beginPath();
                if (type === 'tank') octx.rect(ix - 6, iy - 6, 12, 12);
                else if (type === 'fast') { octx.moveTo(ix, iy - 8); octx.lineTo(ix + 4, iy); octx.lineTo(ix, iy + 6); octx.lineTo(ix - 4, iy); octx.closePath(); }
                else if (type === 'boss') { for (let i = 0; i < 6; i++) { const a = (Math.PI / 3) * i; octx.lineTo(ix + Math.cos(a) * 8, iy + Math.sin(a) * 8); } octx.closePath(); }
                else if (type === 'bulwark') { octx.rect(ix - 7, iy - 7, 14, 14); }
                else if (type === 'splitter') { octx.moveTo(ix, iy - 8); octx.lineTo(ix + 7, iy + 5); octx.lineTo(ix - 7, iy + 5); octx.closePath(); }
                else octx.arc(ix, iy, 6, 0, Math.PI * 2);
                octx.fill();
                octx.shadowBlur = 0;

                octx.font = '11px Orbitron, sans-serif';
                octx.fillStyle = '#fff';
                octx.fillText(type.toUpperCase(), ix + 15, y);
                octx.textAlign = 'right';
                octx.fillText(totalKills[type], offCanvas.width - padding - 15, y);
                octx.textAlign = 'left';
                y += 22;
            }
        }

        // 2. TOWERS PANEL
        const towerHeight = 168;
        const tx = padding;
        const ty = bannerHeight + padding;
        octx.fillStyle = 'rgba(5, 5, 16, 0.95)';
        octx.fillRect(tx, ty, panelWidth, towerHeight);
        octx.strokeStyle = '#00f3ff';
        octx.strokeRect(tx, ty, panelWidth, towerHeight);

        octx.fillStyle = '#00f3ff';
        octx.font = 'bold 14px Orbitron, sans-serif';
        octx.fillText('DEFENSE GRID', tx + 10, ty + 25);

        // Core Tower Stats
        octx.font = '11px Orbitron, sans-serif';
        octx.fillStyle = '#00ff41';
        octx.fillText(`CORE: LVL ${baseLevel + 1} | ${lives} LIVES`, tx + 10, ty + 45);

        let ty_off = ty + 70;
        ['basic', 'rapid', 'sniper', 'arc'].forEach(type => {
            const config = TOWERS[type];
            const typeTowers = towers.filter(t => t.type === type);
            const avgLevel = typeTowers.length > 0 ? Math.round(typeTowers.reduce((sum, t) => sum + t.level, 0) / typeTowers.length) : 0;

            const ix = tx + 20;
            const iy = ty_off - 5;

            octx.fillStyle = config.color;
            octx.beginPath();
            if (type === 'basic') octx.rect(ix - 6, iy - 6, 12, 12);
            else if (type === 'rapid') octx.arc(ix, iy, 6, 0, Math.PI * 2);
            else if (type === 'sniper') { octx.save(); octx.translate(ix, iy); octx.rotate(Math.PI / 4); octx.rect(-6, -6, 12, 12); octx.restore(); }
            else {
                for (let i = 0; i < 6; i++) {
                    const a = (Math.PI * 2 * i / 6) - Math.PI / 2;
                    const x = ix + Math.cos(a) * 6;
                    const y = iy + Math.sin(a) * 6;
                    if (i === 0) octx.moveTo(x, y);
                    else octx.lineTo(x, y);
                }
                octx.closePath();
            }
            octx.fill();

            octx.font = '11px Orbitron, sans-serif';
            octx.fillStyle = '#fff';
            octx.fillText(type.toUpperCase(), ix + 15, ty_off);
            octx.textAlign = 'right';
            octx.fillText(`${typeTowers.length} (L${avgLevel})`, tx + panelWidth - 15, ty_off);
            octx.textAlign = 'left';
            ty_off += 22;
        });

        // Stylized watermark/border at the bottom
        octx.strokeStyle = '#00f3ff';
        octx.lineWidth = 4;
        octx.strokeRect(10, 10, offCanvas.width - 20, offCanvas.height - 20);

        // Capture the finished offline canvas
        const snapshot = offCanvas.toDataURL('image/png');

        // Check Web Share API
        if (navigator.share) {
            const blob = await (await fetch(snapshot)).blob();
            const file = new File([blob], 'neon_defense_status.png', { type: 'image/png' });

            await navigator.share({
                title: 'The Neon Defense — Status Report',
                text: shareText,
                files: [file]
            });
        } else {
            await navigator.clipboard.writeText(shareText);
            alert("Status report copied to clipboard! Opening enhanced snapshot...");
            const win = window.open();
            win.document.write(`<body style="background:#050510; display:flex; justify-content:center; align-items:center; height:100vh; margin:0;">
                <img src="${snapshot}" style="max-width:95%; max-height:95%; border:2px solid #00f3ff; box-shadow:0 0 30px #00f3ff;">
                </body>`);
        }
    } catch (err) {
        console.error("Sharing failed:", err);
        alert("Transmission interrupted. Check logs.");
    }
};

function resetGameLogic() {
    money = 100;
    lives = 20;
    wave = 1;
    energy = 0; // Reset Energy
    isWaveActive = false;
    prepTimer = 30;
    frameCount = 0;
    targetingAbility = null;
    totalKills = { basic: 0, fast: 0, tank: 0, boss: 0, splitter: 0, mini: 0, bulwark: 0, shifter: 0 };

    // Reset ability cooldowns
    for (let k in abilities) abilities[k].cooldown = 0;

    baseLevel = 0; // Reset base
    towers = [];
    markArcNetworkDirty();
    arcTowerLinks = [];
    arcLightningBursts = [];
    selectedTowerType = 'basic';
    selectedPlacedTower = null;
    selectedBase = false;
    selectedRift = null;
    selectedZone = -1;
    document.getElementById('selection-panel').classList.add('hidden');
    selectTower('basic');

    enemies = [];
    projectiles = [];
    particles = [];
    arcLightningBursts = [];
    spawnQueue = []; // Clear spawn queue on reset

    // Reset paths to initial state
    paths = [];
    calculatePath();

    startPrepPhase();
    updateUI();
}

// ---------------------------------------------------------------------------
// Path Worker Management (C4-17) — async rift generation via Web Worker.
// ---------------------------------------------------------------------------

let _pathWorker = null;
let _pathWorkerBusy = false;

function _getPathWorker() {
    if (!_pathWorker) {
        _pathWorker = new Worker('scripts/workers/path_worker.js');
        _pathWorker.onmessage = _onPathWorkerMessage;
        _pathWorker.onerror = function (e) {
            console.error('[PathWorker] Error:', e.message);
            _pathWorkerBusy = false;
        };
    }
    return _pathWorker;
}

/** Apply one generated rift to game state (side-effects from generateNewPath). */
function _applyGeneratedRift(newPathPoints, foundZone) {
    paths.push({ points: newPathPoints, level: 1, zone: foundZone });

    // Destroy any towers sitting on the new path.
    for (let i = towers.length - 1; i >= 0; i--) {
        const t = towers[i];
        if (t.hardpointId) continue;
        const tolerance = GRID_SIZE / 2;
        let hit = false;
        for (let j = 0; j < newPathPoints.length - 1; j++) {
            const p1 = newPathPoints[j];
            const p2 = newPathPoints[j + 1];
            if (Math.abs(p1.y - p2.y) < 1) {
                if (Math.abs(t.y - p1.y) < tolerance
                    && t.x >= Math.min(p1.x, p2.x) - tolerance
                    && t.x <= Math.max(p1.x, p2.x) + tolerance) { hit = true; break; }
            } else {
                if (Math.abs(t.x - p1.x) < tolerance
                    && t.y >= Math.min(p1.y, p2.y) - tolerance
                    && t.y <= Math.max(p1.y, p2.y) + tolerance) { hit = true; break; }
            }
        }
        if (hit) {
            money += Math.floor((t.cost * t.level) * 0.7);
            createParticles(t.x, t.y, '#fff', 10);
            towers.splice(i, 1);
            markArcNetworkDirty();
        }
    }
    updateUI();
}

function _onPathWorkerMessage(e) {
    const msg = e.data;
    if (msg.type === 'path_ready') {
        _applyGeneratedRift(msg.newPathPoints, msg.foundZone);
        pendingRiftGenerations = Math.max(0, pendingRiftGenerations - 1);
    } else if (msg.type === 'batch_done') {
        _pathWorkerBusy = false;
        if (msg.remaining > 0) {
            console.warn(`[RIFT BACKLOG] Worker finished with ${msg.remaining} unplaced rifts.`);
            pendingRiftGenerations = Math.max(pendingRiftGenerations, msg.remaining);
        }
        // If startPrepPhase was called while worker was busy (and silently skipped
        // _requestRiftGeneration), continue the work now that the worker is free.
        if (pendingRiftGenerations > 0) {
            const maxAttempts = Math.min(1800, 120 + pendingRiftGenerations * 40);
            _requestRiftGeneration(pendingRiftGenerations, maxAttempts);
        }
    }
}

/**
 * Kick off async rift generation via the worker.
 * count     — number of rifts to generate.
 * maxAttempts — hard ceiling on total A* attempts inside the worker.
 */
function _requestRiftGeneration(count, maxAttempts) {
    if (_pathWorkerBusy || count <= 0) return;
    _pathWorkerBusy = true;
    const { cols, rows } = getWorldGridSize();
    const serializedPaths = paths.map(p => ({
        points: p.points.map(pt => ({ x: pt.x, y: pt.y })),
        zone: p.zone || 1
    }));
    const serializedHardpoints = hardpoints.map(hp => ({ c: hp.c, r: hp.r, type: hp.type }));
    _getPathWorker().postMessage({
        type: 'generate_batch',
        state: {
            cols, rows, wave,
            gridSize: GRID_SIZE,
            zone0Radius: ZONE0_RADIUS_CELLS,
            pathingRules: PATHING_RULES,
            paths: serializedPaths,
            hardpoints: serializedHardpoints,
            count,
            maxAttempts: maxAttempts || Math.min(1800, 120 + count * 40)
        }
    });
}

function getExpectedRiftCountByWave(currentWave) {
    let scheduled = 0;
    for (let w = 2; w <= currentWave; w++) {
        if (w <= 50) {
            if ((w - 1) % 10 === 0) scheduled++;
        } else {
            if ((w - 1) % 5 === 0) scheduled++;
        }
    }
    return 1 + scheduled; // Initial path + scheduled additions
}

function startPrepPhase() {
    isWaveActive = false;
    currentWaveTotalEnemies = 0;
    currentWaveDistribution = null;
    pendingRiftGenerations = 0;
    // Don't reset money/lives/towers here, just timer
    prepTimer = 30;
    spawnQueue = []; // Clear any remaining enemies from previous wave if it ended prematurely

    // UI Updates
    document.getElementById('skip-btn').style.display = 'block';
    document.getElementById('wave-display').innerText = wave; // Show incoming wave number

    // Auto-update Wave Intel if open
    const panel = document.getElementById('wave-info-panel');
    if (panel && !panel.classList.contains('hidden')) {
        updateWavePanel();
    }

    // New Path Generation
    // Up to Wave 50: Every 10 waves (11, 21, 31, 41, 51)
    // After Wave 50: Every 5 waves (56, 61, 66...)
    // Reconcile expected-vs-actual rifts so missed placements are re-queued.
    if (wave > 1) {
        const expectedRifts = getExpectedRiftCountByWave(wave);
        const missingRifts = Math.max(0, expectedRifts - paths.length);
        if (missingRifts > pendingRiftGenerations) {
            pendingRiftGenerations = missingRifts;
        }
    }

    if (pendingRiftGenerations > 0) {
        // Async: no frame-budget concern, so use the larger resetGame formula.
        const maxAttempts = Math.min(1800, 120 + pendingRiftGenerations * 40);
        _requestRiftGeneration(pendingRiftGenerations, maxAttempts);
    }
}

window.skipPrep = function () {
    startWave();
};

function startWave(options = {}) {
    const { silent = false, persist = true, tutorialProgress = true } = options;
    isWaveActive = true;
    prepTimer = 0;
    document.getElementById('skip-btn').style.display = 'none';

    // Tutorial Step Advance
    if (tutorialProgress && tutorialActive && tutorialStep === 4) {
        nextTutorialStep();
    }

    // Clear Temporal Mutations (Fleeting)
    // Unlike Rift Tiers, mutations only last for the wave they occur in.
    paths.forEach(p => p.mutation = null);

    // Rift Upgrades (Post Wave 50) - PERMANENT
    if (wave > 50) {
        paths.forEach(p => {
            if (Math.random() < 0.10) {
                p.level++;
                console.log(`!!! RIFT EVOLVED !!! Tier: ${p.level}`);
            }
        });
    }

    // Auto-update Wave Intel if open (to show Tier upgrades/mutations immediately)
    const panel = document.getElementById('wave-info-panel');
    if (panel && !panel.classList.contains('hidden')) {
        updateWavePanel();
    }

    if (persist) saveGame(); // Save on wave start

    waveTimer = 0;
    spawnTimer = 0;
    spawnQueue = [];
    const baseCount = 5 + Math.floor(wave * 2.5);

    // Check for Mutation (Every 20 waves)
    if (wave % 20 === 0) {
        generateMutation();
    }

    // Play wave start sound
    if (!silent) {
        AudioEngine.init();
        AudioEngine.playSFX('build');
    }

    for (let i = 0; i < baseCount; i++) {
        let type = 'basic';
        const r = Math.random();

        if (wave < 3) {
            type = 'basic';
        } else if (wave < 5) {
            type = r < 0.3 ? 'fast' : 'basic';
        } else if (wave < 10) {
            if (wave % 5 === 0 && i < 2) type = 'tank';
            else if (r < 0.2) type = 'fast';
            else if (r < 0.25) type = 'tank';
            else type = 'basic';
        } else {
            const chance = Math.random();
            if (chance < 0.08 && wave >= 30) type = 'shifter';
            else if (chance < 0.15 && wave >= 20) type = 'bulwark';
            else if (chance < 0.30 && wave >= 15) type = 'splitter';
            else if (chance < 0.50) type = 'fast';
            else if (chance < 0.70) type = 'tank';
            else type = 'basic';
        }
        spawnQueue.push(type);
    }

    // Boss Handling
    if (wave % 10 === 0) {
        const randomIndex = Math.floor(Math.random() * (spawnQueue.length + 1));
        spawnQueue.splice(randomIndex, 0, 'boss');
    }

    if (wave > 50 && wave % 5 === 0 && wave % 10 !== 0) {
        if (Math.random() < 0.25) {
            console.log("!!! SURPRISE BOSS DETECTED !!!");
            const randomIndex = Math.floor(Math.random() * (spawnQueue.length + 1));
            spawnQueue.splice(randomIndex, 0, 'boss');
            AudioEngine.playSFX('hit');
        }
    }

    currentWaveTotalEnemies = spawnQueue.length;
    currentWaveDistribution = getEnemyCountsFromQueue(spawnQueue);

    updateUI();
}

function generateMutation() {
    // Pick a random rift to mutate
    const targetRift = paths[Math.floor(Math.random() * paths.length)];

    // Mutation Profiles
    const profiles = [
        { name: 'CRIMSON', color: '#ff0033', hp: 1.6, speed: 1.2, reward: 2.0 },
        { name: 'VOID', color: '#aa00ff', hp: 1.4, speed: 1.5, reward: 2.5 },
        { name: 'TITAN', color: '#00ffaa', hp: 3.0, speed: 0.7, reward: 3.0 },
        { name: 'PHASE', color: '#ffffff', hp: 1.2, speed: 2.0, reward: 1.5 },
        { name: 'NEON', color: '#fcee0a', hp: 1.8, speed: 1.3, reward: 2.0 }
    ];

    const profile = profiles[Math.floor(Math.random() * profiles.length)];

    targetRift.mutation = {
        key: profile.name,
        name: profile.name,
        color: profile.color,
        hpMulti: profile.hp,
        speedMulti: profile.speed,
        rewardMulti: profile.reward
    };

    console.log(`!!! RIFT MUTATED !!! Sector: ${profile.name}`);
    AudioEngine.playSFX('hit'); // Alert sound
}

