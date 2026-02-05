extends Node
class_name ProceduralCarSFX

@export var bus_name: StringName = &"SFX"
@export var sample_rate := 44100
@export var buffer_length_sec := 0.12

var _player: AudioStreamPlayer = null
var _gen: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null

var _phase := 0.0
var _t := 0.0

# engine state
var _engine_on := false
var _engine_rpm := 0.0       # 0..1
var _engine_amp := 0.0       # smoothed
var _engine_target_amp := 0.0

# one-shot envelopes
var _tick_env := 0.0
var _tick_decay := 0.0

var _hit_env := 0.0
var _hit_decay := 0.0

var _noise_seed := 12345

func _ready() -> void:
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = sample_rate
	_gen.buffer_length = buffer_length_sec

	_player = AudioStreamPlayer.new()
	_player.bus = bus_name
	_player.stream = _gen
	add_child(_player)

	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback

func set_engine(on: bool) -> void:
	_engine_on = on
	_engine_target_amp = 0.25 if on else 0.0

func set_rpm01(v: float) -> void:
	_engine_rpm = clampf(v, 0.0, 1.0)

func tick(strength := 1.0) -> void:
	_tick_env = max(_tick_env, 0.45 * clampf(strength, 0.0, 1.0))
	_tick_decay = 18.0

func hit(strength := 1.0) -> void:
	_hit_env = max(_hit_env, 0.85 * clampf(strength, 0.0, 1.0))
	_hit_decay = 9.0

func _process(delta: float) -> void:
	if _playback == null:
		return

	# keep buffer fed
	var frames_needed := _playback.get_frames_available()
	if frames_needed <= 0:
		return

	# smooth engine amp
	var k := 1.0 - pow(0.001, delta) # fast-ish smoothing
	_engine_amp = lerpf(_engine_amp, _engine_target_amp, k)

	var dt := 1.0 / float(sample_rate)

	for i in range(frames_needed):
		_t += dt

		# --- engine: hum + a bit of "combustion" noise ---
		var base_hz := lerpf(45.0, 120.0, _engine_rpm)      # low fundamental
		var buzz_hz := lerpf(90.0, 260.0, _engine_rpm)      # higher harmonic

		_phase += TAU * base_hz * dt
		if _phase > TAU:
			_phase -= TAU

		var hum := sin(_phase) * 0.7 + sin(_phase * (buzz_hz / base_hz)) * 0.3

		var n := _noise() * 0.35
		var engine := (hum * 0.7 + n * 0.3) * _engine_amp

		# --- tick: short noisy burst + tiny pitch pop ---
		if _tick_env > 0.0001:
			_tick_env = maxf(0.0, _tick_env - _tick_decay * dt)
		var tick := (_noise() * 0.8 + sin(_phase * 6.0) * 0.2) * _tick_env

		# --- hit: low thump + noise ---
		if _hit_env > 0.0001:
			_hit_env = maxf(0.0, _hit_env - _hit_decay * dt)
		var thump := sin(_phase * 0.5) * 0.8
		var hit := (thump * 0.6 + _noise() * 0.4) * _hit_env

		# mix
		var s := engine + tick + hit

		# soft clip
		s = tanh(s * 1.6) * 0.6

		_playback.push_frame(Vector2(s, s))

func _noise() -> float:
	# simple deterministic LCG noise in [-1,1]
	_noise_seed = int((_noise_seed * 1103515245 + 12345) & 0x7fffffff)
	return (float(_noise_seed) / 1073741824.0) - 1.0
