extends Node3D

## Shared car visuals (STL body, wheels, materials) used by garage and race.
## Defaults match `garage.tscn` / `car_vehicle_visual.tscn`.

@export var wheel_scale: float = 1
## When set (e.g. opponent), applied to the car body after the STL mesh loads.
@export var body_paint: StandardMaterial3D

#@export var body_node_path: NodePath = NodePath("body")

const _CarFile := preload("res://scripts/car_file.gd")

var _waiting_for_stl: bool = false

func _enter_tree() -> void:
	_apply_car_file()


func _ready() -> void:
	apply_equipped_wheels()
	_apply_wheel_scale()
	var loaded_body := get_node_or_null("CarBody") as Node
	if loaded_body != null:
		_hide_baked_wheels(loaded_body)
		if loaded_body.has_signal(&"stl_loaded"):
			loaded_body.connect(&"stl_loaded", Callable(self, "_on_body_hide_wheels"))
	var car_body := get_node_or_null("body") as MeshInstance3D
	if car_body != null and body_paint != null:
		# CarBody `_ready` runs before this node, so the STL may already be loaded.
		if car_body.mesh != null:
			_apply_body_paint(car_body)
		elif car_body.has_signal(&"stl_loaded"):
			_waiting_for_stl = true
			car_body.connect(&"stl_loaded", Callable(self, "_on_car_body_stl_loaded").bind(car_body))

func _on_body_hide_wheels(_mesh: Variant) -> void:
	var loaded_body := get_node_or_null("CarBody") as Node
	if loaded_body != null:
		_hide_baked_wheels(loaded_body)


func _hide_baked_wheels(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and _is_baked_wheel(child as MeshInstance3D):
			(child as MeshInstance3D).visible = false
		_hide_baked_wheels(child)


func _is_baked_wheel(mesh_instance: MeshInstance3D) -> bool:
	var label := String(mesh_instance.name).to_lower()
	if label.contains("wheel") or label.contains("tire"):
		return true
	if mesh_instance.mesh == null:
		return false
	for i in mesh_instance.mesh.get_surface_count():
		var mat := mesh_instance.get_surface_override_material(i)
		if mat == null:
			mat = mesh_instance.mesh.surface_get_material(i)
		if mat == null:
			continue
		var mat_name := String(mat.resource_name).to_lower()
		if mat_name.contains("wheel") or mat_name.contains("tire"):
			return true
	return false


func _on_car_body_stl_loaded(_mesh: Mesh, car_body: MeshInstance3D) -> void:
	_waiting_for_stl = false
	_apply_body_paint(car_body)


func _apply_car_file() -> void:
	var spec: Dictionary = _CarFile.load_path(GameState.PLAYER_CAR_FILE)
	var errors: Variant = spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY and not (errors as Array).is_empty():
		return
	var model: Variant = spec.get("model", {})
	if typeof(model) == TYPE_DICTIONARY:
		var model_dict: Dictionary = model
		_apply_mount(get_node_or_null("CarBody") as Node3D, str(model_dict.get("path", "")), model_dict, float(model_dict.get("height", 5.0)))
	var wheels: Variant = spec.get("wheels", {})
	if typeof(wheels) != TYPE_DICTIONARY:
		return
	var wheel_dict: Dictionary = wheels
	wheel_scale = float(wheel_dict.get("scale", wheel_scale))
	var mounts: Variant = wheel_dict.get("mounts", [])
	if typeof(mounts) != TYPE_ARRAY:
		return
	var wheel_path := str(wheel_dict.get("path", ""))
	var wheel_height := float(wheel_dict.get("height", 0.5))
	for item in mounts:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var mount: Dictionary = item
		var wheel := get_node_or_null(str(mount.get("node", ""))) as Node3D
		_apply_mount(wheel, wheel_path, mount, wheel_height)


func _apply_mount(node: Node3D, model_path: String, mount: Dictionary, height: float) -> void:
	if node == null or node.get("stl_path") == null:
		return
	if not model_path.is_empty():
		node.set("stl_path", model_path)
	var pos: Variant = mount.get("position", null)
	if pos is Vector3:
		node.position = pos
	var rot: Variant = mount.get("rotation", null)
	if rot is Vector3:
		node.set("stl_rotation_degrees", rot)
	node.set("auto_scale_to_height", height)


func apply_equipped_wheels() -> void:
	apply_wheel_set(GameState.get_equipped_wheel())


func apply_wheel_set(wheel: Dictionary) -> void:
	if wheel.is_empty():
		return
	for wname in ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]:
		apply_wheel_to_mount(get_node_or_null(wname) as Node3D, wheel)


func apply_wheel_to_mount(mount: Node3D, wheel: Dictionary) -> void:
	if mount == null or wheel.is_empty():
		return
	var path := str(wheel.get("path", ""))
	if path.is_empty() or mount.get("stl_path") == null:
		return
	wheel_scale = float(wheel.get("scale", wheel_scale))
	var height := float(wheel.get("height", 0.5))
	var changed := str(mount.get("stl_path")) != path
	mount.visible = true
	mount.set("stl_path", path)
	mount.set("auto_scale_to_height", height)
	if changed and mount.has_method(&"load_model"):
		for child in mount.get_children():
			mount.remove_child(child)
			child.free()
		if mount is MeshInstance3D:
			(mount as MeshInstance3D).mesh = null
		mount.call(&"load_model")
	if mount is MeshInstance3D:
		(mount as MeshInstance3D).scale = Vector3.ONE * wheel_scale


