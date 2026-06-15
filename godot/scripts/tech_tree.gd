extends Node
## Autoload "Tech" — the Tech Tree strategy layer (ROADMAP Milestone E).
##
## v2: a large Path-of-Exile-style WEB. A central START node is always
## allocated; every other node can only be allocated when it is adjacent to a
## node you already own, so Research Points (RP) must be spent *pathing* toward
## what you want. Nodes come in three kinds:
##   - small   (cost 1): tiny effects that stack deep
##   - notable (cost 4): a meaningful single bonus
##   - keystone(cost 8): powerful, often with a drawback, and mutually
##                       exclusive with a rival keystone (pick one, not both)
## RP is earned slowly (+1 per wave cleared) and, with allocations, PERSISTS
## across runs in a separate file from the per-run save. Allocations can be
## refunded (single leaf node, or a full free respec).
##
## Effects accumulate into `fx`, read live by gameplay (world.gd / main.gd).
## Godot leads this feature; mirror the graph + effects to JS and Flutter.

const SAVE_PATH := "user://neon_defense_tech.json"
const START_ID := "start"

# Control-branch frost tuning.
const CHILL_FRAMES := 120 # chill duration (2 s @ 60 Hz)
const CHILL_SLOW := 0.5 # chilled enemies move at 50% speed
# Offense keystone execution.
const EXECUTE_THRESHOLD := 0.15
const EXECUTE_BONUS := 2.0
# Core keystone restore.
const LAST_STAND_LIVES := 5

# UI: node kinds and the pixel spacing applied to the grid coordinates.
const GRID_SPACING := 78.0
const RP_PER_WAVE := 1 # slow, deliberate progression

signal changed ## RP / allocation changed — UI refreshes on this.

const BRANCHES: Array[String] = ["OFFENSE", "CONTROL", "ECONOMY", "CORE"]

## Small-node templates: type -> {name, desc, fx}. Keeps the dense filler nodes
## terse and consistent.
const SMALL := {
	"dmg": {name = "WEAPON CALIBRATION", desc = "+3% tower damage", fx = {dmg_mult = 1.03}},
	"rate": {name = "SERVO ACTUATORS", desc = "+3% fire rate", fx = {cooldown_mult = 0.97}},
	"range": {name = "OPTICS ARRAY", desc = "+4% tower range", fx = {range_mult = 1.04}},
	"reward": {name = "SALVAGE CREW", desc = "+3% credits from kills", fx = {reward_mult = 1.03}},
	"thermal": {name = "CRYO TUNING", desc = "+4% damage to chilled/frozen", fx = {thermal_mult = 1.04}},
	"emp_r": {name = "PULSE COILS", desc = "+4% EMP radius", fx = {emp_radius_mult = 1.04}},
	"emp_f": {name = "CRYO CELLS", desc = "+4% EMP freeze time", fx = {emp_freeze_mult = 1.04}},
	"money": {name = "WAR RESERVES", desc = "+25 starting credits", fx = {start_money = 25.0}},
	"energy": {name = "POWER CELLS", desc = "+5 starting energy", fx = {start_energy = 5.0}},
	"regen": {name = "ENERGY SIPHON", desc = "+0.2 energy per kill", fx = {energy_per_kill = 0.2}},
	"upcost": {name = "PRECISION MACHINING", desc = "-3% upgrade cost", fx = {upgrade_cost_mult = 0.97}},
	"repair": {name = "REPAIR NANITES", desc = "-4% repair cost", fx = {repair_cost_mult = 0.96}},
}

# --- runtime graph ---
var nodes: Array = [] ## Array[Dictionary]: id, branch, kind, pos, cost, name, desc, fx, neighbors, excludes
var by_id: Dictionary = {}
var rp := 0
var allocated: Dictionary = {} ## id -> true (START is always present)
var fx: Dictionary = {}

func _ready() -> void:
	_build_graph()
	_load()
	if not allocated.has(START_ID):
		allocated[START_ID] = true
	_recompute()

# ---------------------------------------------------------------------------
# Graph construction
# ---------------------------------------------------------------------------

func _add(id: String, branch: String, kind: String, x: float, y: float, cost: int,
		nm: String, desc: String, node_fx: Dictionary, neighbors: Array, excludes: Array = []) -> void:
	var n := {
		id = id, branch = branch, kind = kind, pos = Vector2(x, y), cost = cost,
		name = nm, desc = desc, fx = node_fx, neighbors = neighbors.duplicate(),
		excludes = excludes.duplicate(),
	}
	nodes.append(n)
	by_id[id] = n

