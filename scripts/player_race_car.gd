extends CharacterBody3D

## Forward speed along world +Z (m/s).
var forward_speed: float = 0.0
## Car heading in radians. 0 means pointing along world +Z.
var heading_yaw: float = 0.0

const ACCELERATION := 24.0
const BRAKING := 40.0
const COAST_FACTOR := 0.985
const REF_GEAR_RATIO := 2.80
const RPM_IDLE := 800.0
const RPM_SHIFT_START := 5000.0
const RPM_REDLINE := 6200.0
const RPM_CRITICAL := 6800.0
const RPM_METER_MAX := 8000.0
const OVERREV_HOLD_S := 0.55

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
var _gearbox: Dictionary = {}
var _gear: int = 0
var _shift_timer: float = 0.0
var _overrev_time: float = 0.0
var _engine_blown: bool = false

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	_apply_camera_mode()
	_gearbox = GameState.get_equipped_gearbox()
	_gear = 0
	var race := get_parent()
	if race != null:
		_touch = race.get_node_or_null("RaceUI/MobileControls")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			_cam_mode = (_cam_mode + 1) % 4
			_apply_camera_mode()
			get_viewport().set_input_as_handled()
			return
		if not _is_automatic():
			if event.keycode == KEY_E:
				_request_shift(1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_Q:
				_request_shift(-1)
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


func get_gear_label() -> String:
	var count := _gear_count()
	if _is_automatic():
		return "D%d / %d" % [_gear + 1, count]
	return "%d / %d" % [_gear + 1, count]


func is_automatic_gearbox() -> bool:
	return _is_automatic()


func is_engine_blown() -> bool:
	return _engine_blown


func get_rpm() -> float:
	if _engine_blown:
		return 0.0
	var top := _gear_top_mps(_gear)
	if top <= 0.05:
		return RPM_IDLE
	var rpm := RPM_IDLE + (RPM_REDLINE - RPM_IDLE) * (forward_speed / top)
	return clampf(rpm, RPM_IDLE, RPM_METER_MAX)


func get_rpm_shift_start() -> float:
	return RPM_SHIFT_START


func get_rpm_redline() -> float:
	return RPM_REDLINE


func get_rpm_critical() -> float:
	return RPM_CRITICAL


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
	_poll_touch_shifts()
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		rotation.y = heading_yaw
		return

	var max_mps: float = GameState.get_effective_vmax_kmh() / 3.6
	var throttle := _throttle_down()
	var brake := _brake_down()
	var steer := _steer_input()
	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	if _engine_blown:
		throttle = false
	elif _is_automatic():
		_auto_shift(throttle, brake)

	if throttle and _shift_timer <= 0.0:
		forward_speed += _gear_acceleration() * delta
	elif brake:
		forward_speed -= BRAKING * delta
	else:
		forward_speed *= pow(COAST_FACTOR, delta * 60.0)
	if _engine_blown:
		forward_speed *= pow(0.96, delta * 60.0)

	forward_speed = clampf(forward_speed, 0.0, max_mps)
	heading_yaw += steer * TURN_RATE_RAD * delta

	var forward_dir := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	velocity = forward_dir * forward_speed
	move_and_slide()

	_keep_on_track()
	rotation.y = heading_yaw
	_update_overrev(delta)


func _is_automatic() -> bool:
	return bool(_gearbox.get("automatic", false))


func _gear_count() -> int:
	return _ratios().size()


func _ratios() -> Array:
	var ratios: Variant = _gearbox.get("ratios", [1.0])
	if typeof(ratios) != TYPE_ARRAY or ratios.is_empty():
		return [1.0]
	return ratios


func _gear_top_mps(gear_index: int) -> float:
	var ratios := _ratios()
	var i := clampi(gear_index, 0, ratios.size() - 1)
	var top_ratio := float(ratios[ratios.size() - 1])
	var ratio := maxf(float(ratios[i]), 0.01)
	var vmax_mps: float = GameState.get_effective_vmax_kmh() / 3.6
	return vmax_mps * (top_ratio / ratio)


func _gear_acceleration() -> float:
	var ratios := _ratios()
	var ratio := float(ratios[clampi(_gear, 0, ratios.size() - 1)])
	var gear_top := _gear_top_mps(_gear)
	var headroom := 1.0
	if gear_top > 0.05:
		var progress := forward_speed / gear_top
		if progress >= 1.12:
			return 0.0
		if progress >= 1.0:
			headroom = 0.14
		else:
			headroom = 1.0 - progress * progress
	var hp_scale: float = GameState.engine_power_hp / 280.0
	return ACCELERATION * (ratio / REF_GEAR_RATIO) * hp_scale * headroom


func _request_shift(direction: int) -> void:
	if _engine_blown or _shift_timer > 0.0:
		return
	var next := _gear + direction
	if next < 0 or next >= _gear_count():
		return
	_gear = next
	_shift_timer = float(_gearbox.get("shift_time", 0.15))
	_overrev_time = 0.0


func _auto_shift(throttle: bool, brake: bool) -> void:
	if _shift_timer > 0.0:
		return
	var top := _gear_top_mps(_gear)
	if throttle and _gear < _gear_count() - 1 and forward_speed >= top * 0.90:
		_request_shift(1)
		return
	if _gear <= 0:
		return
	var prev_top := _gear_top_mps(_gear - 1)
	if forward_speed < prev_top * 0.38:
		_request_shift(-1)
	elif (brake or not throttle) and forward_speed < prev_top * 0.62:
		_request_shift(-1)


func _update_overrev(delta: float) -> void:
	if _engine_blown or _is_automatic():
		_overrev_time = 0.0
		return
	if get_rpm() >= RPM_CRITICAL:
		_overrev_time += delta
		if _overrev_time >= OVERREV_HOLD_S:
			_engine_blown = true
	else:
		_overrev_time = maxf(0.0, _overrev_time - delta * 2.0)


func _poll_touch_shifts() -> void:
	if _is_automatic() or _touch == null:
		return
	if _touch.has_method(&"pop_shift_up") and _touch.pop_shift_up():
		_request_shift(1)
	if _touch.has_method(&"pop_shift_down") and _touch.pop_shift_down():
		_request_shift(-1)


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
