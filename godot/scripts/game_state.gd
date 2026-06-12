extends Node
## Autoload "State" — observable game state mirroring the JS module globals
## (money, lives, wave, energy, isWaveActive, gameState) with signals so the
## UI updates on change instead of polling.

signal money_changed(value: float)
signal lives_changed(value: int)
signal energy_changed(value: float)
signal wave_changed(value: int)
signal wave_active_changed(active: bool)
signal phase_changed(phase: int)
signal toast_requested(message: String)
signal selection_changed

enum Phase { START, PLAYING, GAME_OVER }

var money := C.STARTING_MONEY:
	set(v):
		money = v
		money_changed.emit(v)
var lives := C.STARTING_LIVES:
	set(v):
		lives = v
		lives_changed.emit(v)
var energy := 0.0:
	set(v):
		energy = clampf(v, 0.0, C.MAX_ENERGY)
		energy_changed.emit(energy)
var wave := 1:
	set(v):
		wave = v
		wave_changed.emit(v)
var is_wave_active := false:
	set(v):
		is_wave_active = v
		wave_active_changed.emit(v)
var phase := Phase.START:
	set(v):
		phase = v
		phase_changed.emit(v)
var paused := false

## Fixed-step frame counter — JS effects key off frameCount (pulses use
## sin(frameCount * 0.1)); frozen while paused like the JS loop.
var frame_count := 0

## Screen shake (JS startShake/decay): keep the larger impulse, x0.9/frame.
var shake_amount := 0.0

var player_name := ""
var total_kills := {}

# --- Selection (mutually exclusive, JS handleClick semantics) ---
var selected_tower = null # Tower (world.gd inner class)
var selected_rift = null # Rift dictionary
var selected_base := false
var build_target := Vector2.INF # Vector2.INF = none
var selected_tower_type: StringName = &""

func is_playing() -> bool:
	return phase == Phase.PLAYING and not paused

func start_shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, amount)

func show_toast(message: String) -> void:
	toast_requested.emit(message)

func add_energy(amount: float) -> void:
	energy = energy + amount

func record_kill(type: StringName) -> void:
	total_kills[type] = int(total_kills.get(type, 0)) + 1

func clear_selection() -> void:
	selected_tower = null
	selected_rift = null
	selected_base = false
	build_target = Vector2.INF
	selected_tower_type = &""
	selection_changed.emit()

func select_tower(tower) -> void:
	clear_selection()
	selected_tower = tower
	selection_changed.emit()

func select_rift(rift) -> void:
	clear_selection()
	selected_rift = rift
	selection_changed.emit()

func select_base() -> void:
	clear_selection()
	selected_base = true
	selection_changed.emit()

func select_build_target(snap: Vector2) -> void:
	clear_selection()
	build_target = snap
	selection_changed.emit()

func select_tower_type(type: StringName) -> void:
	var kept := build_target
	clear_selection()
	build_target = kept
	selected_tower_type = type
	selection_changed.emit()

func reset() -> void:
	money = C.STARTING_MONEY
	lives = C.STARTING_LIVES
	energy = 0.0
	wave = 1
	is_wave_active = false
	paused = false
	frame_count = 0
	shake_amount = 0.0
	total_kills = {}
	clear_selection()
