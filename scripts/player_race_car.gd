extends CharacterBody3D

## Speed along the car's nose (m/s).
var forward_speed: float = 0.0
## Car heading in radians. 0 means pointing along world +Z.
var heading_yaw: float = 0.0

const ACCELERATION := 24.0
const BRAKING := 40.0
const COAST_FACTOR := 0.985
const REF_GEAR_RATIO := 2.80
const RPM_IDLE_MIN := 500.0
const RPM_IDLE := 600.0 ## C1 idle sits between 500 and 700.
const RPM_SHIFT_START := 5500.0
const RPM_REDLINE := 6500.0
const RPM_CRITICAL := 6700.0
const RPM_METER_MAX := 7000.0
const OVERREV_HOLD_S := 0.55

const WHEELBASE_M := 2.59
const MAX_STEER_RAD := 0.52 ## ~30° lock.
const STEER_RESPONSE := 3.2 ## Steering-rack speed, rad/s.
const MASS_KG := 1360.0
const CG_HEIGHT_M := 0.48
const GRAVITY := 9.81
const MU_DRY := 1.02
const MU_OFFROAD := 0.48
## Front-engine C1: nose is heavier, so the CG sits just ahead of the wheelbase midpoint.
const FRONT_AXLE_FRACTION := 0.46
const CORNERING_FRONT := 52000.0 ## N/rad, both front tires.
const CORNERING_REAR := 64000.0
const GRIP_FADE_SPEED := 2.0 ## Tires need to be rolling before they bite.

## Half the drag-strip width (m). Past this counts as off-road.
const TRACK_X_LIMIT := 18.0
const OFFROAD_ACCEL_SCALE := 0.42
const OFFROAD_DRAG := 0.993
const OFFROAD_MAX_SPEED_SCALE := 0.5

const CAM_FAR := 0
const CAM_CLOSE := 1
const CAM_COCKPIT := 2
const CAM_BUMPER := 3

@onready var _cam: Camera3D = $RaceCamera
@onready var _engine_sound: Node = $EngineSound
@onready var _visual: Node3D = $CarPivot
var _cam_mode: int = CAM_FAR
var _steer_angle: float = 0.0
var _lateral_speed: float = 0.0 ## m/s toward car +X.
var _yaw_rate: float = 0.0
var _car_center := Vector3(0.0, 0.0, 1.9)
var _wheelbase: float = WHEELBASE_M
var _touch: Node = null
var _gearbox: Dictionary = {}
var _gear: int = 0
var _shift_timer: float = 0.0
var _overrev_time: float = 0.0
var _engine_blown: bool = false
var _off_road: bool = false

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	_cache_axles()
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
	return clampf(rpm, RPM_IDLE_MIN, RPM_METER_MAX)


func get_rpm_shift_start() -> float:
	return RPM_SHIFT_START


func get_rpm_redline() -> float:
	return RPM_REDLINE


func get_rpm_critical() -> float:
	return RPM_CRITICAL


func _cache_axles() -> void:
	if _visual == null:
		return
	_car_center = _visual.position
	var rear_wheel := _visual.get_node_or_null("WheelBackLeft") as Node3D
	var front_wheel := _visual.get_node_or_null("WheelFrontLeft") as Node3D
	if rear_wheel != null and front_wheel != null:
		_wheelbase = maxf(front_wheel.position.z - rear_wheel.position.z, 0.5)


func _target_steer(steer: float) -> float:
	return clampf(steer, -1.0, 1.0) * MAX_STEER_RAD


