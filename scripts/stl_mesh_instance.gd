extends MeshInstance3D

## Runtime STL loader for Godot projects where the STL importer is unavailable.
## It parses both binary and ASCII STL and builds an `ArrayMesh` at runtime.

@export var stl_path: String = "res://assets/vette-c1.stl"
@export var center_model: bool = true
@export var auto_scale_to_height: float = 4.5 # meters; set <= 0 to disable
@export var manual_scale: float = 1.0
@export var print_debug: bool = true

# Extra multiplier applied after auto/manual scale; useful to quickly enlarge/shrink.
@export var scale_multiplier: float = 1.0

# Optional rotation (degrees) applied to the model after centering/scaling.
# Useful when an STL's up-axis differs from the project's up-axis (e.g. model is vertical).
@export var apply_rotation: bool = true
@export var stl_rotation_degrees: Vector3 = Vector3(-90.0, 0.0, 0.0) # default: rotate -90° on X to lay model horizontally

signal stl_loaded(mesh)

# Optional material to apply to the loaded mesh. If left empty a default
# StandardMaterial3D will be created and used.
@export var car_material: StandardMaterial3D

static var _mesh_cache: Dictionary = {} # key -> ArrayMesh


func _rotate_by_euler_degs(vec: Vector3, degs: Vector3) -> Vector3:
	# Rotate a vector by Euler angles (degrees) around X, then Y, then Z.
	var r := degs * (PI / 180.0)
	if r.x != 0.0:
		vec = vec.rotated(Vector3(1, 0, 0), r.x)
	if r.y != 0.0:
		vec = vec.rotated(Vector3(0, 1, 0), r.y)
	if r.z != 0.0:
		vec = vec.rotated(Vector3(0, 0, 1), r.z)
	return vec


func _ready() -> void:
	load_stl_into_mesh()


func _apply_material_override() -> void:
	# Apply material override per MeshInstance3D instance.
	# (Important for cached meshes: `mesh` can be shared, but `material_override` is not.)
	if car_material != null:
		# Duplicate to avoid mutating the original resource in the inspector.
		var mat := car_material.duplicate()
		# If it's a StandardMaterial3D we can safely force alpha/transmission.
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_color.a = 1.0
			# StandardMaterial3D in Godot 4 exposes `transmission`.
			(mat as StandardMaterial3D).transmission = 0.0
		material_override = mat
	else:
		var default_mat := StandardMaterial3D.new()
		default_mat.albedo_color = Color(0.15, 0.45, 0.85, 1)
		default_mat.metallic = 0.6
		default_mat.roughness = 0.35
		# Disable any transmission for opacity
		default_mat.transmission = 0.0
		material_override = default_mat


func load_stl_into_mesh() -> void:
	var key := "%s|center=%s|auto_scale_h=%s|manual_scale=%s|scale_mul=%s|apply_rot=%s|rot=%s" % [stl_path, center_model, auto_scale_to_height, manual_scale, scale_multiplier, apply_rotation, stl_rotation_degrees]
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key]
		_apply_material_override()
		# Let listeners (e.g. car visual scripts) know the mesh is available.
		emit_signal("stl_loaded", mesh)
		if print_debug:
			print("[STL] Loaded from cache:", stl_path, " key=", key)
		return

	var abs_path := ProjectSettings.globalize_path(stl_path)
	if not FileAccess.file_exists(abs_path):
		push_warning("[STL] File not found: " + stl_path + " (abs: " + abs_path + ")")
		return

	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		push_warning("[STL] Failed to open: " + abs_path)
		return

	var file_size := file.get_length()
	var bytes := file.get_buffer(file_size)
	file.close()

	if bytes.size() < 84:
		push_warning("[STL] File too small to be STL: " + abs_path)
		return

	var is_binary := _looks_like_binary_stl(bytes, file_size)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)

	if is_binary:
		var bounds := _parse_binary_stl(bytes, vertices, normals)
		min_v = bounds.min_v
		max_v = bounds.max_v
	else:
		var bounds := _parse_ascii_stl(bytes, vertices, normals)
		min_v = bounds.min_v
		max_v = bounds.max_v

	if vertices.is_empty():
		push_warning("[STL] No vertices parsed from STL: " + abs_path)
		return

	var scale := manual_scale
	var height := max_v.y - min_v.y
	if auto_scale_to_height > 0.0 and height > 0.000001:
		scale = auto_scale_to_height / height

	# Apply user multiplier
	scale *= scale_multiplier

	var center := Vector3.ZERO
	if center_model:
		center = (min_v + max_v) * 0.5

	# Apply transform to vertices (center/scale), then optionally rotate to desired orientation.
	# Apply center/scale and rotation to vertices and normals
	for i in vertices.size():
		var v := (vertices[i] - center) * scale
		if apply_rotation:
			v = _rotate_by_euler_degs(v, stl_rotation_degrees)
		vertices[i] = v

		if i < normals.size():
			var n := normals[i]
			if apply_rotation:
				n = _rotate_by_euler_degs(n, stl_rotation_degrees)
			normals[i] = n

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	mesh = m
	_mesh_cache[key] = m

	_apply_material_override()

	# Notify listeners that the mesh finished loading so other nodes (e.g. Garage)
	# can react (align wheels, recalc bounds, etc.).
	emit_signal("stl_loaded", m)

	if print_debug:
		print("[STL] Loaded:", stl_path,
			" binary=", is_binary,
			" verts=", vertices.size(),
			" min=", min_v, " max=", max_v,
			" height=", height,
			" scale=", scale,
			" scale_mul=", scale_multiplier,
			" center=", center,
			" rot=", (stl_rotation_degrees if apply_rotation else Vector3.ZERO),
			" surfaces=", (m.get_surface_count() if m.has_method(&"get_surface_count") else -1))


