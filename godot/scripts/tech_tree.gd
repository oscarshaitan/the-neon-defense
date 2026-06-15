extends Node
## Autoload "Tech" — the Tech Tree strategy layer (ROADMAP Milestone E /
## GAME_BALANCE_ANALYSIS section 5). Research Points (RP) and unlocked nodes are
## PERSISTENT across runs (separate file from the per-run save) so progression
## carries over. Node effects are accumulated into `fx` and read live by
## gameplay (world.gd / main.gd), so most unlocks take effect immediately;
## start-of-run bonuses (credits/lives/energy) apply when a fresh run begins.
##
## Godot leads this feature; mirror the node table + effects to JS and Flutter
## when porting.

const SAVE_PATH := "user://neon_defense_tech.json"

# Control-branch frost tuning.
const CHILL_FRAMES := 120 # Cryo Conductors chill duration (2 s @ 60 Hz)
const CHILL_SLOW := 0.5 # chilled enemies move at 50% speed
# Offense capstone execution.
const EXECUTE_THRESHOLD := 0.15
const EXECUTE_BONUS := 2.0
# Core capstone restore.
const LAST_STAND_LIVES := 5

signal changed ## RP balance or unlocked set changed — UI refreshes on this.

const BRANCHES: Array[String] = ["OFFENSE", "CONTROL", "ECONOMY", "CORE"]

## Node graph. tier 1-3 are the lane, tier 4 is the capstone. `prereq` is the
## node id that must be unlocked first ("" = always available). `fx` lists the
## effect contributions accumulated into `fx` (see _apply).
const NODES := [
	# --- OFFENSE ---
	{id = "off_1", branch = "OFFENSE", tier = 1, cost = 2, prereq = "",
		name = "FOCUSED OPTICS", desc = "+8% tower damage", fx = {dmg_mult = 1.08}},
	{id = "off_2", branch = "OFFENSE", tier = 2, cost = 3, prereq = "off_1",
		name = "OVERCHARGED ROUNDS", desc = "+12% tower damage", fx = {dmg_mult = 1.12}},
	{id = "off_3", branch = "OFFENSE", tier = 3, cost = 4, prereq = "off_2",
		name = "EXTENDED BARRELS", desc = "+12% tower range", fx = {range_mult = 1.12}},
	{id = "off_4", branch = "OFFENSE", tier = 4, cost = 6, prereq = "off_3",
		name = "EXECUTIONER", desc = "Enemies below 15% HP take double damage",
		fx = {execute = true}},
	# --- CONTROL (frost package) ---
	{id = "con_1", branch = "CONTROL", tier = 1, cost = 2, prereq = "",
		name = "CRYO CONDUCTORS", desc = "Arc attacks chill enemies (slow)",
		fx = {arc_chill = true}},
	{id = "con_2", branch = "CONTROL", tier = 2, cost = 3, prereq = "con_1",
		name = "CRYO EMP", desc = "EMP freeze lasts 50% longer", fx = {emp_freeze_mult = 1.5}},
	{id = "con_3", branch = "CONTROL", tier = 3, cost = 4, prereq = "con_2",
		name = "THERMAL WEAKNESS", desc = "Chilled/frozen enemies take +25% damage",
		fx = {thermal_mult = 1.25}},
	{id = "con_4", branch = "CONTROL", tier = 4, cost = 6, prereq = "con_3",
		name = "DEEP FREEZE PROTOCOL", desc = "EMP blast radius +50%",
		fx = {emp_radius_mult = 1.5}},
	# --- ECONOMY ---
	{id = "eco_1", branch = "ECONOMY", tier = 1, cost = 2, prereq = "",
		name = "SALVAGE ROUTINES", desc = "+15% credits from kills", fx = {reward_mult = 1.15}},
	{id = "eco_2", branch = "ECONOMY", tier = 2, cost = 3, prereq = "eco_1",
		name = "BULK DISCOUNT", desc = "Tower upgrades cost 20% less",
		fx = {upgrade_cost_mult = 0.8}},
	{id = "eco_3", branch = "ECONOMY", tier = 3, cost = 4, prereq = "eco_2",
		name = "WAR CHEST", desc = "Start each run with +150 credits", fx = {start_money = 150.0}},
	{id = "eco_4", branch = "ECONOMY", tier = 4, cost = 6, prereq = "eco_3",
		name = "LIQUIDATION", desc = "Selling towers refunds 100%", fx = {sell_refund = 1.0}},
	# --- CORE SYSTEMS ---
	{id = "core_1", branch = "CORE", tier = 1, cost = 2, prereq = "",
		name = "REINFORCED PLATING", desc = "Start each run with +5 lives", fx = {start_lives = 5}},
	{id = "core_2", branch = "CORE", tier = 2, cost = 3, prereq = "core_1",
		name = "FIELD REPAIRS", desc = "Base repairs cost 30% less", fx = {repair_cost_mult = 0.7}},
	{id = "core_3", branch = "CORE", tier = 3, cost = 4, prereq = "core_2",
		name = "EMERGENCY CAPACITORS", desc = "Start each run with +30 energy",
		fx = {start_energy = 30.0}},
	{id = "core_4", branch = "CORE", tier = 4, cost = 6, prereq = "core_3",
		name = "LAST STAND PROTOCOL",
		desc = "Once per run, survive a fatal breach (restore 5 lives)", fx = {last_stand = true}},
]

