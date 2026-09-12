extends Node3D

## Builds the winding road course (6× quarter mile) and answers path queries.

const ROAD_HALF_W := 20.0
const BAKE_STEP := 2.0
const CURB_W := 0.45
const CURB_H := 0.16
const CURB_L := 2.0
const CURB_RED := Color(0.82, 0.12, 0.12, 1)
const CURB_WHITE := Color(0.92, 0.92, 0.9, 1)
const CHECK_BLACK := Color(0.06, 0.06, 0.07, 1)
const CHECK_WHITE := Color(0.94, 0.94, 0.92, 1)
const POST_COLOR := Color(0.12, 0.12, 0.13, 1)
const ROAD_COLOR := Color(0.18, 0.19, 0.2, 1)
const TERRAIN_COLOR := Color(0.14, 0.16, 0.13, 1)

## Straight meters or arc (radius, signed degrees). +deg increases yaw (toward +X).
const _BODY_SEGS: Array = [
	["S", 402.336],
	["A", 95.0, -65.0],
	["S", 180.0],
	["A", 75.0, 95.0],
	["S", 140.0],
	["A", 60.0, -85.0],
	["S", 110.0],
	["A", 50.0, 110.0],
	["S", 180.0],
	["A", 42.0, -155.0],
	["S", 150.0],
	["A", 85.0, 75.0],
	["S", 160.0],
	["A", 65.0, -90.0],
	["S", 120.0],
	["A", 55.0, 50.0],
	["A", 55.0, -50.0],
]

var _pts: PackedVector3Array = PackedVector3Array()
var _yaws: PackedFloat32Array = PackedFloat32Array()
var _dists: PackedFloat32Array = PackedFloat32Array()
var _length: float = 0.0
var _pos := Vector3.ZERO
var _yaw: float = 0.0
var _hint_i: int = 0
var _road_mi: MeshInstance3D
var _built: bool = false


func is_road_course() -> bool:
	return _built


func get_length() -> float:
	return _length


func get_half_width() -> float:
	return ROAD_HALF_W


func get_road_mesh_instance() -> MeshInstance3D:
	return _road_mi


func remaining_distance(world: Vector3) -> float:
	return maxf(0.0, _length - closest_sample(world)["s"])


func sample_at(s: float) -> Dictionary:
	if _pts.is_empty():
		return _empty_sample()
	s = clampf(s, 0.0, _length)
	var i := _index_at_distance(s)
	var j := mini(i + 1, _pts.size() - 1)
	var t := 0.0
	var span: float = _dists[j] - _dists[i]
	if span > 0.0001:
		t = (s - _dists[i]) / span
	var pos := _pts[i].lerp(_pts[j], t)
	var yaw := lerp_angle(_yaws[i], _yaws[j], t)
	return _make_sample(pos, yaw, s, 0.0)


