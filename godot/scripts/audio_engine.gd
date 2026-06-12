extends Node
## Autoload "AudioEngine" — synthesizes the JS AudioEngine's procedural
## patterns (00_core.js:406-705) into AudioStreamWAV buffers, lazily per
## track: 15 wave-indexed 16-step loops + the threat loop, and the 4 SFX
## (square shoot 400->100, saw explosion 100->10, triangle hit 150->50,
## sine build 200->800). Unmapped notes fall back to 60 Hz like the JS.

const SAMPLE_RATE := 22050

# JS AudioEngine.notes — intentionally incomplete; missing notes -> 60 Hz.
const NOTES := {
	"C2": 65.41, "G2": 98.00, "A2": 110.00, "F2": 87.31,
	"C3": 130.81, "Eb3": 155.56, "Gb3": 185.00, "G3": 196.00, "Bb3": 233.08,
	"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
	"A4": 440.00, "B4": 493.88,
	"C5": 523.25, "D5": 587.33, "Eb5": 622.25, "E5": 659.25, "F5": 698.46,
	"Gb5": 739.99, "G5": 783.99,
}

const MELODIES_NORMAL := [
	{lead = ["C4", "E4", "G4", 0, "F4", "A4", "C5", 0, "G4", "B4", "D5", 0, "C5", "G4", "E4", "D4"],
		bass = ["C2", 0, "G2", "C2", "F2", 0, "C3", "F2", "G2", 0, "D3", "G2", "C2", "G2", "E2", "D2"]},
	{lead = ["A4", "C5", "E5", 0, "F4", "A4", "C5", 0, "C4", "E4", "G4", 0, "G4", "B4", "D5", 0],
		bass = ["A2", 0, "E2", "A2", "F2", 0, "C3", "F2", "C2", 0, "G2", "C2", "G2", 0, "D3", "G2"]},
	{lead = ["D4", "F4", "A4", "C5", "G4", "Bb4", "D5", 0, "F4", "A4", "C5", 0, "C4", "E4", "G4", 0],
		bass = ["D2", 0, "A2", "D2", "G2", 0, "D3", "G2", "F2", 0, "C3", "F2", "C2", 0, "G2", "C2"]},
	{lead = ["E4", "F4", "G4", 0, "F4", "G4", "A4", 0, "G4", "Ab4", "C5", 0, "Eb5", "D5", "C5", "Bb4"],
		bass = ["E2", 0, "B2", "E2", "F2", 0, "C3", "F2", "G2", 0, "D3", "G2", "Ab2", 0, "Eb3", "Ab2"]},
	{lead = ["C4", "D4", "E4", "G4", "A4", "G4", "E4", "D4", "C5", "A4", "G4", "E4", "D4", "C4", "D4", "E4"],
		bass = ["C2", "C2", "G2", "G2", "A2", "A2", "F2", "F2", "C2", "C2", "G2", "G2", "A2", "A2", "F2", "F2"]},
	{lead = ["C4", "E4", "G4", "B4", "D5", "B4", "G4", "E4", "F4", "A4", "C5", "E5", "D5", "C5", "A4", "F4"],
		bass = ["C2", 0, "G2", "C2", "D2", 0, "A2", "D2", "F2", 0, "C3", "F2", "G2", 0, "D3", "G2"]},
	{lead = ["G4", "B4", "D5", "F5", "E5", "C5", "B4", "G4", "A4", "C5", "E5", "G4", "F4", "D4", "B3", "G3"],
		bass = ["G2", 0, "D3", "G2", "F2", 0, "C3", "F2", "C2", 0, "G2", "C2", "Bb2", 0, "F2", "Bb2"]},
	{lead = ["C4", "Db4", "D4", "Eb4", "E4", "Eb4", "D4", "Db4", "C4", "G3", "C4", "Db4", "D4", "A3", "D4", "Eb4"],
		bass = ["C2", "Db2", "D2", "Eb2", "E2", "Eb2", "D2", "Db2", "C2", "G1", "C2", "Db2", "D2", "A1", "D2", "Eb2"]},
	{lead = ["C4", "G4", "C5", "G4", "E4", "B4", "E5", "B4", "F4", "C5", "F5", "C5", "G4", "D5", "G5", "D5"],
		bass = ["C2", 0, 0, 0, "E2", 0, 0, 0, "F2", 0, 0, 0, "G2", 0, 0, 0]},
	{lead = [0, "C4", 0, "E4", "G4", 0, "F4", 0, 0, "A4", 0, "C5", "G4", 0, "D5", 0],
		bass = ["C2", 0, "G2", 0, "C2", 0, "F2", 0, "F2", 0, "C3", 0, "G2", 0, "D3", 0]},
	{lead = ["G4", "Bb4", "D5", "Eb5", "D5", "Bb4", "G4", "F4", "G4", "D4", "G4", "Bb4", "C5", "Bb4", "A4", "F4"],
		bass = ["G2", 0, "D3", "G2", "Eb2", 0, "Bb2", "Eb2", "C2", 0, "G2", "C2", "F2", 0, "C3", "F2"]},
	{lead = ["C4", 0, "C4", "Eb4", 0, "F4", "Gb4", "G4", 0, "Bb4", 0, "C5", 0, "G4", "Eb4", "C4"],
		bass = ["C2", "C2", 0, "Eb2", "Eb2", 0, "F2", "G2", "C2", "C2", 0, "Bb1", "Bb1", 0, "G1", "F1"]},
	{lead = ["C5", 0, "G4", 0, "E4", 0, "C4", 0, "D5", 0, "A4", 0, "F4", 0, "D4", 0],
		bass = ["C2", "G2", "C3", "G2", "A2", "E3", "A3", "E3", "F2", "C3", "F3", "C3", "G2", "D3", "G3", "D3"]},
	{lead = ["A3", "C4", "E4", "A4", "G4", "E4", "C4", "B3", "F3", "A3", "C4", "F4", "E4", "C4", "A3", "G3"],
		bass = ["A1", "A1", "E2", "E2", "G1", "G1", "D2", "D2", "F1", "F1", "C2", "C2", "E1", "E1", "B1", "B1"]},
	{lead = ["E4", "E4", "G4", "A4", "B4", "B4", "D5", "E5", "D5", "D5", "B4", "A4", "G4", "G4", "E4", "D4"],
		bass = ["E2", "E2", "G2", "G2", "A2", "A2", "B2", "B2", "D3", "D3", "B2", "B2", "A2", "A2", "G2", "F2"]},
]
const MELODY_THREAT := {
	lead = ["C5", "Eb5", "G5", "Eb5", "Gb5", "Eb5", "C5", "Bb4", "C5", "Eb5", "Gb5", "Eb5", "F5", "Eb5", "D5", "Bb4"],
	bass = ["C2", 0, "C2", 0, "Eb2", 0, "Eb2", 0, "Gb2", 0, "Gb2", 0, "G2", 0, "G2", 0],
}

