class_name PartsRegister
extends RefCounted

## Catalog of engines, transmissions, wheels, and bolt-on parts.
## `.car` files reference entries by id instead of copying them.

const ENGINES := "engines"
const TRANSMISSIONS := "transmissions"
const WHEELS := "wheels"
const PARTS := "parts"

static var _cache: Dictionary = {}


static func load_path(path: String) -> Dictionary:
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if typeof(cached) == TYPE_DICTIONARY:
			return cached
	var loaded := _read(path)
	_cache[path] = loaded
	return loaded


static func find(register: Dictionary, category: String, part_id: String) -> Dictionary:
	var rows: Variant = register.get(category, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = item
		if str(part.get("id", "")) == part_id:
			return part
	return {}


static func _read(path: String) -> Dictionary:
	var result := _empty()
	result.source = path
	if path.is_empty():
		result.errors.append("Parts register path is empty.")
		return result
	if not FileAccess.file_exists(path):
		result.errors.append("Parts register not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Could not open parts register: %s" % path)
		return result
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Parts register root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.engines = _rows(root.get(ENGINES, []), ENGINES, result)
	result.transmissions = _rows(root.get(TRANSMISSIONS, []), TRANSMISSIONS, result)
	result.wheels = _rows(root.get(WHEELS, []), WHEELS, result)
	result.parts = _rows(root.get(PARTS, []), PARTS, result)
	return result


static func _rows(value: Variant, category: String, result: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Parts register '%s' must be a list." % category)
		return rows
	var seen: Dictionary = {}
	for item in value:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A %s entry must be an object." % category)
			continue
		var part: Dictionary = item
		var part_id := str(part.get("id", ""))
		if part_id.is_empty():
			result.errors.append("A %s entry is missing an id." % category)
			continue
		if seen.has(part_id):
			result.errors.append("Duplicate %s id '%s'." % [category, part_id])
			continue
		seen[part_id] = true
		var copy: Dictionary = part.duplicate()
		copy["id"] = part_id
		rows.append(copy)
	return rows


static func _empty() -> Dictionary:
	return {
		"source": "",
		"engines": [],
		"transmissions": [],
		"wheels": [],
		"parts": [],
		"errors": [],
	}
