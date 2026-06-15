extends Node
## Autoload "Tech" — the Tech Tree strategy layer (ROADMAP Milestone E).
##
## v3: a large Path-of-Exile-style WEB, generated procedurally so it scales for
## an endless game. A central START is always allocated; around it sit
## concentric rings of NOTABLE "hubs", each ringed by a wheel of small "pip"
## nodes, all stitched together by short travel-node paths with circumferential
## loops (so there is never a single best route). KEYSTONES live on the outer
## rim in mutually-exclusive pairs (allocate one and its rival locks out).
##
## Allocation is PATH-BASED — a node is only reachable when adjacent to one you
## already own, so Research Points (RP, +1 per wave) are spent pathing toward
## goals. RP + allocations PERSIST across runs in a separate save file.
## Allocations can be refunded (single leaf, connectivity-checked, or a free
## REFUND ALL respec). Effects accumulate into `fx`, read live by gameplay.
##
## Godot leads this feature; mirror the generator + effects to JS and Flutter.

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

const GRID_SPACING := 78.0 # grid units -> pixels in the UI
const RP_PER_WAVE := 1 # slow, deliberate progression

signal changed ## RP / allocation changed — UI refreshes on this.

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

## Per-theme small-node mixes (drawn around hubs and along travel paths).
const THEME_SMALLS := {
	"OFFENSE": ["dmg", "dmg", "rate", "range"],
	"CONTROL": ["thermal", "emp_r", "emp_f", "rate"],
	"ECONOMY": ["reward", "money", "upcost", "repair"],
	"CORE": ["energy", "regen", "repair", "money"],
}

## Per-theme notable hubs, cycled as rings are filled.
const THEME_NOTABLES := {
	"OFFENSE": [
		{name = "WEAPON CORE", desc = "+12% tower damage", fx = {dmg_mult = 1.12}},
		{name = "HAIR TRIGGER", desc = "+18% fire rate", fx = {cooldown_mult = 0.82}},
		{name = "LONG BARREL", desc = "+15% tower range", fx = {range_mult = 1.15}},
		{name = "HIGH CALIBER", desc = "+15% tower damage", fx = {dmg_mult = 1.15}},
	],
	"CONTROL": [
		{name = "CRYO CORE", desc = "+15% damage to chilled/frozen", fx = {thermal_mult = 1.15}},
		{name = "PULSE CORE", desc = "+25% EMP radius", fx = {emp_radius_mult = 1.25}},
		{name = "DEEP CHILL", desc = "+25% EMP freeze time", fx = {emp_freeze_mult = 1.25}},
		{name = "FROST EDGE", desc = "+18% damage to chilled/frozen", fx = {thermal_mult = 1.18}},
	],
	"ECONOMY": [
		{name = "TRADE HUB", desc = "+12% credits from kills", fx = {reward_mult = 1.12}},
		{name = "BARGAIN", desc = "-18% upgrade cost", fx = {upgrade_cost_mult = 0.82}},
		{name = "SCRAPYARD", desc = "-35% repair cost", fx = {repair_cost_mult = 0.65}},
		{name = "BULLION", desc = "+200 starting credits", fx = {start_money = 200.0}},
	],
	"CORE": [
		{name = "REACTOR NODE", desc = "+25 starting energy", fx = {start_energy = 25.0}},
		{name = "SIPHON ARRAY", desc = "+0.5 energy per kill", fx = {energy_per_kill = 0.5}},
		{name = "ABLATIVE PLATING", desc = "+1 starting life", fx = {start_lives = 1}},
		{name = "FORTRESS CORE", desc = "+40 starting energy", fx = {start_energy = 40.0}},
	],
}

## Rim keystones, placed in order around the outer ring. Mutually-exclusive in
## adjacent pairs: (0,1), (2,3), (4,5), (6,7), (8,9) — partner index = i ^ 1.
const KEYSTONES := [
	{name = "EXECUTIONER", desc = "Enemies below 15% HP take double damage.", fx = {execute = true}},
	{name = "OVERWHELM", desc = "+35% damage, but -12% fire rate.", fx = {dmg_mult = 1.35, cooldown_mult = 1.12}},
	{name = "DEEP FREEZE PROTOCOL", desc = "+50% EMP radius & freeze, +20% thermal.", fx = {emp_radius_mult = 1.5, emp_freeze_mult = 1.5, thermal_mult = 1.2}},
	{name = "PERMAFROST", desc = "+45% thermal damage, but -10% tower damage.", fx = {thermal_mult = 1.45, dmg_mult = 0.9}},
	{name = "LIQUIDATION", desc = "Selling towers refunds 100%.", fx = {sell_refund = 1.0}},
	{name = "WAR PROFITEER", desc = "+35% credits, but sell refund drops to 40%.", fx = {reward_mult = 1.35, sell_refund = 0.4}},
	{name = "LAST STAND PROTOCOL", desc = "Once per run, survive a fatal breach.", fx = {last_stand = true}},
	{name = "BULWARK", desc = "+5 starting lives, but -15% tower damage.", fx = {start_lives = 5, dmg_mult = 0.85}},
	{name = "GLASS CANNON", desc = "+50% damage, but -15% range.", fx = {dmg_mult = 1.5, range_mult = 0.85}},
	{name = "SIEGE DOCTRINE", desc = "+40% range, but -15% fire rate.", fx = {range_mult = 1.4, cooldown_mult = 1.15}},
]

