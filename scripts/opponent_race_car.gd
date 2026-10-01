extends CharacterBody3D

## Same planar vehicle as the player. The racing line is only a driver:
## it picks steer, throttle, and brake. The tires still make the motion.

const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")
const _SkidMarks := preload("res://scripts/skid_marks.gd")

## The path-following opponent from before the tire simulation.
const ARCADE_REF_RATIO := 2.80
const ARCADE_REF_ACCEL := 24.0
const ARCADE_RATIOS: Array[float] = [2.52, 1.52, 1.00]

## Opponent preset `accel_scale` that matches the player's drive force.
const PRESET_ACCEL_REF := 0.30
## Share of the tire grip the driver plans to use in corners.
const CORNER_GRIP_USE := 0.5
## Heading error that asks for full steering input.
const STEER_FULL_ERROR_RAD := 0.175
## Steering per meter of drift from the chosen lane.
const STEER_PER_LANE_M := 0.1
## How far ahead, in seconds of travel, the driver reads the road heading.
const STEER_LOOKAHEAD_S := 0.4
## Steering against the current yaw rate, per rad/s.
const STEER_YAW_DAMPING := 0.55
## Body slip speed where the driver stops steering at the line and catches the slide.
const SLIDE_LATERAL_MPS := 4.0
const LANE_EDGE_MARGIN_M := 1.8

var forward_speed: float = 0.0

var _dynamics: _VehicleDynamics = _VehicleDynamics.new()
var _skids: _SkidMarks
var _visual: Node3D
var _gearbox: Dictionary = {}
var _gear: int = 0
var _shift_timer: float = 0.0
var _shift_time: float = 0.35
var _drive_scale: float = 1.0
var _max_mps: float = 40.0
var _lane_x: float = 0.0
var _lane_ready: bool = false
var _path_s: float = 0.0
var _path_yaw: float = 0.0
var _lateral: float = 0.0
var _arcade_active: bool = false
var _arcade_gear: int = 0
var _arcade_shift: float = 0.0
var _arcade_accel: float = 7.0


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	# Layer 2 is cars. Keep the road mask and also collide with other cars.
	collision_mask = collision_mask | collision_layer
	_visual = get_node_or_null("CarPivot") as Node3D
	var i: int = clampi(GameState.selected_opponent_id, 0, GameState.OPPONENTS.size() - 1)
	var opp: Dictionary = GameState.OPPONENTS[i]
	_drive_scale = float(opp.get("accel_scale", PRESET_ACCEL_REF)) / PRESET_ACCEL_REF
	_shift_time = float(opp.get("shift_time", 0.35))
	var player_vmax: float = GameState.get_effective_vmax_kmh() / 3.6
	_max_mps = player_vmax * float(opp.get("vmax_scale", 0.90))
	_arcade_accel = ARCADE_REF_ACCEL * float(opp.get("accel_scale", 0.30)) * (GameState.engine_power_hp / 280.0)
	_lane_x = global_position.x
	_apply_car_spec()
	_layout_wheels()
	_dynamics.yaw = rotation.y
	_skids = _SkidMarks.new()
	_skids.name = "SkidMarks"
	add_child(_skids)
	_gearbox = GameState.get_equipped_gearbox()
	_gear = 0


func get_path_s() -> float:
	return _path_s


func planar_velocity() -> Vector3:
	if GameState.arcade_drive:
		return Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * forward_speed
	return _dynamics.cg_velocity


## Moves this car out of another car and keeps the bumped speed. No damage.
func apply_car_bump(offset: Vector3, new_velocity: Vector3) -> void:
	var planar := Vector3(new_velocity.x, 0.0, new_velocity.z)
	if not GameState.arcade_drive:
		global_position += offset
		_dynamics.cg_velocity = planar
		velocity = planar
		_sync_motion_state()
		return
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var track := _race_track(get_parent())
	if track != null and track.has_method(&"sample_at"):
		var sample: Dictionary = track.sample_at(_path_s)
		var yaw := float(sample.get("yaw", rotation.y))
		forward = Vector3(sin(yaw), 0.0, cos(yaw))
		var right: Vector3 = sample.get("right", Vector3(cos(yaw), 0.0, -sin(yaw)))
		_path_s += offset.dot(forward)
		_lane_x += offset.dot(right)
		_lane_ready = true
	global_position += offset
	forward_speed = clampf(planar.dot(forward), 0.0, _max_mps)


func _physics_process(delta: float) -> void:
	if GameState.arcade_drive:
		_physics_arcade(delta)
	else:
		_physics_simulation(delta)