func _apply_wheel_scale() -> void:
	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
	for wname in wheel_names:
		var wheel := get_node_or_null(wname) as MeshInstance3D
		if wheel != null:
			wheel.scale = Vector3.ONE * wheel_scale


func _apply_body_paint(car_body: MeshInstance3D) -> void:
	if body_paint == null:
		return
	var m := body_paint.duplicate()
	if m is StandardMaterial3D:
		(m as StandardMaterial3D).albedo_color.a = 1.0
		(m as StandardMaterial3D).transmission = 0.0
	car_body.material_override = m


## Runtime paint updates (e.g. from the garage spray pistol).
#func set_car_body_color(color: Color) -> void:
	#var car_body := get_node_or_null("CarBody") as MeshInstance3D
	#if car_body == null:
		#return
#
	## Build a material based on whatever is currently on the body.
	#var base := car_body.material_override
	#var mat: StandardMaterial3D
	#if base is StandardMaterial3D:
		#mat = (base as StandardMaterial3D).duplicate()
	#elif body_paint != null and body_paint is StandardMaterial3D:
		#mat = (body_paint as StandardMaterial3D).duplicate()
	#else:
		#mat = StandardMaterial3D.new()
		#mat.metallic = 0.4
		#mat.roughness = 0.35
#
	#var c := color
	#c.a = 1.0
	#mat.albedo_color = c
	#mat.transmission = 0.0
#
	#body_paint = mat
#
	## If the STL is already loaded, apply immediately; otherwise wait for it.
	#if car_body.mesh != null:
		#_apply_body_paint(car_body)
	#elif car_body.has_signal(&"stl_loaded") and not _waiting_for_stl:
		#_waiting_for_stl = true
		#car_body.connect(&"stl_loaded", Callable(self, "_on_car_body_stl_loaded").bind(car_body))

func set_car_body_color(new_color: Color) -> void:
	print_debug("[DEBUG CAR COLOR] selected=", new_color)
	#var body = get_node_or_null(body_node_path)
	var body = find_child("body", true, false)
	if not body:
		print_debug("body not found: body")
		return

	# iterujemy po wszystkich powierzchniach karoserii
	var surface_count = body.mesh.get_surface_count()
	for i in range(surface_count):
		var mat = body.get_surface_override_material(i)

		# jeśli nie ma materiału override, pobierz domyślny
		if not mat:
			mat = body.mesh.surface_get_material(i)

		if mat:
			# sklonuj materiał, żeby nie zmieniać oryginału
			var mat_copy = mat.duplicate()
			body.set_surface_override_material(i, mat_copy)

			# zmiana koloru
			if mat_copy is StandardMaterial3D:
				mat_copy.albedo_texture = null
				mat_copy.albedo_color = new_color
			elif mat_copy is ShaderMaterial:
				# jeśli shader ma uniform 'albedo_color'
				if mat_copy.has_parameter("albedo_color"):
					mat_copy.set_shader_parameter("albedo_color", new_color)
			else:
				push_warning("Nieobsługiwany typ materiału: %s" % mat_copy)

## Align wheel bottoms to the top of a horizontal floor mesh (same logic as former garage-only code).
func align_wheels_to_floor(floor_mesh_instance: MeshInstance3D) -> void:
	if floor_mesh_instance == null or floor_mesh_instance.mesh == null:
		return

	var faabb := floor_mesh_instance.get_aabb()
	var minp := faabb.position
	var maxp := faabb.position + faabb.size
	var floor_top_y := -INF
	for x in [minp.x, maxp.x]:
		for y in [minp.y, maxp.y]:
			for z in [minp.z, maxp.z]:
				var corner := Vector3(x, y, z)
				var world := floor_mesh_instance.global_transform * corner
				floor_top_y = maxf(floor_top_y, world.y)

	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]
	for wname in wheel_names:
		var wheel := get_node_or_null(wname) as Node3D
		if wheel == null:
			continue
		var bottom_y := _mesh_bottom_y(wheel)
		if bottom_y == INF:
			continue
		var delta := floor_top_y - bottom_y
		if absf(delta) > 0.0001:
			var gp := wheel.global_position
			gp.y += delta
			wheel.global_position = gp


func _mesh_bottom_y(node: Node3D) -> float:
	var bottom_y := INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb := (node as MeshInstance3D).get_aabb()
		var wmin := aabb.position
		var wmax := wmin + aabb.size
		for wx in [wmin.x, wmax.x]:
			for wy in [wmin.y, wmax.y]:
				for wz in [wmin.z, wmax.z]:
					var world := node.global_transform * Vector3(wx, wy, wz)
					bottom_y = minf(bottom_y, world.y)
	for child in node.get_children():
		if child is Node3D:
			bottom_y = minf(bottom_y, _mesh_bottom_y(child as Node3D))
	return bottom_y
