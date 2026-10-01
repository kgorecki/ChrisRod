extends RefCounted

## Planar rigid-body vehicle. Steering sets the front wheel angle. Tires make
## forces. Forces make yaw torque. Torque changes yaw rate, and yaw rate turns
## the car. Nothing steers the body toward a target heading.
##
## Asphalt and grass, four wheels, rear-wheel drive, one grip value. Normal
## load moves with acceleration, but there is no suspension. Grass is a strong
## deterrent: less grip, less drive, and a speed-dependent drag.

class SurfaceProfile:
	var grip_multiplier: float = 1.0
	var rolling_resistance: float = 0.015
	var drive_multiplier: float = 1.0
	## Extra scale on the steered wheel angle. Grip already cuts cornering force.
	var steer_multiplier: float = 1.0
	## Per wheel. Force magnitude is this times speed squared, opposing the contact velocity.
	var speed_resistance: float = 0.0


class Config:
	var mass_kg: float = 1360.0
	var gravity: float = 9.81
	var wheelbase_m: float = 2.59
	var track_width_m: float = 1.55
	## Height of the mass center above the tire contact plane. This is the lever
	## for longitudinal and lateral load transfer.
	var cg_height_m: float = 0.48
	## Fraction of the wheelbase from the mass center forward to the front axle.
	## Below 0.5 puts more static weight on the front axle.
	var front_axle_fraction: float = 0.46
	## 0 uses mass * cg_to_front * cg_to_rear once the wheels are placed.
	var yaw_inertia_override_kgm2: float = 0.0

	## Low-speed lock. At speed the rack stops at the angle for steer_full_lateral_accel.
	var max_steer_rad: float = 0.52
	## Steady lateral acceleration a full steering input asks for, in m/s².
	## The road-wheel angle is atan(this * wheelbase / speed²), never past max_steer_rad.
	var steer_full_lateral_accel: float = 9.0
	## How fast the steering input is chased, in 1/seconds.
	var steer_input_response: float = 8.0
	## 1 is linear. Higher values keep a short press near center; holding still reaches full lock.
	var steer_input_curve: float = 1.8
	## Maximum steering-rack speed.
	var steer_rate_rad_s: float = 2.4

	## Friction coefficient at grip_reference_rating. Force limit is grip * normal load.
	var grip_mu: float = 1.05
	var grip_reference_rating: float = 3.0
	var grip_mu_per_rating: float = 0.12
	## Lateral slip where a pure cornering tire is entering saturation.
	## Force there is about 80% of the grip limit. Twice that slip is near the
	## limit, and further slip adds very little.
	var slip_angle_full_grip_rad: float = 0.11
	## Higher values stay linear longer, then flatten. 2 is a gentle circle.
	var slip_curve_order: float = 3.0
	## Added to forward speed in the slip angle so a stopped wheel does not
	## treat a tiny lateral velocity as a right angle.
	var slip_speed_regularization_mps: float = 1.5
	## Smooths the sign of brake and rolling forces around zero speed.
	var longitudinal_smoothing_mps: float = 0.4
	## How quickly normal load follows acceleration. Keeps transfer continuous.
	var load_transfer_response_s: float = 0.06

	## Propulsion force at reference_gear_ratio, before the tire limit.
	## The player scales this by the current gear and horsepower.
	var drive_force_n: float = 7800.0
	var reference_gear_ratio: float = 2.80
	var reference_power_hp: float = 280.0
	## Total brake request shared across all four wheels, before the tire limit.
	## Above the car's total grip, so a hard stop can use up the friction circle.
	var brake_force_n: float = 16000.0
	## Share of brake_force_n applied by the front axle.
	var brake_front_fraction: float = 0.62
	## How fast the throttle and brake requests are chased, in 1/seconds.
	var throttle_response: float = 10.0
	## Width of the asphalt-to-grass blend at the road edge.
	var edge_blend_m: float = 2.2
	var air_density: float = 1.225
	## Cd * frontal area. Drag force is 0.5 * air_density * drag_area_m2 * speed^2.
	var drag_area_m2: float = 0.20

	var debug_force_scale: float = 0.0003
	var debug_velocity_scale: float = 0.12

	var asphalt := SurfaceProfile.new()
	var grass := SurfaceProfile.new()


