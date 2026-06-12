class_name Hints
extends RefCounted
## Onboarding hints (JS 00_core.js:299-397): versioned seen-keys, one hint at
## a time for 3.6 s; suppressed while paused or in the tutorial.

signal hint_shown(text: String)
signal hint_hidden

const VERSION := 3
const SEEN_PATH := "user://onboarding_hints.json"

var _seen := {}
var _queue: Array[Dictionary] = []
var active := ""

func _init() -> void:
	_load_seen()

func maybe_show(key: StringName, text: String) -> void:
	if _seen.get(String(key), false) or active != "":
		for queued in _queue:
			if queued.key == key:
				return
	if _seen.get(String(key), false):
		return
	_queue.append({key = key, text = text})
	show_next()

func show_next() -> void:
	if active != "" or _queue.is_empty() or not State.is_playing():
		return
	var next: Dictionary = _queue.pop_front()
	_seen[String(next.key)] = true
	_save_seen()
	active = next.text
	hint_shown.emit(active)

func hide_current() -> void:
	active = ""
	hint_hidden.emit()
	show_next()

func _load_seen() -> void:
	if not FileAccess.file_exists(SEEN_PATH):
		return
	var file := FileAccess.open(SEEN_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text()) if file else null
	if data is Dictionary and int(data.get("version", 0)) == VERSION:
		_seen = data.get("seen", {})

func _save_seen() -> void:
	var file := FileAccess.open(SEEN_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({version = VERSION, seen = _seen}))
