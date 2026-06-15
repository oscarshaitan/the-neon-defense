class_name World
extends Node2D
## Game world: entities, waves, combat, abilities, placement, and effects.
## Entities are lightweight RefCounted data objects updated here in tight
## loops and drawn batched by the render layers (the JS architecture) —
## per-entity nodes would cost far more at 200+ enemies.

signal rifts_changed
signal hardpoints_changed
signal wave_started
signal tower_built
signal build_target_selected

const CELL := 200.0 # spatial hash cell (JS ENEMY_SPATIAL_GRID)

var rng := RandomNumberGenerator.new()
var core_cell := Vector2i(C.WORLD_COLS / 2, C.WORLD_ROWS / 2)
var core_pos: Vector2

# --- Entities ---
class Enemy:
	var type: StringName
	var hp: float
	var max_hp: float
	var speed: float
	var color: Color
	var reward: float
	var width: float
	var pos: Vector2
	var path: PackedVector2Array
	var path_index := 0
	var rift_level := 1
	var is_mutant := false
	var frozen := 0
	var chill := 0 # Tech CONTROL: slowed (not stopped) by arc Cryo Conductors
	var static_charges := 0.0
	var stun := 0
	var invisible := false
	var dead := false

class Tower:
	var type: StringName
	var pos: Vector2
	var damage: float
	var range: float
	var cooldown := 0
	var max_cooldown: int
	var color: Color
	var base_cost: float
	var total_cost: float
	var level := 1
	var hardpoint: Dictionary = {} # empty = soft point
	var scale := 1.0
	var overclocked := false
	var overclock_timer := 0
	var arc_bonus := 1

class Projectile:
	var pos: Vector2
	var target: Enemy
	var damage: float
	var speed: float
	var color: Color

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var projectiles: Array[Projectile] = []
# Arc-tower network (JS arcTowerLinks): [{a: Tower, b: Tower, strength: int}].
# Rebuilt lazily whenever towers are added/removed.
var arc_tower_links: Array = []
var _arc_network_dirty := true
var hardpoints: Array[Dictionary] = [] # {id, type, cell, pos, occupied}
var rifts: Array[Dictionary] = [] # {cells, points, level, zone, mutation}

# --- Wave state ---
var prep_timer := 0.0
var is_prep_phase := false
var spawn_timer := 0
var spawn_queue: Array[StringName] = []
var current_wave_distribution := {}

# --- Base turret (JS baseLevel/baseCooldown) ---
var base_level := 0
var base_cooldown := 0
var _last_stand_used := false # Tech CORE capstone fires once per run

# --- Abilities ---
var targeting_ability: StringName = &""

# --- Debug / command center (JS showNoBuildOverlay) ---
var show_no_build_overlay := false

# --- Spatial hash ---
var _grid := {}
var _taunter_grid := {}

# --- Effects pools (budgets per quality profile) ---
var particles: Array = [] # {pos, vel, life, color, priority}
var lights: Array = [] # {pos, radius, color, life}
var arc_bursts: Array = [] # {a, b, life, intensity}
var quality := 0 # index into C.QUALITY_PROFILES
var auto_quality := true
var _ema_ms := 16.0
var _down_count := 0
var _up_count := 0

var save_system: SaveSystem
var tutorial: Tutorial
var hints: Hints

func _ready() -> void:
	rng.randomize()
	core_pos = (Vector2(core_cell) + Vector2(0.5, 0.5)) * C.GRID_SIZE
	_build_hardpoints()
	save_system = SaveSystem.new(self)
	tutorial = Tutorial.new()
	hints = Hints.new()

# ---------------------------------------------------------------------------
# Hardpoints (JS buildHardpoints)
# ---------------------------------------------------------------------------

func _build_hardpoints() -> void:
	hardpoints.clear()
	for i in C.CORE_HP_COUNT:
		var angle := TAU * i / C.CORE_HP_COUNT - PI / 2
		_add_hardpoint("core_%d" % i, &"core",
				core_pos + Vector2(cos(angle), sin(angle)) * C.CORE_HP_RADIUS_CELLS * C.GRID_SIZE)
	var micro_index := 0
	for ring in C.MICRO_RINGS:
		for i in ring.count:
			var angle: float = TAU * i / ring.count + ring.angle_offset - PI / 2
			_add_hardpoint("micro_%d" % micro_index, &"micro",
					core_pos + Vector2(cos(angle), sin(angle)) * ring.radius_cells * C.GRID_SIZE)
			micro_index += 1

func _add_hardpoint(id: String, type: StringName, world_pos: Vector2) -> void:
	var cell := Vector2i(world_pos / C.GRID_SIZE)
	hardpoints.append({id = id, type = type, cell = cell,
			pos = (Vector2(cell) + Vector2(0.5, 0.5)) * C.GRID_SIZE, occupied = false})

func hardpoint_cells() -> Dictionary:
	var cells := {}
	for hp in hardpoints:
		cells[hp.cell] = true
	return cells

func hardpoint_at(snap: Vector2) -> Dictionary:
	var best := {}
	var best_d := C.HP_SNAP_RADIUS
	for hp in hardpoints:
		var d: float = hp.pos.distance_to(snap)
		if d < best_d:
			best_d = d
			best = hp
	return best

# ---------------------------------------------------------------------------
# Fixed-step logic (driven by main.gd at 60 Hz)
# ---------------------------------------------------------------------------

func step() -> void:
	State.frame_count += 1
	_step_wave()
	_step_enemies()
	_step_towers()
	_step_base()
	_step_projectiles()
	_step_effects()
	save_system.flush_queued()
	if State.frame_count % 30 == 0:
		var threat := false
		for e in enemies:
			if e.type == &"boss" or e.is_mutant:
				threat = true
				break
		AudioEngine.update_music(State.wave, threat)