## Small templated node.
func _small(id: String, branch: String, type: String, x: float, y: float, neighbors: Array) -> void:
	var t: Dictionary = SMALL[type]
	_add(id, branch, "small", x, y, 1, t.name, t.desc, t.fx, neighbors)

func _link(a: String, b: String) -> void:
	if by_id.has(a) and not by_id[a].neighbors.has(b):
		by_id[a].neighbors.append(b)
	if by_id.has(b) and not by_id[b].neighbors.has(a):
		by_id[b].neighbors.append(a)

func _build_graph() -> void:
	nodes.clear()
	by_id.clear()
	_add(START_ID, "", "start", 0, 0, 0, "CORE UPLINK", "Allocation origin.", {}, [])

	# === OFFENSE (up) =======================================================
	_small("of1", "OFFENSE", "dmg", 0, -1, [START_ID])
	_small("of2", "OFFENSE", "dmg", 0, -2, ["of1"])
	_add("ofN1", "OFFENSE", "notable", 0, -3, 4, "FOCUSED OPTICS", "+10% tower damage",
			{dmg_mult = 1.10}, ["of2"])
	# left fork — fire rate
	_small("of3", "OFFENSE", "rate", -1, -3, ["ofN1"])
	_small("of4", "OFFENSE", "rate", -2, -3, ["of3"])
	_add("ofN2", "OFFENSE", "notable", -3, -3, 4, "BALLISTICS ARRAY", "+15% fire rate",
			{cooldown_mult = 0.85}, ["of4"])
	_small("of4b", "OFFENSE", "dmg", -3, -2, ["ofN2"])
	# right fork — range
	_small("of5", "OFFENSE", "range", 1, -3, ["ofN1"])
	_small("of6", "OFFENSE", "range", 2, -3, ["of5"])
	_add("ofN3", "OFFENSE", "notable", 3, -3, 4, "TARGETING UPLINK", "+12% tower range",
			{range_mult = 1.12}, ["of6"])
	_small("of6b", "OFFENSE", "range", 3, -2, ["ofN3"])
	# trunk to keystones
	_small("of7", "OFFENSE", "dmg", 0, -4, ["ofN1"])
	_small("of8", "OFFENSE", "dmg", 0, -5, ["of7"])
	_add("ofK1", "OFFENSE", "keystone", -1, -6, 8, "EXECUTIONER",
			"Enemies below 15% HP take double damage.", {execute = true}, ["of8"], ["ofK2"])
	_add("ofK2", "OFFENSE", "keystone", 1, -6, 8, "OVERWHELM",
			"+35% damage, but -12% fire rate.", {dmg_mult = 1.35, cooldown_mult = 1.12},
			["of8"], ["ofK1"])

	# === CONTROL (right) ====================================================
	_small("cf1", "CONTROL", "rate", 1, 0, [START_ID])
	_small("cf2", "CONTROL", "thermal", 2, 0, ["cf1"])
	_add("cfN1", "CONTROL", "notable", 3, 0, 4, "CRYO CONDUCTORS",
			"Arc attacks chill enemies (slow).", {arc_chill = true}, ["cf2"])
	# up fork — EMP
	_small("cf3", "CONTROL", "emp_r", 3, -1, ["cfN1"])
	_small("cf4", "CONTROL", "emp_f", 3, -2, ["cf3"])
	_add("cfN2", "CONTROL", "notable", 3, -3, 4, "OVERCHARGED EMP",
			"+25% EMP radius and freeze time", {emp_radius_mult = 1.25, emp_freeze_mult = 1.25},
			["cf4"])
	# down fork — thermal
	_small("cf5", "CONTROL", "thermal", 3, 1, ["cfN1"])
	_small("cf6", "CONTROL", "thermal", 3, 2, ["cf5"])
	_add("cfN3", "CONTROL", "notable", 3, 3, 4, "THERMAL LANCE", "+20% damage to chilled/frozen",
			{thermal_mult = 1.20}, ["cf6"])
	_small("cf6b", "CONTROL", "thermal", 4, 3, ["cfN3"])
	# trunk to keystones
	_small("cf7", "CONTROL", "emp_f", 4, 0, ["cfN1"])
	_small("cf8", "CONTROL", "thermal", 5, 0, ["cf7"])
	_add("cfK1", "CONTROL", "keystone", 6, -1, 8, "DEEP FREEZE PROTOCOL",
			"+50% EMP radius & freeze, +20% thermal damage.",
			{emp_radius_mult = 1.5, emp_freeze_mult = 1.5, thermal_mult = 1.2}, ["cf8"], ["cfK2"])
	_add("cfK2", "CONTROL", "keystone", 6, 1, 8, "PERMAFROST",
			"+45% damage to chilled/frozen, but -10% tower damage.",
			{thermal_mult = 1.45, dmg_mult = 0.90}, ["cf8"], ["cfK1"])

	# === ECONOMY (down) =====================================================
	_small("ef1", "ECONOMY", "reward", 0, 1, [START_ID])
	_small("ef2", "ECONOMY", "reward", 0, 2, ["ef1"])
	_add("efN1", "ECONOMY", "notable", 0, 3, 4, "SALVAGE NETWORK", "+12% credits from kills",
			{reward_mult = 1.12}, ["ef2"])
	# left fork — costs
	_small("ef3", "ECONOMY", "upcost", -1, 3, ["efN1"])
	_small("ef4", "ECONOMY", "repair", -2, 3, ["ef3"])
	_add("efN2", "ECONOMY", "notable", -3, 3, 4, "FIELD LOGISTICS",
			"-15% upgrade cost, -30% repair cost", {upgrade_cost_mult = 0.85, repair_cost_mult = 0.70},
			["ef4"])
	# right fork — starting credits
	_small("ef5", "ECONOMY", "money", 1, 3, ["efN1"])
	_small("ef6", "ECONOMY", "money", 2, 3, ["ef5"])
	_add("efN3", "ECONOMY", "notable", 3, 3, 4, "WAR CHEST", "+150 starting credits",
			{start_money = 150.0}, ["ef6"])
	# trunk to keystones
	_small("ef7", "ECONOMY", "reward", 0, 4, ["efN1"])
	_small("ef8", "ECONOMY", "reward", 0, 5, ["ef7"])
	_add("efK1", "ECONOMY", "keystone", -1, 6, 8, "LIQUIDATION",
			"Selling towers refunds 100%.", {sell_refund = 1.0}, ["ef8"], ["efK2"])
	_add("efK2", "ECONOMY", "keystone", 1, 6, 8, "WAR PROFITEER",
			"+35% credits, but sell refund drops to 40%.",
			{reward_mult = 1.35, sell_refund = 0.40}, ["ef8"], ["efK1"])

	# === CORE (left) ========================================================
	_small("rf1", "CORE", "energy", -1, 0, [START_ID])
	_small("rf2", "CORE", "regen", -2, 0, ["rf1"])
	_add("rfN1", "CORE", "notable", -3, 0, 4, "CAPACITOR BANK", "+25 starting energy",
			{start_energy = 25.0}, ["rf2"])
	# up fork — durability
	_small("rf3", "CORE", "repair", -3, -1, ["rfN1"])
	_small("rf4", "CORE", "repair", -3, -2, ["rf3"])
	_add("rfN2", "CORE", "notable", -3, -3, 5, "REINFORCED PLATING", "+2 starting lives",
			{start_lives = 2}, ["rf4"])
	# down fork — energy
	_small("rf5", "CORE", "regen", -3, 1, ["rfN1"])
	_small("rf6", "CORE", "energy", -3, 2, ["rf5"])
	_add("rfN3", "CORE", "notable", -3, 3, 4, "OVERCLOCKED REACTOR", "+40 starting energy",
			{start_energy = 40.0}, ["rf6"])
	# trunk to keystones
	_small("rf7", "CORE", "repair", -4, 0, ["rfN1"])
	_small("rf8", "CORE", "energy", -5, 0, ["rf7"])
	_add("rfK1", "CORE", "keystone", -6, -1, 8, "LAST STAND PROTOCOL",
			"Once per run, survive a fatal breach (restore 5 lives).", {last_stand = true},
			["rf8"], ["rfK2"])
	_add("rfK2", "CORE", "keystone", -6, 1, 8, "BULWARK",
			"+5 starting lives, but -15% tower damage.", {start_lives = 5, dmg_mult = 0.85},
			["rf8"], ["rfK1"])

	# Near-center ring links — lets you travel between branches for hybrid
	# builds, so there is no single linear "best" path.
	_link("of1", "cf1")
	_link("cf1", "ef1")
	_link("ef1", "rf1")
	_link("rf1", "of1")

	# Normalize adjacency to be bidirectional: each node declares its parent,
	# so add the reverse edge so reachability and refund-connectivity traverse
	# the web from either side.
	for n in nodes:
		for nb in n.neighbors:
			if by_id.has(nb) and not by_id[nb].neighbors.has(n.id):
				by_id[nb].neighbors.append(n.id)

