extends Node3D

## Builds a road course from a `.trk` graph and answers path queries.

@export_file("*.trk") var track_path: String = "res://assets/tracks/track1.trk"

const ROAD_HALF_W := 20.0
const BAKE_STEP := 2.0
const FILLET_MIN_ANGLE := 0.06 ## ~3.5 degrees; smaller turns stay as a sharp join
const FILLET_LEN_FRACTION := 0.4
const FILLET_MAX_CUT := 80.0
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

var _pts: PackedVector3Array = PackedVector3Array()
var _yaws: PackedFloat32Array = PackedFloat32Array()
var _dists: PackedFloat32Array = PackedFloat32Array()
var _half_ws: PackedFloat32Array = PackedFloat32Array()
var _surfaces: PackedStringArray = PackedStringArray()
var _road_types: PackedStringArray = PackedStringArray()
var _length: float = 0.0
var _pos := Vector3.ZERO
var _yaw: float = 0.0
var _seg_half_w: float = ROAD_HALF_W
var _seg_surface: String = "regular"
var _seg_road_type: String = "regular"
var _hint_i: int = 0
var _road_mi: MeshInstance3D
var _built: bool = false


func is_road_course() -> bool:
	return _built


func get_length() -> float:
	return _length


func get_half_width() -> float:
	if _half_ws.is_empty():
		return ROAD_HALF_W
	return _half_ws[0]


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
	return _make_sample(pos, yaw, s, 0.0, i)


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
	return _make_sample(_pts[best_i], yaw, _dists[best_i], lateral, best_i)


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
	if _pts.size() < 2:
		return
	_build_terrain()
	_build_road_mesh()
	_build_curbs()
	_build_obstacles()
	_build_narrow_signs()
	_build_finish_line()
	_built = true


func _ready() -> void:
	if GameState.selected_race_type == GameState.RACE_ROAD:
		build_road_course()


func _empty_sample() -> Dictionary:
	return _make_sample(Vector3.ZERO, 0.0, 0.0, 0.0)


func _make_sample(pos: Vector3, yaw: float, s: float, lateral: float, index: int = 0) -> Dictionary:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hw := ROAD_HALF_W
	var surface := TrackFile.SURFACE_REGULAR
	var rtype := TrackFile.ROAD_REGULAR
	if index >= 0 and index < _half_ws.size():
		hw = _half_ws[index]
		surface = _surfaces[index]
		rtype = _road_types[index]
	var extents := TrackFile.driveable_extents(hw * 2.0, rtype)
	return {
		"position": pos,
		"forward": forward,
		"right": right,
		"yaw": yaw,
		"s": s,
		"lateral": lateral,
		"half_width": hw,
		"left_ext": extents.x,
		"right_ext": extents.y,
		"surface": surface,
		"road_type": rtype,
		"obstacle_left": TrackFile.obstacle_left(rtype),
		"obstacle_right": TrackFile.obstacle_right(rtype),
	}


func _build_path() -> void:
	_pts.clear()
	_yaws.clear()
	_dists.clear()
	_half_ws.clear()
	_surfaces.clear()
	_road_types.clear()
	_pos = Vector3.ZERO
	_yaw = 0.0
	_length = 0.0
	var data := TrackFile.load_path(track_path)
	for warning in data.warnings:
		push_warning("[track] %s" % warning)
	if not data.errors.is_empty():
		for error_text in data.errors:
			push_error("[track] %s" % error_text)
		return
	var path_ids: Array = data.path_ids
	if path_ids.size() < 2:
		push_error("[track] Race path is too short.")
		return
	var n := path_ids.size()
	var pts: Array[Vector3] = []
	var roads: Array[Dictionary] = []
	for i in n:
		pts.append(TrackFile.world_position(data.nodes[int(path_ids[i])]))
	for i in range(n - 1):
		roads.append(TrackFile.find_road(data, int(path_ids[i]), int(path_ids[i + 1])))
	var cuts: PackedFloat32Array = PackedFloat32Array()
	cuts.resize(n)
	for i in range(1, n - 1):
		cuts[i] = _fillet_cut(pts[i - 1], pts[i], pts[i + 1])
	_apply_road(roads[0])
	_pos = pts[0]
	_yaw = atan2(pts[1].x - pts[0].x, pts[1].z - pts[0].z)
	_push_sample()
	for i in range(1, n - 1):
		var in_dir := (pts[i] - pts[i - 1])
		in_dir.y = 0.0
		if in_dir.length() > 0.0001:
			in_dir = in_dir.normalized()
		var out_dir := (pts[i + 1] - pts[i])
		out_dir.y = 0.0
		if out_dir.length() > 0.0001:
			out_dir = out_dir.normalized()
		var cut: float = cuts[i]
		_apply_road(roads[i - 1])
		if cut < 0.05:
			_append_to(pts[i])
			continue
		var p0 := pts[i] - in_dir * cut
		var p2 := pts[i] + out_dir * cut
		_append_to(p0)
		_append_bezier(p0, pts[i], p2, roads[i - 1], roads[i])
	_apply_road(roads[n - 2])
	_append_to(pts[n - 1])


