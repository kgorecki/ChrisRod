extends Node3D

# Controller for the reusable Car visual (CarBody + wheels).
# Exposes simple API used by scenes (garage, race).

@export var stl_path: String = "res://assets/vette-c1.stl"
@export var car_material: StandardMaterial3D
@export var wheel_scale: float = 1.0
@export var center_model: bool = true
@export var auto_scale_to_height: float = 0.55

@onready var _car_body: MeshInstance3D = $CarBody
@onready var _wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelBackLeft", "WheelBackRight"]

func _ready() -> void:
	# Apply exports to the child stl loader if present
	if _car_body != null:
		if _car_body.has_method("load_stl_into_mesh"):
			_car_body.stl_path = stl_path
			_car_body.center_model = center_model
			_car_body.auto_scale_to_height = auto_scale_to_height
			_car_body.car_material = car_material
			# connect to reload event
			if _car_body.has_signal("stl_loaded"):
				_car_body.connect("stl_loaded", Callable(self, "_on_carbody_loaded"))
	# apply wheel scale immediately
	_apply_wheel_scale()

func _apply_wheel_scale() -> void:
	for name in _wheel_names:
		var w := get_node_or_null(name) as MeshInstance3D
		if w:
			w.scale = Vector3.ONE * wheel_scale

func set_model(path: String) -> void:
	stl_path = path
	if _car_body != null and _car_body.has_method("load_stl_into_mesh"):
		_car_body.stl_path = path
		_car_body.car_material = car_material
		_car_body.load_stl_into_mesh()

func set_material(mat: StandardMaterial3D) -> void:
	car_material = mat
	if _car_body != null:
		_car_body.car_material = mat
		if _car_body.mesh != null:
			_car_body.material_override = mat

func set_wheel_scale(s: float) -> void:
	wheel_scale = s
	_apply_wheel_scale()

func align_to_floor(floor_node: Node = null) -> void:
	# Align wheels so their bottoms sit on the provided floor_node's top.
	# If floor_node is null, try to find a node named "Floor" in the scene tree root.
	var floor_top_y := 0.0
	var floor_mesh_instance: MeshInstance3D = null
	if floor_node != null:
		floor_mesh_instance = floor_node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	else:
		var root := get_tree().get_current_scene()
		if root != null and root.has_node("Floor"):
			var fnode := root.get_node("Floor")
			floor_mesh_instance = fnode.get_node_or_null("MeshInstance3D") as MeshInstance3D

	if floor_mesh_instance != null and floor_mesh_instance.mesh != null:
		var faabb := floor_mesh_instance.get_aabb()
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
		floor_top_y = 0.0

	# For each wheel, compute bottom in world space and nudge up
	for name in _wheel_names:
		var wheel := get_node_or_null(name) as MeshInstance3D
		if wheel == null:
			continue
		# ensure scale applied
		wheel.scale = Vector3.ONE * wheel_scale
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
		var delta := floor_top_y - bottom_y
		if abs(delta) > 0.0001:
			var gp := wheel.global_position
			gp.y += delta
			wheel.global_position = gp

func _on_carbody_loaded(mesh) -> void:
	# Re-align when body mesh is ready
	align_to_floor()