class Wheel:
	var local_position: Vector3 = Vector3.ZERO
	var offset: Vector3 = Vector3.ZERO
	var steer_angle: float = 0.0
	var driven: bool = false
	var front: bool = false
	var grip: float = 1.05
	var static_load: float = 0.0
	var normal_load: float = 0.0
	var forward_velocity: float = 0.0
	var lateral_velocity: float = 0.0
	var slip_angle: float = 0.0
	## Drive/brake demand divided by the current grip limit. Past 1, more
	## demand adds almost no longitudinal force. There is no wheel spin model.
	var long_slip: float = 0.0
	var long_force: float = 0.0
	var lat_force: float = 0.0
	## Magnitude of the tire force divided by grip * normal load.
	var grip_utilization: float = 0.0
	var force_body: Vector3 = Vector3.ZERO
	## 0 is asphalt, 1 is fully on grass.
	var surface_blend: float = 0.0
	var surface_name: String = "asphalt"


var config := Config.new()
var cg_local: Vector3 = Vector3.ZERO
var cg_velocity: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var yaw_rate: float = 0.0
var yaw_inertia: float = 2000.0

var _wheels: Array[Wheel] = []
var _steer_input: float = 0.0
var _steer_angle: float = 0.0
var _tire_grip: float = 1.05
var _long_accel: float = 0.0
var _lat_accel: float = 0.0
var _wheelbase: float = 2.59
var _front_track: float = 1.55
var _rear_track: float = 1.55
var _static_front_axle: float = 0.0
var _static_rear_axle: float = 0.0
var _drive_filtered: float = 0.0
var _brake_filtered: float = 0.0


func _init() -> void:
	var grass := config.grass
	## Weaker than asphalt, still enough lateral force to steer back to the road.
	grass.grip_multiplier = 0.62
	grass.rolling_resistance = 0.04
	grass.drive_multiplier = 0.30
	grass.steer_multiplier = 0.90
	grass.speed_resistance = 1.0


func apply_setup(chassis: Dictionary, grip_rating: float) -> void:
	if not chassis.is_empty():
		config.mass_kg = float(chassis.get("mass", config.mass_kg))
		config.wheelbase_m = float(chassis.get("wheelbase", config.wheelbase_m))
		config.cg_height_m = float(chassis.get("cg_height", config.cg_height_m))
		config.front_axle_fraction = float(chassis.get("front_axle_fraction", config.front_axle_fraction))
		var steer_deg := float(chassis.get("max_steer_deg", rad_to_deg(config.max_steer_rad)))
		config.max_steer_rad = deg_to_rad(steer_deg)
	var rating := grip_rating - config.grip_reference_rating
	_tire_grip = maxf(config.grip_mu + rating * config.grip_mu_per_rating, 0.2)
	_apply_grip_to_wheels()
	if _wheels.size() == 4:
		_distribute_weight()


func set_wheel_positions(local_positions: Array) -> void:
	if local_positions.size() != 4:
		return
	var pts: Array[Vector3] = []
	for point in local_positions:
		pts.append(point as Vector3)
	var front_z := (pts[0].z + pts[1].z) * 0.5
	var rear_z := (pts[2].z + pts[3].z) * 0.5
	var span := front_z - rear_z
	if absf(span) < 0.2:
		span = config.wheelbase_m if span >= 0.0 else -config.wheelbase_m
	var cg_x := 0.0
	for point in pts:
		cg_x += point.x
	cg_x /= float(pts.size())
	var cg_z := front_z - config.front_axle_fraction * span
	cg_local = Vector3(cg_x, config.cg_height_m, cg_z)
	_wheels.clear()
	for i in pts.size():
		var wheel := Wheel.new()
		wheel.local_position = pts[i]
		wheel.offset = Vector3(pts[i].x - cg_local.x, 0.0, pts[i].z - cg_local.z)
		wheel.front = i < 2
		wheel.driven = i >= 2
		wheel.grip = _tire_grip
		_wheels.append(wheel)
	_distribute_weight()
	_update_inertia()


