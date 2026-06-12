class_name RenderLayers
## Canvas layers for the world. Godot 2D is retained-mode: _draw() output is
## cached until queue_redraw(), so static layers (grid, rift trunks,
## hardpoints) cost nothing per frame — the optimization the JS/Flutter
## versions needed sprite/Picture caches for comes free here. Only the
## dynamic layer redraws every frame.

## Static grid — drawn once.
class GridLayer extends Node2D:
	func _ready() -> void:
		z_index = 0

	func _draw() -> void:
		const EXTRA := C.GRID_SIZE * 60.0
		var w := C.WORLD_COLS * C.GRID_SIZE
		var h := C.WORLD_ROWS * C.GRID_SIZE
		var color := Color(1, 1, 1, 0.08)
		var x := -EXTRA
		while x <= w + EXTRA:
			draw_line(Vector2(x, -EXTRA), Vector2(x, h + EXTRA), color, 1.0)
			x += C.GRID_SIZE
		var y := -EXTRA
		while y <= h + EXTRA:
			draw_line(Vector2(-EXTRA, y), Vector2(w + EXTRA, y), color, 1.0)
			y += C.GRID_SIZE

## Static rift trunks + hardpoint slots — redrawn only when they change.
class StaticWorldLayer extends Node2D:
	var world: World

	func _ready() -> void:
		z_index = 1
		world.rifts_changed.connect(queue_redraw)
		world.hardpoints_changed.connect(queue_redraw)
		State.selection_changed.connect(queue_redraw)

	func _draw() -> void:
		for rift in world.rifts:
			var points: PackedVector2Array = rift.points
			if points.size() < 2:
				continue
			var highlighted: bool = State.selected_rift == rift
			var mutation: Dictionary = rift.mutation
			var line_color: Color = mutation.color if not mutation.is_empty() \
					else (C.COL_PINK if rift.level > 1 else C.COL_BLUE)
			# Wide glow trunk.
			var glow := line_color
			glow.a = 0.2 if highlighted else 0.06
			draw_polyline(points, glow, C.GRID_SIZE * (1.6 if highlighted else 0.8))
			# Dashed center line [10,10].
			for j in points.size() - 1:
				var a := points[j]
				var b := points[j + 1]
				var seg_len := a.distance_to(b)
				var dir := (b - a) / seg_len
				var d := 0.0
				while d < seg_len:
					var e := minf(d + 10.0, seg_len)
					draw_line(a + dir * d, a + dir * e, line_color, 4.0 if highlighted else 2.0)
					d += 20.0
		# Hardpoint slots.
		for hp in world.hardpoints:
			var is_core: bool = hp.type == &"core"
			var radius := C.GRID_SIZE * (0.36 if is_core else 0.25)
			var ring := C.COL_GREEN if is_core else C.COL_YELLOW
			if hp.occupied:
				draw_circle(hp.pos, radius, Color(1, 1, 1, 0.06))
				draw_arc(hp.pos, radius, 0, TAU, 24, Color(1, 1, 1, 0.3), 2.0)
			else:
				var fill := ring
				fill.a = 0.09
				draw_circle(hp.pos, radius, fill)
				draw_arc(hp.pos, radius, 0, TAU, 24, ring, 2.4 if is_core else 1.8)
				var cross := radius * 0.45
				var cross_color := ring
				cross_color.a = 0.7
				draw_line(hp.pos - Vector2(cross, 0), hp.pos + Vector2(cross, 0), cross_color, 1.2)
				draw_line(hp.pos - Vector2(0, cross), hp.pos + Vector2(0, cross), cross_color, 1.2)

