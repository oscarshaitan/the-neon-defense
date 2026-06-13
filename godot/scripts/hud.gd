class_name Hud
extends CanvasLayer
## All UI built in code: stats bar, tower bar, abilities, selection panel,
## wave intel, pause menu, tutorial overlay, hints/toasts, start + game over.
## Signal-driven (State notifiers) with a 100 ms sync for countdown values —
## the same update model as the JS/Flutter versions.

var world: World
var main: Node

var _font := SystemFont.new()

# Screens / panels
var _start_screen: Control
var _game_over: Control
var _hud_root: Control
var _pause_menu: Control
var _selection_panel: PanelContainer
var _wave_intel: PanelContainer
var _tutorial_box: Control
var _toast: Label
var _hint: Label

# Stats labels
var _wave_label: Label
var _lives_label: Label
var _credits_label: Label
var _center_label: Label
var _fps_label: Label
var _energy_bar: ProgressBar
var _tower_buttons := {}

var _wave_intel_open := false
var _toast_timer: SceneTreeTimer

# Command center (JS debug panel): SHA-256-gated developer tools. The hash is
# the SHA-256 of the access code (matches the JS gate in 00_core.js).
const _DEBUG_HASH := "73ceb15f18bb0a313c8880abe54bf61a529dd8f1e75b084dd39926a1518d3d2f"
const _DEBUG_UNLOCK_PATH := "user://debug_unlocked.cfg"
var _debug_unlocked := false

func _ready() -> void:
	layer = 10
	_debug_unlocked = FileAccess.file_exists(_DEBUG_UNLOCK_PATH)
	_build_start_screen()
	_build_hud()
	_build_pause_menu()
	_build_game_over()

	State.phase_changed.connect(_on_phase_changed)
	State.money_changed.connect(func(_v): _refresh_stats())
	State.lives_changed.connect(func(_v): _refresh_stats())
	State.wave_changed.connect(func(_v): _refresh_stats())
	State.energy_changed.connect(func(v): _energy_bar.value = v)
	State.selection_changed.connect(_refresh_selection)
	State.toast_requested.connect(_show_toast)
	world.tutorial.changed.connect(_refresh_tutorial)
	world.hints.hint_shown.connect(_on_hint_shown)
	world.hints.hint_hidden.connect(_on_hint_hidden)

	var sync := Timer.new()
	sync.wait_time = 0.1
	sync.autostart = true
	sync.timeout.connect(_refresh_stats)
	add_child(sync)
	_on_phase_changed(State.phase)

# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l

