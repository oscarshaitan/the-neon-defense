class_name C
## All balance data, mirrored 1:1 from the JS reference (js/scripts/00_core.js).
## This file is the parity contract — change it only when the JS changes.

const GRID_SIZE := 40.0
const ZONE0_RADIUS_CELLS := 6
const WORLD_COLS := 140
const WORLD_ROWS := 90

const MAX_TOWER_RANGE := 800.0

# JS frame-based numbers run at 60 fps; the game logic steps at fixed 60 Hz.
const LOGIC_FPS := 60

# --- Towers (JS TOWERS) ---
const TOWERS := {
	&"basic": {cost = 50.0, range = 100.0, damage = 10.0, cooldown = 30, color = Color("00f3ff")},
	&"rapid": {cost = 120.0, range = 80.0, damage = 4.0, cooldown = 10, color = Color("fcee0a")},
	&"sniper": {cost = 200.0, range = 250.0, damage = 50.0, cooldown = 90, color = Color("ff00ac")},
	&"arc": {cost = 180.0, range = 100.0, damage = 8.0, cooldown = 34, color = Color("7cd7ff")},
}
const TOWER_ORDER: Array[StringName] = [&"basic", &"rapid", &"sniper", &"arc"]

# --- Enemies (JS ENEMIES) ---
const ENEMIES := {
	&"basic": {hp = 30.0, speed = 1.5, color = Color("ff0000"), reward = 10.0, width = 20.0},
	&"fast": {hp = 20.0, speed = 2.5, color = Color("ffff00"), reward = 15.0, width = 16.0},
	&"tank": {hp = 100.0, speed = 0.8, color = Color("ff00ff"), reward = 30.0, width = 24.0},
	&"boss": {hp = 500.0, speed = 0.5, color = Color("ff8800"), reward = 200.0, width = 40.0},
	&"splitter": {hp = 80.0, speed = 1.2, color = Color("00ff41"), reward = 40.0, width = 28.0},
	&"mini": {hp = 20.0, speed = 2.0, color = Color("00ff41"), reward = 5.0, width = 12.0},
	&"bulwark": {hp = 350.0, speed = 0.6, color = Color("fcee0a"), reward = 60.0, width = 32.0},
	&"shifter": {hp = 60.0, speed = 1.5, color = Color("ff00ac"), reward = 60.0, width = 20.0},
}

# --- Arc tower rules ---
const ARC_STATIC_THRESHOLD := 100.0
const ARC_STUN_FRAMES := 30
# Inter-tower lightning network (JS ARC_TOWER_RULES): cardinally aligned arc
# towers 1–3 cells apart link up; a connected component grants every member a
# bonus equal to its size (capped at maxBonus).
const ARC_MIN_LINK_CELLS := 1
const ARC_MAX_LINK_CELLS := 3
const ARC_MAX_BONUS := 5

# --- Hardpoints (JS HARDPOINT_RULES) ---
const HP_SNAP_RADIUS := GRID_SIZE * 0.45
const CORE_HP_COUNT := 6
const CORE_HP_RADIUS_CELLS := ZONE0_RADIUS_CELLS
const CORE_MULT := {damage = 1.08, range = 1.06, cooldown = 0.95, scale = 1.0}
const MICRO_RINGS := [
	{count = 10, radius_cells = 13, angle_offset = PI / 10},
	{count = 14, radius_cells = 17, angle_offset = 0.0},
]
const MICRO_MULT := {damage = 0.82, range = 0.86, cooldown = 1.12, scale = 0.78}

# --- Economy ---
const STARTING_MONEY := 100.0
const STARTING_LIVES := 20
const MAX_ENERGY := 100.0

# --- Abilities ---
const EMP_COST := 40.0
const EMP_RADIUS := 120.0
const EMP_DURATION_FRAMES := 300
const OVERCLOCK_COST := 25.0
const OVERCLOCK_DURATION_FRAMES := 600

# --- Waves ---
const PREP_TIMER_SECONDS := 30.0
const SPAWN_INTERVAL_FRAMES := 60

# --- Mutations (JS generateMutation profiles) ---
const MUTATION_PROFILES := [
	{key = "CRIMSON", color = Color("ff0033"), hp = 1.6, speed = 1.2, reward = 2.0},
	{key = "VOID", color = Color("aa00ff"), hp = 1.4, speed = 1.5, reward = 2.5},
	{key = "TITAN", color = Color("00ffaa"), hp = 3.0, speed = 0.7, reward = 3.0},
	{key = "PHASE", color = Color("ffffff"), hp = 1.2, speed = 2.0, reward = 1.5},
	{key = "NEON", color = Color("fcee0a"), hp = 1.8, speed = 1.3, reward = 2.0},
]

# --- Quality profiles (JS QUALITY_PROFILES) ---
const QUALITY_PROFILES := [
	{name = "HIGH", max_particles = 900, max_lights = 140, max_arc_bursts = 180},
	{name = "MED", max_particles = 620, max_lights = 90, max_arc_bursts = 140},
	{name = "LOW", max_particles = 420, max_lights = 65, max_arc_bursts = 96},
]
const QUALITY_DOWNGRADE_FRAME_MS := 22.0
const QUALITY_DOWNGRADE_EMA_MS := 19.5
const QUALITY_UPGRADE_FRAME_MS := 15.8
const QUALITY_UPGRADE_EMA_MS := 15.3
const QUALITY_DOWNGRADE_WINDOW := 45
const QUALITY_UPGRADE_WINDOW := 240

# --- Pathing rules (JS PATHING_RULES) ---
const CORE_REPULSION_RADIUS := 9.0
const CORE_REPULSION_STRENGTH := 14.0
const NEAR_CORE_STRAIGHT_RADIUS := 8.0
const NEAR_CORE_TURN_PENALTY := 18.0
const MERGE_MIN_CORE_DISTANCE := 7.0

# --- Palette ---
const COL_BG := Color("050510")
const COL_BLUE := Color("00f3ff")
const COL_PINK := Color("ff00ac")
const COL_GREEN := Color("00ff41")
const COL_YELLOW := Color("fcee0a")
const COL_RED := Color("ff4444")

static func enemy_def(type: StringName) -> Dictionary:
	return ENEMIES[type]

static func tower_def(type: StringName) -> Dictionary:
	return TOWERS[type]