func layout_about(body_center: Vector3) -> void:
	var reach := config.wheelbase_m * config.front_axle_fraction
	var tail := config.wheelbase_m - reach
	var half := config.track_width_m * 0.5
	cg_local = Vector3(body_center.x, config.cg_height_m, body_center.z)
	var pts: Array[Vector3] = [
		cg_local + Vector3(-half, 0.0, reach),
		cg_local + Vector3(half, 0.0, reach),
		cg_local + Vector3(-half, 0.0, -tail),
		cg_local + Vector3(half, 0.0, -tail),
	]
	set_wheel_positions(pts)


func wheels() -> Array[Wheel]:
	return _wheels


func steer_angle() -> float:
	return _steer_angle


## Peak acceleration the asphalt tires allow on a flat road, in m/s².
func grip_accel() -> float:
	return _tire_grip * config.asphalt.grip_multiplier * config.gravity


func longitudinal_speed() -> float:
	return (_basis().inverse() * cg_velocity).z


func lateral_speed() -> float:
	return (_basis().inverse() * cg_velocity).x


func body_velocity() -> Vector3:
	return _basis().inverse() * cg_velocity


func longitudinal_accel() -> float:
	return _long_accel


func lateral_accel() -> float:
	return _lat_accel


func reset_motion() -> void:
	cg_velocity = Vector3.ZERO
	yaw_rate = 0.0
	_long_accel = 0.0
	_lat_accel = 0.0
	_drive_filtered = 0.0
	_brake_filtered = 0.0
	_restore_static_loads()


func reset_all_motion() -> void:
	reset_motion()
	_steer_input = 0.0
	_steer_angle = 0.0
	for wheel in _wheels:
		wheel.steer_angle = 0.0
		wheel.force_body = Vector3.ZERO
		wheel.slip_angle = 0.0
		wheel.long_slip = 0.0
		wheel.long_force = 0.0
		wheel.lat_force = 0.0
		wheel.grip_utilization = 0.0
		wheel.forward_velocity = 0.0
		wheel.lateral_velocity = 0.0


func update_steering(dt: float, steer_input: float) -> void:
	_apply_steering(dt, steer_input)


## 0 on the asphalt side of the road edge, 1 once `edge_blend_m` into the grass.
func grass_amount(lateral: float, left_extent: float, right_extent: float) -> float:
	var outside := 0.0
	if lateral < -left_extent:
		outside = -left_extent - lateral
	elif lateral > right_extent:
		outside = lateral - right_extent
	var edge := maxf(config.edge_blend_m, 0.05)
	return smoothstep(0.0, edge, outside)


## Samples the road under each wheel. With no track every wheel is on asphalt.
func sample_surfaces(track: Object, body: Transform3D) -> void:
	var blends: Array[float] = []
	for wheel in _wheels:
		var amount := 0.0
		if track != null and track.has_method(&"closest_sample"):
			var sample: Dictionary = track.closest_sample(body * wheel.local_position)
			amount = grass_amount(
				float(sample.get("lateral", 0.0)),
				float(sample.get("left_ext", 0.0)),
				float(sample.get("right_ext", 0.0))
			)
		blends.append(amount)
	set_surface_blends(blends)


## Propulsion request for one gear. Force falls toward the top of the gear and
## ends a little past it. The tires still decide how much of it reaches the road.
func drive_force(gear_ratio: float, gear_top_mps: float, speed: float, power_hp: float) -> float:
	var headroom := 1.0
	if gear_top_mps > 0.05:
		var progress := maxf(speed, 0.0) / gear_top_mps
		if progress >= 1.12:
			return 0.0
		if progress >= 1.0:
			headroom = 0.14
		else:
			headroom = 1.0 - progress * progress
	var power_scale := power_hp / maxf(config.reference_power_hp, 1.0)
	var ratio_scale := gear_ratio / maxf(config.reference_gear_ratio, 0.01)
	return config.drive_force_n * ratio_scale * power_scale * headroom