func _button(text: String, color: Color, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", 13)
	b.add_theme_color_override(&"font_color", color)
	b.add_theme_color_override(&"font_hover_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	b.add_theme_stylebox_override(&"normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(color, 0.15)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b

func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(C.COL_BG, 0.94)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	p.add_theme_stylebox_override(&"panel", style)
	return p

# ---------------------------------------------------------------------------
# Start / game over screens
# ---------------------------------------------------------------------------

func _build_start_screen() -> void:
	_start_screen = Control.new()
	_start_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_start_screen)
	var bg := ColorRect.new()
	bg.color = C.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_screen.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 14)
	_start_screen.add_child(box)
	var title := _label("THE NEON DEFENSE", 40, C.COL_BLUE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _label("GODOT EDITION", 12, Color(C.COL_BLUE, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(Control.new())
	# Buttons depend on save presence — rebuilt on phase change.
	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override(&"separation", 10)
	box.add_child(actions)

func _refresh_start_actions() -> void:
	var actions: VBoxContainer = _start_screen.find_child("Actions", true, false)
	for child in actions.get_children():
		child.queue_free()
	if world.save_system.has_save():
		actions.add_child(_label("SAVE DATA FOUND", 10, C.COL_GREEN))
		actions.add_child(_button("CONTINUE", C.COL_GREEN, main.continue_game))
		actions.add_child(_button("NEW GAME", C.COL_BLUE, func():
			world.save_system.clear_save()
			main.start_game()))
	else:
		actions.add_child(_button("INITIATE", C.COL_BLUE, main.start_game))

func _build_game_over() -> void:
	_game_over = Control.new()
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.visible = false
	add_child(_game_over)
	var bg := ColorRect.new()
	bg.color = Color(C.COL_BG, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 12)
	_game_over.add_child(box)
	var title := _label("SYSTEM FAILURE", 32, C.COL_PINK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_label("SECTOR OVERRUN", 12, Color(C.COL_PINK, 0.6)))
	var wave_label := _label("", 11, Color(C.COL_BLUE, 0.5))
	wave_label.name = "WaveLabel"
	box.add_child(wave_label)
	box.add_child(_button("REBOOT SYSTEM", C.COL_PINK, main.reset_game))

# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.visible = false
	add_child(_hud_root)

	# --- Stats bar (top) ---
	var stats := _panel(C.COL_BLUE)
	stats.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stats.offset_left = 8
	stats.offset_right = -8
	stats.offset_top = 8
	_hud_root.add_child(stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	stats.add_child(row)
	_wave_label = _label("WAVE: 1", 12, C.COL_BLUE)
	var wave_btn := Button.new()
	wave_btn.flat = true
	wave_btn.pressed.connect(func():
		_wave_intel_open = not _wave_intel_open
		_refresh_wave_intel())
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_btn.add_child(_wave_label)
	wave_btn.custom_minimum_size = Vector2(90, 0)
	row.add_child(wave_btn)
	_lives_label = _label("LIVES: 20", 12, C.COL_BLUE)
	row.add_child(_lives_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_center_label = _label("", 12, C.COL_GREEN)
	row.add_child(_center_label)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)
	_credits_label = _label("CREDITS: 100", 12, C.COL_YELLOW)
	row.add_child(_credits_label)
	_fps_label = _label("FPS: --", 11, Color(C.COL_BLUE, 0.7))
	row.add_child(_fps_label)
	row.add_child(_button("II", C.COL_BLUE, main.toggle_pause))

	# --- START WAVE ---
	var start_wave := _button("START WAVE", C.COL_GREEN, world.skip_prep)
	start_wave.name = "StartWave"
	start_wave.set_anchors_preset(Control.PRESET_CENTER_TOP)
	start_wave.offset_top = 64
	start_wave.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_root.add_child(start_wave)

	# --- Tower bar (bottom center) ---
	var tower_bar := _panel(Color(C.COL_BLUE, 0.7))
	tower_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tower_bar.offset_bottom = -16
	tower_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tower_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_root.add_child(tower_bar)
	var tower_row := HBoxContainer.new()
	tower_row.add_theme_constant_override(&"separation", 8)
	tower_bar.add_child(tower_row)
	var hotkeys := {&"basic": "Q", &"rapid": "W", &"sniper": "E", &"arc": "R"}
	for type in C.TOWER_ORDER:
		var def := C.tower_def(type)
		var b := _button("%s\n[%s] $%d" % [String(type).to_upper(), hotkeys[type], int(def.cost)],
				def.color, main.choose_tower_type.bind(type))
		_tower_buttons[type] = b
		tower_row.add_child(b)

	# --- Abilities (right) ---
	var abilities := _panel(Color(C.COL_BLUE, 0.5))
	abilities.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	abilities.offset_right = -8
	abilities.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	abilities.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hud_root.add_child(abilities)
	var ability_col := VBoxContainer.new()
	ability_col.add_theme_constant_override(&"separation", 8)
	abilities.add_child(ability_col)
	ability_col.add_child(_button("EMP\n[1] 40⚡", C.COL_BLUE,
			world.start_targeting.bind(&"emp")))
	ability_col.add_child(_button("OVERCLOCK\n[2] 25⚡", C.COL_YELLOW,
			world.start_targeting.bind(&"overclock")))
	ability_col.add_child(_label("ENERGY", 9, Color(C.COL_BLUE, 0.6)))
	_energy_bar = ProgressBar.new()
	_energy_bar.max_value = C.MAX_ENERGY
	_energy_bar.show_percentage = false
	_energy_bar.custom_minimum_size = Vector2(0, 10)
	ability_col.add_child(_energy_bar)

	# --- Recenter (bottom right) ---
	var recenter := _button("◎", C.COL_BLUE, main.recenter)
	recenter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	recenter.offset_right = -16
	recenter.offset_bottom = -16
	recenter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	recenter.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_root.add_child(recenter)

	# --- Selection panel (bottom left) ---
	_selection_panel = _panel(Color(C.COL_PINK, 0.7))
	_selection_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_selection_panel.offset_left = 8
	_selection_panel.offset_bottom = -16
	_selection_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_selection_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_selection_panel.visible = false
	_hud_root.add_child(_selection_panel)

	# --- Wave intel (top left) ---
	_wave_intel = _panel(Color(C.COL_BLUE, 0.7))
	_wave_intel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_wave_intel.offset_left = 8
	_wave_intel.offset_top = 64
	_wave_intel.visible = false
	_hud_root.add_child(_wave_intel)

	# --- Toast + hint ---
	_toast = _label("", 11, C.COL_YELLOW)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 70
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.visible = false
	_hud_root.add_child(_toast)
	_hint = _label("", 10, Color("e6fcff", 0.85))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_bottom = -110
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.visible = false
	_hud_root.add_child(_hint)

	# --- Tutorial overlay ---
	_tutorial_box = _panel(C.COL_BLUE)
	_tutorial_box.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tutorial_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tutorial_box.visible = false
	_hud_root.add_child(_tutorial_box)

func _refresh_stats() -> void:
	if not _hud_root.visible:
		return
	_wave_label.text = "WAVE: %d" % State.wave
	_lives_label.text = "LIVES: %d" % State.lives
	_credits_label.text = "CREDITS: %d" % int(State.money)
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if world.is_prep_phase:
		_center_label.text = "NEXT WAVE: %ds" % ceili(world.prep_timer)
		_center_label.add_theme_color_override(&"font_color", C.COL_GREEN)
	elif State.is_wave_active:
		_center_label.text = "ENEMIES: %d" % (world.enemies.size() + world.spawn_queue.size())
		_center_label.add_theme_color_override(&"font_color", C.COL_RED)
	else:
		_center_label.text = ""
	var start_wave: Button = _hud_root.find_child("StartWave", true, false)
	start_wave.visible = world.is_prep_phase
	for type in _tower_buttons:
		_tower_buttons[type].disabled = State.money < C.tower_def(type).cost
	if _wave_intel_open:
		_refresh_wave_intel()
	if _selection_panel.visible:
		_refresh_selection()

# ---------------------------------------------------------------------------
# Selection panel (tower / rift / base variants)
# ---------------------------------------------------------------------------

func _refresh_selection() -> void:
	for child in _selection_panel.get_children():
		child.queue_free()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(190, 0)
	col.add_theme_constant_override(&"separation", 5)
	_selection_panel.add_child(col)

	if State.selected_tower != null:
		var t = State.selected_tower
		col.add_child(_label("TOWER INFO", 11, C.COL_PINK))
		col.add_child(_label("TYPE: %s   LVL: %d" % [String(t.type).to_upper(), t.level], 10, Color.WHITE))
		col.add_child(_label("DMG: %.1f   RNG: %.0f" % [t.damage, t.range], 10, Color.WHITE))
		var up_cost := World.upgrade_cost(t)
		col.add_child(_button("UPGRADE  $%d" % int(up_cost),
				C.COL_GREEN if State.money >= up_cost else Color(1, 1, 1, 0.3),
				world.upgrade_selected))
		col.add_child(_button("SELL  $%d" % int(World.sell_value(t)), C.COL_RED, world.sell_selected))
		col.add_child(_button("CLOSE", Color(1, 1, 1, 0.5), State.clear_selection))
		_selection_panel.visible = true
	elif State.selected_rift != null:
		var rift = State.selected_rift
		col.add_child(_label("RIFT INTEL", 11, C.COL_PINK))
		col.add_child(_label("TIER: %d   ZONE: %d" % [rift.level, rift.zone], 10, Color.WHITE))
		col.add_child(_label("HP x%.2f  SPD x%.2f" % [1 + (rift.level - 1) * 0.5,
				1 + (rift.level - 1) * 0.15], 10, Color.WHITE))
		if not rift.mutation.is_empty():
			col.add_child(_label("!! %s MUTATION !!" % rift.mutation.key, 10, rift.mutation.color))
		col.add_child(_button("CLOSE", Color(1, 1, 1, 0.5), State.clear_selection))
		_selection_panel.visible = true
	elif State.selected_base:
		col.add_child(_label("HOME BASE", 11, C.COL_PINK))
		col.add_child(_label("TURRET LVL: %d   LIVES: %d" % [world.base_level, State.lives], 10, Color.WHITE))
		var repair := world.base_repair_cost()
		col.add_child(_button("REPAIR  $%d" % int(repair),
				C.COL_GREEN if State.money >= repair else Color(1, 1, 1, 0.3), world.repair_base))
		if world.base_level < 10:
			var up := world.base_upgrade_cost()
			col.add_child(_button("%s TURRET  $%d" % ["INSTALL" if world.base_level == 0 else "UPGRADE", int(up)],
					C.COL_BLUE if State.money >= up else Color(1, 1, 1, 0.3), world.upgrade_base))
		else:
			col.add_child(_label("MAX LEVEL", 10, Color(1, 1, 1, 0.4)))
		col.add_child(_button("CLOSE", Color(1, 1, 1, 0.5), State.clear_selection))
		_selection_panel.visible = true
	else:
		_selection_panel.visible = false

# ---------------------------------------------------------------------------
# Wave intel
# ---------------------------------------------------------------------------

func _refresh_wave_intel() -> void:
	_wave_intel.visible = _wave_intel_open
	if not _wave_intel_open:
		return
	for child in _wave_intel.get_children():
		child.queue_free()
	var report := WaveIntel.report(State.wave, world.rifts, State.is_wave_active,
			world.current_wave_distribution)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(230, 0)
	col.add_theme_constant_override(&"separation", 5)
	_wave_intel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label("WAVE %d INTEL" % report.wave, 11, C.COL_BLUE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("X", Color(1, 1, 1, 0.5), func():
		_wave_intel_open = false
		_refresh_wave_intel()))
	var threat := _label("THREAT: %s" % report.threat, 10, report.threat_color)
	col.add_child(threat)
	col.add_child(_label("RIFTS: %d" % report.total_rifts, 10, Color.WHITE))
	col.add_child(_label(report.mutation_status, 9, Color(1, 1, 1, 0.6)))
	if not report.tags.is_empty():
		var tag_text := ""
		for tag in report.tags:
			tag_text += "[%s] " % tag.label
		col.add_child(_label(tag_text, 9, C.COL_YELLOW))
	col.add_child(_label("EXPECTED HOSTILES", 9, Color(C.COL_BLUE, 0.6)))
	var dist_text := ""
	for type in WaveIntel.ORDER:
		var count := int(report.distribution.get(type, 0))
		if count > 0:
			dist_text += "%s:%d  " % [String(type), count]
	col.add_child(_label(dist_text, 9, Color.WHITE))

# ---------------------------------------------------------------------------
# Input guard
# ---------------------------------------------------------------------------

## True if a screen-space tap lands on a visible, input-consuming HUD control
## (panel, button, label). main.gd uses this so a tap on the selection panel
## never falls through to the world handler and closes the menu.
func blocks_world_tap(screen_pos: Vector2) -> bool:
	if _pause_menu.visible and _pause_menu.get_global_rect().has_point(screen_pos):
		return true
	return _control_blocks(_hud_root, screen_pos)

func _control_blocks(node: Node, screen_pos: Vector2) -> bool:
	if node is Control:
		var c := node as Control
		if c.visible and c.mouse_filter == Control.MOUSE_FILTER_STOP \
				and c.get_global_rect().has_point(screen_pos):
			return true
	for child in node.get_children():
		if _control_blocks(child, screen_pos):
			return true
	return false

# ---------------------------------------------------------------------------
# Pause menu
# ---------------------------------------------------------------------------

func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.visible = false
	add_child(_pause_menu)
	var bg := ColorRect.new()
	bg.color = Color(C.COL_BG, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(bg)
	var panel := _panel(Color(C.COL_BLUE, 0.5))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_menu.add_child(panel)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)

func refresh_pause_menu() -> void:
	_pause_menu.visible = State.paused and not world.tutorial.active
	if not _pause_menu.visible:
		return
	var col: VBoxContainer = _pause_menu.find_child("Col", true, false)
	for child in col.get_children():
		child.queue_free()
	var title := _label("PAUSED", 22, C.COL_BLUE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(_button("RESUME", C.COL_BLUE, main.toggle_pause))
	col.add_child(_button("SAVE", C.COL_GREEN, func():
		world.save_system.save_now()
		State.show_toast("GAME SAVED")))
	col.add_child(_button("RESET", C.COL_PINK, func():
		main.toggle_pause()
		main.reset_game()))
	col.add_child(_label("SOUND", 9, Color(C.COL_BLUE, 0.5)))
	col.add_child(_button("SOUND: %s" % ("OFF" if AudioEngine.muted else "ON"),
			C.COL_GREEN if not AudioEngine.muted else Color(1, 1, 1, 0.4), func():
		AudioEngine.toggle_mute()
		refresh_pause_menu()))
	var music := HSlider.new()
	music.max_value = 1.0
	music.step = 0.05
	music.value = AudioEngine.music_volume
	music.custom_minimum_size = Vector2(180, 16)
	music.value_changed.connect(AudioEngine.set_music_volume)
	col.add_child(_label("MUSIC", 8, Color(C.COL_BLUE, 0.5)))
	col.add_child(music)
	var sfx := HSlider.new()
	sfx.max_value = 1.0
	sfx.step = 0.05
	sfx.value = AudioEngine.sfx_volume
	sfx.custom_minimum_size = Vector2(180, 16)
	sfx.value_changed.connect(AudioEngine.set_sfx_volume)
	col.add_child(_label("SFX", 8, Color(C.COL_BLUE, 0.5)))
	col.add_child(sfx)
	col.add_child(_label("DETAILS", 9, Color(C.COL_BLUE, 0.5)))
	var quality_row := HBoxContainer.new()
	quality_row.add_theme_constant_override(&"separation", 6)
	col.add_child(quality_row)
	for i in 3:
		var selected: bool = not world.auto_quality and world.quality == i
		quality_row.add_child(_button(C.QUALITY_PROFILES[i].name,
				C.COL_GREEN if selected else Color(C.COL_BLUE, 0.6), func():
			world.set_quality_manual(i)
			refresh_pause_menu()))
	quality_row.add_child(_button("AUTO", C.COL_GREEN if world.auto_quality else Color(C.COL_BLUE, 0.6), func():
		world.auto_quality = true
		State.show_toast("DETAILS: AUTO")
		refresh_pause_menu()))
	_build_command_center(col)

# ---------------------------------------------------------------------------
# Command center (JS debug panel) — SHA-256-gated developer tools
# ---------------------------------------------------------------------------

func _build_command_center(col: VBoxContainer) -> void:
	if not _debug_unlocked:
		col.add_child(_label("COMMAND CENTER", 9, Color(C.COL_PINK, 0.5)))
		var pass_field := LineEdit.new()
		pass_field.secret = true
		pass_field.placeholder_text = "ACCESS CODE"
		pass_field.custom_minimum_size = Vector2(180, 24)
		col.add_child(pass_field)
		var unlock_btn := _button("UNLOCK COMMAND CENTER", C.COL_PINK, Callable())
		unlock_btn.pressed.connect(func(): _attempt_debug_unlock(pass_field, unlock_btn))
		pass_field.text_submitted.connect(func(_t): _attempt_debug_unlock(pass_field, unlock_btn))
		col.add_child(unlock_btn)
		return

	col.add_child(_label("COMMAND CENTER", 9, C.COL_PINK))
	col.add_child(_button("+1M CREDITS", C.COL_YELLOW, world.debug_add_money))
	var rift_row := HBoxContainer.new()
	rift_row.add_theme_constant_override(&"separation", 6)
	col.add_child(rift_row)
	rift_row.add_child(_button("NEW RIFT", C.COL_BLUE, world.debug_create_rift))
	rift_row.add_child(_button("LEVEL UP RIFT", C.COL_BLUE, world.debug_level_up_rift))
	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override(&"separation", 6)
	col.add_child(wave_row)
	wave_row.add_child(_button("+1 WAVE", C.COL_GREEN, func(): world.debug_increase_wave(1, true)))
	wave_row.add_child(_button("+5 WAVES", C.COL_GREEN, func(): world.debug_increase_wave(5, true)))
	wave_row.add_child(_button("+10 WAVES", C.COL_GREEN, func(): world.debug_increase_wave(10, true)))
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override(&"separation", 6)
	col.add_child(lvl_row)
	lvl_row.add_child(_button("+5 LVL", C.COL_YELLOW, func(): world.debug_upgrade_all_towers(5)))
	lvl_row.add_child(_button("+10 LVL", C.COL_YELLOW, func(): world.debug_upgrade_all_towers(10)))
	lvl_row.add_child(_button("+25 LVL", C.COL_YELLOW, func(): world.debug_upgrade_all_towers(25)))
	col.add_child(_button("REBUILD RIFTS", C.COL_BLUE, world.debug_rebuild_rifts))
	col.add_child(_button("TOGGLE OVERLAY", C.COL_PINK, world.toggle_no_build_overlay))
	var spawn_grid := GridContainer.new()
	spawn_grid.columns = 4
	spawn_grid.add_theme_constant_override(&"h_separation", 4)
	spawn_grid.add_theme_constant_override(&"v_separation", 4)
	col.add_child(spawn_grid)
	for type in [&"basic", &"fast", &"tank", &"splitter", &"bulwark", &"shifter", &"boss"]:
		spawn_grid.add_child(_button(String(type).to_upper(), C.COL_RED,
				func(): world.debug_spawn(type)))

## JS unlockDebug: SHA-256 the entered code; unlock + persist on match, else
## flash "ACCESS DENIED" for one second.
func _attempt_debug_unlock(field: LineEdit, btn: Button) -> void:
	if field.text.sha256_text() == _DEBUG_HASH:
		_debug_unlocked = true
		FileAccess.open(_DEBUG_UNLOCK_PATH, FileAccess.WRITE) # persist unlock marker
		refresh_pause_menu()
	else:
		btn.text = "ACCESS DENIED"
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(btn):
				btn.text = "UNLOCK COMMAND CENTER")

# ---------------------------------------------------------------------------
# Tutorial / toast
# ---------------------------------------------------------------------------

func _refresh_tutorial() -> void:
	var tutorial := world.tutorial
	_tutorial_box.visible = tutorial.active
	refresh_pause_menu()
	if not tutorial.active:
		return
	for child in _tutorial_box.get_children():
		child.queue_free()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override(&"separation", 10)
	_tutorial_box.add_child(col)
	col.add_child(_label("INCOMING TRANSMISSION", 9, C.COL_PINK))
	var msg := _label(tutorial.current_text(), 11, Color("e6fcff"))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(380, 0)
	col.add_child(msg)
	if tutorial.is_modal_step():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		col.add_child(row)
		row.add_child(_button("UNDERSTOOD", C.COL_BLUE, tutorial.next))
		if tutorial.can_skip():
			row.add_child(_button("SKIP", Color(1, 1, 1, 0.5), tutorial.skip))
		_tutorial_box.set_anchors_preset(Control.PRESET_CENTER)
	else:
		_tutorial_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_tutorial_box.offset_top = 100

func _on_hint_shown(text: String) -> void:
	_hint.text = text
	_hint.visible = true
	get_tree().create_timer(3.6).timeout.connect(world.hints.hide_current)

func _on_hint_hidden() -> void:
	_hint.visible = false

func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast_timer = get_tree().create_timer(2.4)
	var this_timer := _toast_timer
	this_timer.timeout.connect(func():
		if _toast_timer == this_timer:
			_toast.visible = false)

# ---------------------------------------------------------------------------
# Phase switching
# ---------------------------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	_start_screen.visible = phase == State.Phase.START
	_hud_root.visible = phase == State.Phase.PLAYING
	_game_over.visible = phase == State.Phase.GAME_OVER
	if phase == State.Phase.START:
		_refresh_start_actions()
	elif phase == State.Phase.GAME_OVER:
		var wave_label: Label = _game_over.find_child("WaveLabel", true, false)
		wave_label.text = "WAVE %d" % State.wave
	refresh_pause_menu()
	_refresh_stats()
