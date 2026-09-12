extends Node3D

## Matches Ground in race.tscn: BoxMesh (40, 1, 520) centered at (0, -0.5, 210).
const GROUND_HALF_W := 20.0
const GROUND_Z_MIN := -50.0
const GROUND_Z_MAX := 470.0
const FINISH_Z := 402.336

const CURB_W := 0.45
const CURB_H := 0.16
const CURB_L := 2.0
const CURB_RED := Color(0.82, 0.12, 0.12, 1)
const CURB_WHITE := Color(0.92, 0.92, 0.9, 1)

const CHECK_BLACK := Color(0.06, 0.06, 0.07, 1)
const CHECK_WHITE := Color(0.94, 0.94, 0.92, 1)
const POST_COLOR := Color(0.12, 0.12, 0.13, 1)


func _ready() -> void:
	if GameState.selected_race_type == GameState.RACE_ROAD:
		return
	_build_curbs()
	_build_finish_line()


func _make_mat(color: Color, roughness: float = 0.72) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _build_curbs() -> void:
	var left_x := -(GROUND_HALF_W - CURB_W * 0.5)
	var right_x := GROUND_HALF_W - CURB_W * 0.5
	var count: int = int((GROUND_Z_MAX - GROUND_Z_MIN) / CURB_L)
	var red_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	var y := CURB_H * 0.5
	for i in count:
		var z := GROUND_Z_MIN + CURB_L * (i + 0.5)
		var xform_l := Transform3D(Basis.IDENTITY, Vector3(left_x, y, z))
		var xform_r := Transform3D(Basis.IDENTITY, Vector3(right_x, y, z))
		if i % 2 == 0:
			red_xforms.append(xform_l)
			white_xforms.append(xform_r)
		else:
			white_xforms.append(xform_l)
			red_xforms.append(xform_r)
	_add_curb_multimesh("CurbRed", CURB_RED, red_xforms)
	_add_curb_multimesh("CurbWhite", CURB_WHITE, white_xforms)


func _add_curb_multimesh(node_name: String, color: Color, xforms: Array[Transform3D]) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(CURB_W, CURB_H, CURB_L)
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
	add_child(mmi)


func _build_finish_line() -> void:
	var root := Node3D.new()
	root.name = "FinishLineVisual"
	root.position = Vector3(0.0, 0.0, FINISH_Z)
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
	var y := 0.02
	var black_xforms: Array[Transform3D] = []
	var white_xforms: Array[Transform3D] = []
	for row in ROWS:
		for col in COLS:
			var pos := Vector3(
				origin_x + (col + 0.5) * SQUARE,
				y,
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