var music_volume := 0.5
var sfx_volume := 0.7
var muted := false

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _current_track := ""
var _track_cache := {}
var _sfx_cache := {}
var _last_shoot_frame := -1000000

func _ready() -> void:
	_load_settings()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Master"
	add_child(_music_player)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)

# ---------------------------------------------------------------------------
# Music (JS updateMusic): threat track while a boss/mutant is alive, else
# the wave-indexed normal loop ((wave-1) % 15).
# ---------------------------------------------------------------------------

func update_music(wave: int, has_threat: bool) -> void:
	var track := "threat" if has_threat else "normal_%d" % ((wave - 1) % 15)
	if track == _current_track:
		return
	_current_track = track
	if muted:
		return
	_music_player.stream = _get_track(track)
	_music_player.volume_db = linear_to_db(music_volume)
	_music_player.play()

func pause_music() -> void:
	_music_player.stream_paused = true

func resume_music() -> void:
	if not muted:
		_music_player.stream_paused = false

func stop_music() -> void:
	_current_track = ""
	_music_player.stop()

func _get_track(name: String) -> AudioStreamWAV:
	if _track_cache.has(name):
		return _track_cache[name]
	var threat := name == "threat"
	var melody: Dictionary = MELODY_THREAT if threat else MELODIES_NORMAL[int(name.split("_")[1])]
	var stream := _render_loop(melody, threat)
	_track_cache[name] = stream
	return stream

func _note_freq(note) -> float:
	if note is String and NOTES.has(note):
		return NOTES[note]
	return 60.0 # JS `this.notes[note] || 60`

