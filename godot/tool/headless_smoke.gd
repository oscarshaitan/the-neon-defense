extends SceneTree
## Headless gameplay smoke test:
##   /path/to/godot --headless -s tool/headless_smoke.gd
## Boots the real main scene, starts a game, builds towers, fast-forwards
## through the first wave, and asserts the core invariants. Exits non-zero
## on failure so it can gate CI.

var _failures: Array[String] = []

# Autoload globals and project class_names aren't available at this script's
# compile time (it loads before the project does under -s); resolve them
# dynamically so the engine doesn't log recoverable compile errors.
var S: Node
var Con: GDScript
var WI: GDScript

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		printerr("  FAIL  ", label)

func _initialize() -> void:
	_run()

func _run() -> void:
	print("== Neon Defense headless smoke test ==")
	await process_frame
	S = root.get_node("/root/State")
	Con = load("res://scripts/constants.gd")
	WI = load("res://scripts/wave_intel.gd")
	_check(S != null, "State autoload present")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var world = main.world
	_check(world != null, "world initialized")
	_check(world.hardpoints.size() == 30, "30 hardpoints built")

	main.start_game()
	world.tutorial.skip()
	await process_frame
	_check(S.phase == S.Phase.PLAYING, "phase -> PLAYING")
	_check(world.is_prep_phase, "prep phase active")
	_check(world.rifts.size() >= 1, "initial rift generated")
	if not world.rifts.is_empty():
		var rift = world.rifts[0]
		_check(rift.points.size() >= 3, "rift path has waypoints")
		var last: Vector2 = rift.points[rift.points.size() - 1]
		_check(last.distance_to(world.core_pos) < Con.GRID_SIZE,
				"rift terminates at the core")

	# Build a tower on a core hardpoint and one on a free tile.
	var hp = world.hardpoints[0]
	_check(world.build_tower(hp.pos, &"basic"), "tower built on hardpoint")
	if not world.towers.is_empty():
		var t = world.towers[0]
		_check(absf(t.damage - 10.0 * 1.08) < 0.001, "core hardpoint damage x1.08")
		_check(t.max_cooldown == roundi(30 * 0.95), "core hardpoint cooldown x0.95")
	# Snipers (range 250) so the whole final approach to the core is covered
	# regardless of which gap the randomly generated rift enters through.
	S.money = 1000.0
	var built_free := 0
	for offset in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		var free_snap: Vector2 = world.snap_to_grid(world.core_pos + offset * Con.GRID_SIZE)
		if world.is_tile_free(free_snap) and world.build_tower(free_snap, &"sniper"):
			built_free += 1
	_check(built_free >= 2, "towers built on free tiles around the core")
	_check(S.money < 1000.0, "money deducted on build")

	# The random rift can spawn 80+ cells out, so a core-only ring may never
	# see an enemy inside the frame budget. Drop a sniper (range 250) on a
	# free tile next to the rift's spawn point so it engages immediately.
	if not world.rifts.is_empty():
		var spawn_built := false
		for point in world.rifts[0].points:
			for n_offset in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1),
					Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				var near_snap: Vector2 = world.snap_to_grid(point + n_offset * Con.GRID_SIZE)
				if world.is_tile_free(near_snap) and world.build_tower(near_snap, &"sniper"):
					spawn_built = true
					break
			if spawn_built:
				break
		_check(spawn_built, "sniper built beside the rift spawn")

	# Fast-forward: skip prep, then run 30 simulated seconds of logic.
	world.skip_prep()
	var spawned_any := false
	var killed_any := false
	var start_kills := 0
	var max_projectiles := 0
	var min_dist := INF
	for frame in 1800:
		world.step()
		if not world.enemies.is_empty():
			spawned_any = true
			for e in world.enemies:
				for t in world.towers:
					min_dist = minf(min_dist, e.pos.distance_to(t.pos))
		max_projectiles = maxi(max_projectiles, world.projectiles.size())
		var kills := 0
		for type in S.total_kills:
			kills += S.total_kills[type]
		if kills > start_kills:
			killed_any = true
	print("  diag: towers=%d max_projectiles=%d min_enemy_tower_dist=%.0f lives=%d enemies_now=%d" % [
			world.towers.size(), max_projectiles, min_dist, S.lives, world.enemies.size()])
	_check(spawned_any, "enemies spawned during the wave")
	_check(killed_any, "towers killed enemies")
	_check(S.lives <= Con.STARTING_LIVES, "lives tracked")

	# Abilities: force energy and fire an EMP.
	S.energy = 50.0
	world.start_targeting(&"emp")
	_check(world.targeting_ability == &"emp", "EMP targeting armed")
	world.use_ability(world.core_pos)
	_check(S.energy < 50.0, "EMP consumed energy")

	# Save / load round trip.
	world.save_system.save_now()
	await create_timer(0.2).timeout
	_check(world.save_system.has_save(), "save written")
	var money_before: float = S.money
	var wave_before: int = S.wave
	_check(world.save_system.load_game(), "save loaded")
	_check(absf(S.money - money_before) < 0.001, "money survives round trip")
	_check(S.wave == wave_before, "wave survives round trip")
	_check(world.is_prep_phase, "load lands in prep phase")

	# Wave intel parity spot checks (JS distributeByWeights outputs).
	var w1: Dictionary = WI.predicted_distribution(1)
	_check(int(w1.get(&"basic", 0)) == 7, "wave 1 predicts 7 basics")
	var w10: Dictionary = WI.predicted_distribution(10)
	_check(int(w10.get(&"boss", 0)) == 1, "wave 10 predicts a boss")
	var total10 := 0
	for type in w10:
		total10 += w10[type]
	_check(total10 == 31, "wave 10 predicts 31 hostiles")

	if _failures.is_empty():
		print("== ALL CHECKS PASSED ==")
		quit(0)
	else:
		printerr("== %d CHECKS FAILED ==" % _failures.size())
		quit(1)
