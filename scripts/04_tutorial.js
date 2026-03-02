// --- Tutorial Logic ---
window.startTutorial = function () {
    if (completedTutorial) return;
    tutorialActive = true;
    tutorialStep = 0;
    isPaused = true; // Pause game logic during dialog
    const overlay = document.getElementById('tutorial-overlay');
    if (overlay) {
        overlay.classList.remove('hidden');
        overlay.classList.remove('allow-game-input');
        overlay.style.pointerEvents = 'auto';
        const box = overlay.querySelector('.tutorial-box');
        if (box) box.style.pointerEvents = 'auto';
    }
    updateTutorialBox();
};

window.nextTutorialStep = function () {
    tutorialStep++;
    updateTutorialBox();
};

window.skipTutorial = function () {
    tutorialActive = false;
    isPaused = false; // Resume game
    const overlay = document.getElementById('tutorial-overlay');
    if (overlay) {
        overlay.classList.add('hidden');
        overlay.classList.remove('allow-game-input');
        overlay.style.pointerEvents = '';
        const box = overlay.querySelector('.tutorial-box');
        if (box) box.style.pointerEvents = '';
    }
    localStorage.setItem('neonDefenseTutorialComplete', 'true');
    completedTutorial = true;
    showNextHint();
};

let tutorialTypeInterval = null;
function updateTutorialBox() {
    const msg = document.getElementById('tutorial-msg');
    const nextBtn = document.getElementById('tutorial-next-btn');
    const skipBtn = document.getElementById('tutorial-skip-btn');
    const overlay = document.getElementById('tutorial-overlay');
    if (!msg || !nextBtn || !skipBtn || !overlay) return;
    const box = overlay.querySelector('.tutorial-box');

    nextBtn.style.display = 'none';
    skipBtn.style.display = 'none';
    overlay.classList.remove('allow-game-input');
    overlay.style.pointerEvents = 'auto';
    if (box) box.style.pointerEvents = 'auto';

    let text = "";
    switch (tutorialStep) {
        case 0:
            text = "Welcome, Commander. Our sector is under threat. We need to establish a defense perimeter immediately.";
            nextBtn.innerHTML = "UNDERSTOOD";
            nextBtn.style.display = 'block';
            skipBtn.style.display = 'block';
            isPaused = true;
            break;
        case 1:
            text = "Command protocol loaded. You will now place your first defense node.";
            nextBtn.innerHTML = "UNDERSTOOD";
            nextBtn.style.display = 'block';
            isPaused = true;
            break;
        case 2:
            text = "First, select a tactical position.<br><strong>Hardpoint:</strong> fixed anchor slot with placement bonuses.<br><strong>Soft point:</strong> any normal empty grid tile without slot bonuses.<br>Now <strong>tap an empty square</strong> near the Core to target it.";
            isPaused = false; // Allow interaction
            overlay.classList.add('allow-game-input');
            overlay.style.pointerEvents = 'none';
            if (box) box.style.pointerEvents = 'none';
            break;
        case 3:
            text = "Position locked. Now, <strong>choose a Tower type</strong> from the deployment panel below.";
            isPaused = false;
            overlay.classList.add('allow-game-input');
            overlay.style.pointerEvents = 'none';
            if (box) box.style.pointerEvents = 'none';
            break;
        case 4:
            text = "Defense initialized. When you're ready to engage the enemy, click <strong>START WAVE</strong>.";
            isPaused = false;
            overlay.classList.add('allow-game-input');
            overlay.style.pointerEvents = 'none';
            if (box) box.style.pointerEvents = 'none';
            break;
        default:
            finishTutorial();
            return;
    }

    // Typewriter Effect
    if (tutorialTypeInterval) clearInterval(tutorialTypeInterval);
    msg.innerHTML = "";

    // If it contains HTML tags (strong), don't type it out character by character to avoid broken tags
    if (text.includes('<')) {
        msg.innerHTML = text;
    } else {
        let i = 0;
        tutorialTypeInterval = setInterval(() => {
            msg.innerHTML += text[i];
            i++;
            if (i >= text.length) clearInterval(tutorialTypeInterval);
        }, 20);
    }
}

function finishTutorial() {
    tutorialActive = false;
    isPaused = false; // Ensure game resumes
    const overlay = document.getElementById('tutorial-overlay');
    if (overlay) {
        overlay.classList.add('hidden');
        overlay.classList.remove('allow-game-input');
        overlay.style.pointerEvents = '';
        const box = overlay.querySelector('.tutorial-box');
        if (box) box.style.pointerEvents = '';
    }
    localStorage.setItem('neonDefenseTutorialComplete', 'true');
    completedTutorial = true;
    showNextHint();
}