func record_frame_ms(ms: float) -> void:
	_ema_ms = _ema_ms * 0.9 + ms * 0.1
	if not auto_quality:
		return
	if ms > C.QUALITY_DOWNGRADE_FRAME_MS or _ema_ms > C.QUALITY_DOWNGRADE_EMA_MS:
		_up_count = 0
		_down_count += 1
		if _down_count >= C.QUALITY_DOWNGRADE_WINDOW:
			_down_count = 0
			if quality < 2:
				quality += 1
				State.show_toast("AUTO: DETAILS → " + C.QUALITY_PROFILES[quality].name)
	elif ms < C.QUALITY_UPGRADE_FRAME_MS and _ema_ms < C.QUALITY_UPGRADE_EMA_MS:
		_down_count = 0
		_up_count += 1
		if _up_count >= C.QUALITY_UPGRADE_WINDOW:
			_up_count = 0
			if quality > 0:
				quality -= 1
				State.show_toast("AUTO: DETAILS → " + C.QUALITY_PROFILES[quality].name)
	else:
		_down_count = 0
		_up_count = 0

func set_quality_manual(index: int) -> void:
	auto_quality = false
	quality = clampi(index, 0, 2)
	State.show_toast("DETAILS: " + C.QUALITY_PROFILES[quality].name)

# ---------------------------------------------------------------------------
# Waves (JS startPrepPhase/startWave/spawnEnemy)
# ---------------------------------------------------------------------------

func start_prep_phase() -> void:
	is_prep_phase = true
	prep_timer = C.PREP_TIMER_SECONDS
	_generate_missing_rifts()

func skip_prep() -> void:
	if is_prep_phase:
		prep_timer = 0.0

func _generate_missing_rifts() -> void:
	var target := 1 + (State.wave - 1) / 10 if State.wave <= 50 else 6 + (State.wave - 51) / 5
	target = clampi(target, 1, 20)
	var hp_cells := hardpoint_cells()
	var core_slots: Array = []
	for hp in hardpoints:
		if hp.type == &"core":
			core_slots.append(hp.cell)
	while rifts.size() < target:
		var result: Dictionary
		if rifts.is_empty():
			result = Pathfinding.generate_initial_rift(C.WORLD_COLS, C.WORLD_ROWS, core_cell, hp_cells, rng)
		else:
			result = Pathfinding.generate_new_rift(C.WORLD_COLS, C.WORLD_ROWS, core_cell,
					hp_cells, core_slots, rifts, State.wave, rng)
		if result.is_empty():
			break
		var points := PackedVector2Array()
		for cell in result.cells:
			points.append((Vector2(cell) + Vector2(0.5, 0.5)) * C.GRID_SIZE)
		var rift := {cells = result.cells, points = points, level = 1, zone = result.zone, mutation = {}}
		rifts.append(rift)
		_destroy_towers_on_path(points)
	rifts_changed.emit()

## JS generateNewPath tower destruction: new rifts destroy overlapping
## non-hardpoint towers with a 70% refund.
func _destroy_towers_on_path(points: PackedVector2Array) -> void:
	var doomed: Array[Tower] = []
	for t in towers:
		if not t.hardpoint.is_empty():
			continue
		for j in points.size() - 1:
			if segment_box_hit(t.pos, points[j], points[j + 1], C.GRID_SIZE / 2):
				doomed.append(t)
				break
	for t in doomed:
		State.money += floorf(t.base_cost * t.level * 0.7)
		create_particles(t.pos, Color.WHITE, 10)
		remove_tower(t)

static func segment_box_hit(p: Vector2, a: Vector2, b: Vector2, tolerance: float) -> bool:
	if absf(a.y - b.y) < 1.0:
		return absf(p.y - a.y) < tolerance and p.x >= minf(a.x, b.x) - tolerance \
				and p.x <= maxf(a.x, b.x) + tolerance
	return absf(p.x - a.x) < tolerance and p.y >= minf(a.y, b.y) - tolerance \
			and p.y <= maxf(a.y, b.y) + tolerance

func _step_wave() -> void:
	if is_prep_phase:
		prep_timer -= 1.0 / C.LOGIC_FPS
		if prep_timer <= 0.0:
			_start_wave()
		return
	if State.is_wave_active:
		spawn_timer += 1
		if spawn_timer >= C.SPAWN_INTERVAL_FRAMES and not spawn_queue.is_empty():
			spawn_timer = 0
			_spawn_next()
		if spawn_queue.is_empty() and enemies.is_empty():
			State.is_wave_active = false
			Tech.award_wave(State.wave) # earn Research Points for the cleared wave
			State.wave += 1
			start_prep_phase()
			save_system.save_now()

