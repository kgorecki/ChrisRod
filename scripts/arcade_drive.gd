extends RefCounted

## The driving model used before the tire simulation: speed is integrated
## directly, and a bicycle chassis with a yaw cap turns the car.

const ACCELERATION := 24.0
const BRAKING := 40.0
const COAST_FACTOR := 0.985
const REF_GEAR_RATIO := 2.80
const WHEELBASE_M := 2.59
const MAX_STEER_RAD := 0.52
const STEER_RESPONSE := 3.2
const MASS_KG := 1360.0
const CG_HEIGHT_M := 0.48
const GRAVITY := 9.81
const MU_DRY := 1.02
const MU_OFFROAD := 0.48
const FRONT_AXLE_FRACTION := 0.46
const CORNERING_FRONT := 52000.0
const CORNERING_REAR := 64000.0
const GRIP_FADE_SPEED := 2.0
const TRACK_X_LIMIT := 18.0
const OFFROAD_ACCEL_SCALE := 0.42
const OFFROAD_DRAG := 0.993
const OFFROAD_MAX_SPEED_SCALE := 0.5

var forward_speed: float = 0.0
var heading_yaw: float = 0.0
var steer_angle: float = 0.0

var _lateral_speed: float = 0.0
var _yaw_rate: float = 0.0
var _off_road: bool = false
var _wheelbase: float = WHEELBASE_M
var _mass_kg: float = MASS_KG
var _cg_height: float = CG_HEIGHT_M
var _front_axle_fraction: float = FRONT_AXLE_FRACTION
var _max_steer_rad: float = MAX_STEER_RAD
var _wheel_grip: float = 3.0


func apply_spec(chassis: Dictionary, grip_rating: float) -> void:
	if not chassis.is_empty():
		_mass_kg = float(chassis.get("mass", _mass_kg))
		_wheelbase = float(chassis.get("wheelbase", _wheelbase))
		_cg_height = float(chassis.get("cg_height", _cg_height))
		_front_axle_fraction = float(chassis.get("front_axle_fraction", _front_axle_fraction))
		_max_steer_rad = deg_to_rad(float(chassis.get("max_steer_deg", rad_to_deg(_max_steer_rad))))
	_wheel_grip = clampf(grip_rating, 1.0, 5.0)


func reset() -> void:
	forward_speed = 0.0
	steer_angle = 0.0
	_stop_slide()


func _stop_slide() -> void:
	_lateral_speed = 0.0
	_yaw_rate = 0.0


## Gear acceleration is already scaled by ratio, power, and headroom.
func step(
	body: CharacterBody3D,
	delta: float,
	steer: float,
	throttle: bool,
	brake: bool,
	shifting: bool,
	blown: bool,
	gear_accel: float,
	max_mps: float,
	car_center: Vector3
) -> void:
	_update_surface(body)
	var speed_before := forward_speed
	var accel_scale := OFFROAD_ACCEL_SCALE if _off_road else 1.0
	if throttle and not shifting:
		forward_speed += gear_accel * accel_scale * _grip_accel_scale() * delta
	elif brake:
		forward_speed -= BRAKING * delta
	else:
		forward_speed *= pow(COAST_FACTOR, delta * 60.0)
	if blown:
		forward_speed *= pow(0.96, delta * 60.0)
	if _off_road:
		forward_speed *= pow(OFFROAD_DRAG, delta * 60.0)
		forward_speed = minf(forward_speed, max_mps * OFFROAD_MAX_SPEED_SCALE)
	forward_speed = clampf(forward_speed, 0.0, max_mps)

	var longitudinal_accel := (forward_speed - speed_before) / maxf(delta, 0.0001)
	var steer_target := clampf(steer, -1.0, 1.0) * _max_steer_rad * _grip_steer_scale()
	if absf(steer) < 0.01:
		steer_target = 0.0
	steer_angle = move_toward(steer_angle, steer_target, STEER_RESPONSE * delta)
	_step_chassis(delta, longitudinal_accel)
	if absf(steer_angle) < 0.02:
		var straighten := clampf(12.0 * delta, 0.0, 1.0)
		_yaw_rate = lerpf(_yaw_rate, 0.0, straighten)
		_lateral_speed = lerpf(_lateral_speed, 0.0, straighten)
	var yaw_cap := absf(forward_speed * tan(steer_angle) / _wheelbase) * 1.2 * _grip_steer_scale() + 0.08
	_yaw_rate = clampf(_yaw_rate, -yaw_cap, yaw_cap)
	_lateral_speed = clampf(_lateral_speed, -forward_speed * 0.45, forward_speed * 0.45)
	forward_speed = clampf(forward_speed, 0.0, max_mps)
	heading_yaw += _yaw_rate * delta

	var forward_dir := Vector3(sin(heading_yaw), 0.0, cos(heading_yaw))
	var right_dir := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	body.velocity = forward_dir * forward_speed + right_dir * _lateral_speed
	_apply_heading(body, car_center)