function generateNewPath(options = {}) {
    const relaxedLevel = Math.max(0, Math.min(2, Number(options.relaxedLevel || 0)));
    const aggressivePlacement = !!options.aggressivePlacement;
    const suppressLogs = !!options.suppressLogs;
    if (!hardpoints.length) buildHardpoints();

    // Target: Center (Base)
    const { cols, rows } = getWorldGridSize();

    let centerC = Math.floor(cols / 2);
    let centerR = Math.floor(rows / 2);

    if (paths.length > 0 && paths[0].points.length > 0) {
        const p = paths[0].points;
        const base = p[p.length - 1];
        centerC = Math.floor(base.x / GRID_SIZE);
        centerR = Math.floor(base.y / GRID_SIZE);
    }

    const endNode = { c: centerC, r: centerR };

    // Helper to check if grid cell is occupied by any existing path
    const isLocationOnPath = (c, r) => {
        for (const path of paths) {
            for (const p of path.points) {
                const pc = Math.floor(p.x / GRID_SIZE);
                const pr = Math.floor(p.y / GRID_SIZE);
                if (pc === c && pr === r) return true;
            }
        }
        return false;
    };

    // 1. Pick Best Candidate Start (Wave-biased orbital zoning + body-relative dispersion)
    let bestStartNode = null;
    let foundZone = -1;
    const cornerDistances = [
        Math.hypot(centerC, centerR),
        Math.hypot(cols - 1 - centerC, centerR),
        Math.hypot(centerC, rows - 1 - centerR),
        Math.hypot(cols - 1 - centerC, rows - 1 - centerR)
    ];
    const maxRadiusByMap = Math.max(...cornerDistances);
    const mapZoneCap = Math.max(3, Math.floor((maxRadiusByMap - ZONE0_RADIUS_CELLS) / 3));
    const maxZone = Math.max(3, Math.min(15, mapZoneCap));
    const orbitalDensity = 0.62; // Softer 2n^2-inspired shell capacity.
    const getOrbitalShellCapacity = (zone) => Math.max(1, Math.round((2 * zone * zone) * orbitalDensity));
    const riftLoadTarget = Math.max(paths.length + 1, getExpectedRiftCountByWave(wave));
    const zoneCounts = new Array(maxZone + 1).fill(0);
    for (const p of paths) {
        const z = Math.max(1, Math.min(maxZone, p.zone || 1));
        zoneCounts[z]++;
    }

    let targetZone = 1;
    let cumulativeCapacity = 0;
    for (let z = 1; z <= maxZone; z++) {
        cumulativeCapacity += getOrbitalShellCapacity(z);
        targetZone = z;
        if (cumulativeCapacity >= riftLoadTarget) break;
    }

    const desiredZoneCounts = new Array(maxZone + 1).fill(0);
    let remainingDesired = riftLoadTarget;
    for (let z = 1; z <= targetZone && remainingDesired > 0; z++) {
        const cap = getOrbitalShellCapacity(z);
        const desired = Math.min(cap, remainingDesired);
        desiredZoneCounts[z] = desired;
        remainingDesired -= desired;
    }
    const baseMinRiftSpacing = wave < 120 ? 0.95 : (wave < 300 ? 0.85 : (wave < 700 ? 0.75 : 0.65));
    const minRiftSpacing = aggressivePlacement ? 0 : Math.max(0.2, baseMinRiftSpacing - (relaxedLevel * 0.35));
    const candidateAttempts = aggressivePlacement
        ? Math.min(1400, 360 + Math.floor(wave / 6) + (relaxedLevel * 320))
        : Math.min(960, 180 + Math.floor(wave / 8) + (relaxedLevel * 260));
    const spawnHardpointBuffer = 0;
    const mergeHardpointBuffer = 0;

    // Keep minimum tactical presence in inner shells so core-adjacent play doesn't collapse.
    const innerZoneTargets = {
        1: riftLoadTarget >= 8 ? 2 : 1,
        2: riftLoadTarget >= 16 ? 2 : 0,
        3: riftLoadTarget >= 24 ? 2 : 0
    };
    let forcedZone = null;
    let strongestDeficit = 0;
    const searchZoneLimit = Math.min(maxZone, targetZone + (aggressivePlacement ? 2 : 1));
    for (let z = 1; z <= searchZoneLimit; z++) {
        const floorTarget = innerZoneTargets[z] || 0;
        const desired = Math.max(floorTarget, desiredZoneCounts[z] || 0);
        const deficit = desired - (zoneCounts[z] || 0);
        if (deficit > strongestDeficit) {
            strongestDeficit = deficit;
            forcedZone = z;
        }
    }

    // Weighted zone ordering: still wave-biased outward, but with randomness for organic layouts.
    const zoneOrder = [];
    if (forcedZone !== null) zoneOrder.push(forcedZone);
    const weightedZones = [];
    for (let z = 1; z <= searchZoneLimit; z++) {
        if (z === forcedZone) continue;
        const distanceFromTarget = Math.abs(z - targetZone);
        const desired = Math.max(innerZoneTargets[z] || 0, desiredZoneCounts[z] || 0);
        const deficit = Math.max(0, desired - (zoneCounts[z] || 0));
        const deficitBias = deficit > 0 ? -Math.min(2.8, 0.85 + deficit * 0.55) : 0;
        const innerBias = z <= 3 ? -0.25 : 0;
        const randomness = Math.random() * 1.1;
        const score = (distanceFromTarget * 0.75) + randomness + innerBias + deficitBias;
        weightedZones.push({ z, score });
    }
    weightedZones.sort((a, b) => a.score - b.score);
    zoneOrder.push(...weightedZones.map(item => item.z));

    for (const zoneIndex of zoneOrder) {
        // Electron Shell Capacities: Tightened for inner zones
        const zoneRiftCount = zoneCounts[zoneIndex] || 0;
        const zoneCapacity = Math.max(innerZoneTargets[zoneIndex] || 0, getOrbitalShellCapacity(zoneIndex));
        const relaxedExtraCapacity = aggressivePlacement ? 40 : (relaxedLevel === 0 ? 4 : (relaxedLevel === 1 ? 10 : 20));
        if (zoneRiftCount >= (zoneCapacity + relaxedExtraCapacity)) continue; // Soft cap to preserve organic spread.

        const innerR = ZONE0_RADIUS_CELLS + (zoneIndex - 1) * 3;
        const outerR = ZONE0_RADIUS_CELLS + zoneIndex * 3;
        const zoneCandidates = [];

        for (let i = 0; i < candidateAttempts; i++) {
            // Pick random point in ring [innerR, outerR]
            const angle = Math.random() * Math.PI * 2;
            const dist = innerR + Math.random() * (outerR - innerR);
            const c = Math.round(centerC + Math.cos(angle) * dist);
            const r = Math.round(centerR + Math.sin(angle) * dist);

            // Bounds check
            if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
            if (isLocationOnPath(c, r)) continue;
            // Keep rift spawns away from all hardpoint anchors (core + micro).
            if (isGridNearHardpoint(c, r, spawnHardpointBuffer)) continue;

            // Dispersion & Spacing: check distance to ALL points on ALL paths
            let minDist = Infinity;
            let meetsGlobalSpacing = true;

            if (paths.length === 0) {
                minDist = Math.hypot(c - centerC, r - centerR);
            } else {
                for (const path of paths) {
                    for (const pt of path.points) {
                        const d = Math.hypot(c - (pt.x / GRID_SIZE), r - (pt.y / GRID_SIZE));
                        if (d < minDist) minDist = d;
                        // Progressive spacing relaxation lets late-game keep expanding outward.
                        if (minRiftSpacing > 0 && d < minRiftSpacing) {
                            meetsGlobalSpacing = false;
                            break;
                        }
                    }
                    if (!meetsGlobalSpacing) break;
                }
            }

            if (!meetsGlobalSpacing) continue;

            zoneCandidates.push({ c, r, minDist });
        }

        if (zoneCandidates.length > 0) {
            // Pick from top candidates with slight randomness to avoid mechanical ring patterns.
            zoneCandidates.sort((a, b) => b.minDist - a.minDist);
            const topSlice = zoneCandidates.slice(0, Math.min(zoneCandidates.length, 16));
            const pickIndex = Math.floor(Math.pow(Math.random(), 1.15) * topSlice.length);
            const picked = topSlice[Math.max(0, Math.min(topSlice.length - 1, pickIndex))];
            bestStartNode = { c: picked.c, r: picked.r };
            foundZone = zoneIndex;
            break; // Found valid spot in this zone, stop searching higher zones
        }
    }

    if (!bestStartNode && relaxedLevel >= 2) {
        // Emergency fallback for ultra-late map saturation.
        const emergencyAttempts = aggressivePlacement ? 2200 : 1200;
        for (let i = 0; i < emergencyAttempts; i++) {
            const angle = Math.random() * Math.PI * 2;
            const dist = 10 + Math.random() * 48;
            const c = Math.round(centerC + Math.cos(angle) * dist);
            const r = Math.round(centerR + Math.sin(angle) * dist);
            if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
            if (isLocationOnPath(c, r)) continue;
            if (isGridNearHardpoint(c, r, 0.5)) continue;
            bestStartNode = { c, r };
            foundZone = Math.max(1, Math.min(maxZone, Math.floor((dist - ZONE0_RADIUS_CELLS) / 3) + 1));
            break;
        }
    }

    if (!bestStartNode) {
        if (relaxedLevel < 2) {
            return generateNewPath({ ...options, relaxedLevel: relaxedLevel + 1, suppressLogs: true });
        }
        if (!suppressLogs) {
            console.warn("[MISSION FAILED] Orbital Saturation: No valid rift locations found.");
        }
        return false;
    }

    const startNode = bestStartNode;

    // 2. TARGET SELECTION (Merge or Base)
    let targetNode = endNode;
    let mergePathIndex = -1;
    let mergePointIndex = -1;
    let newPathPoints = null;

    // 3. GENERATE PATH
    const obstacles = [];
    const allowedObstacleKeys = new Set();
    for (let i = 0; i < paths.length; i++) {
        for (let pt of paths[i].points) {
            obstacles.push({
                x: Math.floor(pt.x / GRID_SIZE),
                y: Math.floor(pt.y / GRID_SIZE)
            });
        }
    }
    // Hardpoint cells are protected anchors and should not be used by new rift paths.
    for (const hp of hardpoints) {
        obstacles.push({ x: hp.c, y: hp.r });
    }

    const obstacleSet = new Set(obstacles.map(ob => `${ob.x},${ob.y}`));
    const hasOpenApproach = (c, r) => {
        const neighbors = [
            { c: c, r: r - 1 },
            { c: c + 1, r: r },
            { c: c, r: r + 1 },
            { c: c - 1, r: r }
        ];
        for (const n of neighbors) {
            if (n.c < 0 || n.c >= cols || n.r < 0 || n.r >= rows) continue;
            if (!obstacleSet.has(`${n.c},${n.r}`)) return true;
        }
        return false;
    };

    const coreGapSectors = getCoreGapSectors(centerC, centerR);
    const pathGapByIndex = new Array(paths.length).fill(null);
    const gapUsage = new Map();
    for (let i = 0; i < paths.length; i++) {
        const gap = getCoreEntryGapFromPath(paths[i], centerC, centerR, coreGapSectors, ZONE0_RADIUS_CELLS);
        pathGapByIndex[i] = gap;
        if (gap !== null) gapUsage.set(gap, (gapUsage.get(gap) || 0) + 1);
    }
    const startGap = getCoreGapIndexForCell(startNode.c, startNode.r, centerC, centerR, coreGapSectors);
    const startGapUsage = startGap === null ? 0 : (gapUsage.get(startGap) || 0);
    const mustMergeBeforeZone0 = startGap !== null && startGapUsage > 0;

    const uncoveredGaps = coreGapSectors.filter(g => (gapUsage.get(g.index) || 0) === 0).length;
    // Probability of Direct Core Mission: favors merges, but still creates missing inner trunks.
    const baseDirectProb = 0.5 / (foundZone * foundZone); // Zone 1: 50%, Zone 2: 12.5%
    const gapCoverageBoost = uncoveredGaps > 0 ? Math.min(0.45, uncoveredGaps * 0.08) : 0;
    const directProb = mustMergeBeforeZone0 ? 0 : Math.min(0.8, baseDirectProb + gapCoverageBoost);
    const isDirectMission = Math.random() < directProb;

    const minExpansionDist = aggressivePlacement ? 2 : Math.max(3, 6 - (relaxedLevel * 2));
    const collectMergeTargets = (enforceCoreDistance, options = {}) => {
        const requiredGap = options.requiredGap ?? null;
        const preferredGap = options.preferredGap ?? null;
        const requireOutsideZone0 = !!options.requireOutsideZone0;
        const candidates = [];
        for (let i = 0; i < paths.length; i++) {
            const path = paths[i];
            const pathGap = pathGapByIndex[i];
            if (requiredGap !== null && pathGap !== requiredGap) continue;
            for (let j = 0; j < path.points.length; j++) {
                const pt = path.points[j];
                const pc = Math.floor(pt.x / GRID_SIZE);
                const pr = Math.floor(pt.y / GRID_SIZE);

                const dToSpawn = Math.hypot(startNode.c - pc, startNode.r - pr);
                if (dToSpawn < minExpansionDist) continue;

                const dToCore = Math.hypot(pc - centerC, pr - centerR);
                if (requireOutsideZone0 && dToCore < ZONE0_RADIUS_CELLS) continue;
                if (enforceCoreDistance) {
                    if (dToCore < PATHING_RULES.mergeMinCoreDistance) continue;
                }
                if (isGridNearHardpoint(pc, pr, mergeHardpointBuffer)) continue;
                if (!aggressivePlacement && relaxedLevel === 0 && !hasOpenApproach(pc, pr)) continue;

                let score = dToSpawn + Math.random() * 0.9;
                if (preferredGap !== null && pathGap !== preferredGap) score += 4.5;
                if (!pathRespectsZone0Commitment(path.points, centerC, centerR, ZONE0_RADIUS_CELLS, j)) continue;
                candidates.push({ c: pc, r: pr, pathIndex: i, pointIndex: j, score });
            }
        }
        candidates.sort((a, b) => a.score - b.score);
        return candidates.slice(0, aggressivePlacement ? 420 : 240);
    };

    if (!isDirectMission) {
        let mergeCandidates = [];
        if (mustMergeBeforeZone0 && startGap !== null) {
            mergeCandidates = collectMergeTargets(true, {
                requiredGap: startGap,
                requireOutsideZone0: true
            });
            if (mergeCandidates.length === 0) {
                mergeCandidates = collectMergeTargets(false, {
                    requiredGap: startGap,
                    requireOutsideZone0: true
                });
            }
        } else {
            mergeCandidates = collectMergeTargets(true, { preferredGap: startGap });
            if (mergeCandidates.length === 0) mergeCandidates = collectMergeTargets(false, { preferredGap: startGap });
        }

        const mergePathAttempts = Math.min(
            aggressivePlacement ? 320 : (relaxedLevel === 0 ? 100 : (relaxedLevel === 1 ? 180 : 260)),
            mergeCandidates.length
        );
        for (let i = 0; i < mergePathAttempts; i++) {
            const candidate = mergeCandidates[i];
            const localAllowed = new Set([`${candidate.c},${candidate.r}`]);
            const attemptPath = findPathOnGrid(
                startNode,
                { c: candidate.c, r: candidate.r },
                obstacles,
                localAllowed,
                {
                    coreNode: endNode,
                    lockZone0AfterEntry: true,
                    zone0Radius: ZONE0_RADIUS_CELLS
                }
            );
            if (!attemptPath) continue;

            newPathPoints = attemptPath;
            targetNode = { c: candidate.c, r: candidate.r };
            mergePathIndex = candidate.pathIndex;
            mergePointIndex = candidate.pointIndex;
            break;
        }
    }

    if (!newPathPoints && mustMergeBeforeZone0 && startGap !== null) {
        if (relaxedLevel < 2) {
            return generateNewPath({ ...options, relaxedLevel: relaxedLevel + 1, suppressLogs: true });
        }
        if (!suppressLogs) {
            console.warn("[MISSION FAILED] Gap lane occupied; merge-before-zone0 rule blocked direct core route.");
        }
        return false;
    }

    if (!newPathPoints) {
        // Direct mission or fallback: create/extend trunks through hardpoint gaps.
        const coreEntryCandidates = coreGapSectors
            .map(sector => ({
                gapIndex: sector.index,
                c: Math.round(endNode.c + Math.cos(sector.centerAngle) * Math.max(1, ZONE0_RADIUS_CELLS - 1)),
                r: Math.round(endNode.r + Math.sin(sector.centerAngle) * Math.max(1, ZONE0_RADIUS_CELLS - 1))
            }))
            .filter(t => t.c >= 0 && t.c < cols && t.r >= 0 && t.r < rows && !isGridNearHardpoint(t.c, t.r, 0));

        const rankedEntries = coreEntryCandidates
            .map(t => {
                const key = `${t.c},${t.r}`;
                return {
                    ...t,
                    usage: gapUsage.get(t.gapIndex) || 0,
                    startGapMatch: startGap !== null && t.gapIndex === startGap ? 1 : 0,
                    blocked: obstacleSet.has(key) ? 1 : 0,
                    jitter: Math.random() * 0.25
                };
            })
            .sort((a, b) => {
                if (a.startGapMatch !== b.startGapMatch) return b.startGapMatch - a.startGapMatch;
                if (a.usage !== b.usage) return a.usage - b.usage;
                if (a.blocked !== b.blocked) return a.blocked - b.blocked;
                return a.jitter - b.jitter;
            });

        const preferredEntry = rankedEntries.length ? rankedEntries[0] : null;
        const directTarget = preferredEntry ? { c: preferredEntry.c, r: preferredEntry.r } : endNode;
        const localAllowed = new Set(allowedObstacleKeys);
        if (preferredEntry && preferredEntry.blocked) {
            localAllowed.add(`${preferredEntry.c},${preferredEntry.r}`);
        }
        localAllowed.add(`${endNode.c},${endNode.r}`);

        newPathPoints = findPathOnGrid(
            startNode,
            directTarget,
            obstacles,
            localAllowed,
            {
                coreNode: endNode,
                lockZone0AfterEntry: true,
                zone0Radius: ZONE0_RADIUS_CELLS
            }
        );
        if (newPathPoints && (directTarget.c !== endNode.c || directTarget.r !== endNode.r)) {
            const last = newPathPoints[newPathPoints.length - 1];
            const lastC = Math.floor(last.x / GRID_SIZE);
            const lastR = Math.floor(last.y / GRID_SIZE);
            if (lastC !== endNode.c || lastR !== endNode.r) {
                const bridgeAllowed = new Set(localAllowed);
                bridgeAllowed.add(`${lastC},${lastR}`);
                const bridgePath = findPathOnGrid(
                    { c: lastC, r: lastR },
                    endNode,
                    obstacles,
                    bridgeAllowed,
                    {
                        coreNode: endNode,
                        lockZone0AfterEntry: true,
                        zone0Radius: ZONE0_RADIUS_CELLS
                    }
                );
                if (bridgePath && bridgePath.length > 1) {
                    newPathPoints.push(...bridgePath.slice(1));
                } else {
                    newPathPoints = null;
                }
            }
        }

        targetNode = endNode;
        mergePathIndex = -1;
        mergePointIndex = -1;
    }

    if (!newPathPoints) {
        if (relaxedLevel < 2) {
            return generateNewPath({ ...options, relaxedLevel: relaxedLevel + 1, suppressLogs: true });
        }
        if (!suppressLogs) {
            console.warn("[MISSION FAILED] Pathfinder could not connect new rift.");
        }
        return false;
    }

    if (mergePathIndex !== -1) {
        const targetPath = paths[mergePathIndex];
        const continuation = targetPath.points.slice(mergePointIndex + 1);
        newPathPoints.push(...continuation);
    }

    if (!pathRespectsZone0Commitment(newPathPoints, centerC, centerR, ZONE0_RADIUS_CELLS, 0)) {
        if (relaxedLevel < 2) {
            return generateNewPath({ ...options, relaxedLevel: relaxedLevel + 1, suppressLogs: true });
        }
        if (!suppressLogs) {
            console.warn("[MISSION FAILED] Zone 0 commitment rule violated (path exited and re-entered).");
        }
        return false;
    }

    // Safety guard: don't commit paths that overlap themselves.
    const seenCells = new Set();
    let hasSelfOverlap = false;
    for (const p of newPathPoints) {
        const key = `${Math.floor(p.x / GRID_SIZE)},${Math.floor(p.y / GRID_SIZE)}`;
        if (seenCells.has(key)) {
            hasSelfOverlap = true;
            break;
        }
        seenCells.add(key);
    }
    if (hasSelfOverlap) {
        if (relaxedLevel < 2) {
            return generateNewPath({ ...options, relaxedLevel: relaxedLevel + 1, suppressLogs: true });
        }
        if (!suppressLogs) {
            console.warn("[MISSION FAILED] Generated path self-overlap detected. Path discarded.");
        }
        return false;
    }

    paths.push({ points: newPathPoints, level: 1, zone: foundZone });

    // DESTROY TOWERS ON PATH
    for (let i = towers.length - 1; i >= 0; i--) {
        const t = towers[i];
        if (t.hardpointId) continue;
        const tolerance = GRID_SIZE / 2;
        let hit = false;

        for (let j = 0; j < newPathPoints.length - 1; j++) {
            const p1 = newPathPoints[j];
            const p2 = newPathPoints[j + 1];
            if (Math.abs(p1.y - p2.y) < 1) { // Horizontal
                if (Math.abs(t.y - p1.y) < tolerance && t.x >= Math.min(p1.x, p2.x) - tolerance && t.x <= Math.max(p1.x, p2.x) + tolerance) { hit = true; break; }
            } else { // Vertical
                if (Math.abs(t.x - p1.x) < tolerance && t.y >= Math.min(p1.y, p2.y) - tolerance && t.y <= Math.max(p1.y, p2.y) + tolerance) { hit = true; break; }
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
    return true;
}

function findPathOnGrid(start, end, obstacles, allowedObstacleKeys = null, options = {}) {
    const { cols, rows } = getWorldGridSize();

    const startNode = { c: start.c, r: start.r };
    const endNode = { c: end.c, r: end.r };
    const obstacleSet = new Set((obstacles || []).map(ob => `${ob.x},${ob.y}`));
    const allowedSet = allowedObstacleKeys || new Set();
    const coreNode = options.coreNode || null;
    const lockZone0AfterEntry = !!options.lockZone0AfterEntry && !!coreNode;
    const zone0Radius = Number(options.zone0Radius || ZONE0_RADIUS_CELLS);
    const startsInsideZone0 = lockZone0AfterEntry
        ? isCellInsideZone0(startNode.c, startNode.r, coreNode.c, coreNode.r, zone0Radius)
        : false;

    const isInCurrentBranch = (node, c, r) => {
        let cursor = node;
        while (cursor) {
            if (cursor.c === c && cursor.r === r) return true;
            cursor = cursor.parent;
        }
        return false;
    };

    const openSet = [];
    openSet.push({
        c: startNode.c, r: startNode.r, g: 0,
        h: Math.abs(startNode.c - endNode.c) + Math.abs(startNode.r - endNode.r),
        f: Math.abs(startNode.c - endNode.c) + Math.abs(startNode.r - endNode.r),
        parent: null, dir: null, enteredZone0: startsInsideZone0
    });

    const closedSet = new Map();

    while (openSet.length > 0) {
        let bestIndex = 0;
        for (let i = 1; i < openSet.length; i++) {
            if (openSet[i].f < openSet[bestIndex].f) bestIndex = i;
        }
        const current = openSet.splice(bestIndex, 1)[0];

        if (current.c === endNode.c && current.r === endNode.r) {
            const pathPoints = [];
            const uniqueCells = new Set();
            let temp = current;
            while (temp) {
                const key = `${temp.c},${temp.r}`;
                if (uniqueCells.has(key)) return null;
                uniqueCells.add(key);
                pathPoints.unshift({ x: temp.c * GRID_SIZE + GRID_SIZE / 2, y: temp.r * GRID_SIZE + GRID_SIZE / 2 });
                temp = temp.parent;
            }
            return pathPoints;
        }

        const key = `${current.c},${current.r},${current.enteredZone0 ? 1 : 0}`;
        closedSet.set(key, current.g);

        const neighbors = [
            { c: current.c, r: current.r - 1, dc: 0, dr: -1 },
            { c: current.c + 1, r: current.r, dc: 1, dr: 0 },
            { c: current.c, r: current.r + 1, dc: 0, dr: 1 },
            { c: current.c - 1, r: current.r, dc: -1, dr: 0 }
        ];

        for (const n of neighbors) {
            if (n.c >= 0 && n.c < cols && n.r >= 0 && n.r < rows) {
                const nKey = `${n.c},${n.r}`;
                // Hard block occupied tiles: no path crossing. Merge is allowed only at approved cells.
                if (obstacleSet.has(nKey) && !allowedSet.has(nKey)) continue;
                // Prevent branch loops/folding over itself while searching.
                if (isInCurrentBranch(current, n.c, n.r)) continue;

                const nextInsideZone0 = lockZone0AfterEntry
                    ? isCellInsideZone0(n.c, n.r, coreNode.c, coreNode.r, zone0Radius)
                    : false;
                const nextEnteredZone0 = lockZone0AfterEntry
                    ? (current.enteredZone0 || nextInsideZone0)
                    : false;
                // Once route enters Zone 0, it cannot step back outside.
                if (lockZone0AfterEntry && current.enteredZone0 && !nextInsideZone0) continue;

                let cost = 1;
                const isTurning = current.dir && (current.dir.dc !== n.dc || current.dir.dr !== n.dr);
                if (isTurning) {
                    cost += 5; // Reduced baseline turn penalty for better map coverage
                }

                const distToCore = Math.hypot(n.c - endNode.c, n.r - endNode.r);
                if (isTurning && distToCore < PATHING_RULES.nearCoreStraightRadius) {
                    const turnBias = 1 - (distToCore / PATHING_RULES.nearCoreStraightRadius);
                    cost += PATHING_RULES.nearCoreTurnPenaltyBoost * turnBias;
                }
                cost += getCoreRepulsionPenalty(n.c, n.r, endNode);

                const g = current.g + cost;
                const nStateKey = `${n.c},${n.r},${nextEnteredZone0 ? 1 : 0}`;
                if (closedSet.has(nStateKey) && closedSet.get(nStateKey) <= g) continue;

                let inOpen = false;
                for (const node of openSet) {
                    if (node.c === n.c && node.r === n.r && node.enteredZone0 === nextEnteredZone0) {
                        if (node.g > g) {
                            node.g = g;
                            node.f = g + node.h;
                            node.parent = current;
                            node.dir = { dc: n.dc, dr: n.dr };
                            node.enteredZone0 = nextEnteredZone0;
                        }
                        inOpen = true; break;
                    }
                }

                if (!inOpen) {
                    const h = Math.abs(n.c - endNode.c) + Math.abs(n.r - endNode.r);
                    openSet.push({
                        c: n.c,
                        r: n.r,
                        g: g,
                        h: h,
                        f: g + h,
                        parent: current,
                        dir: { dc: n.dc, dr: n.dr },
                        enteredZone0: nextEnteredZone0
                    });
                }
            }
        }
    }
    return null;
}

window.selectTower = function (type) {
    if (buildTarget) {
        selectedTowerType = type;
        const createdTower = buildTower(buildTarget.x, buildTarget.y);
        if (createdTower) {
            // Tutorial Step Advance
            if (tutorialActive && tutorialStep === 3) {
                nextTutorialStep();
            }
        }
        return;
    }
    selectedTowerType = type;
    selectedPlacedTower = null;
    selectedBase = false;
    document.querySelectorAll('.tower-selector').forEach(el => el.classList.remove('selected'));
    const targetEl = document.querySelector(`.tower-selector[data-type="${type}"]`);
    if (targetEl) targetEl.classList.add('selected');
};

function selectPlacedTower(tower) {
    selectedPlacedTower = tower;
    selectedTowerType = null;
    selectedBase = false;
    document.querySelectorAll('.tower-selector').forEach(el => el.classList.remove('selected'));
    updateSelectionUI();
    maybeShowTowerHint();
}

window.deselectTower = function () {
    selectedTowerType = null;
    selectedPlacedTower = null;
    selectedBase = false;
    selectedRift = null;
    targetingAbility = null;
    buildTarget = null;
    document.querySelectorAll('.tower-selector').forEach(el => el.classList.remove('selected'));
    document.getElementById('controls-bar')?.classList.add('hidden');
    document.getElementById('selection-panel')?.classList.add('hidden');
    updateUI();
    updateSelectionUI();
};

window.upgradeTower = function () {
    if (!selectedPlacedTower) return;
    const cost = getUpgradeCost(selectedPlacedTower);
    if (money >= cost) {
        money -= cost;
        selectedPlacedTower.level++;
        selectedPlacedTower.damage *= 1.2;
        selectedPlacedTower.range = Math.min(selectedPlacedTower.range * 1.1, MAX_TOWER_RANGE);
        selectedPlacedTower.totalCost = (selectedPlacedTower.totalCost || (selectedPlacedTower.cost * (selectedPlacedTower.level - 1))) + cost;
        createParticles(selectedPlacedTower.x, selectedPlacedTower.y, '#00ff41', 15);
        updateSelectionUI();
        updateUI();
        saveGame();
    }
};

window.sellTower = function () {
    if (!selectedPlacedTower) return;
    const refund = Math.floor((selectedPlacedTower.totalCost || selectedPlacedTower.cost) * 0.7);
    money += refund;
    const index = towers.indexOf(selectedPlacedTower);
    if (index > -1) {
        towers.splice(index, 1);
        markArcNetworkDirty();
    }
    createParticles(selectedPlacedTower.x, selectedPlacedTower.y, '#ffffff', 10);
    deselectTower();
    updateUI();
    saveGame();
};

function getUpgradeCost(tower) {
    return Math.floor(tower.cost * 0.5 * tower.level);
}

function getSelectionAnchorWorldPos() {
    if (selectedRift && selectedRift.points && selectedRift.points.length > 0) {
        return selectedRift.points[0];
    }

    if (selectedBase) {
        if (paths.length > 0 && paths[0].points.length > 0) {
            const basePoint = paths[0].points[paths[0].points.length - 1];
            return { x: basePoint.x, y: basePoint.y };
        }

        const { cols, rows } = getWorldGridSize();
        return {
            x: Math.floor(cols / 2) * GRID_SIZE + GRID_SIZE / 2,
            y: Math.floor(rows / 2) * GRID_SIZE + GRID_SIZE / 2
        };
    }

    if (selectedPlacedTower) {
        return { x: selectedPlacedTower.x, y: selectedPlacedTower.y };
    }

    return null;
}

function positionSelectionPanel(panel = document.getElementById('selection-panel')) {
    if (!panel || panel.classList.contains('hidden')) return;

    const anchor = getSelectionAnchorWorldPos();
    if (!anchor) return;

    const screenX = anchor.x * camera.zoom + camera.x;
    const screenY = anchor.y * camera.zoom + camera.y;

    const panelWidth = panel.offsetWidth || 220;
    const panelHeight = panel.offsetHeight || 300;
    const compactLayout = window.innerWidth <= 768;
    const edgePadding = 12;

    const offsetX = compactLayout ? 20 : 50;
    const offsetY = compactLayout ? -Math.max(70, panelHeight * 0.35) : -100;

    const maxLeft = Math.max(edgePadding, window.innerWidth - panelWidth - edgePadding);
    const maxTop = Math.max(edgePadding, window.innerHeight - panelHeight - edgePadding);

    const clampedLeft = Math.min(maxLeft, Math.max(edgePadding, screenX + offsetX));
    const clampedTop = Math.min(maxTop, Math.max(edgePadding, screenY + offsetY));

    panel.style.left = clampedLeft + 'px';
    panel.style.top = clampedTop + 'px';
    panel.style.bottom = 'auto';
    panel.style.right = 'auto';
    panel.style.marginRight = '0';
    panel.style.transform = 'none';
}

function updateSelectionUI() {
    const panel = document.getElementById('selection-panel');

    if (selectedRift) {
        const tier = selectedRift.level || 1;
        const mutation = selectedRift.mutation;

        let hpMulti = (1 + (tier - 1) * 0.5);
        let speedMulti = (1 + (tier - 1) * 0.15);
        let rewardMulti = (1 + (tier - 1) * 0.5);

        if (mutation) {
            hpMulti *= mutation.hpMulti;
            speedMulti *= mutation.speedMulti;
            rewardMulti *= mutation.rewardMulti;
        }

        panel.classList.remove('hidden');
        panel.innerHTML = `
            <h3>RIFT INTEL</h3>
            <div style="margin-bottom: 8px; font-size: 0.9rem; color: #aaa;">Sector Threat Profile</div>
            
            ${mutation ? `
                <div style="background: ${mutation.color}33; border: 1px solid ${mutation.color}; padding: 8px; border-radius: 4px; margin-bottom: 10px;">
                    <div style="font-size: 0.7rem; color: ${mutation.color}; font-weight: bold;">[ MUTATION DETECTED ]</div>
                    <div style="font-size: 1.1rem; color: #fff;">${mutation.name} VORTEX</div>
                </div>
            ` : ''}

            <div class="stats">Tier: <span class="highlight" style="color: var(--neon-pink)">T${tier}</span></div>
            <div class="stat-row"><span>HP Multiplier</span> <span style="color: var(--neon-pink)">x${hpMulti.toFixed(1)}</span></div>
            <div class="stat-row"><span>Speed Multi</span> <span style="color: var(--neon-pink)">x${speedMulti.toFixed(2)}</span></div>
            <div class="stat-row"><span>Cash Reward</span> <span style="color: var(--neon-pink)">x${rewardMulti.toFixed(1)}</span></div>
            
            <p style="font-size: 0.8rem; color: #888; margin-top: 15px; border-top: 1px solid #333; padding-top: 10px;">
                All anomalies from this rift inherit these veteran multipliers.
            </p>
            <div class="actions" style="margin-top: 10px;">
                <button class="action-btn close" onclick="deselectTower()" style="width: 100%;">CLOSE DISPATCH</button>
            </div>
        `;
        positionSelectionPanel(panel);
        return;
    }

    if (selectedBase) {
        panel.classList.remove('hidden');
        panel.innerHTML = `
            <h3>HOME</h3>
            <div style="margin-bottom: 8px; font-size: 0.9rem; color: #aaa;">The Heart of Defense</div>
            <div class="stats">Level: <span class="highlight">${baseLevel}/10</span></div>
            ${baseLevel > 0 ? `
                <div class="stat-row"><span>Damage</span> <span>${baseDamage + (baseLevel - 1) * 10}</span></div>
                <div class="stat-row"><span>Range</span> <span>${baseRange + (baseLevel - 1) * 30}</span></div>
            ` : ''}
            
            <hr style="border: 0; border-top: 1px solid #444; margin: 10px 0;">
            
            <div class="actions">
                <!-- Repair -->
                <button onclick="repairBase()" class="action-btn" style="background: rgba(0, 255, 65, 0.2); border: 1px solid #00ff41; color: #00ff41; width: 100%; margin-bottom: 5px;">
                    REPAIR (+1 Life) <span style="float:right;">$${getRepairCost()}</span>
                </button>
                
                <!-- Upgrade -->
                ${baseLevel < 10 ? `
                <button onclick="upgradeBase()" class="action-btn" style="background: rgba(0, 243, 255, 0.2); border: 1px solid #00f3ff; color: #00f3ff; width: 100%;">
                    ${baseLevel === 0 ? 'INSTALL TURRET' : 'UPGRADE TURRET'} <span style="float:right;">$${200 * (baseLevel + 1)}</span>
                </button>
                ` : '<div style="color: #666; text-align: center; margin-top: 5px;">MAX LEVEL</div>'}

                <button class="action-btn close" onclick="deselectTower()" style="margin-top: 10px;">X</button>
            </div>
        `;
        positionSelectionPanel(panel);
        return;
    }

    if (!selectedPlacedTower) {
        panel.classList.add('hidden');
        return;
    }

    // --- Render Tower Selection UI ---
    const t = selectedPlacedTower;
    const upgradeCost = getUpgradeCost(t);
    const refund = Math.floor((t.totalCost || t.cost) * 0.7);
    const hardpointLabel = t.hardpointType === 'core' ? 'CORE HARDPOINT' : (t.hardpointType === 'micro' ? 'MICRO HARDPOINT' : null);
    const arcBonus = Math.max(1, Math.min(ARC_TOWER_RULES.maxBonus, t.arcNetworkBonus || 1));
    const arcChain = ARC_TOWER_RULES.baseChainTargets;

    panel.classList.remove('hidden');
    panel.innerHTML = `
        <div id="selected-stats">
            <h3>TOWER INFO</h3>
            <div id="sel-type">Type: ${t.type.toUpperCase()}</div>
            <div id="sel-level">Level: ${t.level}</div>
            <div id="sel-damage">Damage: ${Math.floor(t.damage)}</div>
            <div id="sel-range">Range: ${Math.floor(t.range)}</div>
            ${t.type === 'arc' ? `<div id="sel-arc-bonus">Arc Link Bonus: x${arcBonus}</div>` : ''}
            ${t.type === 'arc' ? `<div id="sel-arc-static">Direct Static: +${arcBonus} charge(s)</div>` : ''}
            ${t.type === 'arc' ? `<div id="sel-arc-chain">Chain Targets: ${arcChain} bounce(s)</div>` : ''}
            ${hardpointLabel ? `<div id="sel-slot">Mount: ${hardpointLabel}</div>` : ''}
        </div>
        <div class="actions">
            <button class="action-btn upgrade" onclick="upgradeTower()">
                UPGRADE <span>($${upgradeCost})</span>
            </button>
            <button class="action-btn sell" onclick="sellTower()">
                SELL <span>($${refund})</span>
            </button>
            <button class="action-btn close" onclick="deselectTower()">X</button>
        </div>
    `;
    positionSelectionPanel(panel);
}

function isValidPlacement(x, y, towerConfig) {
    const snap = snapToGrid(x, y);
    const hardpoint = getHardpointAtWorld(snap.x, snap.y);

    // Check UI bounds (approximate) - don't place under controls
    // These are world coordinates, so need to convert UI bounds to world
    const uiTopWorldY = screenToWorld(0, 60).y;
    const uiBottomWorldY = screenToWorld(0, height - 100).y;

    if (snap.y > uiBottomWorldY || snap.y < uiTopWorldY) return { valid: false, reason: 'ui', snap: snap, hardpoint: hardpoint };

    // Check cost
    if (money < towerConfig.cost) return { valid: false, reason: 'cost', snap: snap, hardpoint: hardpoint };

    // Check collision with path
    // Since everything is grid based, we can just check if the point intersects the path segments with a box check
    const tolerance = GRID_SIZE / 2; // Exact hit

    if (!hardpoint) {
        for (const rift of paths) {
            const path = rift.points;
            for (let i = 0; i < path.length - 1; i++) {
                const p1 = path[i];
                const p2 = path[i + 1];

                // Horizontal segment
                if (Math.abs(p1.y - p2.y) < 1) {
                    if (Math.abs(snap.y - p1.y) < tolerance &&
                        snap.x >= Math.min(p1.x, p2.x) - tolerance &&
                        snap.x <= Math.max(p1.x, p2.x) + tolerance) {
                        return { valid: false, reason: 'path', snap: snap, hardpoint: hardpoint };
                    }
                }
                // Vertical segment
                else {
                    if (Math.abs(snap.x - p1.x) < tolerance &&
                        snap.y >= Math.min(p1.y, p2.y) - tolerance &&
                        snap.y <= Math.max(p1.y, p2.y) + tolerance) {
                        return { valid: false, reason: 'path', snap: snap, hardpoint: hardpoint };
                    }
                }
            }
        }
    }

    // Check collision with other towers (grid based equality)
    for (let t of towers) {
        if (Math.abs(t.x - snap.x) < 1 && Math.abs(t.y - snap.y) < 1) {
            return { valid: false, reason: 'tower', snap: snap, hardpoint: hardpoint };
        }
    }

    return { valid: true, snap: snap, hardpoint: hardpoint };
}

function buildTower(worldX, worldY) {
    if (gameState !== 'playing') return null;

    if (selectedTowerType) {
        const towerConfig = TOWERS[selectedTowerType];
        const validation = isValidPlacement(worldX, worldY, towerConfig);

        if (!validation.valid) {
            if (validation.reason === 'path' || validation.reason === 'tower') {
                createParticles(validation.snap ? validation.snap.x : worldX, validation.snap ? validation.snap.y : worldY, '#ff0000', 5);
            }
            return null;
        }

        const selectedHardpoint = validation.hardpoint || null;
        let hardpointRules = null;
        if (selectedHardpoint) {
            hardpointRules = selectedHardpoint.type === 'core' ? HARDPOINT_RULES.core : HARDPOINT_RULES.micro;
        }

        const maxCooldown = hardpointRules
            ? Math.max(4, towerConfig.cooldown * hardpointRules.cooldownMult)
            : towerConfig.cooldown;

        // Place tower
        money -= towerConfig.cost;
        const newTower = {
            x: validation.snap.x,
            y: validation.snap.y,
            ...towerConfig,
            level: 1,
            arcNetworkBonus: selectedTowerType === 'arc' ? 1 : undefined,
            arcNetworkSize: selectedTowerType === 'arc' ? 1 : undefined,
            totalCost: towerConfig.cost,
            cooldown: 0, // Current cooldown
            maxCooldown: maxCooldown, // Store original cooldown as max
            damage: towerConfig.damage * (hardpointRules ? hardpointRules.damageMult : 1),
            range: towerConfig.range * (hardpointRules ? hardpointRules.rangeMult : 1),
            hardpointId: selectedHardpoint ? selectedHardpoint.id : null,
            hardpointType: selectedHardpoint ? selectedHardpoint.type : null,
            hardpointScale: hardpointRules ? hardpointRules.sizeScale : 1
        };
        towers.push(newTower);
        markArcNetworkDirty();

        // Quick flow: keep the newly built tower selected for instant upgrades.
        buildTarget = null;
        selectPlacedTower(newTower);

        createParticles(validation.snap.x, validation.snap.y, towerConfig.color, 5);
        updateUI();
        saveGame(); // Save on build
        return newTower;
    }
    return null;
}