func _start_wave() -> void:
	is_prep_phase = false
	State.is_wave_active = true
	spawn_queue.clear()
	spawn_timer = 0
	var wave := State.wave

	# Mutations last one wave; rifts evolve permanently past wave 50.
	for rift in rifts:
		rift.mutation = {}
	if wave > 50:
		for rift in rifts:
			if rng.randf() < 0.10:
				rift.level += 1
	if wave % 20 == 0 and not rifts.is_empty():
		var target: Dictionary = rifts[rng.randi_range(0, rifts.size() - 1)]
		target.mutation = C.MUTATION_PROFILES[rng.randi_range(0, C.MUTATION_PROFILES.size() - 1)]
		AudioEngine.play_sfx(&"hit")
	rifts_changed.emit()

	# JS startWave composition.
	var count := 5 + int(wave * 2.5)
	for i in count:
		var type: StringName = &"basic"
		var r := rng.randf()
		if wave < 3:
			type = &"basic"
		elif wave < 5:
			type = &"fast" if r < 0.3 else &"basic"
		elif wave < 10:
			if wave % 5 == 0 and i < 2:
				type = &"tank"
			elif r < 0.2:
				type = &"fast"
			elif r < 0.25:
				type = &"tank"
			else:
				type = &"basic"
		else:
			var chance := rng.randf()
			if chance < 0.08 and wave >= 30:
				type = &"shifter"
			elif chance < 0.15 and wave >= 20:
				type = &"bulwark"
			elif chance < 0.30 and wave >= 15:
				type = &"splitter"
			elif chance < 0.50:
				type = &"fast"
			elif chance < 0.70:
				type = &"tank"
			else:
				type = &"basic"
		spawn_queue.append(type)
	if wave % 10 == 0:
		spawn_queue.insert(rng.randi_range(0, spawn_queue.size()), &"boss")
	if wave > 50 and wave % 5 == 0 and wave % 10 != 0 and rng.randf() < 0.25:
		spawn_queue.insert(rng.randi_range(0, spawn_queue.size()), &"boss")
		AudioEngine.play_sfx(&"hit")

	current_wave_distribution = {}
	for t in spawn_queue:
		current_wave_distribution[t] = int(current_wave_distribution.get(t, 0)) + 1
	AudioEngine.play_sfx(&"build")
	save_system.save_now()
	wave_started.emit()
	tutorial.on_wave_started()
	hints.maybe_show(&"camera_controls",
			"Camera controls: drag to pan, pinch/wheel to zoom, recenter to reset.")

## JS spawnEnemy: wave scaling -> rift tier scaling -> mutation multipliers.
func _spawn_next() -> void:
	if spawn_queue.is_empty() or rifts.is_empty():
		return
	var type: StringName = spawn_queue.pop_front()
	var rift: Dictionary = rifts[rng.randi_range(0, rifts.size() - 1)]
	var def := C.enemy_def(type)
	var e := Enemy.new()
	e.type = type
	e.hp = def.hp * (1.0 + State.wave * 0.4)
	e.speed = def.speed
	e.reward = def.reward
	e.color = def.color
	e.width = def.width
	if rift.level > 1:
		e.hp *= 1.0 + (rift.level - 1) * 0.5
		e.speed *= 1.0 + (rift.level - 1) * 0.15
		e.reward = floorf(e.reward * (1.0 + (rift.level - 1) * 0.5))
	if not rift.mutation.is_empty():
		e.hp *= rift.mutation.hp
		e.speed *= rift.mutation.speed
		e.reward = floorf(e.reward * rift.mutation.reward)
		e.color = rift.mutation.color
		e.is_mutant = true
	e.max_hp = e.hp
	e.rift_level = rift.level
	e.path = rift.points
	e.pos = rift.points[0]
	_grid_insert(e)
	enemies.append(e)
	if type == &"boss":
		add_light(e.pos, 150.0, Color("ff8800"))

## JS spawnSubUnits: splitters burst into 2-3 minis.
func _spawn_minis(parent: Enemy) -> void:
	var def := C.enemy_def(&"mini")
	for i in 2 + rng.randi_range(0, 1):
		var e := Enemy.new()
		e.type = &"mini"
		e.hp = parent.max_hp * 0.2
		e.max_hp = e.hp
		e.speed = parent.speed * 1.5
		e.color = parent.color
		e.reward = def.reward
		e.width = def.width
		e.path = parent.path
		e.path_index = parent.path_index
		e.rift_level = parent.rift_level
		e.is_mutant = parent.is_mutant
		e.pos = parent.pos + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 20.0
		_grid_insert(e)
		enemies.append(e)

# ---------------------------------------------------------------------------
# Enemies
# ---------------------------------------------------------------------------

func _step_enemies() -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var e := enemies[i]
		if e.frozen > 0:
			if e.stun > 0:
				e.stun -= 1
			e.frozen -= 1
			if State.frame_count % 16 == 0:
				create_particles(e.pos, C.COL_BLUE, 1, 0)
			i -= 1
			continue
		if e.stun > 0:
			e.stun -= 1
			if State.frame_count % 16 == 0:
				create_particles(e.pos, Color("7cd7ff"), 1, 0)
			i -= 1
			continue
		if e.path_index >= e.path.size():
			_enemy_reached_core(e, i)
			i -= 1
			continue
		var target := e.path[e.path_index]
		var diff := target - e.pos
		var dist := diff.length()
		var old := e.pos
		var spd := e.speed
		if e.chill > 0:
			e.chill -= 1
			spd *= Tech.CHILL_SLOW
			if State.frame_count % 16 == 0:
				create_particles(e.pos, C.COL_BLUE, 1, 0)
		if dist <= spd:
			e.pos = target
			e.path_index += 1
		else:
			e.pos += diff / dist * spd
		_grid_update(e, old)
		if e.type == &"shifter":
			e.invisible = (State.frame_count % 360) > 180
		i -= 1

func _enemy_reached_core(e: Enemy, index: int) -> void:
	_grid_remove(e)
	enemies.remove_at(index)
	State.lives -= 1
	State.start_shake(20.0)
	AudioEngine.play_sfx(&"hit")
	if State.lives <= 0:
		# Tech CORE capstone: Last Stand Protocol — survive once per run.
		if Tech.fx.last_stand and not _last_stand_used:
			_last_stand_used = true
			State.lives = Tech.LAST_STAND_LIVES
			State.show_toast("LAST STAND PROTOCOL")
			create_particles(core_pos, C.COL_GREEN, 30)
		else:
			game_over()

