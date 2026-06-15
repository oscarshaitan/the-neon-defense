extends Node
## Autoload "Tech" — the Tech Tree strategy layer (ROADMAP Milestone E).
##
## v4: a large, PLANAR Path-of-Exile-style web built from cluster "pockets".
## A central START fans into ROOT_BRANCHES radial cones. Each cone is a chain of
## CLUSTERS; a cluster is a BIG node at the centre ringed by small "pip" nodes
## (a wheel graph — planar). Clusters connect along their cone by single clean
## paths, so edges only ever meet at shared nodes (no crossing lines).
##
## A small pip is a minor stat (+3% dmg). The BIG node at a cluster's centre is
## a major upgrade that unlocks ONLY once every pip around it is allocated, costs
## more, and grants a big MIX of whatever its ring contains (e.g. +10% dmg,
## +12% range, +10% fire rate). Branch tips are CAPSTONES — unique unlocks.
## There is no mutual exclusion: anything is takeable if you path + pay for it.
##
## Allocation is PATH-BASED (a node must be adjacent to one you own). RP (+1 per
## wave) and allocations PERSIST across runs in a separate save file, and can be
## refunded (single leaf or a free REFUND ALL). Effects accumulate into `fx`,
## read live by gameplay. Godot leads; mirror the generator + effects to JS/Flutter.

const SAVE_PATH := "user://neon_defense_tech.json"
const START_ID := "start"

# Control-branch frost tuning.
const CHILL_FRAMES := 120 # chill duration (2 s @ 60 Hz)
const CHILL_SLOW := 0.5 # chilled enemies move at 50% speed
# Offense capstone execution.
const EXECUTE_THRESHOLD := 0.15
const EXECUTE_BONUS := 2.0
# Core capstone restore.
const LAST_STAND_LIVES := 5

const GRID_SPACING := 72.0 # grid units -> pixels in the UI
const RP_PER_WAVE := 1 # slow, deliberate progression

# Planar cluster layout. Cones don't overlap, wheels are planar, paths run in
# the gaps between cluster rings -> no crossing lines.
const ROOT_BRANCHES := 8 # radial cones around START
const CLUSTERS_PER_BRANCH := 3 # cluster pockets per cone (last = capstone)
const RING := 6 # pips around each big node
const RADIUS0 := 3.2 # grid distance START -> first cluster centre
const CLUSTER_STEP := 3.2 # grid distance between cluster centres
const RING_RADIUS := 0.95 # pip orbit radius
const PATH_PIPS := 2 # small nodes along each connecting path

signal changed ## RP / allocation changed — UI refreshes on this.
signal research_complete ## Whole tree allocated — the "endgame" (waves continue forever).

const BRANCHES: Array[String] = ["OFFENSE", "CONTROL", "ECONOMY", "CORE"]

## Small-node templates: type -> {name, desc, fx}.
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

## Per-theme pip mixes (each cluster's ring cycles through these).
const THEME_SMALLS := {
	"OFFENSE": ["dmg", "dmg", "rate", "range"],
	"CONTROL": ["thermal", "emp_r", "emp_f", "rate"],
	"ECONOMY": ["reward", "money", "upcost", "repair"],
	"CORE": ["energy", "regen", "repair", "money"],
}

## Big-node tier per type — a major version of the small pip (~3x the pip).
const BIG_FX := {
	"dmg": {dmg_mult = 1.10},
	"rate": {cooldown_mult = 0.90},
	"range": {range_mult = 1.12},
	"reward": {reward_mult = 1.10},
	"thermal": {thermal_mult = 1.12},
	"emp_r": {emp_radius_mult = 1.12},
	"emp_f": {emp_freeze_mult = 1.12},
	"money": {start_money = 100.0},
	"energy": {start_energy = 30.0},
	"regen": {energy_per_kill = 0.5},
	"upcost": {upgrade_cost_mult = 0.90},
	"repair": {repair_cost_mult = 0.85},
}

