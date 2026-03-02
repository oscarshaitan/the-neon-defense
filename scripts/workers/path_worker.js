/**
 * path_worker.js — Web Worker for rift/path generation.
 *
 * Self-contained: no DOM, no canvas, no shared globals.
 * Receives a batch request, generates paths one-by-one, posts each result
 * back as it is completed so the main thread can apply side-effects
 * (tower destruction, UI update) incrementally.
 *
 * Message protocol (Main → Worker):
 *   { type: 'generate_batch', state: {
 *       cols, rows, wave, gridSize, zone0Radius, pathingRules,
 *       paths: [{ points: [{x,y}], zone }],
 *       hardpoints: [{ c, r, type }],
 *       count,        // how many rifts to generate
 *       maxAttempts   // hard ceiling on total attempts
 *   }}
 *
 * Message protocol (Worker → Main):
 *   { type: 'path_ready', newPathPoints: [{x,y}], foundZone: N }
 *   { type: 'batch_done', generated: N, remaining: N }
 */

'use strict';

self.onmessage = function (e) {
    const msg = e.data;
    if (msg.type !== 'generate_batch') return;
    runBatch(msg.state);
};

// ---------------------------------------------------------------------------
// Batch runner
// ---------------------------------------------------------------------------

function runBatch(state) {
    const { cols, rows, wave, gridSize, zone0Radius, pathingRules, hardpoints,
        count, maxAttempts } = state;

    // Deep-copy paths so we can mutate our working set as we add new rifts.
    const paths = state.paths.map(p => ({
        points: p.points.map(pt => ({ x: pt.x, y: pt.y })),
        zone: p.zone || 1
    }));

    let remaining = count;
    let attempts = 0;
    let failStreak = 0;
    let generated = 0;

    const ctx = { cols, rows, wave, gridSize, zone0Radius, pathingRules, paths, hardpoints };

    while (remaining > 0 && attempts < maxAttempts) {
        // Mirror the failStreak thresholds from startPrepPhase / resetGame.
        const relaxedLevel = failStreak >= 9 ? 2 : (failStreak >= 3 ? 1 : 0);
        const aggressivePlacement = failStreak >= 14;

        const result = generateOneRift(ctx, relaxedLevel, aggressivePlacement);

        if (result) {
            paths.push({ points: result.newPathPoints, zone: result.foundZone });
            self.postMessage({ type: 'path_ready', newPathPoints: result.newPathPoints, foundZone: result.foundZone });
            remaining--;
            generated++;
            failStreak = 0;
        } else {
            failStreak++;
        }
        attempts++;
    }

    self.postMessage({ type: 'batch_done', generated, remaining });
}

// ---------------------------------------------------------------------------
// Core generation — tries relaxedLevel 0→2 then aggressivePlacement, mirrors
// the original generateNewPath recursion but without side-effects.
// ---------------------------------------------------------------------------