func _physics_simulation(delta: float) -> void:
	if _arcade_active:
		_dynamics.reset_all_motion()
		_dynamics.yaw = rotation.y
		_dynamics.cg_velocity = Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * maxf(forward_speed, 0.0)
		_arcade_active = false
	var race := get_parent()
	var track := _race_track(race)
	_capture_lane(track)
	_project_progress(track)
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		_dynamics.reset_all_motion()
		_hold_still()
		return

	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	else:
		_auto_shift()

	var steer := 0.0
	var throttle := true
	var brake := false
	if track != null:
		var command := _drive_command(track)
		steer = command.x
		throttle = command.y > 0.5
		brake = command.z > 0.5

	if _escape_obstacle(track):
		_dynamics.reset_motion()
		_dynamics.update_steering(delta, 0.0)
		_hold_still()
		return

	var drive := 0.0
	var brake_input := 0.0
	if throttle and _shift_timer <= 0.0:
		drive = _requested_drive_force()
	elif brake:
		brake_input = 1.0
	_dynamics.sample_surfaces(track, global_transform)
	_dynamics.step(delta, steer, drive, brake_input)
	_sync_motion_state()
	_dynamics.pose_body(self, true)
	move_and_slide()
	if _slide_hit_obstacle():
		_dynamics.reset_motion()
		_sync_motion_state()
		velocity = Vector3.ZERO
		_skids.end_strips()
	else:
		_skids.record(_dynamics.wheels(), global_transform)


func _physics_arcade(delta: float) -> void:
	if not _arcade_active:
		_arcade_gear = 0
		_arcade_shift = 0.0
		_arcade_active = true
	var race := get_parent()
	var track := _race_track(race)
	_capture_lane(track)
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		forward_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _arcade_shift > 0.0:
		_arcade_shift = maxf(0.0, _arcade_shift - delta)
	else:
		var top := _arcade_gear_top(_arcade_gear)
		if _arcade_gear < ARCADE_RATIOS.size() - 1 and forward_speed >= top * 0.90:
			_arcade_gear += 1
			_arcade_shift = _shift_time
		else:
			forward_speed += _arcade_gear_accel() * delta
	forward_speed = minf(forward_speed, _max_mps)
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


func _arcade_gear_top(gear_index: int) -> float:
	var i := clampi(gear_index, 0, ARCADE_RATIOS.size() - 1)
	var top_ratio: float = ARCADE_RATIOS[ARCADE_RATIOS.size() - 1]
	var ratio: float = maxf(ARCADE_RATIOS[i], 0.01)
	return _max_mps * (top_ratio / ratio)


func _arcade_gear_accel() -> float:
	var ratio: float = ARCADE_RATIOS[clampi(_arcade_gear, 0, ARCADE_RATIOS.size() - 1)]
	var top := _arcade_gear_top(_arcade_gear)
	var headroom := 1.0
	if top > 0.05:
		var progress := clampf(forward_speed / top, 0.0, 1.0)
		if progress >= 1.0:
			return 0.0
		headroom = 1.0 - progress * progress
	return _arcade_accel * (ratio / ARCADE_REF_RATIO) * headroom


func _hold_still() -> void:
	_sync_motion_state()
	_dynamics.pose_body(self, false)
	move_and_slide()
	_skids.end_strips()


func _race_track(race: Node) -> Node:
	if race != null and race.has_method(&"get_race_track"):
		return race.get_race_track()
	return null


func _apply_car_spec() -> void:
	var chassis: Dictionary = {}
	var spec: Variant = GameState.car_spec.get("chassis", {})
	if typeof(spec) == TYPE_DICTIONARY:
		chassis = spec
	var wheel: Dictionary = GameState.get_equipped_wheel()
	var grip_rating := clampf(float(wheel.get("grip", 3.0)), 1.0, 5.0)
	_dynamics.apply_setup(chassis, grip_rating)


func _layout_wheels() -> void:
	var points: Array[Vector3] = []
	if _visual != null:
		for wname in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
			var wheel := _visual.get_node_or_null(wname) as Node3D
			if wheel == null:
				points.clear()
				break
			points.append(to_local(wheel.global_position))
	if points.size() == 4:
		_dynamics.set_wheel_positions(points)
	else:
		var center := Vector3(0.0, 0.0, 1.9)
		if _visual != null:
			center = Vector3(_visual.position.x, 0.0, _visual.position.z)
		_dynamics.layout_about(center)


func _sync_motion_state() -> void:
	forward_speed = _dynamics.longitudinal_speed()


