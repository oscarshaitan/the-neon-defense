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
	# Cached soft radial-gradient sprite for muzzle flashes / dynamic lights —
	# the Godot analogue of the JS LIGHT_GRADIENT_CACHE (white core → transparent
	# edge), drawn modulated per light. One texture, reused for every flash.
	var _light_tex: GradientTexture2D
	# Viewport cull rect (world space) recomputed each frame; entities outside
	# it are skipped so off-screen enemies/projectiles/particles cost nothing
	# to draw (the JS edition culls the same way; Godot 2D _draw is immediate
	# mode, so without this every entity is drawn every frame).
	var _cull := Rect2(-1e9, -1e9, 2e9, 2e9)

	# Arc-link stroke styles per intensity (JS _LINK_STYLES): a dot → dash →
	# solid progression. Level 5 (= ARC_MAX_BONUS) is a solid neon double-stroke.
	const _LINK_STYLES := [
		{on = 1.0, off = 16.0, w = 1.3, color = Color(0.392, 0.725, 0.949, 0.42)},
		{on = 2.0, off = 11.0, w = 1.6, color = Color(0.463, 0.792, 0.988, 0.55)},
		{on = 5.0, off = 8.0, w = 1.8, color = Color(0.533, 0.855, 1.0, 0.67)},
		{on = 12.0, off = 4.0, w = 2.1, color = Color(0.647, 0.910, 1.0, 0.80)},
	]

	func _ready() -> void:
		z_index = 2
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		_light_tex = GradientTexture2D.new()
		_light_tex.gradient = grad
		_light_tex.fill = GradientTexture2D.FILL_RADIAL
		_light_tex.fill_from = Vector2(0.5, 0.5)
		_light_tex.fill_to = Vector2(1.0, 0.5)
		_light_tex.width = 64
		_light_tex.height = 64

	func _process(_delta: float) -> void:
		queue_redraw()

	func _update_cull_rect() -> void:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			_cull = Rect2(-1e9, -1e9, 2e9, 2e9)
			return
		var z: float = cam.zoom.x if cam.zoom.x > 0.0 else 1.0
		var half := get_viewport_rect().size / (2.0 * z)
		# Margin covers entity extents + the largest light glow (boss r150).
		_cull = Rect2(cam.get_screen_center_position() - half, half * 2.0) \
				.grow(C.GRID_SIZE * 4.0)

	func _visible(p: Vector2) -> bool:
		return _cull.has_point(p)

	func _draw() -> void:
		var frame := State.frame_count
		_update_cull_rect()
		if world.show_no_build_overlay:
			_draw_no_build_overlay()
		_draw_spawn_discs(frame)
		_draw_base(frame)
		_draw_build_target(frame)
		_draw_towers(frame)
		_draw_arc_tower_links()
		_draw_enemies(frame)
		_draw_projectiles()
		_draw_arc_bursts()
		_draw_particles()
		_draw_lights()
		_draw_targeting_overlay()

	## JS spatial-zoning debug overlay: zone-0 no-rift disc, concentric zone
	## rings (every 3 cells), and the wide no-build buffer along each rift.
	func _draw_no_build_overlay() -> void:
		var center := world.core_pos
		var zone0 := C.ZONE0_RADIUS_CELLS * C.GRID_SIZE
		draw_circle(center, zone0, Color(1, 0, 0, 0.05))
		draw_arc(center, zone0, 0, TAU, 64, Color(1, 0, 0, 0.4), 2.0)
		var r := C.ZONE0_RADIUS_CELLS + 3
		while r < 60:
			draw_arc(center, r * C.GRID_SIZE, 0, TAU, 64, Color(C.COL_BLUE, 0.2), 2.0)
			r += 3
		# No-build buffers (~1.5 cells each side) along every rift.
		var buffer := C.GRID_SIZE * 1.5
		for rift in world.rifts:
			var points: PackedVector2Array = rift.points
			if points.size() >= 2:
				draw_polyline(points, Color(1, 0, 0, 0.3), buffer * 2.0)

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
			if not _visible(t.pos): continue
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
			if not _visible(e.pos): continue
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
			if not _visible(p.pos): continue
			draw_circle(p.pos, 3.0, p.color)

	func _draw_arc_bursts() -> void:
		for burst in world.arc_bursts:
			if not _visible(burst.a) and not _visible(burst.b): continue
			var alpha: float = clampf(burst.life / 8.0, 0, 1)
			var intensity: int = burst.intensity
			var pts := _build_arc_path(burst.a, burst.b, intensity, burst.get("phase", 0.0))
			# Two-layer bolt (JS): wide soft glow halo, then a bright sharp core.
			draw_polyline(pts, Color(0.486, 0.843, 1.0, 0.18 * alpha),
					1.2 + intensity * 0.7)
			draw_polyline(pts, Color(0.776, 0.965, 1.0, 0.95 * alpha),
					0.8 + intensity * 0.35)

	## JS traceElectricArcPath: a multi-segment bolt jittered by a sine phase and
	## a zig-zag, tapered to zero at both endpoints by a sin envelope.
	func _build_arc_path(a: Vector2, b: Vector2, intensity: int, phase: float) \
			-> PackedVector2Array:
		const SEGMENTS := 7
		var dir := b - a
		var len := maxf(1.0, dir.length())
		var normal := Vector2(-dir.y, dir.x) / len
		var amp_base := 2.2 + intensity * 0.7
		var ph := State.frame_count * 0.55 + phase
		var ph73 := ph * 0.73
		var pts := PackedVector2Array([a])
		for i in range(1, SEGMENTS):
			var ti := float(i) / SEGMENTS
			var base := a + dir * ti
			var envelope := sin(ti * PI)
			var zig := 1.0 if i % 2 == 0 else -1.0
			var jitter := sin(ph + i * 1.7) * 0.85 + cos(ph73 + i * 2.3) * 0.55
			var offset := (zig * amp_base + jitter * amp_base * 0.65) * envelope
			pts.append(base + normal * offset)
		pts.append(b)
		return pts

	func _draw_particles() -> void:
		for p in world.particles:
			if not _visible(p.pos): continue
			var c: Color = p.color
			c.a = clampf(p.life, 0, 1)
			draw_rect(Rect2(p.pos, Vector2(3, 3)), c)

	func _draw_lights() -> void:
		# Soft radial glow stamped from the cached gradient sprite (JS drawImage
		# of LIGHT_GRADIENT_CACHE), modulated by the light colour and life — a
		# punchy flash instead of the old flat hard-edged discs.
		const ALPHA_SCALE := 0.55
		for l in world.lights:
			if not _visible(l.pos): continue
			var c: Color = l.color
			c.a = clampf(l.life, 0, 1) * ALPHA_SCALE
			var r: float = l.radius
			draw_texture_rect(_light_tex, Rect2(l.pos - Vector2(r, r),
					Vector2(r * 2, r * 2)), false, c)

	func _draw_arc_tower_links() -> void:
		for link in world.arc_tower_links:
			var pa: Vector2 = link.a.pos
			var pb: Vector2 = link.b.pos
			var lvl := clampi(int(link.strength), 1, C.ARC_MAX_BONUS)
			if lvl < C.ARC_MAX_BONUS:
				var s: Dictionary = _LINK_STYLES[lvl - 1]
				_draw_dashed_line(pa, pb, s.on, s.off, s.color, s.w)
			else:
				# Level 5: solid neon — wide diffuse halo, then bright thin core.
				draw_line(pa, pb, Color(0.471, 0.824, 1.0, 0.28), 10.0)
				draw_line(pa, pb, Color(0.784, 0.961, 1.0, 0.94), 2.4)

	func _draw_dashed_line(a: Vector2, b: Vector2, on: float, off: float,
			color: Color, width: float) -> void:
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 0.001:
			return
		var dir := seg / seg_len
		var step := on + off
		var d := 0.0
		while d < seg_len:
			var e := minf(d + on, seg_len)
			draw_line(a + dir * d, a + dir * e, color, width)
			d += step

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