func hit_enemy(e: Enemy, damage: float) -> void:
	damage *= Tech.fx.dmg_mult # Tech OFFENSE: global tower damage
	if e.frozen > 0:
		damage *= 1.2 # JS hitEnemy frozen bonus
	if e.frozen > 0 or e.chill > 0:
		damage *= Tech.fx.thermal_mult # Tech CONTROL: Thermal Weakness
	# Tech OFFENSE capstone: Executioner — finish low-HP targets.
	if Tech.fx.execute and e.max_hp > 0.0 and e.hp / e.max_hp <= Tech.EXECUTE_THRESHOLD:
		damage *= Tech.EXECUTE_BONUS
	e.hp -= damage
	if e.hp <= 0 and not e.dead:
		e.dead = true
		_grid_remove(e)
		enemies.erase(e)
		State.money += e.reward * Tech.fx.reward_mult # Tech ECONOMY: Salvage
		State.add_energy(1.0 + Tech.fx.energy_per_kill) # Tech CORE: Energy Siphon
		State.record_kill(e.type)
		create_particles(e.pos, e.color, 4, 2)
		add_light(e.pos, 60.0, e.color)
		AudioEngine.play_sfx(&"explosion")
		if e.type == &"splitter":
			_spawn_minis(e)
		save_system.queue_auto_save()

func apply_static(e: Enemy, amount: float) -> void:
	e.static_charges += amount
	if e.static_charges >= C.ARC_STATIC_THRESHOLD:
		e.static_charges = 0.0
		e.stun = C.ARC_STUN_FRAMES

# ---------------------------------------------------------------------------
# Towers + base (JS updateTowers)
# ---------------------------------------------------------------------------

func _step_towers() -> void:
	_refresh_arc_network()
	for t in towers:
		var cd_rate := 1
		if t.overclocked:
			cd_rate = 2
			t.overclock_timer -= 1
			if t.overclock_timer <= 0:
				t.overclocked = false
			if State.frame_count % 14 == 0:
				create_particles(t.pos, C.COL_YELLOW, 1, 0)
		if t.cooldown > 0:
			t.cooldown -= cd_rate
		var target := _find_target(t.pos, t.range)
		if target != null and t.cooldown <= 0:
			_fire(t, target)
			t.cooldown = t.max_cooldown

## JS isArcLinkPair: two arc towers link when cardinally aligned and 1–3 cells
## apart (Manhattan).
func _is_arc_link_pair(a: Tower, b: Tower) -> bool:
	var ac := floori(a.pos.x / C.GRID_SIZE)
	var ar := floori(a.pos.y / C.GRID_SIZE)
	var bc := floori(b.pos.x / C.GRID_SIZE)
	var br := floori(b.pos.y / C.GRID_SIZE)
	var dc := absi(ac - bc)
	var dr := absi(ar - br)
	var spacing := dc + dr
	var aligned := (dc == 0 and dr > 0) or (dr == 0 and dc > 0)
	if not aligned:
		return false
	return spacing >= C.ARC_MIN_LINK_CELLS and spacing <= C.ARC_MAX_LINK_CELLS

## JS refreshArcTowerNetwork: build link adjacency, find connected components
## via DFS, and grant each member a bonus = component size (capped). Each link's
## strength = max bonus of its endpoints. Rebuilt only when towers change.
func _refresh_arc_network() -> void:
	if not _arc_network_dirty:
		return
	_arc_network_dirty = false

	var arc_towers: Array[Tower] = []
	for t in towers:
		if t.type == &"arc":
			arc_towers.append(t)
	arc_tower_links = []
	if arc_towers.is_empty():
		return

	var adjacency := {}
	for t in arc_towers:
		adjacency[t] = []
	for i in arc_towers.size():
		for j in range(i + 1, arc_towers.size()):
			var a: Tower = arc_towers[i]
			var b: Tower = arc_towers[j]
			if not _is_arc_link_pair(a, b):
				continue
			adjacency[a].append(b)
			adjacency[b].append(a)
			arc_tower_links.append({a = a, b = b, strength = 1})

	var visited := {}
	for t in arc_towers:
		if visited.has(t):
			continue
		var stack: Array[Tower] = [t]
		var component: Array[Tower] = []
		visited[t] = true
		while not stack.is_empty():
			var node: Tower = stack.pop_back()
			component.append(node)
			for next in adjacency[node]:
				if visited.has(next):
					continue
				visited[next] = true
				stack.append(next)
		var bonus := clampi(component.size(), 1, C.ARC_MAX_BONUS)
		for node in component:
			node.arc_bonus = bonus

	for link in arc_tower_links:
		link.strength = clampi(maxi(link.a.arc_bonus, link.b.arc_bonus), 1, C.ARC_MAX_BONUS)

func _step_base() -> void:
	if base_level <= 0:
		return
	if base_cooldown > 0:
		base_cooldown -= 1
	var range := 150.0 + (base_level - 1) * 30.0
	var target := _find_nearest(core_pos, range)
	if target != null and base_cooldown <= 0:
		var p := Projectile.new()
		p.pos = core_pos
		p.target = target
		p.damage = 20.0 + (base_level - 1) * 10.0
		p.speed = 12.0
		p.color = C.COL_GREEN
		projectiles.append(p)
		base_cooldown = maxi(8, 35 - base_level * 5)
		AudioEngine.play_shoot()

## JS targeting: bulwark taunters first, else nearest targetable enemy.
func _find_target(pos: Vector2, radius: float) -> Enemy:
	var taunter := _query_nearest(_taunter_grid, pos, radius)
	if taunter != null:
		return taunter
	return _query_nearest(_grid, pos, radius)

