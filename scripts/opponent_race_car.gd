extends CharacterBody3D

var forward_speed: float = 0.0
var _accel: float = 12.0
var _max_mps: float = 58.0


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	var i: int = clampi(GameState.selected_opponent_id, 0, GameState.OPPONENTS.size() - 1)
	var opp: Dictionary = GameState.OPPONENTS[i]
	_accel = float(opp.get("accel", 12.0))
	_max_mps = float(opp.get("vmax", 58.0))


func _physics_process(delta: float) -> void:
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		return

	forward_speed += _accel * delta
	forward_speed = min(forward_speed, _max_mps)
	velocity = Vector3(0.0, velocity.y, forward_speed)
	move_and_slide()