function generateOneRift(ctx, startRelaxedLevel, startAggressive) {
    // Try progressively relaxed levels (mirrors original recursive retry).
    for (let rl = startRelaxedLevel; rl <= 2; rl++) {
        const result = tryGenerateAtLevel(ctx, rl, startAggressive);
        if (result) return result;
    }
    // Last-ditch: aggressivePlacement if not already set.
    if (!startAggressive) {
        const result = tryGenerateAtLevel(ctx, 2, true);
        if (result) return result;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Single attempt at a specific relaxedLevel — pure computation, no side-effects.
// Returns { newPathPoints, foundZone } or null.
// ---------------------------------------------------------------------------

function tryGenerateAtLevel(ctx, relaxedLevel, aggressivePlacement) {
    const { cols, rows, wave, gridSize, zone0Radius, pathingRules, paths, hardpoints } = ctx;

    // Resolve center (end node = base/core).
    let centerC = Math.floor(cols / 2);
    let centerR = Math.floor(rows / 2);
    if (paths.length > 0 && paths[0].points.length > 0) {
        const p = paths[0].points;
        const base = p[p.length - 1];
        centerC = Math.floor(base.x / gridSize);
        centerR = Math.floor(base.y / gridSize);
    }
    const endNode = { c: centerC, r: centerR };

    // Helper: is a grid cell occupied by any existing path?
    const isLocationOnPath = (c, r) => {
        for (const path of paths) {
            for (const p of path.points) {
                if (Math.floor(p.x / gridSize) === c && Math.floor(p.y / gridSize) === r) return true;
            }
        }
        return false;
    };

    // -----------------------------------------------------------------------
    // 1. Pick best candidate start
    // -----------------------------------------------------------------------
    const cornerDistances = [
        Math.hypot(centerC, centerR),
        Math.hypot(cols - 1 - centerC, centerR),
        Math.hypot(centerC, rows - 1 - centerR),
        Math.hypot(cols - 1 - centerC, rows - 1 - centerR)
    ];
    const maxRadiusByMap = Math.max(...cornerDistances);
    const mapZoneCap = Math.max(3, Math.floor((maxRadiusByMap - zone0Radius) / 3));
    const maxZone = Math.max(3, Math.min(15, mapZoneCap));
    const orbitalDensity = 0.62;
    const getOrbitalShellCapacity = z => Math.max(1, Math.round((2 * z * z) * orbitalDensity));

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

    let bestStartNode = null;
    let foundZone = -1;

    for (const zoneIndex of zoneOrder) {
        const zoneRiftCount = zoneCounts[zoneIndex] || 0;
        const zoneCapacity = Math.max(innerZoneTargets[zoneIndex] || 0, getOrbitalShellCapacity(zoneIndex));
        const relaxedExtraCapacity = aggressivePlacement ? 40 : (relaxedLevel === 0 ? 4 : (relaxedLevel === 1 ? 10 : 20));
        if (zoneRiftCount >= (zoneCapacity + relaxedExtraCapacity)) continue;

        const innerR = zone0Radius + (zoneIndex - 1) * 3;
        const outerR = zone0Radius + zoneIndex * 3;
        const zoneCandidates = [];

        for (let i = 0; i < candidateAttempts; i++) {
            const angle = Math.random() * Math.PI * 2;
            const dist = innerR + Math.random() * (outerR - innerR);
            const c = Math.round(centerC + Math.cos(angle) * dist);
            const r = Math.round(centerR + Math.sin(angle) * dist);

            if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
            if (isLocationOnPath(c, r)) continue;
            if (_isGridNearHardpoint(c, r, spawnHardpointBuffer, null, hardpoints)) continue;

            let minDist = Infinity;
            let meetsGlobalSpacing = true;
            if (paths.length === 0) {
                minDist = Math.hypot(c - centerC, r - centerR);
            } else {
                for (const path of paths) {
                    for (const pt of path.points) {
                        const d = Math.hypot(c - (pt.x / gridSize), r - (pt.y / gridSize));
                        if (d < minDist) minDist = d;
                        if (minRiftSpacing > 0 && d < minRiftSpacing) { meetsGlobalSpacing = false; break; }
                    }
                    if (!meetsGlobalSpacing) break;
                }
            }
            if (!meetsGlobalSpacing) continue;
            zoneCandidates.push({ c, r, minDist });
        }

        if (zoneCandidates.length > 0) {
            zoneCandidates.sort((a, b) => b.minDist - a.minDist);
            const topSlice = zoneCandidates.slice(0, Math.min(zoneCandidates.length, 16));
            const pickIndex = Math.floor(Math.pow(Math.random(), 1.15) * topSlice.length);
            const picked = topSlice[Math.max(0, Math.min(topSlice.length - 1, pickIndex))];
            bestStartNode = { c: picked.c, r: picked.r };
            foundZone = zoneIndex;
            break;
        }
    }

    // Emergency fallback at relaxedLevel 2.
    if (!bestStartNode && relaxedLevel >= 2) {
        const emergencyAttempts = aggressivePlacement ? 2200 : 1200;
        for (let i = 0; i < emergencyAttempts; i++) {
            const angle = Math.random() * Math.PI * 2;
            const dist = 10 + Math.random() * 48;
            const c = Math.round(centerC + Math.cos(angle) * dist);
            const r = Math.round(centerR + Math.sin(angle) * dist);
            if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
            if (isLocationOnPath(c, r)) continue;
            if (_isGridNearHardpoint(c, r, 0.5, null, hardpoints)) continue;
            bestStartNode = { c, r };
            foundZone = Math.max(1, Math.min(maxZone, Math.floor((dist - zone0Radius) / 3) + 1));
            break;
        }
    }

    if (!bestStartNode) return null;

    const startNode = bestStartNode;

    // -----------------------------------------------------------------------
    // 2. Build obstacle set and gap data.
    // -----------------------------------------------------------------------
    const obstacles = [];
    for (let i = 0; i < paths.length; i++) {
        for (const pt of paths[i].points) {
            obstacles.push({ x: Math.floor(pt.x / gridSize), y: Math.floor(pt.y / gridSize) });
        }
    }
    for (const hp of hardpoints) obstacles.push({ x: hp.c, y: hp.r });

    const obstacleSet = new Set(obstacles.map(ob => `${ob.x},${ob.y}`));
    const hasOpenApproach = (c, r) => {
        const ns = [{ c, r: r - 1 }, { c: c + 1, r }, { c, r: r + 1 }, { c: c - 1, r }];
        for (const n of ns) {
            if (n.c < 0 || n.c >= cols || n.r < 0 || n.r >= rows) continue;
            if (!obstacleSet.has(`${n.c},${n.r}`)) return true;
        }
        return false;
    };

    const coreGapSectors = _getCoreGapSectors(centerC, centerR, hardpoints);
    const pathGapByIndex = new Array(paths.length).fill(null);
    const gapUsage = new Map();
    for (let i = 0; i < paths.length; i++) {
        const gap = _getCoreEntryGapFromPath(paths[i], centerC, centerR, coreGapSectors, zone0Radius, gridSize);
        pathGapByIndex[i] = gap;
        if (gap !== null) gapUsage.set(gap, (gapUsage.get(gap) || 0) + 1);
    }
    const startGap = _getCoreGapIndexForCell(startNode.c, startNode.r, centerC, centerR, coreGapSectors);
    const startGapUsage = startGap === null ? 0 : (gapUsage.get(startGap) || 0);
    const mustMergeBeforeZone0 = startGap !== null && startGapUsage > 0;
    const uncoveredGaps = coreGapSectors.filter(g => (gapUsage.get(g.index) || 0) === 0).length;

    const baseDirectProb = 0.5 / (foundZone * foundZone);
    const gapCoverageBoost = uncoveredGaps > 0 ? Math.min(0.45, uncoveredGaps * 0.08) : 0;
    const directProb = mustMergeBeforeZone0 ? 0 : Math.min(0.8, baseDirectProb + gapCoverageBoost);
    const isDirectMission = Math.random() < directProb;

    const minExpansionDist = aggressivePlacement ? 2 : Math.max(3, 6 - (relaxedLevel * 2));
    const mergeHardpointBuffer = 0;

    const collectMergeTargets = (enforceCoreDistance, opts = {}) => {
        const requiredGap = opts.requiredGap ?? null;
        const preferredGap = opts.preferredGap ?? null;
        const requireOutsideZone0 = !!opts.requireOutsideZone0;
        const candidates = [];
        for (let i = 0; i < paths.length; i++) {
            const path = paths[i];
            const pathGap = pathGapByIndex[i];
            if (requiredGap !== null && pathGap !== requiredGap) continue;
            for (let j = 0; j < path.points.length; j++) {
                const pt = path.points[j];
                const pc = Math.floor(pt.x / gridSize);
                const pr = Math.floor(pt.y / gridSize);
                const dToSpawn = Math.hypot(startNode.c - pc, startNode.r - pr);
                if (dToSpawn < minExpansionDist) continue;
                const dToCore = Math.hypot(pc - centerC, pr - centerR);
                if (requireOutsideZone0 && dToCore < zone0Radius) continue;
                if (enforceCoreDistance && dToCore < pathingRules.mergeMinCoreDistance) continue;
                if (_isGridNearHardpoint(pc, pr, mergeHardpointBuffer, null, hardpoints)) continue;
                if (!aggressivePlacement && relaxedLevel === 0 && !hasOpenApproach(pc, pr)) continue;
                let score = dToSpawn + Math.random() * 0.9;
                if (preferredGap !== null && pathGap !== preferredGap) score += 4.5;
                if (!_pathRespectsZone0Commitment(path.points, centerC, centerR, zone0Radius, j, gridSize)) continue;
                candidates.push({ c: pc, r: pr, pathIndex: i, pointIndex: j, score });
            }
        }
        candidates.sort((a, b) => a.score - b.score);
        return candidates.slice(0, aggressivePlacement ? 420 : 240);
    };

    // -----------------------------------------------------------------------
    // 3. Attempt merge or direct path.
    // -----------------------------------------------------------------------
    let newPathPoints = null;
    let mergePathIndex = -1;
    let mergePointIndex = -1;

    if (!isDirectMission) {
        let mergeCandidates = [];
        if (mustMergeBeforeZone0 && startGap !== null) {
            mergeCandidates = collectMergeTargets(true, { requiredGap: startGap, requireOutsideZone0: true });
            if (mergeCandidates.length === 0) {
                mergeCandidates = collectMergeTargets(false, { requiredGap: startGap, requireOutsideZone0: true });
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
                startNode, { c: candidate.c, r: candidate.r },
                obstacles, localAllowed,
                { coreNode: endNode, lockZone0AfterEntry: true, zone0Radius, gridSize, cols, rows, pathingRules }
            );
            if (!attemptPath) continue;
            newPathPoints = attemptPath;
            mergePathIndex = candidate.pathIndex;
            mergePointIndex = candidate.pointIndex;
            break;
        }
    }

    if (!newPathPoints && mustMergeBeforeZone0 && startGap !== null) return null;

    if (!newPathPoints) {
        const coreEntryCandidates = coreGapSectors
            .map(sector => ({
                gapIndex: sector.index,
                c: Math.round(endNode.c + Math.cos(sector.centerAngle) * Math.max(1, zone0Radius - 1)),
                r: Math.round(endNode.r + Math.sin(sector.centerAngle) * Math.max(1, zone0Radius - 1))
            }))
            .filter(t => t.c >= 0 && t.c < cols && t.r >= 0 && t.r < rows
                && !_isGridNearHardpoint(t.c, t.r, 0, null, hardpoints));

        const rankedEntries = coreEntryCandidates
            .map(t => ({
                ...t,
                usage: gapUsage.get(t.gapIndex) || 0,
                startGapMatch: startGap !== null && t.gapIndex === startGap ? 1 : 0,
                blocked: obstacleSet.has(`${t.c},${t.r}`) ? 1 : 0,
                jitter: Math.random() * 0.25
            }))
            .sort((a, b) => {
                if (a.startGapMatch !== b.startGapMatch) return b.startGapMatch - a.startGapMatch;
                if (a.usage !== b.usage) return a.usage - b.usage;
                if (a.blocked !== b.blocked) return a.blocked - b.blocked;
                return a.jitter - b.jitter;
            });

        const preferredEntry = rankedEntries.length ? rankedEntries[0] : null;
        const directTarget = preferredEntry ? { c: preferredEntry.c, r: preferredEntry.r } : endNode;
        const localAllowed = new Set();
        if (preferredEntry && preferredEntry.blocked) localAllowed.add(`${preferredEntry.c},${preferredEntry.r}`);
        localAllowed.add(`${endNode.c},${endNode.r}`);

        newPathPoints = findPathOnGrid(
            startNode, directTarget, obstacles, localAllowed,
            { coreNode: endNode, lockZone0AfterEntry: true, zone0Radius, gridSize, cols, rows, pathingRules }
        );
        if (newPathPoints && (directTarget.c !== endNode.c || directTarget.r !== endNode.r)) {
            const last = newPathPoints[newPathPoints.length - 1];
            const lastC = Math.floor(last.x / gridSize);
            const lastR = Math.floor(last.y / gridSize);
            if (lastC !== endNode.c || lastR !== endNode.r) {
                const bridgeAllowed = new Set(localAllowed);
                bridgeAllowed.add(`${lastC},${lastR}`);
                const bridgePath = findPathOnGrid(
                    { c: lastC, r: lastR }, endNode, obstacles, bridgeAllowed,
                    { coreNode: endNode, lockZone0AfterEntry: true, zone0Radius, gridSize, cols, rows, pathingRules }
                );
                if (bridgePath && bridgePath.length > 1) {
                    newPathPoints.push(...bridgePath.slice(1));
                } else {
                    newPathPoints = null;
                }
            }
        }
        mergePathIndex = -1;
        mergePointIndex = -1;
    }

    if (!newPathPoints) return null;

    // Append merge continuation.
    if (mergePathIndex !== -1) {
        const targetPath = paths[mergePathIndex];
        const continuation = targetPath.points.slice(mergePointIndex + 1);
        newPathPoints.push(...continuation);
    }

    // Zone-0 commitment check.
    if (!_pathRespectsZone0Commitment(newPathPoints, centerC, centerR, zone0Radius, 0, gridSize)) return null;

    // Self-overlap check.
    const seenCells = new Set();
    for (const p of newPathPoints) {
        const key = `${Math.floor(p.x / gridSize)},${Math.floor(p.y / gridSize)}`;
        if (seenCells.has(key)) return null;
        seenCells.add(key);
    }

    return { newPathPoints, foundZone };
}

// ---------------------------------------------------------------------------
// A* pathfinder — mirrors findPathOnGrid from 04_tutorial.js exactly.
// Receives all needed data via the opts object instead of globals.
// ---------------------------------------------------------------------------

function findPathOnGrid(start, end, obstacles, allowedObstacleKeys, opts) {
    const { coreNode, lockZone0AfterEntry: lockZone0, zone0Radius, gridSize, cols, rows, pathingRules } = opts;
    const zone0Lock = !!lockZone0 && !!coreNode;

    const obstacleSet = new Set((obstacles || []).map(ob => `${ob.x},${ob.y}`));
    const allowedSet = allowedObstacleKeys || new Set();
    const startsInsideZone0 = zone0Lock
        ? _isCellInsideZone0(start.c, start.r, coreNode.c, coreNode.r, zone0Radius)
        : false;

    const isInCurrentBranch = (node, c, r) => {
        let cursor = node;
        while (cursor) {
            if (cursor.c === c && cursor.r === r) return true;
            cursor = cursor.parent;
        }
        return false;
    };

    const openSet = [{
        c: start.c, r: start.r, g: 0,
        h: Math.abs(start.c - end.c) + Math.abs(start.r - end.r),
        f: Math.abs(start.c - end.c) + Math.abs(start.r - end.r),
        parent: null, dir: null, enteredZone0: startsInsideZone0
    }];
    const closedSet = new Map();

    while (openSet.length > 0) {
        let bestIndex = 0;
        for (let i = 1; i < openSet.length; i++) {
            if (openSet[i].f < openSet[bestIndex].f) bestIndex = i;
        }
        const current = openSet.splice(bestIndex, 1)[0];

        if (current.c === end.c && current.r === end.r) {
            const pathPoints = [];
            const uniqueCells = new Set();
            let temp = current;
            while (temp) {
                const key = `${temp.c},${temp.r}`;
                if (uniqueCells.has(key)) return null;
                uniqueCells.add(key);
                pathPoints.unshift({ x: temp.c * gridSize + gridSize / 2, y: temp.r * gridSize + gridSize / 2 });
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
            if (n.c < 0 || n.c >= cols || n.r < 0 || n.r >= rows) continue;
            const nKey = `${n.c},${n.r}`;
            if (obstacleSet.has(nKey) && !allowedSet.has(nKey)) continue;
            if (isInCurrentBranch(current, n.c, n.r)) continue;

            const nextInsideZone0 = zone0Lock
                ? _isCellInsideZone0(n.c, n.r, coreNode.c, coreNode.r, zone0Radius)
                : false;
            const nextEnteredZone0 = zone0Lock ? (current.enteredZone0 || nextInsideZone0) : false;
            if (zone0Lock && current.enteredZone0 && !nextInsideZone0) continue;

            let cost = 1;
            const isTurning = current.dir && (current.dir.dc !== n.dc || current.dir.dr !== n.dr);
            if (isTurning) cost += 5;

            const distToCore = Math.hypot(n.c - end.c, n.r - end.r);
            if (isTurning && distToCore < pathingRules.nearCoreStraightRadius) {
                const turnBias = 1 - (distToCore / pathingRules.nearCoreStraightRadius);
                cost += pathingRules.nearCoreTurnPenaltyBoost * turnBias;
            }
            cost += _getCoreRepulsionPenalty(n.c, n.r, end, pathingRules);

            const g = current.g + cost;
            const nStateKey = `${n.c},${n.r},${nextEnteredZone0 ? 1 : 0}`;
            if (closedSet.has(nStateKey) && closedSet.get(nStateKey) <= g) continue;

            let inOpen = false;
            for (const node of openSet) {
                if (node.c === n.c && node.r === n.r && node.enteredZone0 === nextEnteredZone0) {
                    if (node.g > g) {
                        node.g = g; node.f = g + node.h; node.parent = current;
                        node.dir = { dc: n.dc, dr: n.dr }; node.enteredZone0 = nextEnteredZone0;
                    }
                    inOpen = true; break;
                }
            }
            if (!inOpen) {
                const h = Math.abs(n.c - end.c) + Math.abs(n.r - end.r);
                openSet.push({ c: n.c, r: n.r, g, h, f: g + h, parent: current, dir: { dc: n.dc, dr: n.dr }, enteredZone0: nextEnteredZone0 });
            }
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// Pure-math helpers (ported from 01_init.js) — all read from explicit args.
// ---------------------------------------------------------------------------

function _isGridNearHardpoint(c, r, radiusCells, hardpointTypes, hardpoints) {
    for (const hp of hardpoints) {
        if (hardpointTypes && !hardpointTypes.includes(hp.type)) continue;
        if (radiusCells <= 0) {
            if (hp.c === c && hp.r === r) return true;
            continue;
        }
        if (Math.hypot(c - hp.c, r - hp.r) <= radiusCells) return true;
    }
    return false;
}

function _getCoreRepulsionPenalty(c, r, endNode, pathingRules) {
    const distToCore = Math.hypot(c - endNode.c, r - endNode.r);
    if (distToCore >= pathingRules.coreRepulsionRadius) return 0;
    const t = 1 - (distToCore / pathingRules.coreRepulsionRadius);
    return pathingRules.coreRepulsionStrength * t * t;
}

function _normalizeAngleRadians(angle) {
    const twoPi = Math.PI * 2;
    let a = angle % twoPi;
    if (a < 0) a += twoPi;
    return a;
}

function _getCoreGapSectors(coreC, coreR, hardpoints) {
    const coreSlots = hardpoints
        .filter(hp => hp.type === 'core')
        .map(hp => ({ angle: _normalizeAngleRadians(Math.atan2(hp.r - coreR, hp.c - coreC)) }))
        .sort((a, b) => a.angle - b.angle);

    if (coreSlots.length < 2) return [];
    const sectors = [];
    for (let i = 0; i < coreSlots.length; i++) {
        const startAngle = coreSlots[i].angle;
        let endAngle = coreSlots[(i + 1) % coreSlots.length].angle;
        if (endAngle <= startAngle) endAngle += Math.PI * 2;
        sectors.push({
            index: i, startAngle, endAngle,
            centerAngle: _normalizeAngleRadians((startAngle + endAngle) / 2)
        });
    }
    return sectors;
}

function _getCoreGapIndexForCell(c, r, coreC, coreR, gapSectors) {
    if (!gapSectors.length) return null;
    if (c === coreC && r === coreR) return null;
    const angle = _normalizeAngleRadians(Math.atan2(r - coreR, c - coreC));
    for (const sector of gapSectors) {
        let testAngle = angle;
        if (testAngle < sector.startAngle) testAngle += Math.PI * 2;
        if (testAngle >= sector.startAngle && testAngle < sector.endAngle) return sector.index;
    }
    return gapSectors[0].index;
}

function _getCoreEntryGapFromPath(path, coreC, coreR, gapSectors, zone0Radius, gridSize) {
    if (!path || !path.points || path.points.length < 2 || !gapSectors.length) return null;
    let entryCell = null;
    for (let i = 1; i < path.points.length; i++) {
        const prev = path.points[i - 1];
        const curr = path.points[i];
        const prevC = Math.floor(prev.x / gridSize);
        const prevR = Math.floor(prev.y / gridSize);
        const currC = Math.floor(curr.x / gridSize);
        const currR = Math.floor(curr.y / gridSize);
        const prevDist = Math.hypot(prevC - coreC, prevR - coreR);
        const currDist = Math.hypot(currC - coreC, currR - coreR);
        if (prevDist >= zone0Radius && currDist < zone0Radius) {
            entryCell = { c: prevC, r: prevR };
            break;
        }
    }
    if (!entryCell) {
        const beforeCore = path.points[path.points.length - 2];
        entryCell = { c: Math.floor(beforeCore.x / gridSize), r: Math.floor(beforeCore.y / gridSize) };
    }
    return _getCoreGapIndexForCell(entryCell.c, entryCell.r, coreC, coreR, gapSectors);
}

function _isCellInsideZone0(c, r, coreC, coreR, zone0Radius) {
    return Math.hypot(c - coreC, r - coreR) < zone0Radius;
}

function _pathRespectsZone0Commitment(points, coreC, coreR, zone0Radius, startIndex, gridSize) {
    if (!points || !points.length) return true;
    let enteredZone0 = false;
    for (let i = Math.max(0, startIndex); i < points.length; i++) {
        const c = Math.floor(points[i].x / gridSize);
        const r = Math.floor(points[i].y / gridSize);
        const inside = _isCellInsideZone0(c, r, coreC, coreR, zone0Radius);
        if (inside) { enteredZone0 = true; }
        else if (enteredZone0) { return false; }
    }
    return true;
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
    return 1 + scheduled;
}
