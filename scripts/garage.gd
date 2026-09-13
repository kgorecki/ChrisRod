extends Node3D

@onready var _car_pivot: Node3D = $CarPivot
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera_pitch: Node3D = $CameraPivot/Pitch
@onready var _camera: Camera3D = $CameraPivot/Pitch/Camera3D

@onready var _clock_menu: Control = $GarageUI/ClockMenu
@onready var _stats_panel: Control = $GarageUI/StatsPanel
@onready var _spray_menu: Control = $GarageUI/ColorPickerMenu
@onready var _spray_color_picker: ColorPicker = $GarageUI/ColorPickerMenu/Panel/Margin/VBox/ColorPicker
@onready var _calendar: StaticBody3D = $InteractCalendar
@onready var _calendar_hint: Label = $GarageUI/CalendarHint

var _orbiting: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.35
var _cam_distance: float = 7.0
var _cam_distance_target: float = 7.0

# Camera zoom limits (mouse wheel + pinch).
const CAM_DISTANCE_DEFAULT := 7.0
const CAM_DISTANCE_MIN := 2.5
const CAM_DISTANCE_MAX := 20.0
const ZOOM_STEP := 0.75
const PINCH_SENSITIVITY := 1.5
# How quickly we interpolate camera distance (higher = snappier).
const ZOOM_SMOOTH_SPEED := 12.0

var _stats_label: Label
var _calendar_home: Transform3D
var _calendar_blend: float = 0.0
var _calendar_inspecting: bool = false
var _calendar_tween: Tween

