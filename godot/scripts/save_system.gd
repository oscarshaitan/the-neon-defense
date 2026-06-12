class_name SaveSystem
## Save/load with the JS neonDefenseSave schema (03_abilities.js:264-296) so
## states are comparable across the three versions. Writes are coalesced and
## deferred off the frame (JS requestIdleCallback parity); kills queue an
## auto-save flushed with a min 120-frame gap / 360-frame max delay.

const SAVE_PATH := "user://neon_defense_save.json"

var world # World

var _auto_pending := false
var _auto_requested_at := 0
var _last_auto_frame := -1000000
var _write_pending := false
var _snapshot := {}

func _init(game_world) -> void:
	world = game_world

func queue_auto_save() -> void:
	if not _auto_pending:
		_auto_pending = true
		_auto_requested_at = State.frame_count

func flush_queued(force := false) -> void:
	if not _auto_pending:
		return
	if not force:
		var since_last := State.frame_count - _last_auto_frame
		var waiting := State.frame_count - _auto_requested_at
		if since_last < 120 and waiting < 360:
			return
	save_now()
	_last_auto_frame = State.frame_count
	_auto_pending = false

func save_now() -> void:
	_snapshot = _build_snapshot()
	if _write_pending:
		return
	_write_pending = true
	# Defer the JSON stringify + file write off the current frame.
	(func() -> void:
		await world.get_tree().create_timer(0.05).timeout
		_write_pending = false
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(_snapshot))
	).call()

func _build_snapshot() -> Dictionary:
	var paths := []
	for rift in world.rifts:
		var points := []
		for p in rift.points:
			points.append({x = p.x, y = p.y})
		paths.append({points = points, level = rift.level, zone = rift.zone,
				mutation = null if rift.mutation.is_empty() else {
					key = rift.mutation.key, name = rift.mutation.key,
					color = "#" + rift.mutation.color.to_html(false),
					hpMulti = rift.mutation.hp, speedMulti = rift.mutation.speed,
					rewardMulti = rift.mutation.reward,
				}})
	var towers := []
	for t in world.towers:
		towers.append({type = String(t.type), x = t.pos.x, y = t.pos.y, level = t.level,
				damage = t.damage, range = t.range, cooldown = t.cooldown,
				maxCooldown = t.max_cooldown, cost = t.base_cost, totalCost = t.total_cost,
				hardpointId = null if t.hardpoint.is_empty() else t.hardpoint.id,
				hardpointType = null if t.hardpoint.is_empty() else String(t.hardpoint.type),
				hardpointScale = t.scale})
	var queue := []
	for type in world.spawn_queue:
		queue.append(String(type))
	var kills := {}
	for type in State.total_kills:
		kills[String(type)] = State.total_kills[type]
	return {
		money = State.money, lives = State.lives, wave = State.wave,
		isWaveActive = State.is_wave_active, prepTimer = world.prep_timer,
		spawnQueue = queue, paths = paths, towers = towers,
		baseLevel = world.base_level, baseCooldown = world.base_cooldown,
		energy = State.energy, playerName = State.player_name, totalKills = kills,
		pendingRiftGenerations = 0, worldCols = C.WORLD_COLS, worldRows = C.WORLD_ROWS,
	}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return false

	world.reset()
	State.clear_selection()
	State.money = float(data.get("money", C.STARTING_MONEY))
	State.lives = int(data.get("lives", C.STARTING_LIVES))
	State.wave = int(data.get("wave", 1))
	State.energy = float(data.get("energy", 0))
	State.player_name = str(data.get("playerName", ""))
	for type_name in data.get("totalKills", {}):
		State.total_kills[StringName(type_name)] = int(data.totalKills[type_name])

	for rift_data in data.get("paths", []):
		var points := PackedVector2Array()
		var cells: Array[Vector2i] = []
		for p in rift_data.get("points", []):
			var v := Vector2(float(p.x), float(p.y))
			points.append(v)
			cells.append(Vector2i(v / C.GRID_SIZE))
		var mutation := {}
		var m = rift_data.get("mutation")
		if m is Dictionary:
			for profile in C.MUTATION_PROFILES:
				if profile.key == str(m.get("key", "")):
					mutation = profile
		world.rifts.append({cells = cells, points = points,
				level = int(rift_data.get("level", 1)),
				zone = int(rift_data.get("zone", 1)), mutation = mutation})

	for t_data in data.get("towers", []):
		var type := StringName(str(t_data.get("type", "basic")))
		if not C.TOWERS.has(type):
			continue
		var t := World.Tower.new()
		t.type = type
		t.pos = Vector2(float(t_data.x), float(t_data.y))
		t.color = C.tower_def(type).color
		t.level = int(t_data.get("level", 1))
		t.damage = float(t_data.get("damage", C.tower_def(type).damage))
		t.range = float(t_data.get("range", C.tower_def(type).range))
		t.cooldown = int(t_data.get("cooldown", 0))
		t.max_cooldown = int(t_data.get("maxCooldown", C.tower_def(type).cooldown))
		t.base_cost = float(t_data.get("cost", C.tower_def(type).cost))
		t.total_cost = float(t_data.get("totalCost", t.base_cost))
		t.scale = float(t_data.get("hardpointScale", 1.0))
		var hp_id = t_data.get("hardpointId")
		if hp_id != null:
			for hp in world.hardpoints:
				if hp.id == str(hp_id):
					hp.occupied = true
					t.hardpoint = hp
		world.towers.append(t)

	world.base_level = int(data.get("baseLevel", 0))
	world.base_cooldown = int(data.get("baseCooldown", 0))

	# JS loadGame demotes a mid-wave load to a 5 s prep phase.
	State.is_wave_active = false
	world.is_prep_phase = true
	world.prep_timer = 5.0 if bool(data.get("isWaveActive", false)) \
			else clampf(float(data.get("prepTimer", 30.0)), 1.0, 30.0)
	world.rifts_changed.emit()
	world.hardpoints_changed.emit()
	return true
