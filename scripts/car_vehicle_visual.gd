extends Node3D

## Shared car visuals (STL body, wheels, materials) used by garage and race.
## Defaults match `garage.tscn` / `car_vehicle_visual.tscn`.

@export var wheel_scale: float = 0.8
## When set (e.g. opponent), applied to the car body after the STL mesh loads.
@export var body_paint: StandardMaterial3D

var _waiting_for_stl: bool = false


func _ready() -> void:
	_apply_wheel_scale()
	var car_body := get_node_or_null("CarBody") as MeshInstance3D
	if car_body != null and body_paint != null:
		# CarBody `_ready` runs before this node, so the STL may already be loaded.
		if car_body.mesh != null:
			_apply_body_paint(car_body)
		elif car_body.has_signal(&"stl_loaded"):
			_waiting_for_stl = true
			car_body.connect(&"stl_loaded", Callable(self, "_on_car_body_stl_loaded").bind(car_body))


func _on_car_body_stl_loaded(_mesh: Mesh, car_body: MeshInstance3D) -> void:
	_waiting_for_stl = false
	_apply_body_paint(car_body)


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
func set_car_body_color(color: Color) -> void:
	var car_body := get_node_or_null("CarBody") as MeshInstance3D
	if car_body == null:
		return

	# Build a material based on whatever is currently on the body.
	var base := car_body.material_override
	var mat: StandardMaterial3D
	if base is StandardMaterial3D:
		mat = (base as StandardMaterial3D).duplicate()
	elif body_paint != null and body_paint is StandardMaterial3D:
		mat = (body_paint as StandardMaterial3D).duplicate()
	else:
		mat = StandardMaterial3D.new()
		mat.metallic = 0.4
		mat.roughness = 0.35

	var c := color
	c.a = 1.0
	mat.albedo_color = c
	mat.transmission = 0.0

	body_paint = mat

	# If the STL is already loaded, apply immediately; otherwise wait for it.
	if car_body.mesh != null:
		_apply_body_paint(car_body)
	elif car_body.has_signal(&"stl_loaded") and not _waiting_for_stl:
		_waiting_for_stl = true
		car_body.connect(&"stl_loaded", Callable(self, "_on_car_body_stl_loaded").bind(car_body))


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
		var wheel := get_node_or_null(wname) as MeshInstance3D
		if wheel == null or wheel.mesh == null:
			continue

		var waabb := wheel.get_aabb()
		var wmin := waabb.position
		var wmax := waabb.position + waabb.size
		var bottom_y := INF
		for wx in [wmin.x, wmax.x]:
			for wy in [wmin.y, wmax.y]:
				for wz in [wmin.z, wmax.z]:
					var corner := Vector3(wx, wy, wz)
					var world := wheel.global_transform * corner
					bottom_y = minf(bottom_y, world.y)

		var delta := floor_top_y - bottom_y
		if absf(delta) > 0.0001:
			var gp := wheel.global_position
			gp.y += delta
			wheel.global_position = gp