## Branch-tip capstones — unique unlocks (no drawbacks, no exclusivity).
## Indexed by branch so each capstone matches its cone's theme.
const CAPSTONES := [
	{name = "EXECUTIONER", desc = "Enemies below 15% HP take double damage.", fx = {execute = true}},
	{name = "DEEP FREEZE PROTOCOL", desc = "+40% EMP radius & freeze time.", fx = {emp_radius_mult = 1.4, emp_freeze_mult = 1.4}},
	{name = "LIQUIDATION", desc = "Selling towers refunds 100%.", fx = {sell_refund = 1.0}},
	{name = "LAST STAND PROTOCOL", desc = "Once per run, survive a fatal breach.", fx = {last_stand = true}},
	{name = "APEX ROUNDS", desc = "+30% tower damage.", fx = {dmg_mult = 1.30}},
	{name = "CRYO CONDUCTORS", desc = "Arc attacks chill enemies (slow).", fx = {arc_chill = true}},
	{name = "MINT", desc = "+30% credits from kills.", fx = {reward_mult = 1.30}},
	{name = "OVERCLOCK CORE", desc = "+28% fire rate.", fx = {cooldown_mult = 0.78}},
]

# --- runtime graph ---
var nodes: Array = [] ## Array[Dictionary]: id, branch, kind, pos, cost, name, desc, fx, neighbors
var by_id: Dictionary = {}
var rp := 0
var allocated: Dictionary = {} ## id -> true (START is always present)
var fx: Dictionary = {}
var _nid := 0

func _ready() -> void:
	_build_graph()
	_load()
	if not allocated.has(START_ID):
		allocated[START_ID] = true
	_recompute()

# ---------------------------------------------------------------------------
# Graph construction (planar cluster web)
# ---------------------------------------------------------------------------

func _add(id: String, branch: String, kind: String, x: float, y: float, cost: int,
		nm: String, desc: String, node_fx: Dictionary, neighbors: Array) -> void:
	nodes.append({
		id = id, branch = branch, kind = kind, pos = Vector2(x, y), cost = cost,
		name = nm, desc = desc, fx = node_fx, neighbors = neighbors.duplicate(),
	})
	by_id[id] = nodes[-1]

func _link(a: String, b: String) -> void:
	if by_id.has(a) and not by_id[a].neighbors.has(b):
		by_id[a].neighbors.append(b)
	if by_id.has(b) and not by_id[b].neighbors.has(a):
		by_id[b].neighbors.append(a)

## Direction unit vector for a compass angle in degrees (0 = up, 90 = right).
func _dir(ang_deg: float) -> Vector2:
	var r := deg_to_rad(ang_deg)
	return Vector2(sin(r), -cos(r))

func _new_id() -> String:
	_nid += 1
	return "n%d" % _nid

## Create an unlinked small pip; returns its id.
func _mk(pos: Vector2, theme: String, type: String) -> String:
	var t: Dictionary = SMALL[type]
	var id := _new_id()
	_add(id, theme, "small", pos.x, pos.y, 1, t.name, t.desc, t.fx, [])
	return id

## Chain `n` pips from `prev_id` toward `b_pos`; returns the last pip id.
func _chain(prev_id: String, a_pos: Vector2, b_pos: Vector2, theme: String, n: int) -> String:
	var types: Array = THEME_SMALLS[theme]
	var prev := prev_id
	for j in range(1, n + 1):
		var p := a_pos.lerp(b_pos, float(j) / (n + 1))
		var id := _mk(p, theme, types[j % types.size()])
		_link(prev, id)
		prev = id
	return prev

## Merge the big-tier effects for every distinct pip type in a ring.
func _mix_fx(present: Dictionary) -> Dictionary:
	var f := {}
	for t in present:
		for key in BIG_FX[t]:
			f[key] = BIG_FX[t][key]
	return f

