extends Node3D

@onready var _car_pivot: Node3D = $CarPivot
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera_pitch: Node3D = $CameraPivot/Pitch
@onready var _camera: Camera3D = $CameraPivot/Pitch/Camera3D

@onready var _clock_menu: Control = $GarageUI/ClockMenu
@onready var _stats_panel: Control = $GarageUI/StatsPanel
@onready var _spray_menu: Control = $GarageUI/ColorPickerMenu
@onready var _spray_color_picker: ColorPicker = $GarageUI/ColorPickerMenu/Panel/Margin/VBox/ColorPicker

var _orbiting: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.35
var _cam_distance: float = 7.0

var _stats_label: Label

func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	_stats_label = _stats_panel.get_node("Panel/Margin/VBox/StatsText") as Label
	_clock_menu.visible = false
	_stats_panel.visible = false
	_spray_menu.visible = false
	$InteractClock.set_meta(&"garage_interact", &"clock")
	$InteractDesk.set_meta(&"garage_interact", &"desk")
	$InteractDoors.set_meta(&"garage_interact", &"doors")
	$InteractSprayPistol.set_meta(&"garage_interact", &"spray")
	# Apply stored paint color immediately (it will wait for the STL if needed).
	if _car_pivot.has_method(&"set_car_body_color"):
		_car_pivot.set_car_body_color(GameState.car_color)
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

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _clock_menu.visible or _stats_panel.visible or _spray_menu.visible:
				return
			_try_interact(mb.position)

	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, 0.1, 1.2)
		_update_camera_transform()
		get_viewport().set_input_as_handled()


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
		&"desk":
			_show_stats()
		&"doors":
			get_tree().change_scene_to_file(GameState.SCENE_OPPONENT_SELECT)
		&"spray":
			_show_spray_picker()


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
	var t := "Car: %s\n\nVmax: %.0f km/h\nEngine power: %.0f hp" % [
		GameState.car_name,
		GameState.vmax_kmh,
		GameState.engine_power_hp,
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
