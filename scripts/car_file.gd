class_name CarFile
extends RefCounted

## Loader for `.car` vehicle files (JSON). A car file names the body mesh,
## wheel mounts, and chassis numbers. Engines, transmissions, and wheels are
## ids into the parts register named by `register`.

const _PartsRegister := preload("res://scripts/parts_register.gd")


static func load_path(path: String) -> Dictionary:
	var empty := _empty_result()
	if path.is_empty():
		empty.errors.append("Car path is empty.")
		return empty
	if not FileAccess.file_exists(path):
		empty.errors.append("Car file not found: %s" % path)
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		empty.errors.append("Could not open car file: %s" % path)
		return empty
	var text := file.get_as_text()
	file.close()
	return parse_text(text, path)


static func parse_text(text: String, source: String = "") -> Dictionary:
	var result := _empty_result()
	result.source = source
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [
			source if not source.is_empty() else "<memory>",
			json.get_error_line(),
			json.get_error_message(),
		])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Car root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.id = str(root.get("id", ""))
	result.name = str(root.get("name", ""))
	if result.id.is_empty():
		result.errors.append("Car is missing an id.")
	_parse_model(root, result)
	_parse_wheels(root, result)
	_parse_parts(root, result)
	_parse_chassis(root, result)
	return result


static func _parse_model(root: Dictionary, result: Dictionary) -> void:
	var model: Variant = root.get("model", {})
	if typeof(model) != TYPE_DICTIONARY:
		result.errors.append("Car model must be an object.")
		return
	var body: Dictionary = model
	var path := str(body.get("path", ""))
	if path.is_empty():
		result.errors.append("Car model is missing a path.")
	result.model = {
		"path": path,
		"position": _vec3(body.get("position", [0.0, 0.55, 0.0])),
		"height": float(body.get("height", 5.0)),
	}


static func _parse_wheels(root: Dictionary, result: Dictionary) -> void:
	var wheels: Variant = root.get("wheels", {})
	if typeof(wheels) != TYPE_DICTIONARY:
		result.errors.append("Car wheels must be an object.")
		return
	var block: Dictionary = wheels
	var mounts: Variant = block.get("mounts", [])
	if typeof(mounts) != TYPE_ARRAY or (mounts as Array).is_empty():
		result.errors.append("Car wheels need at least one mount.")
		mounts = []
	var parsed: Array[Dictionary] = []
	for item in mounts:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A wheel mount must be an object.")
			continue
		var mount: Dictionary = item
		var node := str(mount.get("node", ""))
		if node.is_empty():
			result.errors.append("A wheel mount is missing a node name.")
			continue
		parsed.append({
			"node": node,
			"position": _vec3(mount.get("position", [0.0, 0.0, 0.0])),
			"rotation": _vec3(mount.get("rotation", [0.0, 0.0, 0.0])),
		})
	result.wheels = {
		"path": "",
		"scale": 1.0,
		"height": 0.5,
		"mounts": parsed,
	}


static func _parse_parts(root: Dictionary, result: Dictionary) -> void:
	var parts: Variant = root.get("parts", {})
	if typeof(parts) != TYPE_DICTIONARY:
		result.errors.append("Car parts must be an object.")
		return
	var block: Dictionary = parts
	var register_path := str(root.get("register", ""))
	result.register = register_path
	if register_path.is_empty():
		result.errors.append("Car is missing a parts register path.")
		return
	var register: Dictionary = _PartsRegister.load_path(register_path)
	var register_errors: Variant = register.get("errors", [])
	if typeof(register_errors) == TYPE_ARRAY:
		for err in register_errors:
			result.errors.append(str(err))
	if typeof(register_errors) == TYPE_ARRAY and not (register_errors as Array).is_empty():
		return
	result.engine = _resolve(register, _PartsRegister.ENGINES, block.get("engine", ""), "engine")
	result.transmission = _resolve(register, _PartsRegister.TRANSMISSIONS, block.get("transmission", ""), "transmission")
	var wheel_part := _resolve(register, _PartsRegister.WHEELS, block.get("wheels", ""), "wheels")
	if str(result.engine.get("id", "")).is_empty():
		result.errors.append("Car engine was not found in the parts register.")
	if str(result.transmission.get("id", "")).is_empty():
		result.errors.append("Car transmission was not found in the parts register.")
	if str(wheel_part.get("id", "")).is_empty():
		result.errors.append("Car wheels were not found in the parts register.")
		return
	var wheels: Dictionary = result.wheels
	wheels["path"] = str(wheel_part.get("path", ""))
	wheels["scale"] = float(wheel_part.get("scale", 1.0))
	wheels["height"] = float(wheel_part.get("height", 0.5))
	wheels["grip"] = clampf(float(wheel_part.get("grip", 3.0)), 1.0, 5.0)
	wheels["part"] = str(wheel_part.get("id", ""))
	if str(wheels.get("path", "")).is_empty():
		result.errors.append("Wheel part '%s' is missing a path." % str(wheel_part.get("id", "")))


static func _resolve(register: Dictionary, category: String, part_id: Variant, label: String) -> Dictionary:
	var id := str(part_id)
	if id.is_empty():
		return {}
	var found: Dictionary = _PartsRegister.find(register, category, id)
	if found.is_empty():
		return {}
	found["id"] = id
	found["slot"] = label
	return found


static func _parse_chassis(root: Dictionary, result: Dictionary) -> void:
	var chassis: Variant = root.get("chassis", {})
	if typeof(chassis) != TYPE_DICTIONARY:
		result.errors.append("Car chassis must be an object.")
		return
	var block: Dictionary = chassis
	result.chassis = {
		"mass": float(block.get("mass", 1360.0)),
		"wheelbase": float(block.get("wheelbase", 2.59)),
		"cg_height": float(block.get("cg_height", 0.48)),
		"front_axle_fraction": float(block.get("front_axle_fraction", 0.46)),
		"max_steer_deg": float(block.get("max_steer_deg", 30.0)),
	}


static func _vec3(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 3:
		return Vector3.ZERO
	var nums: Array = value
	return Vector3(float(nums[0]), float(nums[1]), float(nums[2]))


static func _empty_result() -> Dictionary:
	return {
		"source": "",
		"id": "",
		"name": "",
		"register": "",
		"model": {},
		"wheels": {},
		"engine": {},
		"transmission": {},
		"chassis": {},
		"errors": [],
	}