var rp := 0
var unlocked := {} ## id (String) -> true
var fx := {} ## accumulated live effects (see _default_fx)

func _ready() -> void:
	_load()
	_recompute()

# ---------------------------------------------------------------------------
# Effect accumulation
# ---------------------------------------------------------------------------

func _default_fx() -> Dictionary:
	return {
		dmg_mult = 1.0, range_mult = 1.0, reward_mult = 1.0, upgrade_cost_mult = 1.0,
		repair_cost_mult = 1.0, emp_freeze_mult = 1.0, emp_radius_mult = 1.0,
		thermal_mult = 1.0, sell_refund = 0.7,
		start_money = 0.0, start_lives = 0, start_energy = 0.0,
		arc_chill = false, execute = false, last_stand = false,
	}

func _apply(f: Dictionary, key: String, value) -> void:
	if typeof(value) == TYPE_BOOL:
		f[key] = f[key] or value
	elif key == "sell_refund":
		f[key] = maxf(f[key], float(value)) # best refund wins
	elif key.begins_with("start_"):
		f[key] = f[key] + value
	else: # multiplicative (*_mult)
		f[key] = f[key] * float(value)

func _recompute() -> void:
	var f := _default_fx()
	for node in NODES:
		if unlocked.has(node.id):
			for key in node.fx:
				_apply(f, key, node.fx[key])
	fx = f
	changed.emit()

# ---------------------------------------------------------------------------
# Node queries / unlocking
# ---------------------------------------------------------------------------

func node_by_id(id: String) -> Dictionary:
	for node in NODES:
		if node.id == id:
			return node
	return {}

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

func prereq_met(node: Dictionary) -> bool:
	return node.prereq == "" or unlocked.has(node.prereq)

func can_unlock(node: Dictionary) -> bool:
	return not is_unlocked(node.id) and prereq_met(node) and rp >= int(node.cost)

func unlock(id: String) -> bool:
	var node := node_by_id(id)
	if node.is_empty() or not can_unlock(node):
		return false
	rp -= int(node.cost)
	unlocked[id] = true
	_recompute()
	_save()
	return true

func nodes_in_branch(branch: String) -> Array:
	var out := []
	for node in NODES:
		if node.branch == branch:
			out.append(node)
	return out

# ---------------------------------------------------------------------------
# Research Points
# ---------------------------------------------------------------------------

## Awarded when a wave is cleared; scales gently with depth.
func award_wave(cleared_wave: int) -> void:
	var gain := 1 + int(cleared_wave / 10.0)
	rp += gain
	_save()
	changed.emit()
	State.show_toast("+%d RESEARCH" % gain)

func grant_rp(amount: int) -> void:
	rp += amount
	_save()
	changed.emit()

## Debug/respec: wipe all progression.
func reset_progress() -> void:
	rp = 0
	unlocked = {}
	_recompute()
	_save()

# ---------------------------------------------------------------------------
# Persistence (separate from the per-run save so it carries across runs)
# ---------------------------------------------------------------------------

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({rp = rp, unlocked = unlocked.keys()}))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	rp = int(data.get("rp", 0))
	for id in data.get("unlocked", []):
		if not node_by_id(str(id)).is_empty():
			unlocked[str(id)] = true
