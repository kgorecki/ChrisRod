extends Node3D

@onready var _car_pivot: Node3D = $Car
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera_pitch: Node3D = $CameraPivot/Pitch
@onready var _camera: Camera3D = $CameraPivot/Pitch/Camera3D

@onready var _clock_menu: Control = $GarageUI/ClockMenu
@onready var _stats_panel: Control = $GarageUI/StatsPanel

var _orbiting: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.35
var _cam_distance: float = 7.0

var _stats_label: Label

# Single multiplier to scale all wheels from one place (editable in Inspector).
# Default 1.5 chosen so wheels look correct for the current model out-of-the-box.
@export var wheel_scale: float = 0.8


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	_stats_label = _stats_panel.get_node("Panel/Margin/VBox/StatsText") as Label
	_clock_menu.visible = false
	_stats_panel.visible = false
	$InteractClock.set_meta("garage_interact", "clock")
	$InteractDesk.set_meta("garage_interact", "desk")
	$InteractDoors.set_meta("garage_interact", "doors")
	_update_camera_transform()

	# Defer so MeshInstance scripts (like the STL loader) have a chance
	# to populate `MeshInstance3D.mesh` before we inspect it.
	call_deferred("_debug_car_mesh")
	# Also align wheels to the floor after meshes are ready.
	call_deferred("_align_wheels_to_floor")

	# If the CarBody emits a signal when its STL finishes loading, connect to it
	var car_body := _car_pivot.get_node_or_null("CarBody") as MeshInstance3D
	if car_body != null and car_body.has_signal("stl_loaded"):
		car_body.connect("stl_loaded", Callable(self, "_on_carbody_stl_loaded"))


func _on_carbody_stl_loaded(mesh) -> void:
	# When the CarBody's mesh is ready, re-align wheels to the floor.
	_align_wheels_to_floor()


func _align_wheels_to_floor() -> void:
	# Compute floor top Y in world space from the Floor's MeshInstance3D AABB.
	var floor_node := $Floor
	var floor_mesh_instance := floor_node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var floor_top_y := 0.0
	if floor_mesh_instance != null and floor_mesh_instance.mesh != null:
		var faabb := floor_mesh_instance.get_aabb()
		# 8 corners
		var minp := faabb.position
		var maxp := faabb.position + faabb.size
		var top_y := -INF
		for x in [minp.x, maxp.x]:
			for y in [minp.y, maxp.y]:
				for z in [minp.z, maxp.z]:
					var corner := Vector3(x, y, z)
					var world := floor_mesh_instance.global_transform * corner
					top_y = max(top_y, world.y)
		floor_top_y = top_y
	else:
		# Fallback: assume floor top at y = 0
		floor_top_y = 0.0

	# Wheel node names
	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
	for name in wheel_names:
		var wheel := _car_pivot.get_node_or_null(name) as MeshInstance3D
		if wheel == null:
			continue

		# Apply uniform scale multiplier so wheel size can be adjusted from one variable.
		wheel.scale = Vector3.ONE * wheel_scale
		# Get wheel mesh AABB (local) and transform its corners to world to find bottom Y
		var waabb := wheel.get_aabb()
		var wmin := waabb.position
		var wmax := waabb.position + waabb.size
		var bottom_y := INF
		for x in [wmin.x, wmax.x]:
			for y in [wmin.y, wmax.y]:
				for z in [wmin.z, wmax.z]:
					var corner := Vector3(x, y, z)
					var world := wheel.global_transform * corner
					bottom_y = min(bottom_y, world.y)
		# Compute delta to move so bottom_y == floor_top_y
		var delta := floor_top_y - bottom_y
		if abs(delta) > 0.0001:
			var gp := wheel.global_position
			gp.y += delta
			wheel.global_position = gp

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
		if mesh.has_method("get_surface_count"):
			surfaces = mesh.get_surface_count()

	var aabb := car_body.get_aabb() # local-space bounds
	var center_local := aabb.position + aabb.size * 0.5
	var center_world := car_body.global_transform * center_local

	# Also explicitly try loading the STL resource path.
	# This distinguishes "scene reference failed" vs "import/load failed".
	var stl_path := "res://assets/vette-c1.stl"
	var exists_any := ResourceLoader.exists(stl_path)
	var exists_array_mesh := ResourceLoader.exists(stl_path, "ArrayMesh")
	var loaded_any := ResourceLoader.load(stl_path)
	var loaded_any_type := "<null>"
	var exists_mesh: bool = false
	var loaded_mesh: Resource = null
	var loaded_mesh_type := "<null>"

	if loaded_any != null:
		loaded_any_type = loaded_any.get_class()

	# Check Mesh availability even if loaded_any was null (be explicit)
	exists_mesh = ResourceLoader.exists(stl_path, "Mesh")
	loaded_mesh = ResourceLoader.load(stl_path, "Mesh")
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
	if _clock_menu.visible and event.is_action_pressed("ui_cancel"):
		_clock_menu.visible = false
		get_viewport().set_input_as_handled()
		return
	if _stats_panel.visible and event.is_action_pressed("ui_cancel"):
		_stats_panel.visible = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _clock_menu.visible or _stats_panel.visible:
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
		if node.has_meta("garage_interact"):
			_handle_interact(node.get_meta("garage_interact"))
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
		"clock":
			_clock_menu.visible = true
		"desk":
			_show_stats()
		"doors":
			get_tree().change_scene_to_file(GameState.SCENE_OPPONENT_SELECT)


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