## Turns the body to the integrated heading about the mass center, then hands
## the mass-center velocity to the character body.
func pose_body(body: CharacterBody3D, moving: bool) -> void:
	var cg_world := body.global_transform * cg_local
	body.rotation.y = yaw
	var cg_now := body.global_transform * cg_local
	body.global_position += cg_world - cg_now
	body.velocity = cg_velocity if moving else Vector3.ZERO


func set_surface_blends(blends: Array) -> void:
	for i in _wheels.size():
		var blend := 0.0
		if i < blends.size():
			blend = clampf(float(blends[i]), 0.0, 1.0)
		var wheel := _wheels[i]
		wheel.surface_blend = blend
		wheel.surface_name = "grass" if blend > 0.5 else "asphalt"


## One fixed physics step. drive_force_n is the total rear propulsion request.
## brake_input is 0..1. Neither is applied by rewriting velocity.
func step(dt: float, steer_input: float, drive_force_n: float, brake_input: float) -> void:
	if dt <= 0.0 or _wheels.is_empty() or config.mass_kg <= 0.0 or yaw_inertia <= 0.0:
		return
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var slices := 1
	if dt > tick * 1.5:
		slices = clampi(int(ceil(dt / tick)), 1, 4)
	var slice := dt / float(slices)
	var drive_target := maxf(drive_force_n, 0.0)
	var brake_target := clampf(brake_input, 0.0, 1.0)
	for _i in slices:
		_chase_pedals(slice, drive_target, brake_target)
		_integrate(slice, steer_input, _drive_filtered, _brake_filtered)


func _integrate(dt: float, steer_input: float, drive_force_n: float, brake_input: float) -> void:
	_apply_steering(dt, steer_input)
	var basis := _basis()
	var drive_each := 0.0
	var driven := 0
	for wheel in _wheels:
		if wheel.driven:
			driven += 1
	if driven > 0:
		drive_each = maxf(drive_force_n, 0.0) / float(driven)

	var force_body := Vector3.ZERO
	var torque := 0.0
	for wheel in _wheels:
		var tire := _tire_force(wheel, basis, drive_each, brake_input)
		force_body += tire
		# Yaw component of r × F. Positive yaw swings the nose toward body +X.
		torque += wheel.offset.z * tire.x - wheel.offset.x * tire.z
	force_body += _aero_force_body(basis)

	cg_velocity += basis * force_body * (dt / config.mass_kg)
	cg_velocity.y = 0.0
	yaw_rate += torque / yaw_inertia * dt
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	_long_accel = force_body.z / config.mass_kg
	_lat_accel = force_body.x / config.mass_kg
	_update_load_transfer(dt)


func _apply_steering(dt: float, steer_input: float) -> void:
	var target_input := clampf(steer_input, -1.0, 1.0)
	var blend := 1.0 - exp(-config.steer_input_response * dt)
	_steer_input = lerpf(_steer_input, target_input, blend)
	var target_angle := _shaped_steer(_steer_input) * _steer_angle_limit()
	_steer_angle = move_toward(_steer_angle, target_angle, config.steer_rate_rad_s * dt)
	var front_blend := 0.0
	var front_count := 0
	for wheel in _wheels:
		if wheel.front:
			front_blend += wheel.surface_blend
			front_count += 1
	if front_count > 0:
		front_blend /= float(front_count)
	var steer_scale := _blended(front_blend, config.asphalt.steer_multiplier, config.grass.steer_multiplier)
	for wheel in _wheels:
		wheel.steer_angle = _steer_angle * steer_scale if wheel.front else 0.0


## Ground speed, so a slide does not open the rack just because the nose is no longer pointing along the velocity.
func _steer_angle_limit() -> float:
	var speed := Vector2(cg_velocity.x, cg_velocity.z).length()
	var cap := config.max_steer_rad
	if speed < 1.0:
		return cap
	var ay := maxf(config.steer_full_lateral_accel, 0.5)
	var wheelbase := maxf(_wheelbase, 0.5)
	return minf(cap, atan(ay * wheelbase / (speed * speed)))


func _shaped_steer(amount: float) -> float:
	var curve := maxf(config.steer_input_curve, 1.0)
	return signf(amount) * pow(absf(amount), curve)