func _apply_road(road: Dictionary) -> void:
	if road.is_empty():
		_seg_half_w = ROAD_HALF_W
		_seg_surface = TrackFile.SURFACE_REGULAR
		_seg_road_type = TrackFile.ROAD_REGULAR
		return
	_seg_half_w = maxf(float(road.get("width", TrackFile.DEFAULT_WIDTH)) * 0.5, 0.5)
	_seg_surface = str(road.get("surface", TrackFile.SURFACE_REGULAR))
	_seg_road_type = str(road.get("type", TrackFile.ROAD_REGULAR))


func _push_sample() -> void:
	_pts.append(_pos)
	_yaws.append(_yaw)
	_dists.append(_length)
	_half_ws.append(_seg_half_w)
	_surfaces.append(_seg_surface)
	_road_types.append(_seg_road_type)


func _append_to(dest: Vector3) -> void:
	var delta := dest - _pos
	delta.y = 0.0
	var dist := delta.length()
	if dist < 0.0001:
		return
	var dir := delta / dist
	_yaw = atan2(dir.x, dir.z)
	var left := dist
	while left > 0.0001:
		var step := minf(BAKE_STEP, left)
		_pos += dir * step
		_length += step
		_push_sample()
		left -= step


func _fillet_cut(prev_pt: Vector3, corner: Vector3, next_pt: Vector3) -> float:
	var incoming := corner - prev_pt
	var outgoing := next_pt - corner
	incoming.y = 0.0
	outgoing.y = 0.0
	var in_len := incoming.length()
	var out_len := outgoing.length()
	if in_len < 0.05 or out_len < 0.05:
		return 0.0
	var turn := incoming.normalized().dot(outgoing.normalized())
	var angle := acos(clampf(turn, -1.0, 1.0))
	if angle < FILLET_MIN_ANGLE:
		return 0.0
	return minf(FILLET_MAX_CUT, minf(in_len * FILLET_LEN_FRACTION, out_len * FILLET_LEN_FRACTION))


func _append_bezier(
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	road_in: Dictionary,
	road_out: Dictionary
) -> void:
	var approx := p0.distance_to(p1) + p1.distance_to(p2)
	var steps := maxi(10, int(ceil(approx / BAKE_STEP)))
	for k in range(1, steps + 1):
		var t := float(k) / float(steps)
		if t < 0.5:
			_apply_road(road_in)
		else:
			_apply_road(road_out)
		var omt := 1.0 - t
		var pos := p0 * (omt * omt) + p1 * (2.0 * omt * t) + p2 * (t * t)
		pos.y = 0.0
		var deriv := (p1 - p0) * (2.0 * omt) + (p2 - p1) * (2.0 * t)
		deriv.y = 0.0
		if deriv.length_squared() > 0.000001:
			_yaw = atan2(deriv.x, deriv.z)
		_length += _pos.distance_to(pos)
		_pos = pos
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
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	if not _pts.is_empty():
		min_x = _pts[0].x
		max_x = _pts[0].x
		min_z = _pts[0].z
		max_z = _pts[0].z
		for p in _pts:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
	var pad := 400.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(max_x - min_x + pad * 2.0, max_z - min_z + pad * 2.0)
	plane.material = _make_mat(TERRAIN_COLOR, 0.95)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = plane
	mi.position = Vector3((min_x + max_x) * 0.5, -0.08, (min_z + max_z) * 0.5)
	add_child(mi)


