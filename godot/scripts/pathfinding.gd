class_name Pathfinding
## Faithful port of the JS rift generation: findPathOnGrid
## (04_tutorial.js:637-766), generateNewPath (04_tutorial.js:128-635) and the
## initial rift placement calculatePath (01_init.js:829-910).
## Pure static functions over Vector2i cells — runs synchronously during the
## prep phase (web exports have no thread guarantees).

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func _inside_zone0(c: Vector2i, core: Vector2i, zone0: int) -> bool:
	return Vector2(c - core).length() < zone0

static func _core_repulsion(c: Vector2i, core: Vector2i) -> float:
	var dist := Vector2(c - core).length()
	if dist >= C.CORE_REPULSION_RADIUS:
		return 0.0
	var t := 1.0 - dist / C.CORE_REPULSION_RADIUS
	return C.CORE_REPULSION_STRENGTH * t * t

## A* with direction-aware turn penalties, zone-0 commitment lock, core
## repulsion, and merge-allowed obstacle cells. Returns Array[Vector2i] or [].
static func find_path_on_grid(start: Vector2i, end: Vector2i, cols: int, rows: int,
		obstacles: Dictionary, allowed: Dictionary, core: Vector2i, zone0: int) -> Array[Vector2i]:
	var starts_inside := _inside_zone0(start, core, zone0)
	# Node: [c, g, h, f, parent_index, dir, entered_zone0]
	var nodes: Array = []
	var open: Array[int] = []
	var closed := {}

	var h0 := float(absi(start.x - end.x) + absi(start.y - end.y))
	nodes.append([start, 0.0, h0, h0, -1, Vector2i.ZERO, starts_inside])
	open.append(0)

	while not open.is_empty():
		var best_i := 0
		for i in range(1, open.size()):
			if nodes[open[i]][3] < nodes[open[best_i]][3]:
				best_i = i
		var current_idx: int = open[best_i]
		open.remove_at(best_i)
		var current: Array = nodes[current_idx]

		if current[0] == end:
			var cells: Array[Vector2i] = []
			var seen := {}
			var idx := current_idx
			while idx != -1:
				var cell: Vector2i = nodes[idx][0]
				if seen.has(cell):
					return []
				seen[cell] = true
				cells.push_front(cell)
				idx = nodes[idx][4]
			return cells

		closed[str(current[0]) + ("1" if current[6] else "0")] = current[1]

		for dir: Vector2i in DIRS:
			var n: Vector2i = current[0] + dir
			if n.x < 0 or n.x >= cols or n.y < 0 or n.y >= rows:
				continue
			if obstacles.has(n) and not allowed.has(n):
				continue
			# Prevent branch loops/folding over itself while searching.
			var cursor := current_idx
			var in_branch := false
			while cursor != -1:
				if nodes[cursor][0] == n:
					in_branch = true
					break
				cursor = nodes[cursor][4]
			if in_branch:
				continue

			var next_inside := _inside_zone0(n, core, zone0)
			var next_entered: bool = current[6] or next_inside
			# Once a route enters Zone 0 it cannot step back outside.
			if current[6] and not next_inside:
				continue

			var cost := 1.0
			var turning: bool = current[5] != Vector2i.ZERO and current[5] != dir
			if turning:
				cost += 5.0
			var dist_to_core := Vector2(n - end).length()
			if turning and dist_to_core < C.NEAR_CORE_STRAIGHT_RADIUS:
				cost += C.NEAR_CORE_TURN_PENALTY * (1.0 - dist_to_core / C.NEAR_CORE_STRAIGHT_RADIUS)
			cost += _core_repulsion(n, end)

			var g: float = current[1] + cost
			var state_key := str(n) + ("1" if next_entered else "0")
			if closed.has(state_key) and closed[state_key] <= g:
				continue

			var in_open := false
			for oi in open:
				var node: Array = nodes[oi]
				if node[0] == n and node[6] == next_entered:
					if node[1] > g:
						node[1] = g
						node[3] = g + node[2]
						node[4] = current_idx
						node[5] = dir
					in_open = true
					break
			if not in_open:
				var h := float(absi(n.x - end.x) + absi(n.y - end.y))
				nodes.append([n, g, h, g + h, current_idx, dir, next_entered])
				open.append(nodes.size() - 1)
	return []

