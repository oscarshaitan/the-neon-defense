// --- Initialization ---
AudioEngine.loadSettings();
window.onload = () => {
    canvas = document.getElementById('gameCanvas');
    ctx = canvas.getContext('2d');

    resize();
    window.addEventListener('resize', resize);

    setupInput();
    calculatePath();

    // Check for save
    if (localStorage.getItem('neonDefenseSave')) {
        document.getElementById('start-screen').innerHTML = `
            <h1>THE NEON DEFENSE</h1>
            <p>SAVE DATA FOUND</p>
            <button onclick="loadGame()">CONTINUE</button>
            <br><br>
            <button style="font-size: 0.8rem; padding: 10px;" onclick="fullReset()">NEW GAME</button>
        `;
    }

    // Init Audio UI from saved settings
    AudioEngine.updateSoundUI();
    updatePerformanceUI();
    setCommandCenterAccess(localStorage.getItem(DEBUG_UNLOCK_KEY) === 'true');

    // Hotkeys
    window.addEventListener('keydown', (e) => {
        if (gameState !== 'playing') return;

        // Init audio on first interaction
        AudioEngine.init();

        const buildPanel = document.getElementById('controls-bar');
        const selectionPanel = document.getElementById('selection-panel');
        const buildVisible = buildPanel && !buildPanel.classList.contains('hidden');
        const selectionVisible = selectionPanel && !selectionPanel.classList.contains('hidden');

        switch (e.key.toLowerCase()) {
            case 'q':
                if (buildVisible) selectTower('basic');
                break;
            case 'w':
                if (buildVisible) selectTower('rapid');
                break;
            case 'e':
                if (buildVisible) selectTower('sniper');
                break;
            case 'r':
                if (buildVisible) selectTower('arc');
                break;
            case 'u':
                if (selectionVisible && selectedPlacedTower) upgradeTower();
                break;
            case 'backspace':
            case 'delete':
                if (selectionVisible && selectedPlacedTower) sellTower();
                break;
            case 'escape':
                if (selectedPlacedTower || buildTarget || selectedBase || selectedRift || targetingAbility || selectedTowerType) deselectTower();
                else togglePause();
                break;
        }
    });

    // Pre-warm effect pools before first frame so heavy combat never hits the {} fallback
    prewarmEffectPools();

    // Start Loop
    requestAnimationFrame(gameLoop);
};

