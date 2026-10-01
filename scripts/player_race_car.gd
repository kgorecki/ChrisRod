extends CharacterBody3D

## Speed along the car's nose (m/s).
var forward_speed: float = 0.0
## Car heading in radians. 0 means pointing along world +Z.
var heading_yaw: float = 0.0

const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")
const _SkidMarks := preload("res://scripts/skid_marks.gd")
const _ArcadeDrive := preload("res://scripts/arcade_drive.gd")

const RPM_IDLE_MIN := 500.0
const RPM_IDLE := 600.0 ## C1 idle sits between 500 and 700.
const RPM_SHIFT_START := 5500.0
const RPM_REDLINE := 6500.0
const RPM_CRITICAL := 6700.0
const RPM_METER_MAX := 7000.0
const OVERREV_HOLD_S := 0.55

const CAM_FAR := 0
const CAM_CLOSE := 1
const CAM_COCKPIT := 2
const CAM_BUMPER := 3

@export var debug_dynamics: bool = false

@onready var _cam: Camera3D = $RaceCamera
@onready var _engine_sound: Node = $EngineSound
@onready var _visual: Node3D = $CarPivot
var _cam_mode: int = CAM_FAR
var _dynamics: _VehicleDynamics = _VehicleDynamics.new()
var _arcade: _ArcadeDrive = _ArcadeDrive.new()
var _skids: _SkidMarks
var _car_center := Vector3(0.0, 0.0, 1.9)
var _debug_view: MeshInstance3D
var _debug_labels: Array[Label3D] = []
var _touch: Node = null
var _gearbox: Dictionary = {}
var _gear: int = 0
var _shift_timer: float = 0.0
var _overrev_time: float = 0.0
var _engine_blown: bool = false
var _arcade_active: bool = false

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	# Layer 2 is cars. Keep the road mask and also collide with other cars.
	collision_mask = collision_mask | collision_layer
	_apply_car_spec()
	_cache_axles()
	_layout_wheels()
	_dynamics.yaw = rotation.y
	heading_yaw = rotation.y
	_skids = _SkidMarks.new()
	_skids.name = "SkidMarks"
	add_child(_skids)
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


func planar_velocity() -> Vector3:
	if GameState.arcade_drive:
		return _arcade.planar_velocity()
	return _dynamics.cg_velocity


## Moves this car out of another car and keeps the bumped speed. No damage.
func apply_car_bump(offset: Vector3, new_velocity: Vector3) -> void:
	global_position += offset
	var planar := Vector3(new_velocity.x, 0.0, new_velocity.z)
	if GameState.arcade_drive:
		_arcade.apply_planar_velocity(self, planar, _car_center)
		forward_speed = _arcade.forward_speed
		heading_yaw = _arcade.heading_yaw
	else:
		_dynamics.cg_velocity = planar
		velocity = planar
		_sync_motion_state()


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


func _apply_car_spec() -> void:
	var chassis: Dictionary = {}
	var spec: Variant = GameState.car_spec.get("chassis", {})
	if typeof(spec) == TYPE_DICTIONARY:
		chassis = spec
	var wheel: Dictionary = GameState.get_equipped_wheel()
	var grip_rating := clampf(float(wheel.get("grip", 3.0)), 1.0, 5.0)
	_dynamics.apply_setup(chassis, grip_rating)
	_arcade.apply_spec(chassis, grip_rating)


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
		_dynamics.layout_about(Vector3(_car_center.x, 0.0, _car_center.z))


func _sync_motion_state() -> void:
	forward_speed = _dynamics.longitudinal_speed()
	heading_yaw = _dynamics.yaw


func _hold_still() -> void:
	_sync_motion_state()
	_dynamics.pose_body(self, false)
	move_and_slide()
	_skids.end_strips()


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
	if GameState.arcade_drive:
		_physics_arcade(delta)
	else:
		_physics_simulation(delta)