static func _expected_rift_count(wave: int) -> int:
	var scheduled := 0
	for w in range(2, wave + 1):
		if w <= 50:
			if (w - 1) % 10 == 0:
				scheduled += 1
		elif (w - 1) % 5 == 0:
			scheduled += 1
	return 1 + scheduled

static func _gap_sectors(core_slots: Array, core: Vector2i) -> Array:
	var angles: Array[float] = []
	for hp in core_slots:
		angles.append(fposmod(atan2(float(hp.y - core.y), float(hp.x - core.x)), TAU))
	angles.sort()
	if angles.size() < 2:
		return []
	var sectors := []
	for i in angles.size():
		var start_a := angles[i]
		var end_a := angles[(i + 1) % angles.size()]
		if end_a <= start_a:
			end_a += TAU
		sectors.append({index = i, start_a = start_a, end_a = end_a,
				center = fposmod((start_a + end_a) / 2.0, TAU)})
	return sectors

static func _gap_index_for(c: Vector2i, core: Vector2i, sectors: Array) -> int:
	if sectors.is_empty() or c == core:
		return -1
	var angle := fposmod(atan2(float(c.y - core.y), float(c.x - core.x)), TAU)
	for sector in sectors:
		var test := angle
		if test < sector.start_a:
			test += TAU
		if test >= sector.start_a and test < sector.end_a:
			return sector.index
	return sectors[0].index

static func _entry_gap_of_path(cells: Array, core: Vector2i, sectors: Array, zone0: int) -> int:
	if cells.size() < 2 or sectors.is_empty():
		return -1
	var entry := Vector2i(cells[cells.size() - 2])
	for i in range(1, cells.size()):
		var prev: Vector2i = cells[i - 1]
		var curr: Vector2i = cells[i]
		if Vector2(prev - core).length() >= zone0 and Vector2(curr - core).length() < zone0:
			entry = prev
			break
	return _gap_index_for(entry, core, sectors)

static func _respects_zone0(cells: Array, core: Vector2i, zone0: int, from_index: int) -> bool:
	var entered := false
	for i in range(maxi(0, from_index), cells.size()):
		if _inside_zone0(cells[i], core, zone0):
			entered = true
		elif entered:
			return false
	return true

## Initial rift (JS calculatePath): random start >= 10 cells from the core.
static func generate_initial_rift(cols: int, rows: int, core: Vector2i,
		hardpoint_cells: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var start := Vector2i.ZERO
	var valid := false
	for _attempt in 100:
		var c := Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1))
		if Vector2(c - core).length() >= 10 and c != core and not hardpoint_cells.has(c):
			start = c
			valid = true
			break
	var cells := find_path_on_grid(start, core, cols, rows, hardpoint_cells, {},
			core, C.ZONE0_RADIUS_CELLS) if valid else []
	if cells.is_empty():
		# JS fallback manual L path.
		cells = [start, Vector2i(core.x, start.y), core] as Array[Vector2i]
	var zone := maxi(1, mini(15, int((Vector2(start - core).length() - C.ZONE0_RADIUS_CELLS) / 3.0) + 1))
	return {cells = cells, zone = zone}

## New rift (JS generateNewPath) — orbital zone shells, merge-vs-direct
## missions, gap sectors, relaxation retries. Returns {} on failure.
static func generate_new_rift(cols: int, rows: int, core: Vector2i,
		hardpoint_cells: Dictionary, core_slots: Array, paths: Array, wave: int,
		rng: RandomNumberGenerator) -> Dictionary:
	for relaxed in 3:
		var result := _generate_attempt(cols, rows, core, hardpoint_cells, core_slots,
				paths, wave, rng, relaxed)
		if not result.is_empty():
			return result
	return {}