function setupInput() {
    const MOUSE_DRAG_THRESHOLD = 8;
    const TOUCH_DRAG_THRESHOLD = 8;
    let mouseDragDistance = 0;

    // Mouse Down (Start Drag)
    canvas.addEventListener('mousedown', (e) => {
        if (e.button === 0) { // Left click
            // Check if clicking a tower (selection) vs dragging background
            // We'll treat it as a drag candidate, if they don't move much, it's a click
            isDragging = true;
            lastMouseX = e.clientX;
            lastMouseY = e.clientY;
            mouseDragDistance = 0;
        }
    });

    // Mouse Move (Pan & Hover)
    canvas.addEventListener('mousemove', (e) => {
        const rect = canvas.getBoundingClientRect();
        const rawMouseX = e.clientX - rect.left;
        const rawMouseY = e.clientY - rect.top;

        // Pan
        if (isDragging) {
            const dx = e.clientX - lastMouseX;
            const dy = e.clientY - lastMouseY;
            camera.x += dx;
            camera.y += dy;
            mouseDragDistance += Math.hypot(dx, dy);
            lastMouseX = e.clientX;
            lastMouseY = e.clientY;
            maybeShowCameraHint();
        }

        // Apply Camera Transform to Mouse for Logic
        const worldPos = screenToWorld(rawMouseX, rawMouseY);
        mouseX = worldPos.x;
        mouseY = worldPos.y;

        // Update isHovering based on raw mouse being on canvas
        isHovering = true;
    });

    // Mouse Up (End Drag & Handle Click)
    canvas.addEventListener('mouseup', (e) => {
        if (e.button === 0) {
            isDragging = false;
            if (mouseDragDistance <= MOUSE_DRAG_THRESHOLD) {
                handleClick();
            }
            mouseDragDistance = 0;
        }
    });

    // Mouse Leave
    canvas.addEventListener('mouseleave', () => {
        isDragging = false;
        isHovering = false;
        selectedTowerType = null; // Hide ghost
    });

    // Wheel (Zoom)
    canvas.addEventListener('wheel', (e) => {
        e.preventDefault();

        const zoomSpeed = 0.1;
        const direction = e.deltaY > 0 ? -1 : 1;
        let newZoom = camera.zoom + (direction * zoomSpeed);

        // Clamp
        newZoom = Math.max(0.1, Math.min(newZoom, 1.0));

        // Zoom towards mouse pointer logic
        const rect = canvas.getBoundingClientRect();
        const rawMouseX = e.clientX - rect.left;
        const rawMouseY = e.clientY - rect.top;

        // World pos before zoom
        const worldX = (rawMouseX - camera.x) / camera.zoom;
        const worldY = (rawMouseY - camera.y) / camera.zoom;

        // Update zoom
        camera.zoom = newZoom;

        // Calculate new camera.x/y such that worldPos matches rawMousePos
        // rawMouseX = worldX * newZoom + newCameraX
        // newCameraX = rawMouseX - (worldX * newZoom)
        camera.x = rawMouseX - (worldX * newZoom);
        camera.y = rawMouseY - (worldY * newZoom);
        maybeShowCameraHint();

    }, { passive: false });

    // Touch support (Pan & Tap & Pinch Zoom)
    let touchStartX = 0;
    let touchStartY = 0;
    let touchDragDistance = 0;
    let isTouchDragging = false;
    let initialPinchDist = null;
    let lastZoom = 1;

    canvas.addEventListener('touchstart', (e) => {
        if (e.touches.length === 1) {
            e.preventDefault(); // Prevent scrolling/zooming
            const touch = e.touches[0];
            touchStartX = touch.clientX;
            touchStartY = touch.clientY;
            touchDragDistance = 0;
            isTouchDragging = false;

            // Sync mouse pos for hover effects
            const rect = canvas.getBoundingClientRect();
            const rawX = touchStartX - rect.left;
            const rawY = touchStartY - rect.top;
            const worldPos = screenToWorld(rawX, rawY);
            mouseX = worldPos.x;
            mouseY = worldPos.y;
            isHovering = true;
        } else if (e.touches.length === 2) {
            e.preventDefault();
            const t1 = e.touches[0];
            const t2 = e.touches[1];
            initialPinchDist = Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY);
            lastZoom = camera.zoom;
        }
    }, { passive: false });

    canvas.addEventListener('touchmove', (e) => {
        e.preventDefault();
        if (e.touches.length === 1) {
            const touch = e.touches[0];
            const dx = touch.clientX - touchStartX;
            const dy = touch.clientY - touchStartY;
            touchDragDistance += Math.hypot(dx, dy);

            if (isTouchDragging || touchDragDistance > TOUCH_DRAG_THRESHOLD) {
                isTouchDragging = true;
                camera.x += dx;
                camera.y += dy;
                maybeShowCameraHint();
            }
            touchStartX = touch.clientX;
            touchStartY = touch.clientY;
        } else if (e.touches.length === 2 && initialPinchDist) {
            const t1 = e.touches[0];
            const t2 = e.touches[1];
            const currentDist = Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY);

            if (currentDist > 0) {
                const scale = currentDist / initialPinchDist;
                let newZoom = lastZoom * scale;
                newZoom = Math.max(0.1, Math.min(newZoom, 1.0));

                // Zoom center logic could be added here (complex), for now center screen zoom or just zoom
                // To zoom at center of pinch:
                // 1. Get midpoint
                const midX = (t1.clientX + t2.clientX) / 2;
                const midY = (t1.clientY + t2.clientY) / 2;
                const rect = canvas.getBoundingClientRect();
                const rawMidX = midX - rect.left;
                const rawMidY = midY - rect.top;

                // Similar to wheel zoom logic
                const worldX = (rawMidX - camera.x) / camera.zoom;
                const worldY = (rawMidY - camera.y) / camera.zoom;

                camera.zoom = newZoom;

                camera.x = rawMidX - (worldX * newZoom);
                camera.y = rawMidY - (worldY * newZoom);
                maybeShowCameraHint();
            }
        }
    }, { passive: false });

    canvas.addEventListener('touchend', (e) => {
        e.preventDefault();
        if (e.touches.length < 2) {
            initialPinchDist = null;
        }
        if (e.touches.length === 0) {
            if (!isTouchDragging && !initialPinchDist) { // Only click if not dragging and not finishing a pinch
                handleClick();
            }
            isHovering = false; // Stop hovering after touch ends
            isTouchDragging = false;
            touchDragDistance = 0;
        }
    }, { passive: false });

    // Keydown for hotkeys
    window.addEventListener('keydown', (e) => {
        if (e.key === '1') activateAbility('emp');
        if (e.key === '2') activateAbility('overclock');
    });
}