## Everything that moves — redrawn each frame in the JS draw() order.
class DynamicLayer extends Node2D:
	var world: World
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		z_index = 2

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var frame := State.frame_count
		_draw_spawn_discs(frame)
		_draw_base(frame)
		_draw_build_target(frame)
		_draw_towers(frame)
		_draw_enemies(frame)
		_draw_projectiles()
		_draw_arc_bursts()
		_draw_particles()
		_draw_lights()
		_draw_targeting_overlay()

	func _draw_spawn_discs(frame: int) -> void:
		var pulse := 1.0 + sin(frame * 0.1) * 0.2
		for rift in world.rifts:
			if rift.points.is_empty():
				continue
			var spawn: Vector2 = rift.points[0]
			var mutation: Dictionary = rift.mutation
			var color: Color = mutation.color if not mutation.is_empty() \
					else (C.COL_PINK if rift.level > 1 else C.COL_RED)
			var radius := 20.0 * (1.5 if rift.level > 1 or not mutation.is_empty() else 1.0) * pulse
			var halo := color
			halo.a = 0.25
			draw_circle(spawn, radius * 1.35, halo)
			draw_circle(spawn, radius, color)
			draw_circle(spawn, 10.0, Color.BLACK)
			if rift.level > 1:
				_draw_level_pips(rift.level, spawn + Vector2(0, 30))
			if State.selected_rift == rift:
				draw_arc(spawn, 40.0, 0, TAU, 32, C.COL_PINK, 2.0)

	func _draw_base(frame: int) -> void:
		var pos := world.core_pos
		if State.selected_base:
			draw_arc(pos, 40.0, 0, TAU, 32, C.COL_GREEN, 2.0)
			if world.base_level > 0:
				var range := 150.0 + (world.base_level - 1) * 30.0
				draw_circle(pos, range, Color(C.COL_GREEN, 0.1))
				draw_arc(pos, range, 0, TAU, 64, Color(C.COL_GREEN, 0.3), 1.0)
		var diamond := PackedVector2Array([pos + Vector2(0, -18), pos + Vector2(18, 0),
				pos + Vector2(0, 18), pos + Vector2(-18, 0)])
		var halo := C.COL_GREEN
		halo.a = 0.3
		draw_circle(pos, 26.0, halo)
		draw_colored_polygon(diamond, C.COL_GREEN)
		if world.base_level > 0:
			var time := frame / 48.0 # JS Date.now()/800 at 60 fps
			for j in maxi(1, world.base_level / 3):
				var radius := 22.0 + j * 4
				var dir := 1.0 if j % 2 == 0 else -1.0
				var hex := PackedVector2Array()
				for i in 6:
					var angle := PI / 3 * i + time * dir
					hex.append(pos + Vector2(cos(angle), sin(angle)) * radius)
				hex.append(hex[0])
				draw_polyline(hex, Color(C.COL_GREEN, clampf(0.3 + j * 0.2, 0, 1)), 1.5)
			for i in world.base_level:
				var orbit := 0 if i < 5 else 1
				var orbit_count: int = mini(world.base_level, 5) if i < 5 else world.base_level - 5
				var orbit_pos := i if i < 5 else i - 5
				var radius := 32.0 if orbit == 0 else 45.0
				var t := time * 2.0 if orbit == 0 else -time * 1.5
				var angle := t + orbit_pos * TAU / maxi(1, orbit_count)
				var o := pos + Vector2(cos(angle), sin(angle)) * radius
				draw_colored_polygon(PackedVector2Array([
					o + Vector2(cos(angle), sin(angle)) * 5,
					o + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * 5,
					o + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * 5,
				]), Color.WHITE)
		draw_circle(pos, 8.0, Color(1, 1, 1, clampf(0.5 + sin(frame / 12.0) * 0.3, 0, 1)))

	func _draw_build_target(frame: int) -> void:
		if State.build_target == Vector2.INF:
			return
		var bt := State.build_target
		var half := C.GRID_SIZE / 2
		var tl := bt - Vector2(half, half)
		draw_rect(Rect2(tl, Vector2(C.GRID_SIZE, C.GRID_SIZE)), Color(C.COL_BLUE, 0.2))
		var p := C.COL_BLUE
		for corner in [[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
				[Vector2(C.GRID_SIZE, 0), Vector2(-1, 0), Vector2(0, 1)],
				[Vector2(C.GRID_SIZE, C.GRID_SIZE), Vector2(-1, 0), Vector2(0, -1)],
				[Vector2(0, C.GRID_SIZE), Vector2(1, 0), Vector2(0, -1)]]:
			var o: Vector2 = tl + corner[0]
			draw_line(o, o + corner[1] * 10.0, p, 2.0)
			draw_line(o, o + corner[2] * 10.0, p, 2.0)
		# Ghost preview when a type is armed.
		if State.selected_tower_type != &"":
			var v := world.validate_placement(bt, State.selected_tower_type)
			var def := C.tower_def(State.selected_tower_type)
			var ring := C.COL_GREEN if v.valid else Color.RED
			draw_circle(bt, def.range, Color(ring, 0.1))
			draw_arc(bt, def.range, 0, TAU, 64, Color(ring, 0.5), 1.0)
			var scale: float = 1.0 if v.hp.is_empty() \
					else (C.CORE_MULT.scale if v.hp.type == &"core" else C.MICRO_MULT.scale)
			_draw_tower_shape(State.selected_tower_type, bt,
					Color(def.color if v.valid else Color.RED, 0.5), scale)

	func _draw_towers(frame: int) -> void:
		for t in world.towers:
			_draw_tower_shape(t.type, t.pos, t.color, t.scale)
			if t.level > 1:
				_draw_level_pips(t.level, t.pos + Vector2(0, 20))
			if State.selected_tower == t:
				draw_circle(t.pos, t.range, Color(1, 1, 1, 0.1))
				draw_arc(t.pos, t.range, 0, TAU, 64, Color.WHITE, 1.0)
				draw_rect(Rect2(t.pos - Vector2(18, 18), Vector2(36, 36)), Color.WHITE, false, 2.0)
			if t.overclocked:
				var pulse := 1.0 + sin(frame * 0.5) * 0.2
				draw_arc(t.pos, 20.0 * pulse, 0, TAU, 24, C.COL_YELLOW, 2.0)
				draw_circle(t.pos, 18.0 * pulse, Color(1, 1, 1, 0.3))

	func _draw_tower_shape(type: StringName, pos: Vector2, color: Color, s: float) -> void:
		s = maxf(0.5, s)
		match type:
			&"basic":
				draw_rect(Rect2(pos - Vector2(13, 13) * s, Vector2(26, 26) * s), color)
			&"rapid":
				draw_circle(pos, 13.0 * s, color)
			&"sniper":
				draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -15) * s,
						pos + Vector2(15, 0) * s, pos + Vector2(0, 15) * s,
						pos + Vector2(-15, 0) * s]), color)
			&"arc":
				var hex := PackedVector2Array()
				for i in 6:
					var a := TAU * i / 6 - PI / 2
					hex.append(pos + Vector2(cos(a), sin(a)) * 14.0 * s)
				draw_colored_polygon(hex, color)
				draw_circle(pos, 4.0 * s, Color("e9f9ff"))

	func _draw_level_pips(level: int, at: Vector2) -> void:
		var fives := level / 5
		var ones := level % 5
		var total_w := fives * 8.0 + ones * 4.0 + maxf(0, fives + ones - 1) * 5.0
		var x := at.x - total_w / 2
		for i in fives:
			var cx := x + 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(cx, at.y - 4), Vector2(cx + 4, at.y),
					Vector2(cx, at.y + 4), Vector2(cx - 4, at.y)]), Color.WHITE)
			x += 13.0
		for i in ones:
			draw_circle(Vector2(x + 2.0, at.y), 2.0, Color.WHITE)
			x += 9.0

	func _draw_enemies(frame: int) -> void:
		for e in world.enemies:
			var color := e.color
			if e.invisible:
				color.a = 0.2
				draw_circle(e.pos, e.width / 2, color)
				continue
			match e.type:
				&"tank":
					draw_rect(Rect2(e.pos - Vector2(10, 10), Vector2(20, 20)), color)
				&"fast":
					draw_colored_polygon(PackedVector2Array([e.pos + Vector2(0, -12),
							e.pos + Vector2(6, 0), e.pos + Vector2(0, 8),
							e.pos + Vector2(-6, 0)]), color)
				&"boss":
					var hex := PackedVector2Array()
					for i in 6:
						var a := TAU * i / 6
						hex.append(e.pos + Vector2(cos(a), sin(a)) * e.width / 2)
					draw_colored_polygon(hex, color)
				&"splitter":
					draw_colored_polygon(PackedVector2Array([e.pos + Vector2(0, -14),
							e.pos + Vector2(12, 10), e.pos + Vector2(-12, 10)]), color)
				&"mini":
					draw_circle(e.pos, 6.0, color)
				_:
					draw_circle(e.pos, e.width / 2, color)
			if e.rift_level > 1:
				var my := e.pos.y - e.width / 2 - 8
				var ms := minf(6.0, 4.0 + (e.rift_level - 1) / 2)
				draw_colored_polygon(PackedVector2Array([Vector2(e.pos.x, my - ms),
						Vector2(e.pos.x + ms, my), Vector2(e.pos.x, my + ms),
						Vector2(e.pos.x - ms, my)]), Color(1, 1, 1, 0.88))
			if e.hp < e.max_hp:
				draw_rect(Rect2(e.pos + Vector2(-10, -15), Vector2(20, 3)), Color.RED)
				draw_rect(Rect2(e.pos + Vector2(-10, -15),
						Vector2(20.0 * clampf(e.hp / e.max_hp, 0, 1), 3)), Color.GREEN)
			if e.frozen > 0:
				draw_arc(e.pos, e.width / 2 + 2, 0, TAU, 20, C.COL_BLUE, 3.0)
				draw_circle(e.pos, e.width / 2, Color(C.COL_BLUE, 0.3))
			if e.stun > 0:
				var r := e.width / 2 + 8
				var pulse := 1.0 + sin(frame * 0.35 + e.pos.x * 0.01) * 0.12
				draw_arc(e.pos, (r + 4) * pulse, 0, TAU, 20, Color("e6f8ff"), 2.5)
				for i in 6:
					var a := TAU * i / 6 + frame * 0.06
					draw_line(e.pos + Vector2(cos(a), sin(a)) * (r + 1),
							e.pos + Vector2(cos(a), sin(a)) * (r + 9 + (2 if i % 2 == 1 else 0)),
							Color("c4ecff", 0.9), 1.6)
			elif e.static_charges > 0:
				var r := e.width / 2 + 8
				draw_arc(e.pos, r, 0, TAU, 16, Color("7cd7ff", 0.9), 1.5)

	func _draw_projectiles() -> void:
		for p in world.projectiles:
			draw_circle(p.pos, 3.0, p.color)

	func _draw_arc_bursts() -> void:
		for burst in world.arc_bursts:
			var alpha: float = clampf(burst.life / 8.0, 0, 1) * 0.8
			var a: Vector2 = burst.a
			var b: Vector2 = burst.b
			var dir: Vector2 = b - a
			var len := maxf(1.0, dir.length())
			var normal := Vector2(-dir.y, dir.x) / len
			var pts := PackedVector2Array([a])
			for s in range(1, 3):
				var t := s / 3.0
				pts.append(a + dir * t + normal * (_rng.randf() - 0.5) * 12.0 * burst.intensity)
			pts.append(b)
			draw_polyline(pts, Color("7cd7ff", alpha), 0.5 + burst.intensity * 0.4)
			if burst.intensity >= 4:
				draw_polyline(pts, Color("7cd7ff", alpha / 3.0), (0.5 + burst.intensity * 0.4) * 3)

	func _draw_particles() -> void:
		for p in world.particles:
			var c: Color = p.color
			c.a = clampf(p.life, 0, 1)
			draw_rect(Rect2(p.pos, Vector2(3, 3)), c)

	func _draw_lights() -> void:
		for l in world.lights:
			var c: Color = l.color
			c.a = 0.3 * clampf(l.life, 0, 1)
			draw_circle(l.pos, l.radius * 0.5, c)
			c.a *= 0.4
			draw_circle(l.pos, l.radius, c)

	func _draw_targeting_overlay() -> void:
		if world.targeting_ability == &"":
			return
		var pos := get_global_mouse_position()
		if world.targeting_ability == &"emp":
			draw_circle(pos, C.EMP_RADIUS, Color(C.COL_BLUE, 0.1))
			draw_arc(pos, C.EMP_RADIUS, 0, TAU, 48, Color(C.COL_BLUE, 0.8), 1.5)
			draw_line(pos - Vector2(20, 0), pos + Vector2(20, 0), C.COL_BLUE, 1.5)
			draw_line(pos - Vector2(0, 20), pos + Vector2(0, 20), C.COL_BLUE, 1.5)
		else:
			draw_arc(pos, 30.0, 0, TAU, 32, Color(C.COL_YELLOW, 0.8), 1.5)