static func _generate_attempt(cols: int, rows: int, core: Vector2i,
		hardpoint_cells: Dictionary, core_slots: Array, paths: Array, wave: int,
		rng: RandomNumberGenerator, relaxed: int) -> Dictionary:
	var zone0 := C.ZONE0_RADIUS_CELLS
	var path_cell_sets: Array = []
	for p in paths:
		var s := {}
		for cell in p.cells:
			s[cell] = true
		path_cell_sets.append(s)

	var on_any_path := func(c: Vector2i) -> bool:
		for s in path_cell_sets:
			if s.has(c):
				return true
		return false

	# --- Candidate start via orbital zone shells ---
	var corner_d := [Vector2(core).length(), Vector2(cols - 1 - core.x, core.y).length(),
			Vector2(core.x, rows - 1 - core.y).length(),
			Vector2(cols - 1 - core.x, rows - 1 - core.y).length()]
	var max_zone := maxi(3, mini(15, maxi(3, int((corner_d.max() - zone0) / 3.0))))
	var shell_cap := func(z: int) -> int: return maxi(1, roundi(2.0 * z * z * 0.62))

	var load_target := maxi(paths.size() + 1, _expected_rift_count(wave))
	var zone_counts := {}
	for p in paths:
		var z: int = clampi(p.zone, 1, max_zone)
		zone_counts[z] = int(zone_counts.get(z, 0)) + 1

	var target_zone := 1
	var cumulative := 0
	for z in range(1, max_zone + 1):
		cumulative += shell_cap.call(z)
		target_zone = z
		if cumulative >= load_target:
			break

	var desired := {}
	var remaining := load_target
	for z in range(1, target_zone + 1):
		if remaining <= 0:
			break
		var d: int = mini(shell_cap.call(z), remaining)
		desired[z] = d
		remaining -= d

	var base_spacing := 0.95 if wave < 120 else (0.85 if wave < 300 else (0.75 if wave < 700 else 0.65))
	var min_spacing := maxf(0.2, base_spacing - relaxed * 0.35)
	var attempts := mini(960, 180 + wave / 8 + relaxed * 260)

	var inner_targets := {1: 2 if load_target >= 8 else 1, 2: 2 if load_target >= 16 else 0,
			3: 2 if load_target >= 24 else 0}
	var forced_zone := -1
	var strongest := 0
	var search_limit := mini(max_zone, target_zone + 1)
	for z in range(1, search_limit + 1):
		var want: int = maxi(int(inner_targets.get(z, 0)), int(desired.get(z, 0)))
		var deficit: int = want - int(zone_counts.get(z, 0))
		if deficit > strongest:
			strongest = deficit
			forced_zone = z

	var zone_order: Array[int] = []
	if forced_zone != -1:
		zone_order.append(forced_zone)
	var weighted := []
	for z in range(1, search_limit + 1):
		if z == forced_zone:
			continue
		var want: int = maxi(int(inner_targets.get(z, 0)), int(desired.get(z, 0)))
		var deficit: int = maxi(0, want - int(zone_counts.get(z, 0)))
		var bias := -minf(2.8, 0.85 + deficit * 0.55) if deficit > 0 else 0.0
		var inner_bias := -0.25 if z <= 3 else 0.0
		weighted.append({z = z, score = absi(z - target_zone) * 0.75 + rng.randf() * 1.1 + inner_bias + bias})
	weighted.sort_custom(func(a, b): return a.score < b.score)
	for item in weighted:
		zone_order.append(item.z)

	var start := Vector2i(-1, -1)
	var found_zone := -1
	for zone_index in zone_order:
		var cap: int = maxi(int(inner_targets.get(zone_index, 0)), shell_cap.call(zone_index))
		var extra := 4 if relaxed == 0 else (10 if relaxed == 1 else 20)
		if int(zone_counts.get(zone_index, 0)) >= cap + extra:
			continue
		var inner_r := zone0 + (zone_index - 1) * 3
		var outer_r := zone0 + zone_index * 3
		var candidates := []
		for _i in attempts:
			var angle := rng.randf() * TAU
			var dist: float = inner_r + rng.randf() * (outer_r - inner_r)
			var c := Vector2i(roundi(core.x + cos(angle) * dist), roundi(core.y + sin(angle) * dist))
			if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= rows:
				continue
			if on_any_path.call(c) or hardpoint_cells.has(c):
				continue
			var min_d := INF
			var ok := true
			if paths.is_empty():
				min_d = Vector2(c - core).length()
			else:
				for p in paths:
					for cell in p.cells:
						var d := Vector2(c - Vector2i(cell)).length()
						min_d = minf(min_d, d)
						if min_spacing > 0 and d < min_spacing:
							ok = false
							break
					if not ok:
						break
			if ok:
				candidates.append({c = c, min_d = min_d})
		if not candidates.is_empty():
			candidates.sort_custom(func(a, b): return a.min_d > b.min_d)
			var top: Array = candidates.slice(0, mini(candidates.size(), 16))
			var pick := int(pow(rng.randf(), 1.15) * top.size())
			start = top[clampi(pick, 0, top.size() - 1)].c
			found_zone = zone_index
			break

	if start.x == -1 and relaxed >= 2:
		for _i in 1200:
			var angle := rng.randf() * TAU
			var dist := 10.0 + rng.randf() * 48.0
			var c := Vector2i(roundi(core.x + cos(angle) * dist), roundi(core.y + sin(angle) * dist))
			if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= rows:
				continue
			if on_any_path.call(c):
				continue
			var near_hp := false
			for hp in hardpoint_cells:
				if Vector2(c - Vector2i(hp)).length() <= 0.5:
					near_hp = true
					break
			if near_hp:
				continue
			start = c
			found_zone = clampi(int((dist - zone0) / 3.0) + 1, 1, max_zone)
			break
	if start.x == -1:
		return {}

	# --- Obstacles + gap bookkeeping ---
	var obstacles := hardpoint_cells.duplicate()
	for s in path_cell_sets:
		for cell in s:
			obstacles[cell] = true

	var has_open_approach := func(c: Vector2i) -> bool:
		for dir: Vector2i in DIRS:
			var n: Vector2i = c + dir
			if n.x < 0 or n.x >= cols or n.y < 0 or n.y >= rows:
				continue
			if not obstacles.has(n):
				return true
		return false

	var sectors := _gap_sectors(core_slots, core)
	var path_gaps: Array[int] = []
	var gap_usage := {}
	for p in paths:
		var g := _entry_gap_of_path(p.cells, core, sectors, zone0)
		path_gaps.append(g)
		if g != -1:
			gap_usage[g] = int(gap_usage.get(g, 0)) + 1
	var start_gap := _gap_index_for(start, core, sectors)
	var must_merge: bool = start_gap != -1 and int(gap_usage.get(start_gap, 0)) > 0

	var uncovered := 0
	for sector in sectors:
		if int(gap_usage.get(sector.index, 0)) == 0:
			uncovered += 1
	var direct_prob := 0.0 if must_merge else minf(0.8,
			0.5 / (found_zone * found_zone) + (minf(0.45, uncovered * 0.08) if uncovered > 0 else 0.0))
	var is_direct := rng.randf() < direct_prob

	var min_expansion := maxi(3, 6 - relaxed * 2)
	var collect_merges := func(enforce_core_dist: bool, required_gap: int, preferred_gap: int,
			outside_zone0: bool) -> Array:
		var out := []
		for i in paths.size():
			var p: Dictionary = paths[i]
			if required_gap != -1 and path_gaps[i] != required_gap:
				continue
			for j in p.cells.size():
				var cell: Vector2i = p.cells[j]
				var d_spawn := Vector2(start - cell).length()
				if d_spawn < min_expansion:
					continue
				var d_core := Vector2(cell - core).length()
				if outside_zone0 and d_core < zone0:
					continue
				if enforce_core_dist and d_core < C.MERGE_MIN_CORE_DISTANCE:
					continue
				if hardpoint_cells.has(cell):
					continue
				if relaxed == 0 and not has_open_approach.call(cell):
					continue
				if not _respects_zone0(p.cells, core, zone0, j):
					continue
				var score := d_spawn + rng.randf() * 0.9
				if preferred_gap != -1 and path_gaps[i] != preferred_gap:
					score += 4.5
				out.append({cell = cell, path_index = i, point_index = j, score = score})
		out.sort_custom(func(a, b): return a.score < b.score)
		return out.slice(0, mini(out.size(), 240))

	var new_cells: Array[Vector2i] = []
	var merge_path := -1
	var merge_point := -1

	if not is_direct:
		var merges: Array
		if must_merge:
			merges = collect_merges.call(true, start_gap, -1, true)
			if merges.is_empty():
				merges = collect_merges.call(false, start_gap, -1, true)
		else:
			merges = collect_merges.call(true, -1, start_gap, false)
			if merges.is_empty():
				merges = collect_merges.call(false, -1, start_gap, false)
		var tries: int = mini(100 if relaxed == 0 else (180 if relaxed == 1 else 260), merges.size())
		for i in tries:
			var cand: Dictionary = merges[i]
			var attempt := find_path_on_grid(start, cand.cell, cols, rows, obstacles,
					{cand.cell: true}, core, zone0)
			if attempt.is_empty():
				continue
			new_cells = attempt
			merge_path = cand.path_index
			merge_point = cand.point_index
			break

	if new_cells.is_empty() and must_merge:
		return {}

	if new_cells.is_empty():
		# Direct mission through the least-used core gap.
		var entries := []
		for sector in sectors:
			var c := Vector2i(roundi(core.x + cos(sector.center) * maxi(1, zone0 - 1)),
					roundi(core.y + sin(sector.center) * maxi(1, zone0 - 1)))
			if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= rows or hardpoint_cells.has(c):
				continue
			entries.append({gap = sector.index, c = c, usage = int(gap_usage.get(sector.index, 0)),
					match_start = 1 if sector.index == start_gap else 0,
					blocked = 1 if obstacles.has(c) else 0, jitter = rng.randf() * 0.25})
		entries.sort_custom(func(a, b):
			if a.match_start != b.match_start:
				return a.match_start > b.match_start
			if a.usage != b.usage:
				return a.usage < b.usage
			if a.blocked != b.blocked:
				return a.blocked < b.blocked
			return a.jitter < b.jitter)
		var target := core
		var allowed := {core: true}
		if not entries.is_empty():
			target = entries[0].c
			if entries[0].blocked == 1:
				allowed[target] = true
		new_cells = find_path_on_grid(start, target, cols, rows, obstacles, allowed, core, zone0)
		if not new_cells.is_empty() and target != core and new_cells[new_cells.size() - 1] != core:
			var last := new_cells[new_cells.size() - 1]
			var bridge_allowed := allowed.duplicate()
			bridge_allowed[last] = true
			var bridge := find_path_on_grid(last, core, cols, rows, obstacles, bridge_allowed, core, zone0)
			if bridge.size() > 1:
				for i in range(1, bridge.size()):
					new_cells.append(bridge[i])
			else:
				new_cells = []
		merge_path = -1
		merge_point = -1

	if new_cells.is_empty():
		return {}

	if merge_path != -1:
		var cont: Array = paths[merge_path].cells
		for j in range(merge_point + 1, cont.size()):
			new_cells.append(Vector2i(cont[j]))

	if not _respects_zone0(new_cells, core, zone0, 0):
		return {}
	var seen := {}
	for cell in new_cells:
		if seen.has(cell):
			return {}
		seen[cell] = true

	return {cells = new_cells, zone = found_zone}
