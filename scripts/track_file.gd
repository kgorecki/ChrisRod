class_name TrackFile
extends RefCounted

## Loader and validator for `.trk` race-track graphs.
## See `docs/track-format.md`.

const NODE_START := "start"
const NODE_FINISH := "finish"
const NODE_REGULAR := "regular"

const ROAD_REGULAR := "regular"
const ROAD_NARROW := "narrow"
const ROAD_NARROW_LEFT := "narrow-left"
const ROAD_NARROW_RIGHT := "narrow-right"
const ROAD_NARROW_BOTH := "narrow-both"
const ROAD_NARROW_OBSTACLE := "narrow-obstacle"
const ROAD_NARROW_LEFT_OBSTACLE := "narrow-left-obstacle"
const ROAD_NARROW_RIGHT_OBSTACLE := "narrow-right-obstacle"
const ROAD_NARROW_BOTH_OBSTACLE := "narrow-both-obstacle"

const SURFACE_REGULAR := "regular"
const SURFACE_DRY := "dry"
const SURFACE_WET := "wet"
const SURFACE_ICY := "icy"

const DEFAULT_WIDTH := 8.0

const _NODE_TYPES := [NODE_START, NODE_FINISH, NODE_REGULAR]
const _ROAD_TYPES := [
	ROAD_REGULAR,
	ROAD_NARROW,
	ROAD_NARROW_LEFT,
	ROAD_NARROW_RIGHT,
	ROAD_NARROW_BOTH,
	ROAD_NARROW_OBSTACLE,
	ROAD_NARROW_LEFT_OBSTACLE,
	ROAD_NARROW_RIGHT_OBSTACLE,
	ROAD_NARROW_BOTH_OBSTACLE,
]
const _SURFACES := [SURFACE_REGULAR, SURFACE_DRY, SURFACE_WET, SURFACE_ICY]