function screenToWorld(screenX, screenY) {
    return {
        x: (screenX - camera.x) / camera.zoom,
        y: (screenY - camera.y) / camera.zoom
    };
}

function handleClick() {
    if (gameState !== 'playing' || isPaused) return;

    // --- Ability Targeting Integration ---
    if (targetingAbility) {
        if (targetingAbility === 'overclock') {
            // Must target a tower
            let targetTower = null;
            for (let t of towers) {
                if (Math.hypot(t.x - mouseX, t.y - mouseY) < 20) {
                    targetTower = t;
                    break;
                }
            }
            if (targetTower) {
                useAbility('overclock', targetTower);
                return;
            }
        } else if (targetingAbility === 'emp') {
            // Target ground
            useAbility('emp', { x: mouseX, y: mouseY });
            return;
        }
        // If we clicked empty space while targeting, we don't necessarily want to cancel immediately?
        // Actually, let's treat it as a cancel if they clicked far away or just keep targeting.
        // For now, let's allow "right-click to cancel" logic in input setup, and keep targeting here.
    }

    // Check interaction with towers
    // Check if clicked ON a placed tower to select it
    let clickedTower = null;
    for (let t of towers) {
        // Simple circle check
        const dist = Math.hypot(t.x - mouseX, t.y - mouseY);
        if (dist < 20) { // Approx radius
            clickedTower = t;
            break;
        }
    }

    if (clickedTower) {
        selectPlacedTower(clickedTower);
        return;
    }

    // Check interaction with RIFTS (Spawns)
    let clickedRift = null;
    for (let rift of paths) {
        const spawn = rift.points[0];
        const dist = Math.hypot(spawn.x - mouseX, spawn.y - mouseY);
        if (dist < 30) { // Rift selection radius
            clickedRift = rift;
            break;
        }
    }

    if (clickedRift) {
        selectRift(clickedRift);
        return;
    }

    // Check interaction with BASE (Center)
    // Check interaction with BASE (Center)
    // Use the actual base position from the path data
    // (The base is always at the end of the paths)
    if (paths.length > 0) {
        const p = paths[0].points;
        const base = p[p.length - 1];

        if (Math.hypot(mouseX - base.x, mouseY - base.y) < 30) {
            selectBase();
            return;
        }
    }

    // If not clicking a tower, check if we have a build target or are selecting a new one
    // New UX: Tapping empty space selects the spot for potential building (opens panel)

    // 1. If we have a build target and click it again? (Maybe confirm? or just do nothing)
    // 2. If we have a selected tower type (from panel), we might be building?
    //    Actually, if panel is open, we select type then it should build immediately at buildTarget?
    //    Or does selecting type just set selectedTowerType and we have to click again?
    //    The plan says: "Select Tower -> Call buildTower(buildTarget.x, buildTarget.y) -> Hide Panel"
    //    So handleClick just handles the initial empty click.

    // If we are currently IN placement mode (legacy or drag-drop style? No, we are changing to Tap-Select-Build)
    // If selectedTowerType is set, it means we clicked a button in the panel. 
    // If we support "click panel -> click map" (old way), we might need to keep it or disable it.
    // The request implies "show build panel ONLY when user tap empty square".
    // So the flow is: Empty Click -> Panel Shows -> Select Tower -> Build.

    // Snap to grid
    const snap = snapToGrid(mouseX, mouseY);
    const selectedHardpoint = getHardpointAtWorld(snap.x, snap.y);

    // --- Orbital Zone Selection (Tap empty space to highlight zone in Debug Mode) ---
    if (paths.length > 0) {
        const base = paths[0].points[paths[0].points.length - 1];
        const distToCenter = Math.hypot(mouseX - base.x, mouseY - base.y) / GRID_SIZE;

        if (distToCenter < ZONE0_RADIUS_CELLS) {
            selectedZone = 0;
        } else if (distToCenter < 60) {
            const zone = Math.floor((distToCenter - ZONE0_RADIUS_CELLS) / 3) + 1;
            selectedZone = zone;
        } else {
            selectedZone = -1;
        }
    }

    // Check if valid build spot
    let occupied = false;
    for (let t of towers) {
        if (Math.abs(t.x - snap.x) < 1 && Math.abs(t.y - snap.y) < 1) {
            occupied = true; break;
        }
    }

    // Check if on a path (using grid cells)
    // Hardpoints are always buildable anchors, even if a path overlaps.
    if (!occupied && !selectedHardpoint) {
        for (let rift of paths) {
            for (let p of rift.points) {
                const pc = Math.floor(p.x / GRID_SIZE);
                const pr = Math.floor(p.y / GRID_SIZE);
                const snapC = Math.floor(snap.x / GRID_SIZE);
                const snapR = Math.floor(snap.y / GRID_SIZE);
                if (pc === snapC && pr === snapR) {
                    occupied = true;
                    break;
                }
            }
            if (occupied) break;
        }
    }

    if (!occupied) {
        // Toggle behavior: tapping the currently selected empty tile deselects it.
        if (buildTarget && buildTarget.x === snap.x && buildTarget.y === snap.y) {
            deselectTower();
            return;
        }
        selectBuildTarget(snap.x, snap.y);
        return;
    }

    // If clicking on empty space (impossible to reach here logic-wise if occupied check covers everything?)
    // Actually towers/base/rifts checks above cover occupied objects.
    // So if we are here, it's effectively empty space but maybe "occupied" flag was for towers only?
    // We already checked towers/rifts/base above. 

    deselectTower();
}