func _build_road_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(_pts.size() - 1):
		var yaw0: float = _yaws[i]
		var yaw1: float = _yaws[i + 1]
		var t0: String = _road_types[i] if i < _road_types.size() else TrackFile.ROAD_REGULAR
		var t1: String = _road_types[i + 1] if i + 1 < _road_types.size() else t0
		var hw0 := _half_ws[i] if i < _half_ws.size() else ROAD_HALF_W
		var hw1 := _half_ws[i + 1] if i + 1 < _half_ws.size() else hw0
		var e0 := TrackFile.driveable_extents(hw0 * 2.0, t0)
		var e1 := TrackFile.driveable_extents(hw1 * 2.0, t1)
		var r0 := Vector3(cos(yaw0), 0.0, -sin(yaw0))
		var r1 := Vector3(cos(yaw1), 0.0, -sin(yaw1))
		var l0 := _pts[i] - r0 * e0.x
		var rr0 := _pts[i] + r0 * e0.y
		var l1 := _pts[i + 1] - r1 * e1.x
		var rr1 := _pts[i + 1] + r1 * e1.y
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


func _sample_type(i: int) -> String:
	if i < 0 or i >= _road_types.size():
		return TrackFile.ROAD_REGULAR
	return _road_types[i]


func _sample_extents(i: int) -> Vector2:
	var hw := _half_ws[i] if i >= 0 and i < _half_ws.size() else ROAD_HALF_W
	return TrackFile.driveable_extents(hw * 2.0, _sample_type(i))


func _build_curbs() -> void:
	var red_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	var stone_i := 0
	var stride := maxi(1, int(round(CURB_L / BAKE_STEP)))
	var i := 0
	while i < _pts.size():
		var yaw: float = _yaws[i]
		var basis := Basis(Vector3.UP, yaw)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var ext := _sample_extents(i)
		var pos := _pts[i]
		_add_curb_stone(red_xforms, white_xforms, stone_i, basis, pos - right * ext.x)
		_add_curb_stone(red_xforms, white_xforms, stone_i + 1, basis, pos + right * ext.y)
		stone_i += 1
		i += stride
	for j in range(1, _pts.size()):
		var prev := _sample_extents(j - 1)
		var cur := _sample_extents(j)
		if absf(prev.x - cur.x) > 0.35:
			stone_i = _add_perp_curbs(red_xforms, white_xforms, stone_i, j, false, prev.x, cur.x)
		if absf(prev.y - cur.y) > 0.35:
			stone_i = _add_perp_curbs(red_xforms, white_xforms, stone_i, j, true, prev.y, cur.y)
	_add_box_multimesh(self, "CurbRed", Vector3(CURB_W, CURB_H, CURB_L), CURB_RED, red_xforms)
	_add_box_multimesh(self, "CurbWhite", Vector3(CURB_W, CURB_H, CURB_L), CURB_WHITE, white_xforms)


func _add_curb_stone(
	red_xforms: Array[Transform3D],
	white_xforms: Array[Transform3D],
	stone_i: int,
	basis: Basis,
	world: Vector3
) -> void:
	var xf := Transform3D(basis, world + Vector3(0.0, CURB_H * 0.5, 0.0))
	if stone_i % 2 == 0:
		red_xforms.append(xf)
	else:
		white_xforms.append(xf)


func _add_perp_curbs(
	red_xforms: Array[Transform3D],
	white_xforms: Array[Transform3D],
	stone_i: int,
	index: int,
	on_right: bool,
	ext_a: float,
	ext_b: float
) -> int:
	var yaw: float = _yaws[index]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var side := 1.0 if on_right else -1.0
	var along := right * side
	var basis := Basis(Vector3.UP, yaw + PI * 0.5)
	var a := minf(ext_a, ext_b)
	var b := maxf(ext_a, ext_b)
	var span := b - a
	var count := maxi(1, int(ceil(span / CURB_L)))
	var step := span / float(count)
	for k in count:
		var lat := a + (k + 0.5) * step
		_add_curb_stone(red_xforms, white_xforms, stone_i, basis, _pts[index] + along * lat)
		stone_i += 1
	return stone_i