func _physics_simulation(delta: float) -> void:
	if _arcade_active:
		_dynamics.reset_all_motion()
		_dynamics.yaw = heading_yaw
		_dynamics.cg_velocity = Vector3(sin(heading_yaw), 0.0, cos(heading_yaw)) * maxf(forward_speed, 0.0)
		_arcade_active = false
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		_dynamics.reset_all_motion()
		_hold_still()
		_update_engine_sound(false)
		_update_debug_draw()
		return

	var throttle := _throttle_down()
	var brake := _brake_down()
	var steer := _steer_input()
	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	if _engine_blown:
		throttle = false
	elif _is_automatic():
		_auto_shift(throttle, brake)

	var track := _race_track()
	if _escape_obstacle(track):
		_dynamics.reset_motion()
		_dynamics.update_steering(delta, 0.0)
		_hold_still()
		_update_overrev(delta)
		_update_engine_sound(throttle)
		_update_debug_draw()
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

	_update_overrev(delta)
	_update_engine_sound(throttle)
	_update_debug_draw()


func _physics_arcade(delta: float) -> void:
	if not _arcade_active:
		_arcade.forward_speed = maxf(forward_speed, 0.0)
		_arcade.heading_yaw = heading_yaw
		_arcade_active = true
	var race := get_parent()
	if race and race.has_method(&"is_race_started") and not race.is_race_started():
		_arcade.hold(self, delta, _car_center)
		move_and_slide()
		forward_speed = 0.0
		heading_yaw = _arcade.heading_yaw
		_skids.end_strips()
		_update_engine_sound(false)
		return

	var throttle := _throttle_down()
	var brake := _brake_down()
	var steer := _steer_input()
	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
	if _engine_blown:
		throttle = false
	elif _is_automatic():
		_auto_shift(throttle, brake)

	if _escape_obstacle(_race_track()):
		_arcade.hold(self, delta, _car_center)
		move_and_slide()
		forward_speed = 0.0
		heading_yaw = _arcade.heading_yaw
		_skids.end_strips()
		_update_overrev(delta)
		_update_engine_sound(throttle)
		return

	var ratios := _ratios()
	var ratio := float(ratios[clampi(_gear, 0, ratios.size() - 1)])
	_arcade.step(
		self,
		delta,
		steer,
		throttle,
		brake,
		_shift_timer > 0.0,
		_engine_blown,
		_arcade.gear_acceleration(ratio, _gear_top_mps(_gear), forward_speed, GameState.engine_power_hp),
		GameState.get_effective_vmax_kmh() / 3.6,
		_car_center
	)
	move_and_slide()
	if _slide_hit_obstacle():
		_arcade.reset()
		velocity = Vector3.ZERO
	forward_speed = _arcade.forward_speed
	heading_yaw = _arcade.heading_yaw
	_skids.end_strips()
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


## Gear and horsepower scale the configured propulsion force. The tires still
## have to be able to push that hard.
func _requested_drive_force() -> float:
	var ratios := _ratios()
	var ratio := float(ratios[clampi(_gear, 0, ratios.size() - 1)])
	return _dynamics.drive_force(ratio, _gear_top_mps(_gear), forward_speed, GameState.engine_power_hp)


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


func _race_track() -> Node:
	var race := get_parent()
	if race != null and race.has_method(&"get_race_track"):
		return race.get_race_track()
	return null


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