## Concentric rings of notable hubs (outer ring becomes keystones).
const RINGS := [
	{r = 3.6, n = 5, wheel = 6},
	{r = 6.9, n = 8, wheel = 5},
	{r = 10.2, n = 10, wheel = 4},
]

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
# Graph construction (procedural radial web)
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

func _link(a: String, b: String) -> void:
	if by_id.has(a) and not by_id[a].neighbors.has(b):
		by_id[a].neighbors.append(b)
	if by_id.has(b) and not by_id[b].neighbors.has(a):
		by_id[b].neighbors.append(a)

## Direction unit vector for a compass angle in degrees (0 = up, 90 = right).
func _dir(ang_deg: float) -> Vector2:
	var r := deg_to_rad(ang_deg)
	return Vector2(sin(r), -cos(r))

## Branch/theme for an angle (top = OFFENSE, then clockwise).
func _theme_for(ang_deg: float) -> String:
	var a := fmod(ang_deg, 360.0)
	if a < 0.0:
		a += 360.0
	var idx := int(floor((a + 45.0) / 90.0)) % 4
	return BRANCHES[idx]

func _nearest(id: String, candidates: Array) -> String:
	var p: Vector2 = by_id[id].pos
	var best := ""
	var best_d := INF
	for c in candidates:
		var d: float = p.distance_squared_to(by_id[c].pos)
		if d < best_d:
			best_d = d
			best = c
	return best

## A wheel of small "pip" nodes orbiting a hub, ring-linked and tied to the hub.
func _build_wheel(hub: String, center: Vector2, theme: String, k: int, base_ang: float) -> void:
	var types: Array = THEME_SMALLS[theme]
	var wids: Array = []
	for i in k:
		var a := base_ang + (float(i) / k) * 360.0
		var p := center + _dir(a) * 0.95
		var t: Dictionary = SMALL[types[i % types.size()]]
		var wid := "%s_w%d" % [hub, i]
		_add(wid, theme, "small", p.x, p.y, 1, t.name, t.desc, t.fx, [hub])
		wids.append(wid)
	for i in k:
		_link(wids[i], wids[(i + 1) % k])

## Travel path of `m` small nodes between two existing nodes.
func _connect(a: String, b: String, m: int) -> void:
	var pa: Vector2 = by_id[a].pos
	var pb: Vector2 = by_id[b].pos
	var theme: String = by_id[b].branch if by_id[b].branch != "" else by_id[a].branch
	if theme == "":
		theme = "OFFENSE"
	var types: Array = THEME_SMALLS[theme]
	var prev := a
	for j in range(1, m + 1):
		var p := pa.lerp(pb, float(j) / (m + 1))
		var t: Dictionary = SMALL[types[j % types.size()]]
		var tid := "tr_%s_%s_%d" % [a, b, j]
		_add(tid, theme, "small", p.x, p.y, 1, t.name, t.desc, t.fx, [prev])
		prev = tid
	_link(prev, b)

func _build_graph() -> void:
	nodes.clear()
	by_id.clear()
	_add(START_ID, "", "start", 0, 0, 0, "CORE UPLINK", "Allocation origin — always active.", {}, [])

	var notable_idx := {"OFFENSE": 0, "CONTROL": 0, "ECONOMY": 0, "CORE": 0}
	var ring_hubs: Array = [] # per-ring array of hub ids
	var ks := 0
	for ri in RINGS.size():
		var ring: Dictionary = RINGS[ri]
		var is_outer: bool = ri == RINGS.size() - 1
		var ids: Array = []
		for i in int(ring.n):
			var ang := (float(i) / int(ring.n)) * 360.0 + ri * 12.0 # stagger rings
			var theme := _theme_for(ang)
			var pos := _dir(ang) * float(ring.r)
			var hub := "h%d_%d" % [ri, i]
			if is_outer and ks < KEYSTONES.size():
				var k: Dictionary = KEYSTONES[ks]
				_add(hub, theme, "keystone", pos.x, pos.y, 8, k.name, k.desc, k.fx.duplicate(), [])
				ks += 1
			else:
				var pool: Array = THEME_NOTABLES[theme]
				var nb: Dictionary = pool[notable_idx[theme] % pool.size()]
				notable_idx[theme] += 1
				_add(hub, theme, "notable", pos.x, pos.y, 4, nb.name, nb.desc, nb.fx.duplicate(), [])
			_build_wheel(hub, pos, theme, int(ring.wheel), ang)
			ids.append(hub)
		ring_hubs.append(ids)

	# Keystone exclusive pairs (rim hubs, partner index = i ^ 1).
	var outer: Array = ring_hubs[RINGS.size() - 1]
	for k in outer.size():
		var partner := k ^ 1
		if partner < outer.size():
			by_id[outer[k]].excludes = [outer[partner]]

	# Backbone connects to each cluster's GATEWAY pip (wheel[0]), never through
	# the hub — so a hub (e.g. an un-picked keystone) is an optional endpoint and
	# never strands its wheel. START -> inner ring; each ring -> nearest hub of
	# the ring inside it; plus circumferential loops so multiple routes exist.
	for hub in ring_hubs[0]:
		_connect(START_ID, hub + "_w0", 2)
	for ri in range(1, RINGS.size()):
		for hub in ring_hubs[ri]:
			_connect(_nearest(hub, ring_hubs[ri - 1]) + "_w0", hub + "_w0", 2)
	for ri in RINGS.size():
		var ids: Array = ring_hubs[ri]
		for i in ids.size():
			_connect(ids[i] + "_w0", ids[(i + 1) % ids.size()] + "_w0", 2)

	# Make every link bidirectional so reachability and refund-connectivity
	# traverse the web from either side.
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