const _MONTHS := [
	"", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const _WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const _DAYS_IN_MONTH := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	_stats_label = _stats_panel.get_node("Panel/Margin/VBox/StatsText") as Label
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	$InteractClock.set_meta(&"garage_interact", &"clock")
	$InteractDesk/InteractChart.set_meta(&"garage_interact", &"chart")
	$InteractDesk/InteractNewspaper.set_meta(&"garage_interact", &"newspaper")
	$InteractDoors.set_meta(&"garage_interact", &"doors")
	$InteractSprayPistol.set_meta(&"garage_interact", &"spray")
	_calendar.set_meta(&"garage_interact", &"calendar")
	_calendar_home = _calendar.global_transform
	_build_calendar_page()
	_calendar_hint.visible = false
	# Apply stored paint color immediately (it will wait for the STL if needed).
	if _car_pivot.has_method(&"set_car_body_color"):
		_car_pivot.set_car_body_color(GameState.car_color)
	_cam_distance_target = _cam_distance
	_update_camera_transform()

	# Defer so MeshInstance scripts (like the STL loader) have a chance
	# to populate `MeshInstance3D.mesh` before we inspect it.
	call_deferred(&"_debug_car_mesh")
	# Also align wheels to the floor after meshes are ready.
	call_deferred(&"_align_wheels_to_floor")

	# If the CarBody emits a signal when its STL finishes loading, connect to it
	var car_body := _car_pivot.get_node_or_null("CarBody") as MeshInstance3D
	if car_body != null and car_body.has_signal("stl_loaded"):
		car_body.connect("stl_loaded", Callable(self, "_on_carbody_stl_loaded"))


func _on_carbody_stl_loaded(mesh) -> void:
	# When the CarBody's mesh is ready, re-align wheels to the floor.
	_align_wheels_to_floor()


func _align_wheels_to_floor() -> void:
	var floor_mesh_instance := $Floor/MeshInstance3D as MeshInstance3D
	if _car_pivot.has_method(&"align_wheels_to_floor"):
		_car_pivot.align_wheels_to_floor(floor_mesh_instance)

func _process(_delta: float) -> void:
	_camera_pivot.global_position = _car_pivot.global_position

	# Smooth zoom: interpolate distance toward the latest target.
	# (We don't call `_update_camera_transform()` from input handlers so
	# mouse wheel / pinch stays smooth.)
	var delta := _delta
	if absf(_cam_distance - _cam_distance_target) > 0.0001:
		# Exponential smoothing: t = 1 - exp(-k*dt)
		var t := 1.0 - exp(-ZOOM_SMOOTH_SPEED * delta)
		_cam_distance = lerpf(_cam_distance, _cam_distance_target, t)
		_update_camera_transform()
	_update_calendar_transform()


func _debug_car_mesh() -> void:
	# Deterministic debug to see whether the imported car mesh is loaded and
	# where its bounds end up (world vs camera framing issues).
	var car_body := _car_pivot.get_node_or_null("CarBody") as MeshInstance3D
	if car_body == null:
		print("[DEBUG CAR][garage] Missing node `CarPivot/CarBody`.")
		return

	var mesh := car_body.mesh
	var surfaces := 0
	var resource_path := "<null>"
	if mesh != null:
		resource_path = mesh.resource_path
		if mesh.has_method(&"get_surface_count"):
			surfaces = mesh.get_surface_count()

	var aabb := car_body.get_aabb() # local-space bounds
	var center_local := aabb.position + aabb.size * 0.5
	var center_world := car_body.global_transform * center_local

	# Also explicitly try loading the STL resource path.
	# This distinguishes "scene reference failed" vs "import/load failed".
	var stl_path := "res://assets/vette-c1.stl"
	var exists_any := ResourceLoader.exists(stl_path)
	var exists_array_mesh := ResourceLoader.exists(stl_path, &"ArrayMesh")
	var loaded_any := ResourceLoader.load(stl_path)
	var loaded_any_type := "<null>"
	if loaded_any != null:
		loaded_any_type = loaded_any.get_class()

	var exists_mesh := ResourceLoader.exists(stl_path, &"Mesh")
	var loaded_mesh := ResourceLoader.load(stl_path, &"Mesh")
	var loaded_mesh_type := "<null>"
	if loaded_mesh != null:
		loaded_mesh_type = loaded_mesh.get_class()

	var abs_path := ProjectSettings.globalize_path(stl_path)
	var abs_exists := FileAccess.file_exists(abs_path)

	print("[DEBUG CAR][garage] CarBody visible=", car_body.visible, " mesh_null=", mesh == null)
	print("[DEBUG CAR][garage] mesh_resource=", resource_path, " surface_count=", surfaces)
	print("[DEBUG CAR][garage] local_aabb_size=", aabb.size, " local_aabb_pos=", aabb.position)
	print("[DEBUG CAR][garage] global_position=", car_body.global_position, " scale=", car_body.scale)
	print("[DEBUG CAR][garage] center_world=", center_world)
	print("[DEBUG CAR][garage] stl_path_exists(any)=", exists_any, " stl_path_exists(ArrayMesh)=", exists_array_mesh, " loaded_any=", loaded_any != null, " loaded_any_type=", loaded_any_type)
	print("[DEBUG CAR][garage] stl_path_exists(Mesh)=", exists_mesh, " loaded_mesh=", loaded_mesh != null, " loaded_mesh_type=", loaded_mesh_type)
	print("[DEBUG CAR][garage] stl_abs_path=", abs_path, " abs_exists=", abs_exists)


func _unhandled_input(event: InputEvent) -> void:
	if _clock_menu.visible and event.is_action_pressed(&"ui_cancel"):
		_clock_menu.visible = false
		get_viewport().set_input_as_handled()
		return
	if _stats_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_stats_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	if _spray_menu.visible and event.is_action_pressed(&"ui_cancel"):
		_spray_menu.visible = false
		get_viewport().set_input_as_handled()
		return
	if _calendar_inspecting and event.is_action_pressed(&"ui_cancel"):
		_hang_calendar()
		get_viewport().set_input_as_handled()
		return

	if _is_reset_zoom_shortcut(event):
		_cam_distance_target = CAM_DISTANCE_DEFAULT
		get_viewport().set_input_as_handled()
		return

	# Pinch gesture zoom (touch / trackpad).
	if event is InputEventMagnifyGesture:
		if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible:
			return
		var mg := event as InputEventMagnifyGesture
		# `factor` grows when fingers spread (zoom in).
		var denom := 1.0 + (mg.factor * PINCH_SENSITIVITY)
		if absf(denom) < 0.0001:
			return
		_cam_distance_target = clampf(_cam_distance_target / denom, CAM_DISTANCE_MIN, CAM_DISTANCE_MAX)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		# Mouse wheel: use `factor` when available so trackpads behave better.
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor_any: Variant = mb.get(&"factor") # May be missing depending on platform/version.
			var raw_factor: float = 1.0
			if typeof(factor_any) == TYPE_FLOAT or typeof(factor_any) == TYPE_INT:
				raw_factor = float(factor_any)
			var factor := absf(raw_factor)
			if factor < 0.0001:
				factor = 1.0

			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			# Some platforms encode scroll direction in `factor`; if the sign disagrees,
			# flip the direction so zoom in/out is consistent.
			if raw_factor < 0.0:
				dir *= -1.0
			_cam_distance_target = clampf(
				_cam_distance_target + dir * ZOOM_STEP * factor,
				CAM_DISTANCE_MIN,
				CAM_DISTANCE_MAX
			)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible:
				return
			if _calendar_inspecting:
				_hang_calendar()
				get_viewport().set_input_as_handled()
				return
			_try_interact(mb.position)

	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, 0.1, 1.2)
		_update_camera_transform()
		get_viewport().set_input_as_handled()