## Short " · "-joined description of an effect delta (for big-node tooltips).
func _describe(f: Dictionary) -> String:
	var p: Array = []
	if f.has("dmg_mult"):
		p.append("%+d%% dmg" % roundi((f.dmg_mult - 1.0) * 100.0))
	if f.has("cooldown_mult"):
		p.append("%+d%% fire rate" % roundi((1.0 / f.cooldown_mult - 1.0) * 100.0))
	if f.has("range_mult"):
		p.append("%+d%% range" % roundi((f.range_mult - 1.0) * 100.0))
	if f.has("reward_mult"):
		p.append("%+d%% credits" % roundi((f.reward_mult - 1.0) * 100.0))
	if f.has("thermal_mult"):
		p.append("%+d%% vs chilled" % roundi((f.thermal_mult - 1.0) * 100.0))
	if f.has("emp_radius_mult"):
		p.append("%+d%% EMP radius" % roundi((f.emp_radius_mult - 1.0) * 100.0))
	if f.has("emp_freeze_mult"):
		p.append("%+d%% EMP freeze" % roundi((f.emp_freeze_mult - 1.0) * 100.0))
	if f.has("upgrade_cost_mult"):
		p.append("%+d%% upgrade cost" % roundi((f.upgrade_cost_mult - 1.0) * 100.0))
	if f.has("repair_cost_mult"):
		p.append("%+d%% repair cost" % roundi((f.repair_cost_mult - 1.0) * 100.0))
	if f.has("start_money"):
		p.append("+%d credits" % int(f.start_money))
	if f.has("start_energy"):
		p.append("+%d energy" % int(f.start_energy))
	if f.has("energy_per_kill"):
		p.append("+%.1f energy/kill" % f.energy_per_kill)
	return " · ".join(PackedStringArray(p))

## A cluster pocket: a big centre node ringed by pips. Returns inward "entry"
## and outward "exit" pip ids for connecting along the cone.
func _build_cluster(center: Vector2, theme: String, ang: float, capstone_idx: int) -> Dictionary:
	var types: Array = THEME_SMALLS[theme]
	var ring: Array = []
	var present := {}
	for j in RING:
		var aj := ang + float(j) * (360.0 / RING)
		var p := center + _dir(aj) * RING_RADIUS
		var typ: String = types[j % types.size()]
		present[typ] = true
		ring.append(_mk(p, theme, typ))
	for j in RING:
		_link(ring[j], ring[(j + 1) % RING])
	var cid := _new_id()
	if capstone_idx >= 0:
		var k: Dictionary = CAPSTONES[capstone_idx]
		_add(cid, theme, "capstone", center.x, center.y, 10, k.name, k.desc, k.fx.duplicate(), [])
	else:
		var f := _mix_fx(present)
		_add(cid, theme, "big", center.x, center.y, 4 + present.size(),
				"%s NEXUS" % theme, _describe(f), f, [])
	for j in RING:
		_link(cid, ring[j])
	# entry = inward pip (angle ~ ang+180 -> index RING/2), exit = outward (index 0)
	return {entry = ring[RING / 2], exit = ring[0]}

func _build_graph() -> void:
	nodes.clear()
	by_id.clear()
	_nid = 0
	_add(START_ID, "", "start", 0, 0, 0, "CORE UPLINK", "Allocation origin — always active.", {}, [])
	for b in ROOT_BRANCHES:
		var ang := float(b) * (360.0 / ROOT_BRANCHES)
		var theme: String = BRANCHES[b % BRANCHES.size()]
		var prev_id := START_ID
		var prev_pos := Vector2.ZERO
		for i in CLUSTERS_PER_BRANCH:
			var center := _dir(ang) * (RADIUS0 + i * CLUSTER_STEP)
			var is_cap: bool = i == CLUSTERS_PER_BRANCH - 1
			var cl := _build_cluster(center, theme, ang, b if is_cap else -1)
			var last := _chain(prev_id, prev_pos, by_id[cl.entry].pos, theme, PATH_PIPS)
			_link(last, cl.entry)
			prev_id = cl.exit
			prev_pos = by_id[cl.exit].pos

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