func closest_sample(world: Vector3) -> Dictionary:
	if _pts.is_empty():
		return _empty_sample()
	var best_i := _hint_i
	var best_d := INF
	var start_i := maxi(_hint_i - 70, 0)
	var end_i := mini(_hint_i + 90, _pts.size() - 1)
	for i in range(start_i, end_i + 1):
		var d := world.distance_squared_to(_pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	if best_d > 400.0:
		for i in _pts.size():
			var d := world.distance_squared_to(_pts[i])
			if d < best_d:
				best_d = d
				best_i = i
	_hint_i = best_i
	var yaw: float = _yaws[best_i]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var lateral := (world - _pts[best_i]).dot(right)
	return _make_sample(_pts[best_i], yaw, _dists[best_i], lateral)


func finish_basis() -> Transform3D:
	if _pts.is_empty():
		return Transform3D.IDENTITY
	var i := _pts.size() - 1
	var yaw: float = _yaws[i]
	var xf := Transform3D(Basis(Vector3.UP, yaw), _pts[i] + Vector3(0.0, 2.0, 0.0))
	return xf


func build_road_course() -> void:
	if _built:
		return
	_build_path()
	_build_terrain()
	_build_road_mesh()
	_build_curbs()
	_build_finish_line()
	_built = true


func _ready() -> void:
	if GameState.selected_race_type == GameState.RACE_ROAD:
		build_road_course()


func _empty_sample() -> Dictionary:
	return _make_sample(Vector3.ZERO, 0.0, 0.0, 0.0)


func _make_sample(pos: Vector3, yaw: float, s: float, lateral: float) -> Dictionary:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return {
		"position": pos,
		"forward": forward,
		"right": right,
		"yaw": yaw,
		"s": s,
		"lateral": lateral,
	}


func _build_path() -> void:
	_pts.clear()
	_yaws.clear()
	_dists.clear()
	_pos = Vector3.ZERO
	_yaw = 0.0
	_length = 0.0
	_push_sample()
	var planned := 0.0
	for seg in _BODY_SEGS:
		if str(seg[0]) == "S":
			planned += float(seg[1])
		else:
			planned += float(seg[1]) * absf(deg_to_rad(float(seg[2])))
	for seg in _BODY_SEGS:
		if str(seg[0]) == "S":
			_append_straight(float(seg[1]))
		else:
			_append_arc(float(seg[1]), float(seg[2]))
	var remaining: float = GameState.ROAD_RACE_LENGTH_M - planned
	if remaining > 0.05:
		_append_straight(remaining)


func _push_sample() -> void:
	_pts.append(_pos)
	_yaws.append(_yaw)
	_dists.append(_length)


func _append_straight(length: float) -> void:
	var left := length
	while left > 0.0001:
		var step := minf(BAKE_STEP, left)
		_pos += Vector3(sin(_yaw), 0.0, cos(_yaw)) * step
		_length += step
		_push_sample()
		left -= step


func _append_arc(radius: float, angle_deg: float) -> void:
	var ang := deg_to_rad(angle_deg)
	var arc_len := radius * absf(ang)
	var steps := maxi(8, int(ceil(arc_len / BAKE_STEP)))
	var da := ang / float(steps)
	for _i in steps:
		var rdir := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		if da > 0.0:
			var c := _pos + rdir * radius
			_yaw += da
			rdir = Vector3(cos(_yaw), 0.0, -sin(_yaw))
			_pos = c - rdir * radius
		else:
			var c := _pos - rdir * radius
			_yaw += da
			rdir = Vector3(cos(_yaw), 0.0, -sin(_yaw))
			_pos = c + rdir * radius
		_length += radius * absf(da)
		_push_sample()


func _index_at_distance(s: float) -> int:
	var lo := 0
	var hi := _dists.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if _dists[mid] < s:
			lo = mid + 1
		else:
			hi = mid
	return maxi(lo - 1, 0)


func _make_mat(color: Color, roughness: float = 0.72) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _build_terrain() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2800, 2800)
	plane.material = _make_mat(TERRAIN_COLOR, 0.95)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = plane
	mi.position = Vector3(-450.0, -0.08, 700.0)
	add_child(mi)


func _build_road_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := ROAD_HALF_W
	for i in range(_pts.size() - 1):
		var yaw0: float = _yaws[i]
		var yaw1: float = _yaws[i + 1]
		var r0 := Vector3(cos(yaw0), 0.0, -sin(yaw0))
		var r1 := Vector3(cos(yaw1), 0.0, -sin(yaw1))
		var l0 := _pts[i] - r0 * hw
		var rr0 := _pts[i] + r0 * hw
		var l1 := _pts[i + 1] - r1 * hw
		var rr1 := _pts[i + 1] + r1 * hw
		var v := _dists[i] * 0.15
		var v1 := _dists[i + 1] * 0.15
		_add_tri(st, l0, rr0, rr1, Vector2(0, v), Vector2(1, v), Vector2(1, v1))
		_add_tri(st, l0, rr1, l1, Vector2(0, v), Vector2(1, v1), Vector2(0, v1))
	st.generate_normals()
	var mesh := st.commit()
	var mat := _make_mat(ROAD_COLOR, 0.85)
	mesh.surface_set_material(0, mat)
	_road_mi = MeshInstance3D.new()
	_road_mi.name = "RoadMesh"
	_road_mi.mesh = mesh
	add_child(_road_mi)


func _add_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uva: Vector2,
	uvb: Vector2,
	uvc: Vector2
) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.set_uv(uvc)
	st.add_vertex(c)


