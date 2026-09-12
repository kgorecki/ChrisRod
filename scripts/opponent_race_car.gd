extends CharacterBody3D

var forward_speed: float = 0.0
var _accel: float = 12.0
var _max_mps: float = 58.0
var _path_s: float = 0.0
var _lane_x: float = 2.5


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	var i: int = clampi(GameState.selected_opponent_id, 0, GameState.OPPONENTS.size() - 1)
	var opp: Dictionary = GameState.OPPONENTS[i]
	_accel = float(opp.get("accel", 12.0))
	_max_mps = float(opp.get("vmax", 58.0))
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

	forward_speed += _accel * delta
	forward_speed = min(forward_speed, _max_mps)

	var track: Node = null
	if race and race.has_method(&"get_race_track"):
		track = race.get_race_track()
	if track != null and track.has_method(&"sample_at"):
		_path_s += forward_speed * delta
		var sample: Dictionary = track.sample_at(_path_s)
		var right: Vector3 = sample.get("right", Vector3.RIGHT)
		var center: Vector3 = sample.get("position", global_position)
		var dest := center + right * _lane_x
		velocity = Vector3.ZERO
		move_and_slide()
		global_position.x = dest.x
		global_position.z = dest.z
		rotation.y = float(sample.get("yaw", 0.0))
		return

	velocity = Vector3(0.0, velocity.y, forward_speed)
	move_and_slide()