func _find_nearest(pos: Vector2, radius: float) -> Enemy:
	return _query_nearest(_grid, pos, radius)

func _fire(t: Tower, target: Enemy) -> void:
	if t.type == &"arc":
		_fire_arc(t, target)
		return
	var p := Projectile.new()
	p.pos = t.pos
	p.target = target
	p.damage = t.damage
	p.speed = 10.0
	p.color = t.color
	projectiles.append(p)
	add_light(t.pos, 40.0, t.color)
	AudioEngine.play_shoot()

## Arc: instant chain with static charge accumulation (JS fireArcTower).
func _fire_arc(t: Tower, target: Enemy) -> void:
	hit_enemy(target, t.damage)
	apply_static(target, float(t.arc_bonus))
	if Tech.fx.arc_chill:
		target.chill = Tech.CHILL_FRAMES
	add_arc_burst(t.pos, target.pos, t.arc_bonus)
	var visited := {target: true}
	var from := target.pos
	var bounce_damage := t.damage * 0.7
	for _i in 3: # base chain targets
		var next := _query_nearest_excluding(_grid, from, 160.0, visited)
		if next == null:
			break
		hit_enemy(next, bounce_damage)
		if Tech.fx.arc_chill:
			next.chill = Tech.CHILL_FRAMES
		apply_static(next, 1.0)
		add_arc_burst(from, next.pos, maxi(1, t.arc_bonus - 1))
		visited[next] = true
		from = next.pos
	add_light(t.pos, 46.0, t.color)
	AudioEngine.play_shoot()

func _step_projectiles() -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		if p.target == null or p.target.dead or not enemies.has(p.target):
			projectiles.remove_at(i)
			i -= 1
			continue
		var diff := p.target.pos - p.pos
		var dist := diff.length()
		if dist < p.speed:
			hit_enemy(p.target, p.damage)
			projectiles.remove_at(i)
		else:
			p.pos += diff / dist * p.speed
		i -= 1

# ---------------------------------------------------------------------------
# Placement (JS isValidPlacement/buildTower)
# ---------------------------------------------------------------------------

static func snap_to_grid(world_pos: Vector2) -> Vector2:
	return (Vector2(floorf(world_pos.x / C.GRID_SIZE), floorf(world_pos.y / C.GRID_SIZE))
			+ Vector2(0.5, 0.5)) * C.GRID_SIZE

func validate_placement(world_pos: Vector2, type: StringName) -> Dictionary:
	var snap := snap_to_grid(world_pos)
	var hp := hardpoint_at(snap)
	if State.money < C.tower_def(type).cost:
		return {valid = false, reason = "cost", snap = snap, hp = hp}
	if hp.is_empty():
		for rift in rifts:
			var pts: PackedVector2Array = rift.points
			for j in pts.size() - 1:
				if segment_box_hit(snap, pts[j], pts[j + 1], C.GRID_SIZE / 2):
					return {valid = false, reason = "path", snap = snap, hp = hp}
	for t in towers:
		if t.pos.distance_to(snap) < 1.0:
			return {valid = false, reason = "tower", snap = snap, hp = hp}
	return {valid = true, reason = "", snap = snap, hp = hp}

func is_tile_free(snap: Vector2) -> bool:
	for t in towers:
		if t.pos.distance_to(snap) < 1.0:
			return false
	if hardpoint_at(snap).is_empty():
		var cell := Vector2i(snap / C.GRID_SIZE)
		for rift in rifts:
			for rc in rift.cells:
				if Vector2i(rc) == cell:
					return false
	return true

func build_tower(world_pos: Vector2, type: StringName) -> bool:
	var v := validate_placement(world_pos, type)
	if not v.valid:
		if v.reason == "path" or v.reason == "tower":
			create_particles(v.snap, Color.RED, 5)
		return false
	var hp: Dictionary = v.hp
	if not hp.is_empty() and hp.occupied:
		return false
	var def := C.tower_def(type)
	var mult := C.CORE_MULT if (not hp.is_empty() and hp.type == &"core") else C.MICRO_MULT
	State.money -= def.cost
	var t := Tower.new()
	t.type = type
	t.pos = v.snap
	t.color = def.color
	t.base_cost = def.cost
	t.total_cost = def.cost
	if hp.is_empty():
		t.damage = def.damage
		t.range = minf(def.range * Tech.fx.range_mult, C.MAX_TOWER_RANGE)
		t.max_cooldown = maxi(4, roundi(def.cooldown * Tech.fx.cooldown_mult))
	else:
		hp.occupied = true
		t.hardpoint = hp
		t.damage = def.damage * mult.damage
		t.range = minf(def.range * mult.range * Tech.fx.range_mult, C.MAX_TOWER_RANGE)
		t.max_cooldown = maxi(4, roundi(def.cooldown * mult.cooldown * Tech.fx.cooldown_mult))
		t.scale = mult.scale
		hardpoints_changed.emit()
	towers.append(t)
	_arc_network_dirty = true
	create_particles(v.snap, def.color, 5)
	AudioEngine.play_sfx(&"build")
	State.select_tower(t) # JS keeps the new tower selected
	save_system.save_now()
	tower_built.emit()
	tutorial.on_tower_built()
	return true

func remove_tower(t: Tower) -> void:
	if not t.hardpoint.is_empty():
		t.hardpoint.occupied = false
		hardpoints_changed.emit()
	if State.selected_tower == t:
		State.select_tower(null)
	towers.erase(t)
	_arc_network_dirty = true

func upgrade_selected() -> void:
	var t: Tower = State.selected_tower
	if t == null:
		return
	var cost := upgrade_cost(t)
	if State.money < cost:
		return
	State.money -= cost
	t.level += 1
	t.damage *= 1.2
	t.range = minf(t.range * 1.1, C.MAX_TOWER_RANGE)
	t.total_cost += cost
	create_particles(t.pos, C.COL_GREEN, 15)
	save_system.save_now()

