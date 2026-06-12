class_name Tutorial
extends RefCounted
## Tutorial flow (JS 04_tutorial.js): steps 0-1 pause behind a modal dialog;
## steps 2-4 unpause and advance on build-target select, successful build,
## and wave start. SKIP only on step 0.

signal changed

const STEP_TEXTS := [
	"Welcome, Commander. Our sector is under threat. We need to establish a defense perimeter immediately.",
	"Command protocol loaded. You will now place your first defense node.",
	"First, select a tactical position. Hardpoint: fixed anchor slot with placement bonuses. Soft point: any normal empty grid tile without slot bonuses. Now TAP AN EMPTY SQUARE near the Core to target it.",
	"Position locked. Now, CHOOSE A TOWER TYPE from the deployment panel below.",
	"Defense initialized. When you're ready to engage the enemy, click START WAVE.",
]

var active := false
var completed := false
var step := 0

func _init() -> void:
	completed = _load_flag()

func is_modal_step() -> bool:
	return step <= 1

func can_skip() -> bool:
	return step == 0

func current_text() -> String:
	return STEP_TEXTS[clampi(step, 0, STEP_TEXTS.size() - 1)]

func maybe_start() -> void:
	if completed or active:
		return
	active = true
	step = 0
	State.paused = true
	changed.emit()

func next() -> void:
	if not active:
		return
	step += 1
	if step > 4:
		_finish()
		return
	State.paused = is_modal_step()
	changed.emit()

func skip() -> void:
	if active:
		_finish()

func _finish() -> void:
	active = false
	completed = true
	State.paused = false
	var file := FileAccess.open("user://tutorial_complete", FileAccess.WRITE)
	if file:
		file.store_string("true")
	changed.emit()

func _load_flag() -> bool:
	return FileAccess.file_exists("user://tutorial_complete")

func on_build_target_selected() -> void:
	if active and step == 2:
		next()

func on_tower_built() -> void:
	if active and step == 3:
		next()

func on_wave_started() -> void:
	if active and step == 4:
		next()