## Front tires push the nose; rear tires resist the slide. Grip saturates, so a fast car washes out instead of pivoting.
func _step_chassis(delta: float, longitudinal_accel: float) -> void:
	var axle_front := _wheelbase * FRONT_AXLE_FRACTION
	var axle_rear := _wheelbase - axle_front
	var mu := MU_OFFROAD if _off_road else MU_DRY
	var weight := MASS_KG * GRAVITY
	var transfer := MASS_KG * longitudinal_accel * CG_HEIGHT_M / _wheelbase
	var fz_front := maxf(weight * axle_rear / _wheelbase - transfer, weight * 0.12)
	var fz_rear := maxf(weight * axle_front / _wheelbase + transfer, weight * 0.12)
	var long_front := 0.0
	var long_rear := MASS_KG * longitudinal_accel
	if longitudinal_accel < 0.0:
		long_front = MASS_KG * longitudinal_accel * 0.65
		long_rear = MASS_KG * longitudinal_accel * 0.35

	var speed := maxf(forward_speed, 0.35)
	var front_slip := atan2(_lateral_speed + _yaw_rate * axle_front, speed) - _steer_angle
	var rear_slip := atan2(_lateral_speed - _yaw_rate * axle_rear, speed)
	var front_force := _tire_force(front_slip, CORNERING_FRONT, fz_front, long_front, mu)
	var rear_force := _tire_force(rear_slip, CORNERING_REAR, fz_rear, long_rear, mu)
	var rolling := clampf(forward_speed / GRIP_FADE_SPEED, 0.0, 1.0)
	front_force *= rolling
	rear_force *= rolling

	var steer_cos := cos(_steer_angle)
	var steer_sin := sin(_steer_angle)
	var lateral_force := front_force * steer_cos + rear_force
	var yaw_moment := front_force * steer_cos * axle_front - rear_force * axle_rear
	var inertia := MASS_KG * axle_front * axle_rear
	_lateral_speed += (lateral_force / MASS_KG - _yaw_rate * forward_speed) * delta
	_yaw_rate += (yaw_moment / inertia) * delta
	forward_speed += (-front_force * steer_sin / MASS_KG) * delta
	if forward_speed < GRIP_FADE_SPEED:
		var settle := (1.0 - forward_speed / GRIP_FADE_SPEED) * 8.0 * delta
		_lateral_speed = lerpf(_lateral_speed, 0.0, clampf(settle, 0.0, 1.0))
		_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(settle, 0.0, 1.0))


func _tire_force(slip: float, stiffness: float, normal: float, longitudinal: float, mu: float) -> float:
	var limit := mu * normal
	var long_used := clampf(absf(longitudinal) / maxf(limit, 1.0), 0.0, 1.0)
	var lat_limit := limit * sqrt(maxf(0.0, 1.0 - long_used * long_used))
	return clampf(-stiffness * slip, -lat_limit, lat_limit)


func _stop_slide() -> void:
	_lateral_speed = 0.0
	_yaw_rate = 0.0


## Yaw about the car mesh. The body origin sits back by the camera, so rotating it in place orbits the car around the view.
func _apply_heading() -> void:
	var center_world := global_transform * _car_center
	rotation.y = heading_yaw
	var center_now := global_transform * _car_center
	global_position += center_world - center_now


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
		_stop_slide()
		velocity = Vector3.ZERO
		move_and_slide()
		_steer_angle = 0.0
		_apply_heading()
		_update_engine_sound(false)
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

	_update_surface()
	var blocked := _resolve_track_obstacles()
	if blocked:
		forward_speed = 0.0
		_stop_slide()
		velocity = Vector3.ZERO
		move_and_slide()
		_steer_angle = move_toward(_steer_angle, 0.0, STEER_RESPONSE * delta)
		_apply_heading()
		_update_overrev(delta)
		_update_engine_sound(throttle)
		return
	var speed_before := forward_speed
	var accel_scale := OFFROAD_ACCEL_SCALE if _off_road else 1.0
	if throttle and _shift_timer <= 0.0:
		forward_speed += _gear_acceleration() * accel_scale * delta
	elif brake:
		forward_speed -= BRAKING * delta
	else:
		forward_speed *= pow(COAST_FACTOR, delta * 60.0)
	if _engine_blown:
		forward_speed *= pow(0.96, delta * 60.0)
	if _off_road:
		forward_speed *= pow(OFFROAD_DRAG, delta * 60.0)
		forward_speed = minf(forward_speed, max_mps * OFFROAD_MAX_SPEED_SCALE)

	forward_speed = clampf(forward_speed, 0.0, max_mps)
	var longitudinal_accel := (forward_speed - speed_before) / maxf(delta, 0.0001)
	var steer_target := _target_steer(steer)
	if absf(steer) < 0.01:
		steer_target = 0.0
	_steer_angle = move_toward(_steer_angle, steer_target, STEER_RESPONSE * delta)
	_step_chassis(delta, longitudinal_accel)
	if absf(_steer_angle) < 0.02:
		var straighten := clampf(12.0 * delta, 0.0, 1.0)
		_yaw_rate = lerpf(_yaw_rate, 0.0, straighten)
		_lateral_speed = lerpf(_lateral_speed, 0.0, straighten)
	var yaw_cap := absf(forward_speed * tan(_steer_angle) / _wheelbase) * 1.2 + 0.08
	_yaw_rate = clampf(_yaw_rate, -yaw_cap, yaw_cap)
	_lateral_speed = clampf(_lateral_speed, -forward_speed * 0.45, forward_speed * 0.45)
	forward_speed = clampf(forward_speed, 0.0, max_mps)
	heading_yaw += _yaw_rate * delta

	var forward_dir := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	var right_dir := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	velocity = forward_dir * forward_speed + right_dir * _lateral_speed
	move_and_slide()
	if _slide_hit_obstacle():
		forward_speed = 0.0
		_stop_slide()
		velocity = Vector3.ZERO

	_apply_heading()
	_update_overrev(delta)
	_update_engine_sound(throttle)


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