func sell_selected() -> void:
	var t: Tower = State.selected_tower
	if t == null:
		return
	State.money += sell_value(t)
	create_particles(t.pos, Color.WHITE, 10)
	remove_tower(t)
	save_system.save_now()

static func upgrade_cost(t: Tower) -> float:
	return floorf(t.base_cost * 0.5 * t.level * Tech.fx.upgrade_cost_mult) # Tech ECONOMY

static func sell_value(t: Tower) -> float:
	return floorf(t.total_cost * Tech.fx.sell_refund) # Tech ECONOMY (default 0.7)

# --- Base repair/upgrade (JS quirks preserved: +2 lives, +2 levels) ---

func base_repair_cost() -> float:
	var base := 50.0 if State.lives < 20 else 50.0 + (State.lives - 20 + 1) * 25.0
	return floorf(base * Tech.fx.repair_cost_mult) # Tech CORE: Field Repairs

func base_upgrade_cost() -> float:
	return 200.0 * (base_level + 1)

func repair_base() -> void:
	var cost := base_repair_cost()
	if State.money < cost:
		return
	State.money -= cost
	State.lives += 2 # JS repairBase increments twice
	create_particles(core_pos, C.COL_GREEN, 20)
	AudioEngine.play_sfx(&"build")
	save_system.save_now()

func upgrade_base() -> void:
	var cost := base_upgrade_cost()
	if State.money < cost or base_level >= 10:
		return
	State.money -= cost
	base_level += 2 # JS upgradeBase increments twice
	create_particles(core_pos, C.COL_BLUE, 30)
	AudioEngine.play_sfx(&"build")
	save_system.save_now()

# ---------------------------------------------------------------------------
# Abilities (JS abilities)
# ---------------------------------------------------------------------------

func start_targeting(ability: StringName) -> void:
	var cost := C.EMP_COST if ability == &"emp" else C.OVERCLOCK_COST
	if State.energy < cost:
		return
	targeting_ability = ability

func use_ability(world_pos: Vector2) -> void:
	var ability := targeting_ability
	targeting_ability = &""
	if ability == &"emp":
		State.energy -= C.EMP_COST
		var radius: float = C.EMP_RADIUS * Tech.fx.emp_radius_mult # Tech CONTROL: Deep Freeze
		var freeze := int(C.EMP_DURATION_FRAMES * Tech.fx.emp_freeze_mult) # Cryo EMP
		for e in enemies:
			if e.pos.distance_to(world_pos) <= radius:
				e.frozen = freeze
		create_particles(world_pos, C.COL_BLUE, 20)
		add_light(world_pos, 250.0, C.COL_BLUE)
	elif ability == &"overclock":
		var nearest: Tower = null
		var best := 80.0
		for t in towers:
			var d := t.pos.distance_to(world_pos)
			if d < best:
				best = d
				nearest = t
		if nearest == null:
			return
		State.energy -= C.OVERCLOCK_COST
		nearest.overclocked = true
		nearest.overclock_timer = C.OVERCLOCK_DURATION_FRAMES
		create_particles(nearest.pos, C.COL_YELLOW, 15)

# ---------------------------------------------------------------------------
# Effects (budgeted pools)
# ---------------------------------------------------------------------------

func create_particles(pos: Vector2, color: Color, count: int, priority := 1) -> void:
	var max_particles: int = C.QUALITY_PROFILES[quality].max_particles
	for i in count:
		if particles.size() >= max_particles:
			return
		particles.append({pos = pos, vel = Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 5.0,
				life = 1.0, color = color, priority = priority})

func add_light(pos: Vector2, radius: float, color: Color) -> void:
	if lights.size() >= C.QUALITY_PROFILES[quality].max_lights:
		return
	lights.append({pos = pos, radius = radius, color = color, life = 1.0})

func add_arc_burst(a: Vector2, b: Vector2, intensity: int) -> void:
	if arc_bursts.size() >= C.QUALITY_PROFILES[quality].max_arc_bursts:
		return
	arc_bursts.append({a = a, b = b, life = 8, intensity = clampi(intensity, 1, 5),
			phase = rng.randf() * TAU})

func _step_effects() -> void:
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p.pos += p.vel
		p.life -= 0.05
		if p.life <= 0.0:
			particles.remove_at(i)
		i -= 1
	i = lights.size() - 1
	while i >= 0:
		# JS decays light life by 0.1/frame (~10-frame punchy muzzle flash);
		# the old 0.03 lingered ~3× too long and read as a dim blob.
		lights[i].life -= 0.1
		if lights[i].life <= 0.0:
			lights.remove_at(i)
		i -= 1
	i = arc_bursts.size() - 1
	while i >= 0:
		arc_bursts[i].life -= 1
		if arc_bursts[i].life <= 0:
			arc_bursts.remove_at(i)
		i -= 1

# ---------------------------------------------------------------------------
# Spatial hash (JS ENEMY_SPATIAL_GRID + taunter sub-grid; invisible shifters
# are untargetable)
# ---------------------------------------------------------------------------

func _cell_key(pos: Vector2) -> Vector2i:
	return Vector2i(floorf(pos.x / CELL), floorf(pos.y / CELL))

func _grid_insert(e: Enemy) -> void:
	var key := _cell_key(e.pos)
	_grid_bucket(_grid, key).append(e)
	if e.type == &"bulwark":
		_grid_bucket(_taunter_grid, key).append(e)