## Human-readable cumulative bonuses from everything currently allocated.
func stat_summary() -> Array:
	var out: Array = []
	if fx.dmg_mult != 1.0:
		out.append("Damage  %+d%%" % roundi((fx.dmg_mult - 1.0) * 100.0))
	if fx.cooldown_mult != 1.0:
		out.append("Fire rate  %+d%%" % roundi((1.0 / fx.cooldown_mult - 1.0) * 100.0))
	if fx.range_mult != 1.0:
		out.append("Range  %+d%%" % roundi((fx.range_mult - 1.0) * 100.0))
	if fx.reward_mult != 1.0:
		out.append("Credits  %+d%%" % roundi((fx.reward_mult - 1.0) * 100.0))
	if fx.thermal_mult != 1.0:
		out.append("Vs chilled/frozen  %+d%%" % roundi((fx.thermal_mult - 1.0) * 100.0))
	if fx.emp_radius_mult != 1.0:
		out.append("EMP radius  %+d%%" % roundi((fx.emp_radius_mult - 1.0) * 100.0))
	if fx.emp_freeze_mult != 1.0:
		out.append("EMP freeze  %+d%%" % roundi((fx.emp_freeze_mult - 1.0) * 100.0))
	if fx.upgrade_cost_mult != 1.0:
		out.append("Upgrade cost  %+d%%" % roundi((fx.upgrade_cost_mult - 1.0) * 100.0))
	if fx.repair_cost_mult != 1.0:
		out.append("Repair cost  %+d%%" % roundi((fx.repair_cost_mult - 1.0) * 100.0))
	if fx.sell_refund != 0.7:
		out.append("Sell refund  %d%%" % roundi(fx.sell_refund * 100.0))
	if fx.start_money != 0.0:
		out.append("Start credits  +%d" % int(fx.start_money))
	if fx.start_lives != 0:
		out.append("Start lives  +%d" % int(fx.start_lives))
	if fx.start_energy != 0.0:
		out.append("Start energy  +%d" % int(fx.start_energy))
	if fx.energy_per_kill != 0.0:
		out.append("Energy / kill  +%.1f" % fx.energy_per_kill)
	if fx.execute:
		out.append("Execute  (<15% HP -> x2)")
	if fx.arc_chill:
		out.append("Arc attacks chill")
	if fx.last_stand:
		out.append("Last Stand active")
	return out

# ---------------------------------------------------------------------------
# Allocation (path-based; big nodes gated by their whole ring) + refund
# ---------------------------------------------------------------------------

func is_allocated(id: String) -> bool:
	return allocated.has(id)

## A node is reachable when START or any allocated node is a neighbour.
func is_reachable(node: Dictionary) -> bool:
	for nb in node.neighbors:
		if allocated.has(nb):
			return true
	return false

## Big/capstone nodes unlock only once every pip around them is allocated.
func ring_complete(node: Dictionary) -> bool:
	if node.kind != "big" and node.kind != "capstone":
		return true
	for nb in node.neighbors:
		if not allocated.has(nb):
			return false
	return true

func can_allocate(node: Dictionary) -> bool:
	return not is_allocated(node.id) and node.kind != "start" \
			and is_reachable(node) and ring_complete(node) and rp >= int(node.cost)

func allocate(id: String) -> bool:
	var node: Dictionary = by_id.get(id, {})
	if node.is_empty() or not can_allocate(node):
		return false
	var was_complete := is_complete()
	rp -= int(node.cost)
	allocated[id] = true
	_recompute()
	_save()
	if not was_complete and is_complete():
		research_complete.emit() # endgame reached; waves still go forever
	return true

## Endgame condition: the entire tree is allocated.
func is_complete() -> bool:
	return allocated.size() == nodes.size()

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