func hold(body: CharacterBody3D, delta: float, car_center: Vector3) -> void:
	forward_speed = 0.0
	_stop_slide()
	steer_angle = move_toward(steer_angle, 0.0, STEER_RESPONSE * delta)
	body.velocity = Vector3.ZERO
	_apply_heading(body, car_center)


func _grip_accel_scale() -> float:
	return 1.0 + (_wheel_grip - 3.0) * 0.04


func _grip_steer_scale() -> float:
	return 1.0 + (_wheel_grip - 3.0) * 0.12


func _step_chassis(delta: float, longitudinal_accel: float) -> void:
	var axle_front := _wheelbase * _front_axle_fraction
	var axle_rear := _wheelbase - axle_front
	var mu := MU_OFFROAD if _off_road else MU_DRY
	var weight := _mass_kg * GRAVITY
	var transfer := _mass_kg * longitudinal_accel * _cg_height / _wheelbase
	var fz_front := maxf(weight * axle_rear / _wheelbase - transfer, weight * 0.12)
	var fz_rear := maxf(weight * axle_front / _wheelbase + transfer, weight * 0.12)
	var long_front := 0.0
	var long_rear := _mass_kg * longitudinal_accel
	if longitudinal_accel < 0.0:
		long_front = _mass_kg * longitudinal_accel * 0.65
		long_rear = _mass_kg * longitudinal_accel * 0.35

	var speed := maxf(forward_speed, 0.35)
	var front_slip := atan2(_lateral_speed + _yaw_rate * axle_front, speed) - steer_angle
	var rear_slip := atan2(_lateral_speed - _yaw_rate * axle_rear, speed)
	var steer_grip := _grip_steer_scale()
	var front_force := _tire_force(front_slip, CORNERING_FRONT * steer_grip, fz_front, long_front, mu)
	var rear_force := _tire_force(rear_slip, CORNERING_REAR * steer_grip, fz_rear, long_rear, mu)
	var rolling := clampf(forward_speed / GRIP_FADE_SPEED, 0.0, 1.0)
	front_force *= rolling
	rear_force *= rolling

	var steer_cos := cos(steer_angle)
	var steer_sin := sin(steer_angle)
	var lateral_force := front_force * steer_cos + rear_force
	var yaw_moment := front_force * steer_cos * axle_front - rear_force * axle_rear
	var inertia := _mass_kg * axle_front * axle_rear
	_lateral_speed += (lateral_force / _mass_kg - _yaw_rate * forward_speed) * delta
	_yaw_rate += (yaw_moment / inertia) * delta
	forward_speed += (-front_force * steer_sin / _mass_kg) * delta
	if forward_speed < GRIP_FADE_SPEED:
		var settle := (1.0 - forward_speed / GRIP_FADE_SPEED) * 8.0 * delta
		_lateral_speed = lerpf(_lateral_speed, 0.0, clampf(settle, 0.0, 1.0))
		_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(settle, 0.0, 1.0))


func _tire_force(slip: float, stiffness: float, normal: float, longitudinal: float, mu: float) -> float:
	var limit := mu * normal
	var long_used := clampf(absf(longitudinal) / maxf(limit, 1.0), 0.0, 1.0)
	var lat_limit := limit * sqrt(maxf(0.0, 1.0 - long_used * long_used))
	return clampf(-stiffness * slip, -lat_limit, lat_limit)


func gear_acceleration(ratio: float, gear_top: float, speed: float, power_hp: float) -> float:
	var headroom := 1.0
	if gear_top > 0.05:
		var progress := maxf(speed, 0.0) / gear_top
		if progress >= 1.12:
			return 0.0
		if progress >= 1.0:
			headroom = 0.14
		else:
			headroom = 1.0 - progress * progress
	var hp_scale := power_hp / 280.0
	return ACCELERATION * (ratio / REF_GEAR_RATIO) * hp_scale * headroom


func _update_surface(body: Node3D) -> void:
	var race := body.get_parent()
	if race and race.has_method(&"get_race_track"):
		var track: Node = race.get_race_track()
		if track != null and track.has_method(&"closest_sample"):
			var sample: Dictionary = track.closest_sample(body.global_position)
			var lat := float(sample.get("lateral", 0.0))
			var half := TRACK_X_LIMIT
			if track.has_method(&"get_half_width"):
				half = float(track.get_half_width())
			var left_ext := float(sample.get("left_ext", sample.get("half_width", half)))
			var right_ext := float(sample.get("right_ext", sample.get("half_width", half)))
			_off_road = lat < -(left_ext - 1.0) or lat > (right_ext - 1.0)
			return
	_off_road = absf(body.global_position.x) > TRACK_X_LIMIT


func _apply_heading(body: CharacterBody3D, car_center: Vector3) -> void:
	var center_world := body.global_transform * car_center
	body.rotation.y = heading_yaw
	var center_now := body.global_transform * car_center
	body.global_position += center_world - center_now