# ---------------------------------------------------------------------------
# Effect accumulation
# ---------------------------------------------------------------------------

func _default_fx() -> Dictionary:
	return {
		dmg_mult = 1.0, range_mult = 1.0, cooldown_mult = 1.0, reward_mult = 1.0,
		upgrade_cost_mult = 1.0, repair_cost_mult = 1.0, emp_freeze_mult = 1.0,
		emp_radius_mult = 1.0, thermal_mult = 1.0, sell_refund = 0.7,
		start_money = 0.0, start_lives = 0, start_energy = 0.0, energy_per_kill = 0.0,
		arc_chill = false, execute = false, last_stand = false,
	}

func _apply(f: Dictionary, key: String, value) -> void:
	if typeof(value) == TYPE_BOOL:
		f[key] = f[key] or value
	elif key == "sell_refund":
		f[key] = maxf(f[key], float(value)) # best refund wins
	elif key.begins_with("start_") or key == "energy_per_kill":
		f[key] = f[key] + value
	else: # multiplicative (*_mult)
		f[key] = f[key] * float(value)

func _recompute() -> void:
	var f := _default_fx()
	for n in nodes:
		if allocated.has(n.id):
			for key in n.fx:
				_apply(f, key, n.fx[key])
	fx = f
	changed.emit()