func _build_obstacles() -> void:
	var orange := Color(0.93, 0.38, 0.06, 1)
	var white := Color(0.96, 0.96, 0.93, 1)
	var body_xforms: Array[Transform3D] = []
	var stripe_xforms: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "ConstructionBarriers"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"track_obstacle", true)
	add_child(body)
	const BARRIER_L := 1.25
	const BARRIER_H := 1.05
	const BARRIER_W := 0.48
	var stride := maxi(1, int(round(BARRIER_L / BAKE_STEP)))
	var i := 0
	while i < _pts.size():
		var rtype := _sample_type(i)
		var ext := _sample_extents(i)
		var yaw: float = _yaws[i]
		var basis := Basis(Vector3.UP, yaw)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		if TrackFile.obstacle_left(rtype):
			_place_edge_barrier(
				body, body_xforms, stripe_xforms, _pts[i], basis, -right,
				ext.x, BARRIER_L, BARRIER_H, BARRIER_W
			)
		if TrackFile.obstacle_right(rtype):
			_place_edge_barrier(
				body, body_xforms, stripe_xforms, _pts[i], basis, right,
				ext.y, BARRIER_L, BARRIER_H, BARRIER_W
			)
		i += stride
	for j in range(1, _pts.size()):
		var prev_t := _sample_type(j - 1)
		var cur_t := _sample_type(j)
		var prev := _sample_extents(j - 1)
		var cur := _sample_extents(j)
		if TrackFile.obstacle_left(prev_t) != TrackFile.obstacle_left(cur_t) or absf(prev.x - cur.x) > 0.35:
			if TrackFile.obstacle_left(prev_t) or TrackFile.obstacle_left(cur_t):
				_place_perp_barriers(
					body, body_xforms, stripe_xforms, j, false, prev.x, cur.x,
					BARRIER_L, BARRIER_H, BARRIER_W
				)
		if TrackFile.obstacle_right(prev_t) != TrackFile.obstacle_right(cur_t) or absf(prev.y - cur.y) > 0.35:
			if TrackFile.obstacle_right(prev_t) or TrackFile.obstacle_right(cur_t):
				_place_perp_barriers(
					body, body_xforms, stripe_xforms, j, true, prev.y, cur.y,
					BARRIER_L, BARRIER_H, BARRIER_W
				)
	_add_box_multimesh(self, "BarrierOrange", Vector3(BARRIER_W, BARRIER_H, BARRIER_L), orange, body_xforms)
	_add_box_multimesh(self, "BarrierStripe", Vector3(BARRIER_W + 0.04, 0.16, BARRIER_L + 0.04), white, stripe_xforms)


func _build_narrow_signs() -> void:
	const LEAD_M := 12.0
	const OUTSET := 1.15
	const TOE := 0.22
	var root := Node3D.new()
	root.name = "NarrowSigns"
	add_child(root)
	var sign_i := 0
	for j in range(1, _pts.size()):
		var prev_t := _sample_type(j - 1)
		var cur_t := _sample_type(j)
		var now_narrow := TrackFile.narrows_left(cur_t) or TrackFile.narrows_right(cur_t)
		var was_narrow := TrackFile.narrows_left(prev_t) or TrackFile.narrows_right(prev_t)
		if not now_narrow or was_narrow:
			continue
		var s := maxf(0.0, _dists[j] - LEAD_M)
		var sample := sample_at(s)
		var pos: Vector3 = sample["position"]
		var yaw: float = sample["yaw"]
		var right_v: Vector3 = sample["right"]
		var left_ext := float(sample["left_ext"])
		var right_ext := float(sample["right_ext"])
		var left_n := TrackFile.narrows_left(cur_t)
		var right_n := TrackFile.narrows_right(cur_t)
		_add_narrow_sign(
			root, "NarrowSignL%d" % sign_i,
			pos - right_v * (left_ext + OUTSET),
			yaw + TOE, left_n, right_n
		)
		_add_narrow_sign(
			root, "NarrowSignR%d" % sign_i,
			pos + right_v * (right_ext + OUTSET),
			yaw - TOE, left_n, right_n
		)
		sign_i += 1