static func _grid_bucket(grid: Dictionary, key: Vector2i) -> Array:
	if not grid.has(key):
		grid[key] = []
	return grid[key]

func _grid_remove(e: Enemy) -> void:
	var key := _cell_key(e.pos)
	if _grid.has(key):
		_grid[key].erase(e)
	if e.type == &"bulwark" and _taunter_grid.has(key):
		_taunter_grid[key].erase(e)

func _grid_update(e: Enemy, old_pos: Vector2) -> void:
	var old_key := _cell_key(old_pos)
	var new_key := _cell_key(e.pos)
	if old_key == new_key:
		return
	if _grid.has(old_key):
		_grid[old_key].erase(e)
	_grid_bucket(_grid, new_key).append(e)
	if e.type == &"bulwark":
		if _taunter_grid.has(old_key):
			_taunter_grid[old_key].erase(e)
		_grid_bucket(_taunter_grid, new_key).append(e)

func _query_nearest(grid: Dictionary, pos: Vector2, radius: float) -> Enemy:
	return _query_nearest_excluding(grid, pos, radius, {})

func _query_nearest_excluding(grid: Dictionary, pos: Vector2, radius: float,
		exclude: Dictionary) -> Enemy:
	var min_c := Vector2i(floorf((pos.x - radius) / CELL), floorf((pos.y - radius) / CELL))
	var max_c := Vector2i(floorf((pos.x + radius) / CELL), floorf((pos.y + radius) / CELL))
	var r2 := radius * radius
	var best: Enemy = null
	var best_d2 := INF
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			var cell = grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for e: Enemy in cell:
				if e.dead or e.invisible or exclude.has(e):
					continue
				var d2 := e.pos.distance_squared_to(pos)
				if d2 <= r2 and d2 < best_d2:
					best_d2 = d2
					best = e
	return best

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func game_over() -> void:
	save_system.save_now()
	AudioEngine.play_sfx(&"hit")
	AudioEngine.stop_music()
	State.phase = State.Phase.GAME_OVER

func reset() -> void:
	enemies.clear()
	towers.clear()
	arc_tower_links.clear()
	_arc_network_dirty = true
	projectiles.clear()
	particles.clear()
	lights.clear()
	arc_bursts.clear()
	rifts.clear()
	spawn_queue.clear()
	_grid.clear()
	_taunter_grid.clear()
	for hp in hardpoints:
		hp.occupied = false
	base_level = 0
	base_cooldown = 0
	_last_stand_used = false
	is_prep_phase = false
	targeting_ability = &""
	show_no_build_overlay = false
	rifts_changed.emit()
	hardpoints_changed.emit()

# ---------------------------------------------------------------------------
# Debug / command center (JS debug functions in 00_core.js + 05_loop.js)
# ---------------------------------------------------------------------------

func debug_add_money() -> void:
	State.money += 1000000
	save_system.save_now()

## JS debugSpawn: spawn one enemy of a specific type on a random rift.
func debug_spawn(type: StringName) -> void:
	if rifts.is_empty():
		return
	var def := C.enemy_def(type)
	var rift: Dictionary = rifts[rng.randi_range(0, rifts.size() - 1)]
	var e := Enemy.new()
	e.type = type
	e.hp = def.hp * (1.0 + State.wave * 0.4)
	if rift.level > 1:
		e.hp *= 1.0 + (rift.level - 1) * 0.5
	e.max_hp = e.hp
	e.speed = def.speed
	e.reward = def.reward
	e.color = def.color
	e.width = def.width
	e.rift_level = rift.level
	e.path = rift.points
	e.pos = rift.points[0]
	_grid_insert(e)
	enemies.append(e)
	State.is_wave_active = true # ensure systems process it

## JS debugCreateRift: force-generate one extra rift.
func debug_create_rift() -> void:
	var hp_cells := hardpoint_cells()
	var core_slots: Array = []
	for hp in hardpoints:
		if hp.type == &"core":
			core_slots.append(hp.cell)
	var result: Dictionary
	if rifts.is_empty():
		result = Pathfinding.generate_initial_rift(C.WORLD_COLS, C.WORLD_ROWS, core_cell, hp_cells, rng)
	else:
		result = Pathfinding.generate_new_rift(C.WORLD_COLS, C.WORLD_ROWS, core_cell,
				hp_cells, core_slots, rifts, State.wave, rng)
	if result.is_empty():
		return
	var points := PackedVector2Array()
	for cell in result.cells:
		points.append((Vector2(cell) + Vector2(0.5, 0.5)) * C.GRID_SIZE)
	rifts.append({cells = result.cells, points = points, level = 1, zone = result.zone, mutation = {}})
	_destroy_towers_on_path(points)
	rifts_changed.emit()
	AudioEngine.play_sfx(&"build")

## JS debugLevelUpRift: bump a random rift's tier with a flash.
func debug_level_up_rift() -> void:
	if rifts.is_empty():
		return
	var rift: Dictionary = rifts[rng.randi_range(0, rifts.size() - 1)]
	rift.level += 1
	if not rift.points.is_empty():
		var start: Vector2 = rift.points[0]
		create_particles(start, C.COL_PINK, 30)
		add_light(start, 200.0, C.COL_PINK)
	rifts_changed.emit()
	AudioEngine.play_sfx(&"build")

## JS debugIncreaseWave: jump N waves, simulating skipped wave-starts so
## progression pacing (rift evolution, mutation rolls) matches normal play.
func debug_increase_wave(steps: int, auto_start: bool) -> void:
	var count := maxi(1, steps)
	_clear_combat_state()
	for i in count:
		State.wave += 1
		start_prep_phase()
		if i < count - 1:
			_start_wave() # resolve skipped wave instantly
			_clear_combat_state()
	if auto_start:
		_start_wave()
	save_system.save_now()

