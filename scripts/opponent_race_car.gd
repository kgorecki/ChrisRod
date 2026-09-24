extends CharacterBody3D

const REF_RATIO := 2.80
const PLAYER_REF_ACCEL := 24.0
const _RATIOS := [2.52, 1.52, 1.00]

var forward_speed: float = 0.0
var _base_accel: float = 7.0
var _max_mps: float = 45.0
var _path_s: float = 0.0
var _lane_x: float = 2.5
var _gear: int = 0
var _shift_timer: float = 0.0
var _shift_time: float = 0.35


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	var i: int = clampi(GameState.selected_opponent_id, 0, GameState.OPPONENTS.size() - 1)
	var opp: Dictionary = GameState.OPPONENTS[i]
	var player_vmax_mps: float = GameState.get_effective_vmax_kmh() / 3.6
	var hp_scale: float = GameState.engine_power_hp / 280.0
	_base_accel = PLAYER_REF_ACCEL * float(opp.get("accel_scale", 0.30)) * hp_scale
	_max_mps = player_vmax_mps * float(opp.get("vmax_scale", 0.90))
	_shift_time = float(opp.get("shift_time", 0.35))
	_lane_x = global_position.x


func get_path_s() -> float:
	return _path_s


func _physics_process(delta: float) -> void:
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	else:
		var top := _gear_top_mps(_gear)
		if _gear < _RATIOS.size() - 1 and forward_speed >= top * 0.90:
			_gear += 1
			_shift_timer = _shift_time
		else:
			forward_speed += _gear_acceleration() * delta
	forward_speed = minf(forward_speed, _max_mps)

	var track: Node = null
	if race and race.has_method(&"get_race_track"):
		track = race.get_race_track()
	if track != null and track.has_method(&"sample_at"):
		_path_s += forward_speed * delta
		var sample: Dictionary = track.sample_at(_path_s)
		var right: Vector3 = sample.get("right", Vector3.RIGHT)
		var center: Vector3 = sample.get("position", global_position)
		var left_ext := float(sample.get("left_ext", 8.0))
		var right_ext := float(sample.get("right_ext", 8.0))
		var lane := clampf(_lane_x, -(left_ext - 1.6), right_ext - 1.6)
		var dest := center + right * lane
		velocity = Vector3.ZERO
		move_and_slide()
		global_position.x = dest.x
		global_position.z = dest.z
		rotation.y = float(sample.get("yaw", 0.0))
		return

	velocity = Vector3(0.0, velocity.y, forward_speed)
	move_and_slide()


func _gear_top_mps(gear_index: int) -> float:
	var i := clampi(gear_index, 0, _RATIOS.size() - 1)
	var top_ratio: float = _RATIOS[_RATIOS.size() - 1]
	var ratio: float = maxf(_RATIOS[i], 0.01)
	return _max_mps * (top_ratio / ratio)


func _gear_acceleration() -> float:
	var ratio: float = _RATIOS[clampi(_gear, 0, _RATIOS.size() - 1)]
	var top := _gear_top_mps(_gear)
	var headroom := 1.0
	if top > 0.05:
		var progress := clampf(forward_speed / top, 0.0, 1.0)
		if progress >= 1.0:
			return 0.0
		headroom = 1.0 - progress * progress
	return _base_accel * (ratio / REF_RATIO) * headroom