func _looks_like_binary_stl(bytes: PackedByteArray, file_size: int) -> bool:
	# Binary STL header is 80 bytes + uint32 triangle count + 50 bytes per triangle.
	if bytes.size() < 84:
		return false
	var tri_count := _read_u32_le(bytes, 80)
	var expected_size := 84 + tri_count * 50
	return expected_size == file_size


func _parse_binary_stl(bytes: PackedByteArray, vertices_out: PackedVector3Array, normals_out: PackedVector3Array) -> Dictionary:
	var spb := StreamPeerBuffer.new()
	spb.data_array = bytes
	spb.big_endian = false
	spb.seek(80)
	var tri_count := spb.get_u32()
	spb.seek(84)

	vertices_out.resize(tri_count * 3)
	normals_out.resize(tri_count * 3)

	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)

	for tri in range(tri_count):
		var nx := spb.get_float()
		var ny := spb.get_float()
		var nz := spb.get_float()
		var n := Vector3(nx, ny, nz)

		for k in 3:
			var x := spb.get_float()
			var y := spb.get_float()
			var z := spb.get_float()
			var idx := tri * 3 + k
			vertices_out[idx] = Vector3(x, y, z)
			normals_out[idx] = n

			min_v = Vector3(min(min_v.x, x), min(min_v.y, y), min(min_v.z, z))
			max_v = Vector3(max(max_v.x, x), max(max_v.y, y), max(max_v.z, z))

		# attribute byte count (unused)
		spb.get_u16()

	return { "min_v": min_v, "max_v": max_v }


func _parse_ascii_stl(bytes: PackedByteArray, vertices_out: PackedVector3Array, normals_out: PackedVector3Array) -> Dictionary:
	# Very small/simple ASCII STL parser.
	# Note: ASCII STL normals may be present but we also tolerate missing normals.
	var text := bytes.get_string_from_utf8()
	var lines := text.split("\n", false)

	var current_normal := Vector3.ZERO

	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)

	for line in lines:
		line = line.strip_edges()
		if line.begins_with("facet normal "):
			# Expected: facet normal nx ny nz
			var parts := line.split(" ", false)
			if parts.size() >= 5:
				current_normal = Vector3(float(parts[2]), float(parts[3]), float(parts[4]))
		elif line.begins_with("vertex "):
			# Expected: vertex x y z
			var parts := line.split(" ", false)
			if parts.size() >= 4:
				var v := Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
				vertices_out.push_back(v)
				normals_out.push_back(current_normal)

				min_v = Vector3(min(min_v.x, v.x), min(min_v.y, v.y), min(min_v.z, v.z))
				max_v = Vector3(max(max_v.x, v.x), max(max_v.y, v.y), max(max_v.z, v.z))

	return { "min_v": min_v, "max_v": max_v }


func _read_u32_le(bytes: PackedByteArray, offset: int) -> int:
	# Little-endian uint32 read.
	var b0 := bytes[offset + 0]
	var b1 := bytes[offset + 1]
	var b2 := bytes[offset + 2]
	var b3 := bytes[offset + 3]
	return int(b0) | (int(b1) << 8) | (int(b2) << 16) | (int(b3) << 24)