func _render_loop(melody: Dictionary, threat: bool) -> AudioStreamWAV:
	var step_time := 0.125 if threat else 0.2
	var total := int(16 * step_time * SAMPLE_RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(total)
	for step in 16:
		var at := int(step * step_time * SAMPLE_RATE)
		var bass = melody.bass[step]
		if bass is String:
			_mix_note(buffer, at, &"triangle", _note_freq(bass), 0.1, step_time * 0.9)
		var lead = melody.lead[step]
		if lead is String:
			if threat and step % 4 == 0:
				_mix_arp(buffer, at, _note_freq(lead), 0.05, step_time * 0.8)
			else:
				_mix_note(buffer, at, &"square", _note_freq(lead), 0.05, step_time * 0.7)
	return _to_wav(buffer, true)

func _osc(kind: StringName, phase: float) -> float:
	match kind:
		&"sine":
			return sin(phase)
		&"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		&"sawtooth":
			return 2.0 * fposmod(phase / TAU, 1.0) - 1.0
		&"triangle":
			return 2.0 * absf(2.0 * fposmod(phase / TAU, 1.0) - 1.0) - 1.0
	return 0.0

func _mix_note(buffer: PackedFloat32Array, at: int, kind: StringName, freq: float,
		vol: float, duration: float) -> void:
	var n := int(duration * SAMPLE_RATE)
	var phase := 0.0
	for i in n:
		if at + i >= buffer.size():
			break
		# Web Audio exponentialRampToValueAtTime(0.001) gain curve.
		var gain := vol * pow(0.001 / vol, float(i) / maxf(1.0, n - 1))
		buffer[at + i] += _osc(kind, phase) * gain
		phase += TAU * freq / SAMPLE_RATE

func _mix_arp(buffer: PackedFloat32Array, at: int, base_freq: float, vol: float,
		duration: float) -> void:
	var n := int(duration * SAMPLE_RATE)
	var arp := int(0.05 * SAMPLE_RATE)
	var mults := [1.0, 1.25, 1.5, 2.0]
	var phase := 0.0
	for i in n:
		if at + i >= buffer.size():
			break
		var freq: float = base_freq * mults[mini(i / arp, 3)]
		var gain := vol * pow(0.001 / vol, float(i) / maxf(1.0, n - 1))
		buffer[at + i] += _osc(&"square", phase) * gain
		phase += TAU * freq / SAMPLE_RATE

func _to_wav(buffer: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buffer.size() * 2)
	for i in buffer.size():
		var v := int(clampf(buffer[i] * 4.0, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = buffer.size()
	return stream

# ---------------------------------------------------------------------------
# SFX (JS playSFX)
# ---------------------------------------------------------------------------

func play_shoot() -> void:
	# JS playShootSFX throttle by quality (handled by frame distance here).
	if State.frame_count - _last_shoot_frame < 1:
		return
	_last_shoot_frame = State.frame_count
	play_sfx(&"shoot")

func play_sfx(name: StringName) -> void:
	if muted:
		return
	var stream: AudioStreamWAV = _sfx_cache.get(name)
	if stream == null:
		stream = _render_sfx(name)
		_sfx_cache[name] = stream
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

func _render_sfx(name: StringName) -> AudioStreamWAV:
	var buffer := PackedFloat32Array()
	match name:
		&"shoot": # square 400 -> 100 exp, 0.1 s, vol .05 exp decay
			buffer = _sweep(&"square", 400.0, 100.0, 0.1, 0.05, true, true)
		&"explosion": # saw 100 -> 10 exp, 0.3 s, vol .1 linear decay
			buffer = _sweep(&"sawtooth", 100.0, 10.0, 0.3, 0.1, true, false)
		&"hit": # triangle 150 -> 50 linear, 0.2 s, vol .2 linear decay
			buffer = _sweep(&"triangle", 150.0, 50.0, 0.2, 0.2, false, false)
		&"build": # sine 200 -> 800 exp, 0.2 s, vol .05 exp decay
			buffer = _sweep(&"sine", 200.0, 800.0, 0.2, 0.05, true, true)
	return _to_wav(buffer, false)

func _sweep(kind: StringName, f0: float, f1: float, duration: float, vol: float,
		exp_freq: bool, exp_gain: bool) -> PackedFloat32Array:
	var n := int(duration * SAMPLE_RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / maxf(1.0, n - 1)
		var freq := f0 * pow(f1 / f0, t) if exp_freq else lerpf(f0, f1, t)
		var gain := vol * pow(0.001 / vol, t) if exp_gain else vol * (1.0 - t)
		buffer[i] = _osc(kind, phase) * gain
		phase += TAU * freq / SAMPLE_RATE
	return buffer

# ---------------------------------------------------------------------------
# Settings (JS neonAudioSettings)
# ---------------------------------------------------------------------------

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(maxf(0.001, music_volume))
	_save_settings()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_save_settings()

func toggle_mute() -> bool:
	muted = not muted
	if muted:
		_music_player.stream_paused = true
	else:
		_music_player.stream_paused = false
	_save_settings()
	return muted

func _save_settings() -> void:
	var file := FileAccess.open("user://audio_settings.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({music = music_volume, sfx = sfx_volume, muted = muted}))

func _load_settings() -> void:
	if not FileAccess.file_exists("user://audio_settings.json"):
		return
	var file := FileAccess.open("user://audio_settings.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text()) if file else null
	if data is Dictionary:
		music_volume = float(data.get("music", 0.5))
		sfx_volume = float(data.get("sfx", 0.7))
		muted = bool(data.get("muted", false))
