extends Node
## Audio buses, stream cache, one-shots, crossfaded music and looping ambiences.

const LOOPS := ["amb_wind", "amb_forest", "amb_rain", "train_rumble", "steam_hiss", "furnace_fire",
	"music_menu", "music_travel", "music_stop", "music_danger"]

var _cache := {}
var _music := []            # two AudioStreamPlayers used for crossfades
var _music_idx := 0
var current_music := ""
var _amb := {}              # name -> AudioStreamPlayer
var _amb_tweens := {}
var _lowpass: AudioEffectLowPassFilter
var _duck := 0.0            # ambience duck in dB (negative)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lowpass)
	AudioServer.set_bus_effect_enabled(0, 0, false)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55; rev.damping = 0.6; rev.wet = 0.12; rev.dry = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), rev)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music.append(p)
	Settings.changed.connect(apply_volumes)
	apply_volumes()

func apply_volumes() -> void:
	_set_bus("Master", Settings.v["master"])
	_set_bus("Music", Settings.v["music"])
	_set_bus("SFX", Settings.v["sfx"])
	_set_bus("Ambience", Settings.v["ambience"])

func _set_bus(bus: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)) + (_duck if bus == "Ambience" else 0.0))
	AudioServer.set_bus_mute(i, lin <= 0.001)

func stream(n: String) -> AudioStream:
	if _cache.has(n):
		return _cache[n]
	var s: AudioStream = null
	for ext: String in [".ogg", ".wav"]:
		var path := "res://audio/" + n + ext
		if ResourceLoader.exists(path):
			s = load(path)
			break
	if s != null and n in LOOPS:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = int(w.get_length() * w.mix_rate)
	_cache[n] = s
	return s

## Picks a random numbered variant, e.g. "step_grass" -> step_grass_1..4.
func variant(base: String, count: int) -> String:
	return "%s_%d" % [base, randi_range(1, count)]

func play(n: String, vol_db := 0.0, pitch := 1.0, bus := "SFX") -> AudioStreamPlayer:
	var s := stream(n)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = bus
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p

func play_at(n: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, max_dist := 80.0, parent: Node = null) -> AudioStreamPlayer3D:
	var s := stream(n)
	if s == null:
		return null
	var host: Node = parent if parent != null else get_tree().current_scene
	if host == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.bus = "SFX"
	p.attenuation_filter_cutoff_hz = 6000.0
	host.add_child(p)
	if parent != null:
		p.position = pos
	else:
		p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	return p

## Creates a persistent looping 3D emitter (caller owns it).
func loop_3d(n: String, parent: Node, pos := Vector3.ZERO, max_dist := 60.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(n)
	p.max_distance = max_dist
	p.unit_size = 5.0
	p.bus = "SFX"
	p.volume_db = -80.0
	p.position = pos
	parent.add_child(p)
	if p.stream != null:
		p.play()
	return p

func music(n: String, fade := 3.0, vol_db := 0.0) -> void:
	if n == current_music:
		return
	current_music = n
	var old: AudioStreamPlayer = _music[_music_idx]
	_music_idx = 1 - _music_idx
	var nu: AudioStreamPlayer = _music[_music_idx]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -80.0, fade).set_trans(Tween.TRANS_SINE)
	if n != "":
		var s := stream(n)
		if s != null:
			nu.stream = s
			nu.volume_db = -60.0
			nu.play()
			tw.tween_property(nu, "volume_db", vol_db, fade).set_trans(Tween.TRANS_SINE)

func stop_music(fade := 2.0) -> void:
	music("", fade)

func ambience(n: String, vol_db: float, fade := 2.0) -> void:
	var p: AudioStreamPlayer = _amb.get(n)
	if p == null:
		var s := stream(n)
		if s == null:
			return
		p = AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Ambience"
		p.volume_db = -60.0
		add_child(p)
		p.play()
		_amb[n] = p
	if _amb_tweens.has(n) and _amb_tweens[n].is_valid():
		_amb_tweens[n].kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", vol_db, fade)
	_amb_tweens[n] = tw

func stop_all_ambience(fade := 1.5) -> void:
	for n in _amb.keys():
		ambience(n, -80.0, fade)

## Ducks the ambience bus (the "woods go silent" cue).
func duck_ambience(db: float, fade := 1.0) -> void:
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void:
		_duck = x
		apply_volumes(), _duck, db, fade)

func muffle(on: bool, cutoff := 500.0) -> void:
	_lowpass.cutoff_hz = cutoff
	AudioServer.set_bus_effect_enabled(0, 0, on)

func set_muffle_cutoff(hz: float) -> void:
	_lowpass.cutoff_hz = hz