func _is_reset_zoom_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.keycode != KEY_0 and key.keycode != KEY_KP_0:
		return false
	if OS.get_name() == "macOS":
		return key.meta_pressed and not key.ctrl_pressed
	return key.ctrl_pressed and not key.meta_pressed


func _update_camera_transform() -> void:
	_camera_pivot.rotation = Vector3.ZERO
	_camera_pivot.rotate_y(_yaw)
	_camera_pitch.rotation = Vector3.ZERO
	_camera_pitch.rotate_object_local(Vector3.RIGHT, -_pitch)
	_camera.position = Vector3(0.0, 0.6, _cam_distance)
	_camera.look_at(Vector3(0, 0.4, 0), Vector3.UP)


func _try_interact(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider == null:
		return
	var node := collider as Node
	if node == null:
		return
	# Godot may return the collider node itself (e.g. `CollisionShape3D`) instead of its parent
	# `StaticBody3D`. Walk up the tree until we find the interaction metadata.
	while node != null:
		if node.has_meta(&"garage_interact"):
			_handle_interact(node.get_meta(&"garage_interact"))
			return
		node = node.get_parent()


func _raycast(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _handle_interact(kind: Variant) -> void:
	match kind:
		&"clock":
			_clock_menu.visible = true
		&"chart":
			_show_stats()
		&"newspaper":
			get_tree().change_scene_to_file(GameState.SCENE_NEWSPAPER)
		&"doors":
			get_tree().change_scene_to_file(GameState.SCENE_OPPONENT_SELECT)
		&"spray":
			_show_spray_picker()
		&"calendar":
			_bring_calendar_forward()


func _show_spray_picker() -> void:
	# Hide other garage overlays so clicks go to the picker.
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_color_picker.color = GameState.car_color
	_spray_menu.visible = true


func _on_spray_confirm_pressed() -> void:
	GameState.car_color = _spray_color_picker.color
	# Update the preview immediately.
	if _car_pivot.has_method(&"set_car_body_color"):
		_car_pivot.set_car_body_color(GameState.car_color)
	_spray_menu.visible = false


func _on_spray_cancel_pressed() -> void:
	_spray_menu.visible = false


func _show_stats() -> void:
	var box: Dictionary = GameState.get_equipped_gearbox()
	var gears: Variant = box.get("ratios", [])
	var gear_count := 0
	if typeof(gears) == TYPE_ARRAY:
		gear_count = gears.size()
	var kind := "automatic" if bool(box.get("automatic", false)) else "manual"
	var t := "Car: %s\n\nVmax: %.0f km/h\nEngine power: %.0f hp\nGearbox: %s\n%s, %d gears" % [
		GameState.car_name,
		GameState.get_effective_vmax_kmh(),
		GameState.engine_power_hp,
		str(box.get("name", "—")),
		kind,
		gear_count,
	]
	_stats_label.text = t
	_stats_panel.visible = true


func _on_clock_save_pressed() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	if GameState.save_game():
		pass
	_clock_menu.visible = false


func _on_clock_load_pressed() -> void:
	if GameState.load_game():
		GameState.go_to_saved_scene(get_tree())
	_clock_menu.visible = false


func _on_clock_quit_menu_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)
	_clock_menu.visible = false


func _on_clock_close_pressed() -> void:
	_clock_menu.visible = false


func _on_stats_close_pressed() -> void:
	_stats_panel.visible = false


func _bring_calendar_forward() -> void:
	if _calendar_inspecting:
		return
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	_calendar_home = _calendar.global_transform
	_calendar_inspecting = true
	_calendar_hint.visible = true
	if _calendar_tween != null:
		_calendar_tween.kill()
	_calendar_tween = create_tween()
	_calendar_tween.tween_property(self, "_calendar_blend", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hang_calendar() -> void:
	if not _calendar_inspecting:
		return
	_calendar_inspecting = false
	_calendar_hint.visible = false
	if _calendar_tween != null:
		_calendar_tween.kill()
	_calendar_tween = create_tween()
	_calendar_tween.tween_property(self, "_calendar_blend", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _update_calendar_transform() -> void:
	if _calendar_blend <= 0.0001:
		if not _calendar_inspecting:
			_calendar.global_transform = _calendar_home
		return
	_calendar.global_transform = _calendar_home.interpolate_with(_calendar_inspect_transform(), _calendar_blend)


func _calendar_inspect_transform() -> Transform3D:
	var cam_xf := _camera.global_transform
	var pos := cam_xf.origin - cam_xf.basis.z * 1.2
	return Transform3D.IDENTITY.translated(pos).looking_at(cam_xf.origin, Vector3.UP)


func _build_calendar_page() -> void:
	var host := _calendar.get_node("Labels") as Node3D
	for child in host.get_children():
		child.queue_free()
	var now := Time.get_datetime_dict_from_system()
	var year := int(now.get("year", 2026))
	var month := int(now.get("month", 1))
	var today := int(now.get("day", 1))
	var month_name: String = "Month"
	if month >= 1 and month < _MONTHS.size():
		month_name = _MONTHS[month]
	host.add_child(_cal_label("%s  %d" % [month_name, year], Vector3(0.0, 0.35, 0.0), 48, Color(0.98, 0.95, 0.9), 0.0032))
	var cell_w := 0.082
	var cell_h := 0.078
	var origin_x := -3.0 * cell_w
	var week_y := 0.22
	for i in 7:
		host.add_child(_cal_label(_WEEKDAYS[i], Vector3(origin_x + i * cell_w, week_y, 0.0), 22, Color(0.35, 0.18, 0.14), 0.0024))
	var first_wd := _weekday_sunday0(year, month, 1)
	var dim := _days_in_month(year, month)
	var col := first_wd
	var row := 0
	for day in range(1, dim + 1):
		var pos := Vector3(origin_x + col * cell_w, 0.12 - row * cell_h, 0.0)
		var is_today := day == today
		if is_today:
			var mark := MeshInstance3D.new()
			var quad := BoxMesh.new()
			quad.size = Vector3(0.07, 0.07, 0.002)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.75, 0.12, 0.12, 1)
			quad.material = mat
			mark.mesh = quad
			mark.position = pos + Vector3(0.0, 0.0, 0.002)
			host.add_child(mark)
		var color := Color(0.98, 0.94, 0.9) if is_today else Color(0.12, 0.1, 0.08)
		host.add_child(_cal_label(str(day), pos, 28, color, 0.0026))
		col += 1
		if col >= 7:
			col = 0
			row += 1


func _cal_label(text: String, pos: Vector3, font_size: int, color: Color, pixel_size: float) -> Label3D:
	var lab := Label3D.new()
	lab.text = text
	lab.position = pos
	lab.font_size = font_size
	lab.pixel_size = pixel_size
	lab.modulate = color
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.shaded = false
	lab.double_sided = false
	return lab


func _days_in_month(year: int, month: int) -> int:
	if month == 2 and _is_leap_year(year):
		return 29
	if month < 1 or month >= _DAYS_IN_MONTH.size():
		return 31
	return _DAYS_IN_MONTH[month]


func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


func _weekday_sunday0(year: int, month: int, day: int) -> int:
	# Sakamoto: 0 = Sunday.
	var t := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var y := year
	if month < 3:
		y -= 1
	return (y + int(y / 4) - int(y / 100) + int(y / 400) + int(t[month - 1]) + day) % 7
