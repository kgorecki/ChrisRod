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

const CAM_FAR := 0
const CAM_CLOSE := 1
const CAM_COCKPIT := 2
const CAM_BUMPER := 3

@onready var _cam: Camera3D = $RaceCamera
var _cam_mode: int = CAM_FAR
var _touch: Node = null

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	_apply_camera_mode()
	var race := get_parent()
	if race != null:
		_touch = race.get_node_or_null("RaceUI/MobileControls")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_cam_mode = (_cam_mode + 1) % 4
		_apply_camera_mode()
		get_viewport().set_input_as_handled()


func _apply_camera_mode() -> void:
	if _cam == null:
		return
	match _cam_mode:
		CAM_FAR:
			_cam.position = Vector3(0.0, 2.2, -8.5)
			_cam.rotation_degrees = Vector3(-14.0, 180.0, 0.0)
			_cam.fov = 68.0
		CAM_CLOSE:
			_cam.position = Vector3(0.0, 1.45, -4.2)
			_cam.rotation_degrees = Vector3(-10.0, 180.0, 0.0)
			_cam.fov = 70.0
		CAM_COCKPIT:
			_cam.position = Vector3(0.42, 0.88, 1.52)
			_cam.rotation_degrees = Vector3(-2.0, 180.0, 0.0)
			_cam.fov = 72.0
		CAM_BUMPER:
			_cam.position = Vector3(0.0, 0.16, 4.85)
			_cam.rotation_degrees = Vector3(-1.0, 180.0, 0.0)
			_cam.fov = 72.0
	_cam.current = true


func get_forward_speed() -> float:
	return forward_speed


func _steer_input() -> float:
	var s := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		s += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		s -= 1.0
	if _touch != null and _touch.has_method(&"get_steer"):
		var touch_steer: float = _touch.get_steer()
		if not is_zero_approx(touch_steer):
			s = touch_steer
	return clampf(s, -1.0, 1.0)


func _throttle_down() -> bool:
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		return true
	return _touch != null and _touch.has_method(&"is_throttle_down") and _touch.is_throttle_down()


func _brake_down() -> bool:
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		return true
	return _touch != null and _touch.has_method(&"is_brake_down") and _touch.is_brake_down()


func _physics_process(delta: float) -> void:
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		rotation.y = heading_yaw
		return

	var max_mps: float = GameState.vmax_kmh / 3.6
	var throttle := _throttle_down()
	var brake := _brake_down()
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

	_keep_on_track()
	rotation.y = heading_yaw


func _keep_on_track() -> void:
	var race := get_parent()
	if race and race.has_method(&"get_race_track"):
		var track: Node = race.get_race_track()
		if track != null and track.has_method(&"closest_sample"):
			var sample: Dictionary = track.closest_sample(global_position)
			var limit: float = float(track.get_half_width()) - 2.0
			var lateral: float = float(sample.get("lateral", 0.0))
			var clamped := clampf(lateral, -limit, limit)
			if not is_equal_approx(lateral, clamped):
				var right: Vector3 = sample.get("right", Vector3.RIGHT)
				var center: Vector3 = sample.get("position", global_position)
				global_position.x = center.x + right.x * clamped
				global_position.z = center.z + right.z * clamped
				forward_speed *= 0.96
			return
	var px := global_position.x
	var px_clamped := clampf(px, -TRACK_X_LIMIT, TRACK_X_LIMIT)
	if not is_equal_approx(px, px_clamped):
		forward_speed *= 0.96
	global_position.x = px_clamped
