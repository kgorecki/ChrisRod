extends AudioStreamPlayer

const MIX_RATE := 22050.0
const BUFFER_S := 0.12

var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0
var _rumble_phase: float = 0.0
var _rpm: float = 600.0
var _throttle: float = 0.0
var _blown: bool = false
var _shifting: bool = false
var _amp: float = 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_S
	stream = gen
	volume_db = -6.0
	bus = "Master"
	_start_playback()


func set_state(rpm: float, throttle: float, blown: bool, shifting: bool = false) -> void:
	_rpm = rpm
	_throttle = clampf(throttle, 0.0, 1.0)
	_blown = blown
	_shifting = shifting
	if blown:
		_amp = 0.0
		if playing:
			stop()
		return
	_start_playback()


func _start_playback() -> void:
	if playing:
		if _playback == null:
			_playback = get_stream_playback()
		return
	play()
	_playback = get_stream_playback()


func _process(_delta: float) -> void:
	if _blown:
		return
	_fill_buffer()


func _fill_buffer() -> void:
	if _playback == null:
		_playback = get_stream_playback()
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return

	var target_amp := 0.07 + 0.20 * _throttle
	if _shifting:
		target_amp *= 0.35
	_amp = lerpf(_amp, target_amp, 0.08)

	# V8 4-stroke: four exhaust pulses per revolution.
	var fire_hz := maxf(_rpm, 500.0) / 15.0
	var rumble_hz := fire_hz * 0.5
	var roughness := clampf((_rpm - 600.0) / 5900.0, 0.0, 1.0)

	for _i in frames:
		_phase += fire_hz / MIX_RATE
		if _phase >= 1.0:
			_phase -= floorf(_phase)
		_rumble_phase += rumble_hz / MIX_RATE
		if _rumble_phase >= 1.0:
			_rumble_phase -= floorf(_rumble_phase)

		var pulse := 1.0 - _phase
		pulse *= pulse
		var h2 := sin(_phase * TAU * 2.0) * 0.22
		var h3 := sin(_phase * TAU * 3.0) * 0.10
		var rumble := sin(_rumble_phase * TAU) * 0.16
		var noise := (randf() * 2.0 - 1.0) * (0.06 + 0.14 * _throttle * roughness)
		var sample := (pulse * 0.62 + h2 + h3 + rumble + noise) * _amp
		_playback.push_frame(Vector2(sample, sample))