function selectBuildTarget(x, y) {
    buildTarget = { x, y };
    selectedPlacedTower = null;
    selectedBase = false;
    selectedRift = null;
    selectedTowerType = null;

    // Show Panel
    document.getElementById('controls-bar').classList.remove('hidden');
    // Hide other panels
    document.getElementById('selection-panel').classList.add('hidden');

    // Play sound
    // AudioEngine.playSFX('click'); 

    // Tutorial Step Advance
    if (tutorialActive && tutorialStep === 2) {
        nextTutorialStep();
    }
}

function selectBase() {
    selectedBase = true;
    selectedPlacedTower = null;
    selectedRift = null;
    selectedTowerType = null;
    // Clear any potential "ghost" selection from UI
    document.querySelectorAll('.tower-selector').forEach(el => el.classList.remove('selected'));

    updateSelectionUI();
}

function selectRift(rift) {
    selectedRift = rift;
    selectedPlacedTower = null;
    selectedBase = false;
    selectedTowerType = null;
    document.querySelectorAll('.tower-selector').forEach(el => el.classList.remove('selected'));
    updateSelectionUI();
    maybeShowRiftHint();
}

function deselectTower() {
    selectedTowerType = null;
    selectedPlacedTower = null;
    selectedBase = false;
    selectedRift = null;
    targetingAbility = null; // Clear ability targeting
    buildTarget = null;

    // Hide Build Panel
    document.getElementById('controls-bar').classList.add('hidden');

    updateUI();
    updateSelectionUI();
}

// Global functions for Base UI
// Calculate dynamic repair cost: $50 base, +$25 for each life bought beyond 20
window.getRepairCost = function () {
    const baseline = 20;
    if (lives < baseline) return 50;
    return 50 + (lives - baseline + 1) * 25;
};

window.repairBase = function () {
    const cost = getRepairCost();
    if (money >= cost) {
        money -= cost;
        lives++;
        lives++;
        // Use base world coordinates for particles
        if (paths.length > 0) {
            const p = paths[0].points;
            const base = p[p.length - 1];
            createParticles(base.x, base.y, '#00ff41', 20); // Green heal
        }
        AudioEngine.playSFX('build');
        updateUI();
        updateSelectionUI(); // Update buttons just in case
    }
}