func _capture_lane(track: Node) -> void:
	if _lane_ready or track == null or not track.has_method(&"closest_sample"):
		return
	var sample: Dictionary = track.closest_sample(global_transform * _dynamics.cg_local)
	_lane_x = float(sample.get("lateral", 0.0))
	_lane_ready = true


func _project_progress(track: Node) -> void:
	if track == null or not track.has_method(&"closest_sample"):
		return
	var sample: Dictionary = track.closest_sample(global_transform * _dynamics.cg_local)
	_path_s = float(sample.get("s", _path_s))
	_path_yaw = float(sample.get("yaw", _path_yaw))
	_lateral = float(sample.get("lateral", _lateral))


## x is steering input, y is throttle (0 or 1), z is brake (0 or 1).
func _drive_command(track: Node) -> Vector3:
	var planar := Vector2(_dynamics.cg_velocity.x, _dynamics.cg_velocity.z).length()
	var here: Dictionary = track.sample_at(_path_s)
	var left_ext := float(here.get("left_ext", 8.0))
	var right_ext := float(here.get("right_ext", 8.0))
	var lane := clampf(_lane_x, -(left_ext - LANE_EDGE_MARGIN_M), right_ext - LANE_EDGE_MARGIN_M)
	var ahead_yaw := float(track.sample_at(_path_s + planar * STEER_LOOKAHEAD_S).get("yaw", _path_yaw))
	var err := wrapf(ahead_yaw - _dynamics.yaw, -PI, PI)
	var lat_err := _lateral - lane
	var steer := err / STEER_FULL_ERROR_RAD - lat_err * STEER_PER_LANE_M - _dynamics.yaw_rate * STEER_YAW_DAMPING
	var sliding := absf(_dynamics.lateral_speed()) > SLIDE_LATERAL_MPS and forward_speed > 6.0
	if sliding:
		steer = -_dynamics.yaw_rate * STEER_YAW_DAMPING
	if planar < 4.0:
		steer = err / (STEER_FULL_ERROR_RAD * 4.0)
	steer = clampf(steer, -1.0, 1.0)
	var too_fast := planar - _corner_speed(track, planar)
	var braking := (too_fast > 1.8 and absf(steer) < 0.3) or too_fast > 8.0
	var throttle := not braking and too_fast < 0.6 and absf(err) < 0.7 and not sliding
	if planar < 4.0 and absf(err) < 1.2:
		throttle = true
		braking = false
	return Vector3(steer, 1.0 if throttle else 0.0, 1.0 if braking else 0.0)


## Fastest speed the tightest bend in the braking horizon allows.
func _corner_speed(track: Node, planar: float) -> float:
	var ay := _dynamics.grip_accel() * CORNER_GRIP_USE
	var horizon := clampf(planar * 2.8, 36.0, 110.0)
	var step := 6.0
	var count := maxi(int(horizon / step), 1)
	var prev: float = float(track.sample_at(_path_s).get("yaw", _dynamics.yaw))
	var worst := 0.0
	for i in count:
		var yaw: float = float(track.sample_at(_path_s + step * float(i + 1)).get("yaw", prev))
		worst = maxf(worst, absf(wrapf(yaw - prev, -PI, PI)) / step)
		prev = yaw
	if worst < 0.0015:
		return _max_mps
	return minf(_max_mps, sqrt(ay / worst))


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
	return _max_mps * (top_ratio / ratio)


func _requested_drive_force() -> float:
	var ratios := _ratios()
	var ratio := float(ratios[clampi(_gear, 0, ratios.size() - 1)])
	var force := _dynamics.drive_force(ratio, _gear_top_mps(_gear), forward_speed, GameState.engine_power_hp)
	return force * _drive_scale


func _auto_shift() -> void:
	if _shift_timer > 0.0:
		return
	var top := _gear_top_mps(_gear)
	if _gear < _ratios().size() - 1 and forward_speed >= top * 0.90:
		_gear += 1
		_shift_timer = _shift_time
		return
	if _gear <= 0:
		return
	var prev_top := _gear_top_mps(_gear - 1)
	if forward_speed < prev_top * 0.45:
		_gear -= 1
		_shift_timer = _shift_time


func _escape_obstacle(track: Node) -> bool:
	if track == null or not track.has_method(&"obstacle_escape"):
		return false
	var safe: Vector3 = track.obstacle_escape(global_position)
	if safe.is_equal_approx(global_position):
		return false
	global_position = safe
	return true


func _slide_hit_obstacle() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node and (collider as Node).has_meta(&"track_obstacle"):
			return true
	return false