func _update_engine_sound(throttle: bool) -> void:
	if _engine_sound == null or not _engine_sound.has_method(&"set_state"):
		return
	_engine_sound.set_state(get_rpm(), 1.0 if throttle else 0.0, _engine_blown, _shift_timer > 0.0)


func _poll_touch_shifts() -> void:
	if _is_automatic() or _touch == null:
		return
	if _touch.has_method(&"pop_shift_up") and _touch.pop_shift_up():
		_request_shift(1)
	if _touch.has_method(&"pop_shift_down") and _touch.pop_shift_down():
		_request_shift(-1)


func _update_surface() -> void:
	var race := get_parent()
	if race and race.has_method(&"get_race_track"):
		var track: Node = race.get_race_track()
		if track != null and track.has_method(&"closest_sample"):
			var sample: Dictionary = track.closest_sample(global_position)
			var lat := float(sample.get("lateral", 0.0))
			var left_ext := float(sample.get("left_ext", sample.get("half_width", track.get_half_width())))
			var right_ext := float(sample.get("right_ext", sample.get("half_width", track.get_half_width())))
			_off_road = lat < -(left_ext - 1.0) or lat > (right_ext - 1.0)
			return
	_off_road = absf(global_position.x) > TRACK_X_LIMIT


func _resolve_track_obstacles() -> bool:
	var race := get_parent()
	if race == null or not race.has_method(&"get_race_track"):
		return false
	var track: Node = race.get_race_track()
	if track == null or not track.has_method(&"closest_sample"):
		return false
	var sample: Dictionary = track.closest_sample(global_position)
	var lat := float(sample.get("lateral", 0.0))
	var left_ext := float(sample.get("left_ext", 0.0))
	var right_ext := float(sample.get("right_ext", 0.0))
	var center: Vector3 = sample.get("position", global_position)
	var right_v: Vector3 = sample.get("right", Vector3.RIGHT)
	const EDGE := 0.7
	var hit := false
	var safe := global_position
	if bool(sample.get("obstacle_left", false)) and lat < -left_ext and lat > -(left_ext + EDGE):
		hit = true
		safe = center - right_v * maxf(left_ext - 0.5, 0.4)
	elif bool(sample.get("obstacle_right", false)) and lat > right_ext and lat < right_ext + EDGE:
		hit = true
		safe = center + right_v * maxf(right_ext - 0.5, 0.4)
	if hit:
		global_position.x = safe.x
		global_position.z = safe.z
	return hit


func _slide_hit_obstacle() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node and (collider as Node).has_meta(&"track_obstacle"):
			return true
	return false