window.upgradeBase = function () {
    // Cost: 200 * (level + 1)
    const cost = 200 * (baseLevel + 1);

    if (money >= cost && baseLevel < 10) {
        money -= cost;
        baseLevel++;
        baseLevel++;
        // Use base world coordinates for particles
        if (paths.length > 0) {
            const p = paths[0].points;
            const base = p[p.length - 1];
            createParticles(base.x, base.y, '#00f3ff', 30); // Blue upgrade
        }
        AudioEngine.playSFX('build');
        updateUI();
        updateSelectionUI();
    }
}

function getWorldGridSize() {
    return {
        cols: Math.max(1, worldCols || Math.floor(width / GRID_SIZE)),
        rows: Math.max(1, worldRows || Math.floor(height / GRID_SIZE))
    };
}

function getContentGridExtents() {
    let maxC = 0;
    let maxR = 0;
    const includeWorldPoint = (x, y) => {
        const c = Math.max(0, Math.floor(x / GRID_SIZE));
        const r = Math.max(0, Math.floor(y / GRID_SIZE));
        if (c > maxC) maxC = c;
        if (r > maxR) maxR = r;
    };

    for (const path of paths) {
        if (!path || !path.points) continue;
        for (const pt of path.points) includeWorldPoint(pt.x, pt.y);
    }
    for (const t of towers) includeWorldPoint(t.x, t.y);
    for (const hp of hardpoints) includeWorldPoint(hp.x, hp.y);

    return { maxC, maxR };
}

function expandWorldBounds() {
    const viewportCols = Math.max(1, Math.floor(width / GRID_SIZE));
    const viewportRows = Math.max(1, Math.floor(height / GRID_SIZE));
    const { maxC, maxR } = getContentGridExtents();

    const requiredCols = Math.max(
        WORLD_MIN_COLS,
        viewportCols + WORLD_VIEW_MARGIN_COLS,
        maxC + 1 + WORLD_CONTENT_MARGIN_COLS
    );
    const requiredRows = Math.max(
        WORLD_MIN_ROWS,
        viewportRows + WORLD_VIEW_MARGIN_ROWS,
        maxR + 1 + WORLD_CONTENT_MARGIN_ROWS
    );

    worldCols = Math.max(worldCols || 0, requiredCols);
    worldRows = Math.max(worldRows || 0, requiredRows);
}

function resize() {
    const dpr = window.devicePixelRatio || 1;

    // Game Logic Dimensions (Logical Pixels)
    width = window.innerWidth;
    height = window.innerHeight;

    // Rendering Dimensions (Physical Pixels)
    canvas.width = width * dpr;
    canvas.height = height * dpr;

    // CSS scaling handled by styles/*.css (width: 100%, height: 100%)
    // But explicitly setting style matches logical size
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    // Scale drawing context so we use logical coordinates
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    expandWorldBounds();

    // Only regenerate paths on initial load, not during active gameplay
    if (gameState === 'start') {
        calculatePath();
    }

    positionSelectionPanel();
}

function snapToGrid(x, y) {
    const col = Math.floor(x / GRID_SIZE);
    const row = Math.floor(y / GRID_SIZE);
    return {
        x: col * GRID_SIZE + GRID_SIZE / 2,
        y: row * GRID_SIZE + GRID_SIZE / 2,
        col: col,
        row: row
    };
}

function getCoreGridNode() {
    if (paths.length > 0 && paths[0].points && paths[0].points.length > 0) {
        const base = paths[0].points[paths[0].points.length - 1];
        return {
            c: Math.floor(base.x / GRID_SIZE),
            r: Math.floor(base.y / GRID_SIZE)
        };
    }

    const { cols, rows } = getWorldGridSize();
    return {
        c: Math.floor(cols / 2),
        r: Math.floor(rows / 2)
    };
}