func _add_narrow_sign(
	parent: Node3D,
	node_name: String,
	world: Vector3,
	yaw: float,
	left_narrows: bool,
	right_narrows: bool
) -> void:
	const POST_H := 3.45
	var sign := Node3D.new()
	sign.name = node_name
	sign.transform = Transform3D(Basis(Vector3.UP, yaw), world)
	parent.add_child(sign)
	_add_box(sign, "Post", Vector3(0.11, POST_H, 0.11), _make_mat(POST_COLOR, 0.4), Vector3(0.0, POST_H * 0.5, 0.0))
	var face := Node3D.new()
	face.name = "Face"
	face.position = Vector3(0.0, POST_H - 0.18, -0.08)
	face.scale = Vector3(2.0, 2.0, 2.0)
	sign.add_child(face)
	var border := _add_box(face, "Border", Vector3(1.2, 1.2, 0.03), _make_mat(Color(0.08, 0.08, 0.09), 0.45), Vector3(0.0, 0.0, 0.012))
	border.rotation.z = PI * 0.25
	var plate := _add_box(face, "Plate", Vector3(1.02, 1.02, 0.04), _make_mat(Color(0.96, 0.82, 0.08), 0.38), Vector3.ZERO)
	plate.rotation.z = PI * 0.25
	_add_narrow_pictogram(face, left_narrows, right_narrows)


func _add_narrow_pictogram(face: Node3D, left_narrows: bool, right_narrows: bool) -> void:
	var ink := _make_mat(Color(0.07, 0.07, 0.08), 0.5)
	var z := -0.036
	var left := _add_box(face, "EdgeL", Vector3(0.075, 0.62, 0.03), ink, Vector3(-0.2, 0.0, z))
	if left_narrows:
		left.rotation.z = -0.42
	var right := _add_box(face, "EdgeR", Vector3(0.075, 0.62, 0.03), ink, Vector3(0.2, 0.0, z))
	if right_narrows:
		right.rotation.z = 0.42


func _place_edge_barrier(
	body: StaticBody3D,
	body_xforms: Array[Transform3D],
	stripe_xforms: Array[Transform3D],
	center: Vector3,
	basis: Basis,
	outward: Vector3,
	driveable_ext: float,
	barrier_l: float,
	barrier_h: float,
	barrier_w: float
) -> void:
	var lat := driveable_ext + barrier_w * 0.5
	var pos := center + outward * lat + Vector3(0.0, barrier_h * 0.5, 0.0)
	var xf := Transform3D(basis, pos)
	body_xforms.append(xf)
	stripe_xforms.append(Transform3D(basis, pos + Vector3(0.0, 0.18, 0.0)))
	var hit := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(barrier_w, barrier_h, barrier_l)
	hit.shape = box
	hit.transform = xf
	body.add_child(hit)


func _place_perp_barriers(
	body: StaticBody3D,
	body_xforms: Array[Transform3D],
	stripe_xforms: Array[Transform3D],
	index: int,
	on_right: bool,
	ext_a: float,
	ext_b: float,
	barrier_l: float,
	barrier_h: float,
	barrier_w: float
) -> void:
	var yaw: float = _yaws[index]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var along := right if on_right else -right
	var basis := Basis(Vector3.UP, yaw + PI * 0.5)
	var a := minf(ext_a, ext_b)
	var b := maxf(ext_a, ext_b)
	var span := maxf(b - a, barrier_l)
	var count := maxi(1, int(ceil(span / barrier_l)))
	var step := span / float(count)
	for k in count:
		var lat := a + (k + 0.5) * step
		var pos := _pts[index] + along * lat + Vector3(0.0, barrier_h * 0.5, 0.0)
		var xf := Transform3D(basis, pos)
		body_xforms.append(xf)
		stripe_xforms.append(Transform3D(basis, pos + Vector3(0.0, 0.18, 0.0)))
	var hit := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(barrier_w, barrier_h, span)
	hit.shape = box
	var mid := (a + b) * 0.5
	hit.transform = Transform3D(basis, _pts[index] + along * mid + Vector3(0.0, barrier_h * 0.5, 0.0))
	body.add_child(hit)


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


func _add_box(parent: Node3D, node_name: String, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)
	return mi


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
