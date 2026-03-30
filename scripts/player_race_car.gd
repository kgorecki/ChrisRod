extends CharacterBody3D

## Forward speed along world +Z (m/s).
var forward_speed: float = 0.0
## Car heading in radians. 0 means pointing along world +Z.
var heading_yaw: float = 0.0

const ACCELERATION := 24.0
const BRAKING := 40.0
const COAST_FACTOR := 0.985

const TURN_RATE_RAD := 1.85

## Half the ground width (m) minus a small margin so the car stays on the strip.
const TRACK_X_LIMIT := 18.0
func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING


func get_forward_speed() -> float:
	return forward_speed


func _steer_input() -> float:
	var s := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		s += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		s -= 1.0
	return clampf(s, -1.0, 1.0)


func _physics_process(delta: float) -> void:
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		rotation.y = heading_yaw
		return

	var max_mps: float = GameState.vmax_kmh / 3.6
	var throttle := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var brake := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var steer := _steer_input()

	if throttle:
		forward_speed += ACCELERATION * delta
	elif brake:
		forward_speed -= BRAKING * delta
	else:
		forward_speed *= pow(COAST_FACTOR, delta * 60.0)

	forward_speed = clampf(forward_speed, 0.0, max_mps)
	heading_yaw += steer * TURN_RATE_RAD * delta

	var forward_dir := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	velocity = forward_dir * forward_speed
	move_and_slide()

	var px := global_position.x
	var px_clamped := clampf(px, -TRACK_X_LIMIT, TRACK_X_LIMIT)
	if not is_equal_approx(px, px_clamped):
		forward_speed *= 0.96
	global_position.x = px_clamped

	rotation.y = heading_yaw
