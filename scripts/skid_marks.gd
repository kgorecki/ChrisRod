extends MeshInstance3D

## Dark strips on the ground while a tire is past its grip. Each wheel keeps
## its own strip, and a gap or a teleport starts a new one.

const _VehicleDynamics := preload("res://scripts/vehicle_dynamics.gd")

const MARK_Y := 0.035
const MIN_STEP := 0.15
const MAX_STEP := 2.4
const USE_MARK := 0.9
const MAX_VERTS := 9000

var _verts := PackedVector3Array()
var _colors := PackedColorArray()
var _points: Array[Vector3] = []
var _drawing: Array[bool] = []
var _dirty := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	material_override = mat


## One sample per wheel of a vehicle_dynamics car, in wheel order.
func record(wheels: Array, body: Transform3D) -> void:
	for i in wheels.size():
		var wheel: _VehicleDynamics.Wheel = wheels[i]
		var contact := Vector2(wheel.forward_velocity, wheel.lateral_velocity).length()
		stamp(
			i,
			body * wheel.local_position,
			wheel.grip_utilization,
			wheel.slip_angle,
			wheel.long_slip,
			contact,
			wheel.surface_blend
		)
	flush()


func end_strips() -> void:
	for i in _drawing.size():
		_drawing[i] = false


func stamp(
	index: int,
	world: Vector3,
	utilization: float,
	slip_angle: float,
	long_slip: float,
	contact_speed: float,
	surface_blend: float
) -> void:
	_ensure(index)
	var sliding := (
		utilization >= USE_MARK
		and contact_speed > 2.5
		and (absf(slip_angle) > 0.1 or absf(long_slip) > 1.05)
	)
	var point := Vector3(world.x, MARK_Y, world.z)
	if not sliding:
		_drawing[index] = false
		_points[index] = point
		return
	if _drawing[index]:
		var prev := _points[index]
		var delta := Vector3(point.x - prev.x, 0.0, point.z - prev.z)
		var dist := delta.length()
		if dist >= MIN_STEP and dist <= MAX_STEP:
			_add_quad(prev, point, delta / dist, utilization, surface_blend)
			_points[index] = point
			_dirty = true
		elif dist > MAX_STEP:
			_points[index] = point
	else:
		_points[index] = point
	_drawing[index] = true


func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	_trim()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built


func _ensure(index: int) -> void:
	while _points.size() <= index:
		_points.append(Vector3.ZERO)
		_drawing.append(false)


func _add_quad(a: Vector3, b: Vector3, forward: Vector3, utilization: float, surface_blend: float) -> void:
	var side := Vector3(-forward.z, 0.0, forward.x)
	var half := lerpf(0.09, 0.18, smoothstep(USE_MARK, 1.0, utilization))
	side *= half
	var alpha := lerpf(0.45, 0.9, smoothstep(USE_MARK, 1.0, utilization))
	var color := Color(0.015, 0.015, 0.015, alpha).lerp(Color(0.1, 0.11, 0.06, alpha), clampf(surface_blend, 0.0, 1.0))
	var a_left := a + side
	var a_right := a - side
	var b_left := b + side
	var b_right := b - side
	_push(a_left, color)
	_push(b_left, color)
	_push(b_right, color)
	_push(a_left, color)
	_push(b_right, color)
	_push(a_right, color)


func _push(point: Vector3, color: Color) -> void:
	_verts.push_back(point)
	_colors.push_back(color)


func _trim() -> void:
	var extra := _verts.size() - MAX_VERTS
	if extra <= 0:
		return
	extra -= extra % 6
	if extra <= 0:
		return
	_verts = _verts.slice(extra)
	_colors = _colors.slice(extra)