## JS debugRebuildRiftsByWave: wipe rifts and regenerate baseline topology.
func debug_rebuild_rifts() -> void:
	_clear_combat_state()
	State.select_rift(null)
	rifts.clear()
	start_prep_phase() # regenerates initial + missing rifts for the wave
	AudioEngine.play_sfx(&"build")
	save_system.save_now()

## Debug: add N upgrade levels to every tower for free (same per-level stat
## math as upgrade_selected, so range stays clamped to MAX_TOWER_RANGE — it is
## NOT infinite, matching the JS cap).
func debug_upgrade_all_towers(levels: int) -> void:
	for t in towers:
		for _i in levels:
			t.total_cost += upgrade_cost(t) # cost at the pre-increment level
			t.level += 1
			t.damage *= 1.2
			t.range = minf(t.range * 1.1, C.MAX_TOWER_RANGE)
		create_particles(t.pos, C.COL_GREEN, 8)
	State.selection_changed.emit() # refresh the selection panel if open
	save_system.save_now()

## JS toggleNoBuildOverlay: show/hide the spatial-zoning debug overlay.
func toggle_no_build_overlay() -> void:
	show_no_build_overlay = not show_no_build_overlay

## Lightweight tower placement for bulk setup — same stats as build_tower but
## without the per-tower save/select/sfx/signals (caller batches those).
func _stress_build(world_pos: Vector2, type: StringName) -> bool:
	var v := validate_placement(world_pos, type)
	if not v.valid:
		return false
	var hp: Dictionary = v.hp
	if not hp.is_empty() and hp.occupied:
		return false
	var def := C.tower_def(type)
	var mult := C.CORE_MULT if (not hp.is_empty() and hp.type == &"core") else C.MICRO_MULT
	State.money -= def.cost
	var t := Tower.new()
	t.type = type
	t.pos = v.snap
	t.color = def.color
	t.base_cost = def.cost
	t.total_cost = def.cost
	if hp.is_empty():
		t.damage = def.damage
		t.range = minf(def.range * Tech.fx.range_mult, C.MAX_TOWER_RANGE)
		t.max_cooldown = maxi(4, roundi(def.cooldown * Tech.fx.cooldown_mult))
	else:
		hp.occupied = true
		t.hardpoint = hp
		t.damage = def.damage * mult.damage
		t.range = minf(def.range * mult.range * Tech.fx.range_mult, C.MAX_TOWER_RANGE)
		t.max_cooldown = maxi(4, roundi(def.cooldown * mult.cooldown * Tech.fx.cooldown_mult))
		t.scale = mult.scale
	towers.append(t)
	_arc_network_dirty = true
	return true

## Debug: build a synthetic worst-case level so a human can eyeball performance
## under load — maxed base (1000 lives), ~20 level-1 rifts, a dense mix of every
## tower type around the roads/core (with a contiguous arc block that forms a
## connected network), and 100 mixed enemies.
func debug_stress_test() -> void:
	State.money = 10000000.0
	State.lives = 1000
	base_level = 10
	base_cooldown = 0

	# Rift generation is stochastic and can fail a given attempt, so retry up
	# to a bounded number of times rather than bailing on the first miss.
	var attempts := 0
	while rifts.size() < 20 and attempts < 80:
		debug_create_rift()
		attempts += 1
	for rift in rifts:
		rift.level = 1
		rift.mutation = {}

	var placed := 0
	# Connected arc cluster hugging the core (contiguous -> links), close to
	# where the rifts converge so the towers are actually in the fight.
	for dr in range(3, 8):
		for dc in range(3, 8):
			var cell := core_cell + Vector2i(dc, dr)
			if cell.x < 1 or cell.y < 1 \
					or cell.x >= C.WORLD_COLS - 1 or cell.y >= C.WORLD_ROWS - 1:
				continue
			var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * C.GRID_SIZE
			if _stress_build(pos, &"arc"):
				placed += 1
	# Pack the other tower types into a tight ring AROUND the core (all valid
	# tiles within 8 cells) so every rift's final approach runs a gauntlet.
	var others: Array[StringName] = [&"basic", &"rapid", &"sniper"]
	for dr in range(-8, 9):
		for dc in range(-8, 9):
			if placed >= 200:
				break
			if dr == 0 and dc == 0:
				continue # leave the core cell for the base
			if dr >= 3 and dr <= 7 and dc >= 3 and dc <= 7:
				continue # arc cluster already placed here
			var cell := core_cell + Vector2i(dc, dr)
			if cell.x < 1 or cell.y < 1 \
					or cell.x >= C.WORLD_COLS - 1 or cell.y >= C.WORLD_ROWS - 1:
				continue
			var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * C.GRID_SIZE
			if _stress_build(pos, others[(absi(dr) + absi(dc)) % others.size()]):
				placed += 1

	_refresh_arc_network()
	hardpoints_changed.emit()

	var etypes: Array[StringName] = [&"basic", &"fast", &"tank", &"splitter",
			&"bulwark", &"shifter", &"mini", &"boss"]
	for i in 100:
		debug_spawn(etypes[i % etypes.size()])

	State.is_wave_active = true
	rifts_changed.emit()
	save_system.save_now()
	State.show_toast("STRESS: %d towers / 100 enemies / %d rifts" % [placed, rifts.size()])

func _clear_combat_state() -> void:
	enemies.clear()
	projectiles.clear()
	particles.clear()
	arc_bursts.clear()
	arc_tower_links.clear()
	_arc_network_dirty = true
	spawn_queue.clear()
	_grid.clear()
	_taunter_grid.clear()
	State.is_wave_active = false