func _update_debug_draw() -> void:
	if not debug_dynamics:
		if _debug_view != null:
			_debug_view.visible = false
		for label in _debug_labels:
			label.visible = false
		return
	_ensure_debug_view()
	_debug_view.visible = true
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_view.material_override)
	var cg := _dynamics.cg_local
	_debug_cross(mesh, cg, 0.35, Color(1.0, 0.85, 0.2))
	var v_body := _dynamics.body_velocity()
	var v_scale: float = _dynamics.config.debug_velocity_scale
	_debug_line(mesh, cg, cg + Vector3(v_body.x, 0.0, v_body.z) * v_scale, Color(0.3, 0.85, 1.0))
	var accel_scale := 0.12
	var long_a := _dynamics.longitudinal_accel()
	var lat_a := _dynamics.lateral_accel()
	_debug_line(mesh, cg, cg + Vector3(0.0, 0.15, long_a * accel_scale), Color(1.0, 0.55, 0.15))
	_debug_line(mesh, cg, cg + Vector3(lat_a * accel_scale, 0.15, 0.0), Color(0.85, 0.35, 1.0))
	var f_scale: float = _dynamics.config.debug_force_scale
	var weight := maxf(_dynamics.config.mass_kg * _dynamics.config.gravity, 1.0)
	var wheels := _dynamics.wheels()
	for i in wheels.size():
		var wheel: _VehicleDynamics.Wheel = wheels[i]
		var contact := Vector3(wheel.local_position.x, 0.0, wheel.local_position.z)
		var contact_color := Color(0.9, 0.9, 0.9).lerp(Color(0.45, 0.75, 0.3), wheel.surface_blend)
		_debug_cross(mesh, contact, 0.18, contact_color)
		var load_height := wheel.normal_load / weight * 1.6
		_debug_line(mesh, contact, contact + Vector3(0.0, load_height, 0.0), Color(0.95, 0.9, 0.4))
		var ahead := Vector3(sin(wheel.steer_angle), 0.0, cos(wheel.steer_angle))
		var right := Vector3(cos(wheel.steer_angle), 0.0, -sin(wheel.steer_angle))
		_debug_line(mesh, contact, contact + ahead * 0.7, Color(0.3, 0.9, 0.4))
		_debug_line(mesh, contact, contact + ahead * clampf(wheel.long_slip, -2.5, 2.5) * 0.45, Color(0.95, 0.75, 0.2))
		_debug_line(mesh, contact, contact + right * wheel.slip_angle * 1.4, Color(0.4, 0.75, 1.0))
		var used := clampf(wheel.grip_utilization, 0.0, 1.0)
		_debug_line(mesh, contact, contact + wheel.force_body * f_scale, Color(used, 1.0 - used, 0.15))
		if i + 1 < _debug_labels.size():
			var label := _debug_labels[i + 1]
			label.visible = true
			label.position = contact + Vector3(0.0, load_height + 0.35, 0.0)
			var surface := wheel.surface_name
			if wheel.surface_blend > 0.02 and wheel.surface_blend < 0.98:
				surface = "%s %.0f%%" % [wheel.surface_name, wheel.surface_blend * 100.0]
			label.text = "%s\n%.0f N\nuse %.0f%%\nlat %.0f deg\nlong %.2f" % [
				surface,
				wheel.normal_load,
				wheel.grip_utilization * 100.0,
				rad_to_deg(wheel.slip_angle),
				wheel.long_slip,
			]
	mesh.surface_end()
	_debug_view.mesh = mesh
	var summary := _debug_labels[0]
	summary.visible = true
	summary.position = cg + Vector3(0.0, 0.85, 0.0)
	summary.text = "%.0f km/h\nlong a %.1f\nlat a %.1f" % [
		v_body.z * 3.6,
		long_a,
		lat_a,
	]


func _ensure_debug_view() -> void:
	if _debug_view == null:
		_debug_view = MeshInstance3D.new()
		_debug_view.name = "DynamicsDebug"
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_debug_view.material_override = mat
		_debug_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_view)
	if _debug_labels.size() == 5:
		return
	for _i in 5:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 0.002
		label.outline_size = 6
		label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_child(label)
		_debug_labels.append(label)


func _debug_line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)


func _debug_cross(mesh: ImmediateMesh, center: Vector3, size: float, color: Color) -> void:
	_debug_line(mesh, center - Vector3(size, 0.0, 0.0), center + Vector3(size, 0.0, 0.0), color)
	_debug_line(mesh, center - Vector3(0.0, size, 0.0), center + Vector3(0.0, size, 0.0), color)
	_debug_line(mesh, center - Vector3(0.0, 0.0, size), center + Vector3(0.0, 0.0, size), color)