function addHardpointRing(target, keySet, centerC, centerR, cols, rows, count, radiusCells, type, angleOffset = 0) {
    for (let i = 0; i < count; i++) {
        const angle = angleOffset + (i * Math.PI * 2 / count);
        const c = Math.round(centerC + Math.cos(angle) * radiusCells);
        const r = Math.round(centerR + Math.sin(angle) * radiusCells);
        if (c < 0 || c >= cols || r < 0 || r >= rows) continue;

        const key = `${c},${r}`;
        if (keySet.has(key)) continue;
        keySet.add(key);

        target.push({
            id: `${type}-${target.length + 1}`,
            type,
            c,
            r,
            x: c * GRID_SIZE + GRID_SIZE / 2,
            y: r * GRID_SIZE + GRID_SIZE / 2
        });
    }
}

function buildHardpoints() {
    hardpoints = [];

    const { cols, rows } = getWorldGridSize();
    if (cols <= 0 || rows <= 0) return;

    const core = getCoreGridNode();
    const keySet = new Set();

    addHardpointRing(
        hardpoints,
        keySet,
        core.c,
        core.r,
        cols,
        rows,
        HARDPOINT_RULES.core.count,
        HARDPOINT_RULES.core.radiusCells,
        'core',
        Math.PI / 6
    );

    for (const ring of HARDPOINT_RULES.microRings) {
        addHardpointRing(
            hardpoints,
            keySet,
            core.c,
            core.r,
            cols,
            rows,
            ring.count,
            ring.radiusCells,
            'micro',
            ring.angleOffset || 0
        );
    }
}

function getHardpointAtWorld(x, y, tolerance = HARDPOINT_RULES.slotSnapRadius) {
    let best = null;
    let minDist = Infinity;

    for (const hp of hardpoints) {
        const dist = Math.hypot(x - hp.x, y - hp.y);
        if (dist <= tolerance && dist < minDist) {
            minDist = dist;
            best = hp;
        }
    }

    return best;
}