static func load_path(path: String) -> Dictionary:
	var empty := _empty_result()
	if path.is_empty():
		empty.errors.append("Track path is empty.")
		return empty
	if not FileAccess.file_exists(path):
		empty.errors.append("Track file not found: %s" % path)
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		empty.errors.append("Could not open track file: %s" % path)
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
		result.errors.append("Track root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.name = str(root.get("name", ""))
	_parse_nodes(root, result)
	_parse_roads(root, result)
	if result.errors.is_empty():
		_build_race_path(result)
	return result


static func world_position(node: Dictionary) -> Vector3:
	return Vector3(float(node.get("x", 0.0)), 0.0, float(node.get("y", 0.0)))


static func _empty_result() -> Dictionary:
	return {
		"source": "",
		"name": "",
		"nodes": {}, # id -> node dict
		"node_order": [], # ids in file order
		"roads": [],
		"start_id": 0,
		"finish_ids": [],
		"path_ids": [],
		"errors": [],
		"warnings": [],
	}


static func _parse_nodes(root: Dictionary, result: Dictionary) -> void:
	if not root.has("nodes") or typeof(root["nodes"]) != TYPE_ARRAY:
		result.errors.append("Track must contain a `nodes` array.")
		return
	for raw in root["nodes"]:
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Each node must be a JSON object.")
			continue
		var node: Dictionary = raw
		if not node.has("id"):
			result.errors.append("Node is missing `id`.")
			continue
		var id := int(node["id"])
		if result.nodes.has(id):
			result.errors.append("Duplicate node id %d." % id)
			continue
		if not node.has("x") or not node.has("y"):
			result.errors.append("Node %d must have numeric `x` and `y`." % id)
			continue
		var ntype := str(node.get("type", NODE_REGULAR)).strip_edges().to_lower()
		if ntype.is_empty():
			ntype = NODE_REGULAR
		if not _NODE_TYPES.has(ntype):
			result.warnings.append("Node %d has unknown type `%s`; using regular." % [id, ntype])
			ntype = NODE_REGULAR
		var parsed := {
			"id": id,
			"x": float(node["x"]),
			"y": float(node["y"]),
			"type": ntype,
		}
		result.nodes[id] = parsed
		result.node_order.append(id)
		if ntype == NODE_START:
			if result.start_id != 0:
				result.warnings.append("Multiple start nodes; keeping id %d." % result.start_id)
			else:
				result.start_id = id
		elif ntype == NODE_FINISH:
			result.finish_ids.append(id)
	if result.nodes.is_empty():
		result.errors.append("Track has no valid nodes.")
	if result.start_id == 0 and not result.node_order.is_empty():
		result.start_id = int(result.node_order[0])
		result.warnings.append("No start node; using first node %d." % result.start_id)
	if result.finish_ids.is_empty() and not result.node_order.is_empty():
		var last_id := int(result.node_order[result.node_order.size() - 1])
		result.finish_ids.append(last_id)
		result.warnings.append("No finish node; using last node %d." % last_id)


static func _parse_roads(root: Dictionary, result: Dictionary) -> void:
	if not root.has("roads") or typeof(root["roads"]) != TYPE_ARRAY:
		result.errors.append("Track must contain a `roads` array.")
		return
	for raw in root["roads"]:
		if typeof(raw) != TYPE_DICTIONARY:
			result.errors.append("Each road must be a JSON object.")
			continue
		var road: Dictionary = raw
		if not road.has("from") or not road.has("to"):
			result.errors.append("Road is missing `from` or `to`.")
			continue
		var from_id := int(road["from"])
		var to_id := int(road["to"])
		if not result.nodes.has(from_id) or not result.nodes.has(to_id):
			result.errors.append("Road %d -> %d references an unknown node." % [from_id, to_id])
			continue
		if from_id == to_id:
			result.errors.append("Road %d -> %d starts and ends on the same node." % [from_id, to_id])
			continue
		var rtype := str(road.get("type", ROAD_REGULAR)).strip_edges().to_lower()
		if rtype.is_empty():
			rtype = ROAD_REGULAR
		if rtype == ROAD_NARROW:
			rtype = ROAD_NARROW_BOTH
		elif rtype == ROAD_NARROW_OBSTACLE:
			rtype = ROAD_NARROW_BOTH_OBSTACLE
		if not _ROAD_TYPES.has(rtype):
			result.warnings.append(
				"Road %d -> %d has unknown type `%s`; using regular." % [from_id, to_id, rtype]
			)
			rtype = ROAD_REGULAR
		var surface := str(road.get("surface", SURFACE_REGULAR)).strip_edges().to_lower()
		if surface.is_empty():
			surface = SURFACE_REGULAR
		if not _SURFACES.has(surface):
			result.warnings.append(
				"Road %d -> %d has unknown surface `%s`; using regular." % [from_id, to_id, surface]
			)
			surface = SURFACE_REGULAR
		var width := DEFAULT_WIDTH
		if road.has("width"):
			width = float(road["width"])
		if width <= 0.0:
			result.warnings.append(
				"Road %d -> %d has non-positive width; using %.1f." % [from_id, to_id, DEFAULT_WIDTH]
			)
			width = DEFAULT_WIDTH
		result.roads.append({
			"from": from_id,
			"to": to_id,
			"width": width,
			"type": rtype,
			"surface": surface,
		})


static func _build_race_path(result: Dictionary) -> void:
	var outgoing: Dictionary = {}
	for road in result.roads:
		var from_id: int = road["from"]
		if not outgoing.has(from_id):
			outgoing[from_id] = []
		outgoing[from_id].append(road)
	var finish_set: Dictionary = {}
	for fid in result.finish_ids:
		finish_set[int(fid)] = true
	var path: Array[int] = []
	var used: Dictionary = {}
	var current: int = int(result.start_id)
	path.append(current)
	var guard := 0
	while guard < result.roads.size() + 2:
		guard += 1
		if finish_set.has(current) and path.size() > 1:
			break
		var choices: Array = outgoing.get(current, [])
		var next_road: Dictionary = {}
		for road in choices:
			var key := "%d>%d" % [road["from"], road["to"]]
			if used.has(key):
				continue
			next_road = road
			break
		if next_road.is_empty():
			break
		var key := "%d>%d" % [next_road["from"], next_road["to"]]
		used[key] = true
		current = int(next_road["to"])
		path.append(current)
	if path.size() < 2:
		result.errors.append("Could not walk a race path from start to finish.")
		return
	if not finish_set.has(path[path.size() - 1]):
		result.warnings.append("Race path does not end on a finish node.")
	result.path_ids = path


static func normalize_road_type(rtype: String) -> String:
	var t := rtype.strip_edges().to_lower()
	if t == ROAD_NARROW:
		return ROAD_NARROW_BOTH
	if t == ROAD_NARROW_OBSTACLE:
		return ROAD_NARROW_BOTH_OBSTACLE
	return t


static func narrows_left(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return (
		t == ROAD_NARROW_LEFT
		or t == ROAD_NARROW_BOTH
		or t == ROAD_NARROW_LEFT_OBSTACLE
		or t == ROAD_NARROW_BOTH_OBSTACLE
	)


static func narrows_right(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return (
		t == ROAD_NARROW_RIGHT
		or t == ROAD_NARROW_BOTH
		or t == ROAD_NARROW_RIGHT_OBSTACLE
		or t == ROAD_NARROW_BOTH_OBSTACLE
	)


static func obstacle_left(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return t == ROAD_NARROW_LEFT_OBSTACLE or t == ROAD_NARROW_BOTH_OBSTACLE


static func obstacle_right(rtype: String) -> bool:
	var t := normalize_road_type(rtype)
	return t == ROAD_NARROW_RIGHT_OBSTACLE or t == ROAD_NARROW_BOTH_OBSTACLE


## Driveable extents from the centerline: `x` = left, `y` = right, both positive.
static func driveable_extents(full_width: float, rtype: String) -> Vector2:
	var width := maxf(full_width, 1.0)
	var half := width * 0.5
	var inset := width / 3.0
	var left := half
	var right := half
	if narrows_left(rtype):
		left = maxf(half - inset, 0.4)
	if narrows_right(rtype):
		right = maxf(half - inset, 0.4)
	return Vector2(left, right)


static func find_road(result: Dictionary, from_id: int, to_id: int) -> Dictionary:
	for road in result.roads:
		if int(road["from"]) == from_id and int(road["to"]) == to_id:
			return road
	return {}