# ---------------------------------------------------------------------------
# Allocation (path-based) + refund
# ---------------------------------------------------------------------------

func is_allocated(id: String) -> bool:
	return allocated.has(id)

## A node is reachable when START or any allocated node is a neighbour.
func is_reachable(node: Dictionary) -> bool:
	for nb in node.neighbors:
		if allocated.has(nb):
			return true
	return false

func _excluded_blocked(node: Dictionary) -> bool:
	for ex in node.excludes:
		if allocated.has(ex):
			return true
	return false

func can_allocate(node: Dictionary) -> bool:
	return not is_allocated(node.id) and node.kind != "start" \
			and is_reachable(node) and not _excluded_blocked(node) and rp >= int(node.cost)

func allocate(id: String) -> bool:
	var node: Dictionary = by_id.get(id, {})
	if node.is_empty() or not can_allocate(node):
		return false
	rp -= int(node.cost)
	allocated[id] = true
	_recompute()
	_save()
	return true

## A node can be refunded only if removing it leaves every other allocated node
## still connected to START (no orphaned allocations).
func can_refund(id: String) -> bool:
	if id == START_ID or not is_allocated(id):
		return false
	return _all_connected_without(id)

func _all_connected_without(removed: String) -> bool:
	var reachable := {START_ID: true}
	var frontier := [START_ID]
	while not frontier.is_empty():
		var cur: String = frontier.pop_back()
		for nb in by_id[cur].neighbors:
			if nb == removed or reachable.has(nb) or not allocated.has(nb):
				continue
			reachable[nb] = true
			frontier.append(nb)
	for aid in allocated:
		if aid == removed:
			continue
		if not reachable.has(aid):
			return false
	return true

func refund(id: String) -> bool:
	if not can_refund(id):
		return false
	rp += int(by_id[id].cost)
	allocated.erase(id)
	_recompute()
	_save()
	return true

## Free full respec — refunds all spent RP.
func refund_all() -> void:
	var spent := 0
	for aid in allocated:
		if aid != START_ID:
			spent += int(by_id[aid].cost)
	allocated = {START_ID: true}
	rp += spent
	_recompute()
	_save()

func nodes_in_branch(branch: String) -> Array:
	var out := []
	for n in nodes:
		if n.branch == branch:
			out.append(n)
	return out

func total_tree_cost() -> int:
	var total := 0
	for n in nodes:
		total += int(n.cost)
	return total

# ---------------------------------------------------------------------------
# Research Points
# ---------------------------------------------------------------------------

func award_wave(_cleared_wave: int) -> void:
	rp += RP_PER_WAVE
	_save()
	changed.emit()
	State.show_toast("+%d RESEARCH" % RP_PER_WAVE)

func grant_rp(amount: int) -> void:
	rp += amount
	_save()
	changed.emit()

func reset_progress() -> void:
	rp = 0
	allocated = {START_ID: true}
	_recompute()
	_save()

# ---------------------------------------------------------------------------
# Persistence (separate file so it carries across runs)
# ---------------------------------------------------------------------------

func _save() -> void:
	var ids := []
	for aid in allocated:
		if aid != START_ID:
			ids.append(aid)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({rp = rp, allocated = ids}))

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
	allocated[START_ID] = true # START is always allocated
	for id in data.get("allocated", []):
		if by_id.has(str(id)):
			allocated[str(id)] = true