func _build_curbs() -> void:
	var red_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	var edge := ROAD_HALF_W - CURB_W * 0.5
	var y := CURB_H * 0.5
	var stride := maxi(1, int(round(CURB_L / BAKE_STEP)))
	var stone_i := 0
	var i := 0
	while i < _pts.size():
		var yaw: float = _yaws[i]
		var basis := Basis(Vector3.UP, yaw)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var pos := _pts[i] + Vector3(0.0, y, 0.0)
		var xf_l := Transform3D(basis, pos - right * edge)
		var xf_r := Transform3D(basis, pos + right * edge)
		if stone_i % 2 == 0:
			red_xforms.append(xf_l)
			white_xforms.append(xf_r)
		else:
			white_xforms.append(xf_l)
			red_xforms.append(xf_r)
		stone_i += 1
		i += stride
	_add_box_multimesh(self, "CurbRed", Vector3(CURB_W, CURB_H, CURB_L), CURB_RED, red_xforms)
	_add_box_multimesh(self, "CurbWhite", Vector3(CURB_W, CURB_H, CURB_L), CURB_WHITE, white_xforms)


func _build_finish_line() -> void:
	if _pts.is_empty():
		return
	var i := _pts.size() - 1
	var yaw: float = _yaws[i]
	var root := Node3D.new()
	root.name = "FinishLineVisual"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), _pts[i])
	add_child(root)
	_add_checkered_strip(root)
	_add_finish_gantry(root)


func _add_checkered_strip(parent: Node3D) -> void:
	const COLS := 24
	const ROWS := 2
	const SQUARE := 1.25
	var width := COLS * SQUARE
	var origin_x := -width * 0.5
	var origin_z := -ROWS * SQUARE * 0.5
	var black_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	for row in ROWS:
		for col in COLS:
			var pos := Vector3(
				origin_x + (col + 0.5) * SQUARE,
				0.02,
				origin_z + (row + 0.5) * SQUARE
			)
			var xform := Transform3D(Basis.IDENTITY, pos)
			if (row + col) % 2 == 0:
				black_xforms.append(xform)
			else:
				white_xforms.append(xform)
	_add_box_multimesh(parent, "CheckBlack", Vector3(SQUARE, 0.03, SQUARE), CHECK_BLACK, black_xforms)
	_add_box_multimesh(parent, "CheckWhite", Vector3(SQUARE, 0.03, SQUARE), CHECK_WHITE, white_xforms)


func _add_finish_gantry(parent: Node3D) -> void:
	const POST_H := 4.4
	const POST_W := 0.22
	const BANNER_W := 38.6
	const BANNER_H := 0.9
	var post_x := BANNER_W * 0.5
	var post_mat := _make_mat(POST_COLOR, 0.45)
	_add_box(parent, "PostL", Vector3(POST_W, POST_H, POST_W), post_mat, Vector3(-post_x, POST_H * 0.5, 0.0))
	_add_box(parent, "PostR", Vector3(POST_W, POST_H, POST_W), post_mat, Vector3(post_x, POST_H * 0.5, 0.0))
	_add_box(parent, "Crossbar", Vector3(BANNER_W, POST_W, POST_W), post_mat, Vector3(0.0, POST_H, 0.0))
	const BCOLS := 16
	const BROWS := 2
	var cell_w := BANNER_W / float(BCOLS)
	var cell_h := BANNER_H / float(BROWS)
	var banner_y := POST_H - POST_W - BANNER_H * 0.5 - 0.04
	var black_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	for row in BROWS:
		for col in BCOLS:
			var pos := Vector3(
				-BANNER_W * 0.5 + (col + 0.5) * cell_w,
				banner_y + (0.5 - row) * cell_h,
				0.0
			)
			var xform := Transform3D(Basis.IDENTITY, pos)
			if (row + col) % 2 == 0:
				black_xforms.append(xform)
			else:
				white_xforms.append(xform)
	_add_box_multimesh(parent, "BannerBlack", Vector3(cell_w, cell_h, 0.08), CHECK_BLACK, black_xforms)
	_add_box_multimesh(parent, "BannerWhite", Vector3(cell_w, cell_h, 0.08), CHECK_WHITE, white_xforms)


func _add_box(parent: Node3D, node_name: String, size: Vector3, mat: Material, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)


func _add_box_multimesh(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	color: Color,
	xforms: Array[Transform3D]
) -> void:
	if xforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = size
	box.material = _make_mat(color)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	parent.add_child(mmi)