func _tire_force(wheel: Wheel, basis: Basis, drive_each: float, brake_input: float) -> Vector3:
	var omega := Vector3(0.0, yaw_rate, 0.0)
	var contact_world: Vector3 = cg_velocity + omega.cross(basis * wheel.offset)
	var contact_body := basis.inverse() * contact_world
	var fwd := Vector3(sin(wheel.steer_angle), 0.0, cos(wheel.steer_angle))
	var right := Vector3(cos(wheel.steer_angle), 0.0, -sin(wheel.steer_angle))
	var v_long := contact_body.dot(fwd)
	var v_lat := contact_body.dot(right)
	wheel.forward_velocity = v_long
	wheel.lateral_velocity = v_lat

	var reg := maxf(config.slip_speed_regularization_mps, 0.05)
	var slip := atan2(v_lat, absf(v_long) + reg)
	wheel.slip_angle = slip

	var blend := wheel.surface_blend
	var mu := _tire_grip * _blended(blend, config.asphalt.grip_multiplier, config.grass.grip_multiplier)
	wheel.grip = mu
	var limit := mu * wheel.normal_load
	var axle_share := config.brake_front_fraction if wheel.front else (1.0 - config.brake_front_fraction)
	var brake_n := brake_input * config.brake_force_n * axle_share * 0.5
	var along := _smooth_sign(v_long)
	var rolling := _blended(blend, config.asphalt.rolling_resistance, config.grass.rolling_resistance)
	var long_request := -brake_n * along
	long_request -= rolling * wheel.normal_load * along
	if wheel.driven:
		var drive_scale := _blended(blend, config.asphalt.drive_multiplier, config.grass.drive_multiplier)
		long_request += drive_each * drive_scale
	if limit <= 1.0:
		wheel.long_slip = 0.0
		wheel.long_force = 0.0
		wheel.lat_force = 0.0
		wheel.grip_utilization = 0.0
		var unloaded := _surface_drag(blend, contact_body)
		wheel.force_body = unloaded
		return unloaded

	var slip_scale := maxf(config.slip_angle_full_grip_rad, 0.01)
	var s_long := long_request / limit
	var s_lat := slip / slip_scale
	wheel.long_slip = s_long
	var combined := _combined_slip_force(s_long, s_lat, limit)
	wheel.long_force = combined.x
	wheel.lat_force = combined.y
	wheel.grip_utilization = combined.length() / limit
	var force := fwd * combined.x + right * combined.y
	force += _surface_drag(blend, contact_body)
	wheel.force_body = force
	return force


func _surface_drag(blend: float, contact_body: Vector3) -> Vector3:
	var resist := _blended(blend, config.asphalt.speed_resistance, config.grass.speed_resistance)
	if resist <= 0.0:
		return Vector3.ZERO
	var planar := Vector2(contact_body.x, contact_body.z)
	var speed := planar.length()
	return Vector3(-contact_body.x, 0.0, -contact_body.z) * resist * speed


func _chase_pedals(dt: float, drive_target: float, brake_target: float) -> void:
	var blend := 1.0 - exp(-config.throttle_response * dt)
	_drive_filtered = lerpf(_drive_filtered, drive_target, blend)
	_brake_filtered = lerpf(_brake_filtered, brake_target, blend)


func _blended(blend: float, asphalt_value: float, grass_value: float) -> float:
	return lerpf(asphalt_value, grass_value, clampf(blend, 0.0, 1.0))


## One smooth curve for both axes. Small slip is nearly linear. Large slip
## sits on the friction circle and extra slip barely increases the force.
## The mix of s_long and s_lat is the direction on that circle.
func _combined_slip_force(s_long: float, s_lat: float, limit: float) -> Vector2:
	var slip_mag := sqrt(s_long * s_long + s_lat * s_lat)
	if slip_mag <= 0.00001:
		return Vector2.ZERO
	var order := maxf(config.slip_curve_order, 2.0)
	var used := slip_mag / pow(1.0 + pow(slip_mag, order), 1.0 / order)
	var scale := limit * used / slip_mag
	return Vector2(s_long * scale, -s_lat * scale)


