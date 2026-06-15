extends Node2D
## Root node: fixed-step game loop, camera, input routing, and UI wiring.

const FIXED_STEP := 1.0 / C.LOGIC_FPS

var world: World
var camera: Camera2D
var hud: Hud

var _accumulator := 0.0
var _drag_start := Vector2.ZERO
var _dragging := false
var _drag_moved := false
var _shake_rng := RandomNumberGenerator.new()
var _shake_offset := Vector2.ZERO

func _ready() -> void:
	world = World.new()
	add_child(world)

	var grid := RenderLayers.GridLayer.new()
	world.add_child(grid)
	var static_layer := RenderLayers.StaticWorldLayer.new()
	static_layer.world = world
	world.add_child(static_layer)
	var dynamic_layer := RenderLayers.DynamicLayer.new()
	dynamic_layer.world = world
	world.add_child(dynamic_layer)

	camera = Camera2D.new()
	camera.position = world.core_pos
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	hud = Hud.new()
	hud.world = world
	hud.main = self
	add_child(hud)

func _process(delta: float) -> void:
	world.record_frame_ms(delta * 1000.0)

	# Screen shake decays per render frame (JS draw()).
	camera.offset -= _shake_offset
	_shake_offset = Vector2.ZERO
	if State.shake_amount > 0:
		State.shake_amount *= 0.9
		if State.shake_amount < 0.1:
			State.shake_amount = 0.0
		_shake_offset = Vector2(_shake_rng.randf() - 0.5, _shake_rng.randf() - 0.5) \
				* State.shake_amount / camera.zoom.x
		camera.offset += _shake_offset

	# Fixed 60 Hz logic stepping so JS frame-based numbers transfer 1:1.
	if not State.is_playing():
		_accumulator = 0.0
		return
	_accumulator += minf(delta, 0.25)
	var steps := 0
	while _accumulator >= FIXED_STEP and steps < 4:
		world.step()
		_accumulator -= FIXED_STEP
		steps += 1
	if _accumulator >= FIXED_STEP:
		_accumulator = 0.0

# ---------------------------------------------------------------------------
# Input (JS handleClick priority + camera pan/zoom)
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / 1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
				_drag_start = event.position
			else:
				_dragging = false
				# Guard: a tap on a visible HUD control must never fall through
				# to the world handler (which would deselect and close the panel).
				# GUI normally consumes it; belt-and-suspenders for touch quirks.
				if not _drag_moved and not hud.blocks_world_tap(event.position):
					_handle_tap(get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_drag_start) > 8.0: # JS drag threshold
			_drag_moved = true
		if _drag_moved:
			camera.position -= event.relative / camera.zoom.x
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, get_viewport().get_visible_rect().size / 2.0)
	elif event is InputEventKey and event.pressed:
		# Allow OS key-repeat (echo) for the buy/upgrade keys so holding them
		# keeps purchasing; other keys fire once per press.
		if not event.echo or event.keycode in [KEY_U, KEY_F, KEY_G]:
			_handle_key(event.keycode)

func _zoom_at(factor: float, _screen_pos: Vector2) -> void:
	# Max 2.0 (not 1.0): the 1280x720 viewport frames more world at zoom 1 than
	# the JS/Flutter canvases, so extra zoom-in headroom is needed to get as
	# close to the towers as those editions.
	var z := clampf(camera.zoom.x * factor, 0.1, 2.0)
	camera.zoom = Vector2(z, z)

func recenter() -> void:
	camera.position = world.core_pos
	camera.zoom = Vector2.ONE

## JS handleClick priority: ability targeting -> tower (<20) -> rift (<30)
## -> base (<30) -> free tile build target -> deselect.
func _handle_tap(world_pos: Vector2) -> void:
	if not State.is_playing():
		return
	if world.targeting_ability != &"":
		world.use_ability(world_pos)
		return
	for t in world.towers:
		if t.pos.distance_to(world_pos) < 20.0:
			State.select_tower(t)
			world.hints.maybe_show(&"tower_intel",
					"Tower intel: tap a placed tower to inspect stats, then upgrade or sell.")
			return
	for rift in world.rifts:
		if not rift.points.is_empty() and rift.points[0].distance_to(world_pos) < 30.0:
			State.select_rift(rift)
			world.hints.maybe_show(&"rift_intel",
					"Tap rifts to view threat multipliers and sector intel.")
			return
	if world.core_pos.distance_to(world_pos) < 30.0:
		State.select_base()
		return
	var snap := World.snap_to_grid(world_pos)
	if world.is_tile_free(snap):
		if State.build_target == snap:
			State.clear_selection()
			return
		State.select_build_target(snap)
		world.tutorial.on_build_target_selected()
		return
	State.clear_selection()

func _handle_key(keycode: Key) -> void:
	match keycode:
		KEY_Q: choose_tower_type(&"basic")
		KEY_W: choose_tower_type(&"rapid")
		KEY_E: choose_tower_type(&"sniper")
		KEY_R: choose_tower_type(&"arc")
		KEY_1: world.start_targeting(&"emp")
		KEY_2: world.start_targeting(&"overclock")
		KEY_U: world.upgrade_selected()
		KEY_DELETE, KEY_BACKSPACE: world.sell_selected()
		KEY_F: world.repair_base()
		KEY_G: world.upgrade_base() # install / upgrade base turret
		KEY_P: toggle_pause()
		KEY_ESCAPE: handle_escape()

## JS window.selectTower: with a build target armed, picking a type builds
## there immediately.
func choose_tower_type(type: StringName) -> void:
	if State.build_target != Vector2.INF:
		world.build_tower(State.build_target, type)
		return
	State.select_tower_type(type)

func handle_escape() -> void:
	if State.selected_tower != null or State.selected_rift != null or State.selected_base \
			or State.build_target != Vector2.INF or State.selected_tower_type != &"" \
			or world.targeting_ability != &"":
		world.targeting_ability = &""
		State.clear_selection()
		return
	toggle_pause()

func toggle_pause() -> void:
	if State.phase != State.Phase.PLAYING:
		return
	State.paused = not State.paused
	if State.paused:
		AudioEngine.pause_music()
	else:
		AudioEngine.resume_music()
	hud.refresh_pause_menu()

# ---------------------------------------------------------------------------
# Game lifecycle
# ---------------------------------------------------------------------------

func start_game() -> void:
	_apply_tech_run_bonuses()
	State.phase = State.Phase.PLAYING
	world.start_prep_phase()
	world.tutorial.maybe_start()

## Tech Tree start-of-run bonuses (credits/lives/energy). Applied to the fresh
## default state of a new run — never on the save-load path.
func _apply_tech_run_bonuses() -> void:
	State.money += Tech.fx.start_money
	State.lives += Tech.fx.start_lives
	State.energy += Tech.fx.start_energy

func continue_game() -> void:
	if not world.save_system.load_game():
		start_game()
		return
	State.phase = State.Phase.PLAYING
	recenter()

func reset_game() -> void:
	State.reset()
	world.reset()
	_apply_tech_run_bonuses()
	State.phase = State.Phase.PLAYING
	world.start_prep_phase()
