extends RefCounted

## Bumper contact between the two race cars. Overlap is pushed apart and
## closing speed is shared. The hit never stops a car or ends the race.

const CONTACT_MARGIN_M := 0.05
const SEPARATION_SLOP_M := 0.02
const MIN_OVERLAP_M := 0.01
const MIN_CLOSING_MPS := 0.25
const RESTITUTION := 0.2

func resolve(a: CharacterBody3D, b: CharacterBody3D) -> void:
	if a == null or b == null:
		return
	if not a.has_method(&"planar_velocity") or not a.has_method(&"apply_car_bump"):
		return
	if not b.has_method(&"planar_velocity") or not b.has_method(&"apply_car_bump"):
		return
	var box_a := _box(a)
	var box_b := _box(b)
	if box_a.is_empty() or box_b.is_empty():
		return
	var hit := _overlap(box_a, box_b)
	if hit.is_empty():
		return

	var normal := hit["normal"] as Vector2
	var depth := float(hit["depth"])
	var vel_a: Vector3 = a.planar_velocity()
	var vel_b: Vector3 = b.planar_velocity()
	var rel := Vector2(vel_b.x - vel_a.x, vel_b.z - vel_a.z).dot(normal)
	var offset_a := Vector3.ZERO
	var offset_b := Vector3.ZERO
	if depth > MIN_OVERLAP_M:
		var push := normal * (depth + SEPARATION_SLOP_M) * 0.5
		offset_a = Vector3(-push.x, 0.0, -push.y)
		offset_b = Vector3(push.x, 0.0, push.y)
	var new_a := vel_a
	var new_b := vel_b
	if rel < -MIN_CLOSING_MPS:
		# Equal mass. Each car takes half of the bounce; neither is wrecked.
		var change := -(1.0 + RESTITUTION) * rel * 0.5
		var delta := Vector3(normal.x, 0.0, normal.y) * change
		new_a = vel_a - delta
		new_b = vel_b + delta
	if offset_a.is_zero_approx() and offset_b.is_zero_approx() and new_a.is_equal_approx(vel_a):
		return
	a.apply_car_bump(offset_a, new_a)
	b.apply_car_bump(offset_b, new_b)


func _box(body: CharacterBody3D) -> Dictionary:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return {}
	var box := shape_node.shape as BoxShape3D
	var xf := shape_node.global_transform
	var scale := xf.basis.get_scale()
	var axis_x := Vector2(xf.basis.x.x, xf.basis.x.z)
	var axis_z := Vector2(xf.basis.z.x, xf.basis.z.z)
	if axis_x.length_squared() < 0.0001 or axis_z.length_squared() < 0.0001:
		return {}
	return {
		"center": Vector2(xf.origin.x, xf.origin.z),
		"axis_x": axis_x.normalized(),
		"axis_z": axis_z.normalized(),
		"half_x": box.size.x * absf(scale.x) * 0.5,
		"half_z": box.size.z * absf(scale.z) * 0.5,
	}


func _overlap(a: Dictionary, b: Dictionary) -> Dictionary:
	var best_depth := INF
	var best_offset := -1.0
	var best_normal := Vector2.RIGHT
	var axes: Array[Vector2] = [
		a["axis_x"] as Vector2,
		a["axis_z"] as Vector2,
		b["axis_x"] as Vector2,
		b["axis_z"] as Vector2,
	]
	var delta: Vector2 = (b["center"] as Vector2) - (a["center"] as Vector2)
	for axis in axes:
		if axis.length_squared() < 0.0001:
			continue
		var n := axis.normalized()
		var dist := delta.dot(n)
		var depth := _radius(a, n) + _radius(b, n) - absf(dist)
		if depth < -CONTACT_MARGIN_M:
			return {}
		# Equal overlap prefers the axis the cars are actually offset along,
		# so a rear hit pushes forward instead of sideways.
		var offset := absf(dist)
		var closer := depth < best_depth - 0.0001
		var tied := absf(depth - best_depth) <= 0.0001 and offset > best_offset
		if closer or tied:
			best_depth = depth
			best_offset = offset
			best_normal = n if dist >= 0.0 else -n
	return {"normal": best_normal, "depth": best_depth}


func _radius(box: Dictionary, axis: Vector2) -> float:
	var along_x := float(box["half_x"]) * absf((box["axis_x"] as Vector2).dot(axis))
	var along_z := float(box["half_z"]) * absf((box["axis_z"] as Vector2).dot(axis))
	return along_x + along_z