function isGridNearHardpoint(c, r, radiusCells = 0, hardpointTypes = null) {
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

function getCoreRepulsionPenalty(c, r, endNode) {
    const distToCore = Math.hypot(c - endNode.c, r - endNode.r);
    if (distToCore >= PATHING_RULES.coreRepulsionRadius) return 0;
    const t = 1 - (distToCore / PATHING_RULES.coreRepulsionRadius);
    return PATHING_RULES.coreRepulsionStrength * t * t;
}

function normalizeAngleRadians(angle) {
    const twoPi = Math.PI * 2;
    let a = angle % twoPi;
    if (a < 0) a += twoPi;
    return a;
}

function getCoreGapSectors(coreC, coreR) {
    const coreSlots = hardpoints
        .filter(hp => hp.type === 'core')
        .map(hp => ({ angle: normalizeAngleRadians(Math.atan2(hp.r - coreR, hp.c - coreC)) }))
        .sort((a, b) => a.angle - b.angle);

    if (coreSlots.length < 2) return [];

    const sectors = [];
    for (let i = 0; i < coreSlots.length; i++) {
        const startAngle = coreSlots[i].angle;
        let endAngle = coreSlots[(i + 1) % coreSlots.length].angle;
        if (endAngle <= startAngle) endAngle += Math.PI * 2;
        sectors.push({
            index: i,
            startAngle,
            endAngle,
            centerAngle: normalizeAngleRadians((startAngle + endAngle) / 2)
        });
    }
    return sectors;
}

function getCoreGapIndexForCell(c, r, coreC, coreR, gapSectors) {
    if (!gapSectors.length) return null;
    if (c === coreC && r === coreR) return null;

    const angle = normalizeAngleRadians(Math.atan2(r - coreR, c - coreC));
    for (const sector of gapSectors) {
        let testAngle = angle;
        if (testAngle < sector.startAngle) testAngle += Math.PI * 2;
        if (testAngle >= sector.startAngle && testAngle < sector.endAngle) {
            return sector.index;
        }
    }
    return gapSectors[0].index;
}

function getCoreEntryGapFromPath(path, coreC, coreR, gapSectors, zone0Radius = ZONE0_RADIUS_CELLS) {
    if (!path || !path.points || path.points.length < 2 || !gapSectors.length) return null;

    let entryCell = null;
    for (let i = 1; i < path.points.length; i++) {
        const prev = path.points[i - 1];
        const curr = path.points[i];
        const prevC = Math.floor(prev.x / GRID_SIZE);
        const prevR = Math.floor(prev.y / GRID_SIZE);
        const currC = Math.floor(curr.x / GRID_SIZE);
        const currR = Math.floor(curr.y / GRID_SIZE);
        const prevDist = Math.hypot(prevC - coreC, prevR - coreR);
        const currDist = Math.hypot(currC - coreC, currR - coreR);
        if (prevDist >= zone0Radius && currDist < zone0Radius) {
            entryCell = { c: prevC, r: prevR };
            break;
        }
    }

    if (!entryCell) {
        const beforeCore = path.points[path.points.length - 2];
        entryCell = {
            c: Math.floor(beforeCore.x / GRID_SIZE),
            r: Math.floor(beforeCore.y / GRID_SIZE)
        };
    }

    return getCoreGapIndexForCell(entryCell.c, entryCell.r, coreC, coreR, gapSectors);
}

function isCellInsideZone0(c, r, coreC, coreR, zone0Radius = ZONE0_RADIUS_CELLS) {
    return Math.hypot(c - coreC, r - coreR) < zone0Radius;
}

function pathRespectsZone0Commitment(points, coreC, coreR, zone0Radius = ZONE0_RADIUS_CELLS, startIndex = 0) {
    if (!points || !points.length) return true;
    let enteredZone0 = false;
    for (let i = Math.max(0, startIndex); i < points.length; i++) {
        const c = Math.floor(points[i].x / GRID_SIZE);
        const r = Math.floor(points[i].y / GRID_SIZE);
        const inside = isCellInsideZone0(c, r, coreC, coreR, zone0Radius);
        if (inside) {
            enteredZone0 = true;
        } else if (enteredZone0) {
            return false;
        }
    }
    return true;
}

function calculatePath() {
    paths = [];

    // Grid dimensions
    const { cols, rows } = getWorldGridSize();

    // Target: Center of map
    const centerC = Math.floor(cols / 2);
    const centerR = Math.floor(rows / 2);
    const endNode = { c: centerC, r: centerR };
    buildHardpoints();

    // Start: Random point >= 10 units away
    let startC, startR;
    let validStart = false;
    let attempts = 0;

    while (!validStart && attempts < 100) {
        startC = Math.floor(Math.random() * cols);
        startR = Math.floor(Math.random() * rows);

        // Distance check
        const dist = Math.hypot(startC - centerC, startR - centerR);
        if (dist >= 10) {
            // Also ensure it's not ON the center
            if (startC !== centerC || startR !== centerR) {
                if (!isGridNearHardpoint(startC, startR, 0)) {
                    validStart = true;
                }
            }
        }
        attempts++;
    }

    if (!validStart) {
        // Fallback to top-left corner
        startC = 0; startR = 0;
    }

    // Find path while protecting all hardpoint slots (core + micro).
    const hardpointObstacles = hardpoints.map(hp => ({ x: hp.c, y: hp.r }));
    const pathPoints = findPathOnGrid(
        { c: startC, r: startR },
        endNode,
        hardpointObstacles,
        null,
        {
            coreNode: endNode,
            lockZone0AfterEntry: true,
            zone0Radius: ZONE0_RADIUS_CELLS
        }
    );

    if (pathPoints && pathPoints.length > 0) {
        const startDist = Math.hypot(startC - centerC, startR - centerR);
        const startZone = Math.max(1, Math.min(15, Math.floor((startDist - ZONE0_RADIUS_CELLS) / 3) + 1));
        paths.push({ points: pathPoints, level: 1, zone: startZone });
    } else {
        // Fallback manual path if something fails
        console.warn("Failed to generate random path, using fallback");
        const startX = startC * GRID_SIZE + GRID_SIZE / 2;
        const startY = startR * GRID_SIZE + GRID_SIZE / 2;
        const midX = centerC * GRID_SIZE + GRID_SIZE / 2;
        const endX = centerC * GRID_SIZE + GRID_SIZE / 2;
        const endY = centerR * GRID_SIZE + GRID_SIZE / 2;
        const fallbackPath = {
            points: [
                { x: startX, y: startY },
                { x: midX, y: startY },
                { x: endX, y: endY }
            ],
            level: 1,
            zone: 1
        };
        paths.push(fallbackPath);
    }

    buildHardpoints();
    if (typeof window.resetCamera === 'function') {
        window.resetCamera();
    }
}