func _aero_force_body(basis: Basis) -> Vector3:
	var v_body := basis.inverse() * cg_velocity
	var planar := Vector2(v_body.x, v_body.z)
	var speed := planar.length()
	var coeff := 0.5 * config.air_density * config.drag_area_m2 * speed
	return Vector3(-coeff * v_body.x, 0.0, -coeff * v_body.z)


func _smooth_sign(speed: float) -> float:
	var eps := maxf(config.longitudinal_smoothing_mps, 0.05)
	return speed / sqrt(speed * speed + eps * eps)


func _distribute_weight() -> void:
	if _wheels.size() != 4:
		return
	var front_z := (_wheels[0].offset.z + _wheels[1].offset.z) * 0.5
	var rear_z := (_wheels[2].offset.z + _wheels[3].offset.z) * 0.5
	var span := maxf(absf(front_z - rear_z), 0.01)
	var to_front := absf(front_z)
	var to_rear := absf(rear_z)
	_wheelbase = span
	_front_track = maxf(absf(_wheels[0].offset.x - _wheels[1].offset.x), 0.4)
	_rear_track = maxf(absf(_wheels[2].offset.x - _wheels[3].offset.x), 0.4)
	var weight := config.mass_kg * config.gravity
	var front_each := weight * to_rear / span * 0.5
	var rear_each := weight * to_front / span * 0.5
	_static_front_axle = front_each * 2.0
	_static_rear_axle = rear_each * 2.0
	for wheel in _wheels:
		var static_load := front_each if wheel.front else rear_each
		wheel.static_load = static_load
		wheel.normal_load = static_load
		wheel.grip = _tire_grip


## Steady load shift from the mass center: forward accel loads the rear,
## braking loads the front, and lateral accel loads the outside wheels.
## The result is filtered so the normal force does not jump in one tick.
func _update_load_transfer(dt: float) -> void:
	if _wheels.size() != 4:
		return
	var height := maxf(config.cg_height_m, 0.0)
	var long_shift := config.mass_kg * _long_accel * height / _wheelbase
	var front_axle := maxf(_static_front_axle - long_shift, 0.0)
	var rear_axle := maxf(_static_rear_axle + long_shift, 0.0)
	var weight := maxf(config.mass_kg * config.gravity, 1.0)
	var front_share := _static_front_axle / weight
	var lat_moment := config.mass_kg * _lat_accel * height
	var front_transfer := front_share * lat_moment / _front_track
	var rear_transfer := (1.0 - front_share) * lat_moment / _rear_track
	var response := maxf(config.load_transfer_response_s, 0.01)
	var blend := 1.0 - exp(-dt / response)
	for wheel in _wheels:
		var axle := front_axle if wheel.front else rear_axle
		var transfer := front_transfer if wheel.front else rear_transfer
		# Positive lateral accel points to +X. The left wheel (negative X) takes that load.
		var side := 1.0 if wheel.offset.x <= 0.0 else -1.0
		var target := maxf(axle * 0.5 + side * transfer, 0.0)
		wheel.normal_load = lerpf(wheel.normal_load, target, blend)


func _restore_static_loads() -> void:
	for wheel in _wheels:
		wheel.normal_load = wheel.static_load


func _update_inertia() -> void:
	if config.yaw_inertia_override_kgm2 > 0.0:
		yaw_inertia = config.yaw_inertia_override_kgm2
		return
	if _wheels.size() != 4:
		yaw_inertia = config.mass_kg * config.wheelbase_m * config.wheelbase_m / 12.0
		return
	var to_front := absf((_wheels[0].offset.z + _wheels[1].offset.z) * 0.5)
	var to_rear := absf((_wheels[2].offset.z + _wheels[3].offset.z) * 0.5)
	yaw_inertia = maxf(config.mass_kg * to_front * to_rear, 1.0)


func _apply_grip_to_wheels() -> void:
	for wheel in _wheels:
		wheel.grip = _tire_grip


func _basis() -> Basis:
	return Basis(Vector3.UP, yaw)
