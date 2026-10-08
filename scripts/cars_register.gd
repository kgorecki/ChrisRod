class_name CarsRegister
extends RefCounted

## Catalog of cars the newspaper can sell.
## Each entry names a `.car` file instead of copying the vehicle.

const CARS := "cars"

static var _cache: Dictionary = {}


static func load_path(path: String) -> Dictionary:
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if typeof(cached) == TYPE_DICTIONARY:
			return cached
	var loaded := _read(path)
	_cache[path] = loaded
	return loaded


static func _read(path: String) -> Dictionary:
	var result := _empty()
	result.source = path
	if path.is_empty():
		result.errors.append("Cars register path is empty.")
		return result
	if not FileAccess.file_exists(path):
		result.errors.append("Cars register not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Could not open cars register: %s" % path)
		return result
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Cars register root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.cars = _rows(root.get(CARS, []), result)
	return result


static func _rows(value: Variant, result: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Cars register '%s' must be a list." % CARS)
		return rows
	var seen: Dictionary = {}
	for item in value:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A car entry must be an object.")
			continue
		var car: Dictionary = item
		var car_id := str(car.get("id", ""))
		if car_id.is_empty():
			result.errors.append("A car entry is missing an id.")
			continue
		if seen.has(car_id):
			result.errors.append("Duplicate car id '%s'." % car_id)
			continue
		seen[car_id] = true
		var copy: Dictionary = car.duplicate()
		copy["id"] = car_id
		_apply_color(copy, result)
		rows.append(copy)
	return rows


static func _apply_color(car: Dictionary, result: Dictionary) -> void:
	var car_id := str(car.get("id", ""))
	var value: Variant = car.get("color", null)
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 3:
		result.errors.append("Car '%s' color must be [r, g, b] or [r, g, b, a]." % car_id)
		car.erase("color")
		return
	var nums: Array = value
	var alpha := 1.0
	if nums.size() >= 4:
		alpha = float(nums[3])
	car["color"] = Color(float(nums[0]), float(nums[1]), float(nums[2]), alpha)


static func _empty() -> Dictionary:
	return {
		"source": "",
		"cars": [],
		"errors": [],
	}
