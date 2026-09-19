extends Node

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_GARAGE := "res://scenes/garage.tscn"
const SCENE_OPPONENT_SELECT := "res://scenes/opponent_select.tscn"
const SCENE_RACE := "res://scenes/race.tscn"
const SCENE_NEWSPAPER := "res://scenes/newspaper.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"

const MUSIC_GARAGE := "res://assets/music/garage.mp3"
const MUSIC_RACE := "res://assets/music/race.mp3"

const RACE_DRAG := "drag"
const RACE_ROAD := "road"
const QUARTER_MILE_M := 402.336
const ROAD_RACE_LENGTH_M := QUARTER_MILE_M * 6.0

## Display name of the player's car.
var car_name: String = "Basic Car 1"
## Current paint color for the player's car.
var car_color: Color = Color(0.15, 0.45, 0.85, 1.0)
## Fixed stats (km/h and hp) for UI until tuning exists.
var vmax_kmh: float = 220.0
var engine_power_hp: float = 280.0

## Last scene to restore (garage, opponent_select, race).
var current_scene_path: String = SCENE_GARAGE
## Selected opponent id for the next race (0..2).
var selected_opponent_id: int = 0
## `RACE_DRAG` (straight quarter mile) or `RACE_ROAD` (turning course).
var selected_race_type: String = RACE_DRAG

## Whether background music is on. Persisted in settings; also toggled by the garage radio.
var music_enabled: bool = true

## Cash on hand for classifieds (parts and used cars).
var money: int = 2500
## Id of the car currently in the garage.
var current_car_id: String = "basic"
var owned_car_ids: Array[String] = ["basic"]
var owned_part_ids: Array[String] = []
var owned_gearbox_ids: Array[String] = ["gb_auto3"]
var equipped_gearbox_id: String = "gb_auto3"

## Opponent presets for selection and race AI.
## Scales are relative to the player's current effective vmax and 24 m/s² launch.
const OPPONENTS: Array[Dictionary] = [
	{"id": 0, "name": "Rival Nova", "accel_scale": 0.28, "vmax_scale": 0.86, "shift_time": 0.40},
	{"id": 1, "name": "Street Hawk", "accel_scale": 0.34, "vmax_scale": 0.94, "shift_time": 0.28},
	{"id": 2, "name": "Night Runner", "accel_scale": 0.26, "vmax_scale": 0.89, "shift_time": 0.36},
]

const PARTS: Array[Dictionary] = [
	{"id": "carb", "name": "Four-barrel carburetor", "price": 450, "hp": 25, "vmax": 4},
	{"id": "intake", "name": "Performance intake", "price": 320, "hp": 15, "vmax": 2},
	{"id": "exhaust", "name": "Headers & exhaust", "price": 380, "hp": 18, "vmax": 5},
	{"id": "cam", "name": "Racing camshaft", "price": 520, "hp": 30, "vmax": 6},
	{"id": "tires", "name": "Stickier slicks", "price": 280, "hp": 0, "vmax": 8},
]

const DEFAULT_GEARBOX_ID := "gb_auto3"

## Higher ratio = more launch, lower top speed in that gear.
## `top_speed` scales the car's vmax; more gears + a taller last gear raise it.
const GEARBOXES: Array[Dictionary] = [
	{
		"id": "gb_auto3",
		"name": "Automatic 3-speed",
		"price": 0,
		"automatic": true,
		"shift_time": 0.42,
		"top_speed": 0.82,
		"ratios": [2.52, 1.52, 1.00],
	},
	{
		"id": "gb_man3",
		"name": "3-speed manual",
		"price": 420,
		"automatic": false,
		"shift_time": 0.20,
		"top_speed": 0.88,
		"ratios": [2.98, 1.58, 1.00],
	},
	{
		"id": "gb_man4",
		"name": "4-speed manual",
		"price": 740,
		"automatic": false,
		"shift_time": 0.16,
		"top_speed": 0.95,
		"ratios": [3.15, 1.92, 1.34, 1.00],
	},
	{
		"id": "gb_man5",
		"name": "5-speed manual",
		"price": 1150,
		"automatic": false,
		"shift_time": 0.12,
		"top_speed": 1.00,
		"ratios": [3.28, 2.08, 1.48, 1.14, 0.89],
	},
	{
		"id": "gb_race5",
		"name": "5-speed racing",
		"price": 1850,
		"automatic": false,
		"shift_time": 0.07,
		"top_speed": 1.08,
		"ratios": [3.55, 2.22, 1.58, 1.18, 0.76],
	},
]

const USED_CARS: Array[Dictionary] = [
	{"id": "basic", "name": "Basic Car 1", "price": 0, "vmax": 220.0, "hp": 280.0, "color": Color(0.15, 0.45, 0.85, 1.0)},
	{"id": "coupe", "name": "Street Coupe", "price": 1800, "vmax": 235.0, "hp": 300.0, "color": Color(0.72, 0.12, 0.12, 1.0)},
	{"id": "roadster", "name": "Open Roadster", "price": 2400, "vmax": 245.0, "hp": 320.0, "color": Color(0.92, 0.78, 0.18, 1.0)},
	{"id": "hotrod", "name": "Shop Hot Rod", "price": 3600, "vmax": 260.0, "hp": 360.0, "color": Color(0.12, 0.12, 0.12, 1.0)},
]


var _music_player: AudioStreamPlayer
var _music_track: String = ""


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	load_settings()


func new_game() -> void:
	car_name = "Basic Car 1"
	car_color = Color(0.15, 0.45, 0.85, 1.0)
	vmax_kmh = 220.0
	engine_power_hp = 280.0
	current_scene_path = SCENE_GARAGE
	selected_opponent_id = 0
	selected_race_type = RACE_DRAG
	money = 2500
	current_car_id = "basic"
	owned_car_ids.clear()
	owned_car_ids.append("basic")
	owned_part_ids.clear()
	owned_gearbox_ids.clear()
	owned_gearbox_ids.append(DEFAULT_GEARBOX_ID)
	equipped_gearbox_id = DEFAULT_GEARBOX_ID
	refresh_car_stats()


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := {
		"version": 1,
		"car_name": car_name,
		"car_color": [car_color.r, car_color.g, car_color.b, car_color.a],
		"vmax_kmh": vmax_kmh,
		"engine_power_hp": engine_power_hp,
		"current_scene_path": current_scene_path,
		"selected_opponent_id": selected_opponent_id,
		"selected_race_type": selected_race_type,
		"money": money,
		"current_car_id": current_car_id,
		"owned_car_ids": owned_car_ids,
		"owned_part_ids": owned_part_ids,
		"owned_gearbox_ids": owned_gearbox_ids,
		"equipped_gearbox_id": equipped_gearbox_id,
	}
	var json := JSON.stringify(data)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % SAVE_PATH)
		return false
	f.store_string(json)
	f.close()
	return true


func load_game() -> bool:
	if not has_save_file():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	car_name = str(d.get("car_name", car_name))
	var loaded_color: Variant = d.get("car_color", null)
	if typeof(loaded_color) == TYPE_ARRAY and loaded_color.size() >= 3:
		var r := float(loaded_color[0])
		var g := float(loaded_color[1])
		var b := float(loaded_color[2])
		var a := float(loaded_color[3]) if loaded_color.size() >= 4 else 1.0
		car_color = Color(r, g, b, a)
	vmax_kmh = float(d.get("vmax_kmh", vmax_kmh))
	engine_power_hp = float(d.get("engine_power_hp", engine_power_hp))
	current_scene_path = str(d.get("current_scene_path", SCENE_GARAGE))
	selected_opponent_id = int(d.get("selected_opponent_id", 0))
	var race_type := str(d.get("selected_race_type", RACE_DRAG))
	if race_type == RACE_ROAD:
		selected_race_type = RACE_ROAD
	else:
		selected_race_type = RACE_DRAG
	money = int(d.get("money", money))
	current_car_id = str(d.get("current_car_id", current_car_id))
	owned_car_ids = _string_array(d.get("owned_car_ids", owned_car_ids))
	owned_part_ids = _string_array(d.get("owned_part_ids", owned_part_ids))
	owned_gearbox_ids = _string_array(d.get("owned_gearbox_ids", owned_gearbox_ids))
	equipped_gearbox_id = str(d.get("equipped_gearbox_id", equipped_gearbox_id))
	if owned_car_ids.is_empty():
		owned_car_ids = ["basic"]
	if owned_gearbox_ids.is_empty():
		owned_gearbox_ids = [DEFAULT_GEARBOX_ID]
	if listing_by_id(GEARBOXES, equipped_gearbox_id).is_empty():
		equipped_gearbox_id = DEFAULT_GEARBOX_ID
	if not owns_gearbox(equipped_gearbox_id):
		owned_gearbox_ids.append(equipped_gearbox_id)
	refresh_car_stats()
	return true


func listing_by_id(list: Array[Dictionary], item_id: String) -> Dictionary:
	for item in list:
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func owns_part(part_id: String) -> bool:
	return owned_part_ids.has(part_id)


func owns_car(car_id: String) -> bool:
	return owned_car_ids.has(car_id)


func owns_gearbox(gearbox_id: String) -> bool:
	return owned_gearbox_ids.has(gearbox_id)


func get_equipped_gearbox() -> Dictionary:
	var box: Dictionary = listing_by_id(GEARBOXES, equipped_gearbox_id)
	if box.is_empty():
		box = listing_by_id(GEARBOXES, DEFAULT_GEARBOX_ID)
	return box


func get_effective_vmax_kmh() -> float:
	return vmax_kmh * float(get_equipped_gearbox().get("top_speed", 1.0))


func gearbox_ratio_text(box: Dictionary) -> String:
	var ratios: Variant = box.get("ratios", [])
	if typeof(ratios) != TYPE_ARRAY:
		return ""
	var bits: Array[String] = []
	for ratio in ratios:
		bits.append("%.2f" % float(ratio))
	return " · ".join(bits)


func refresh_car_stats() -> void:
	var car: Dictionary = listing_by_id(USED_CARS, current_car_id)
	if car.is_empty():
		car = listing_by_id(USED_CARS, "basic")
	car_name = str(car.get("name", car_name))
	vmax_kmh = float(car.get("vmax", vmax_kmh))
	engine_power_hp = float(car.get("hp", engine_power_hp))
	for part_id in owned_part_ids:
		var part: Dictionary = listing_by_id(PARTS, part_id)
		if part.is_empty():
			continue
		vmax_kmh += float(part.get("vmax", 0.0))
		engine_power_hp += float(part.get("hp", 0.0))


func buy_part(part_id: String) -> String:
	var part: Dictionary = listing_by_id(PARTS, part_id)
	if part.is_empty():
		return "That part is not in the paper."
	if owns_part(part_id):
		return "Already bolted on."
	var price := int(part.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_part_ids.append(part_id)
	refresh_car_stats()
	return ""


func buy_or_equip_gearbox(gearbox_id: String) -> String:
	var box: Dictionary = listing_by_id(GEARBOXES, gearbox_id)
	if box.is_empty():
		return "That gearbox is not in the paper."
	if equipped_gearbox_id == gearbox_id:
		return "Already bolted on."
	if owns_gearbox(gearbox_id):
		equipped_gearbox_id = gearbox_id
		return ""
	var price := int(box.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_gearbox_ids.append(gearbox_id)
	equipped_gearbox_id = gearbox_id
	return ""


func buy_or_select_car(car_id: String) -> String:
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	if car.is_empty():
		return "That car is not listed."
	if current_car_id == car_id:
		return "Already in the garage."
	if owns_car(car_id):
		current_car_id = car_id
		refresh_car_stats()
		return ""
	var price := int(car.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_car_ids.append(car_id)
	current_car_id = car_id
	car_color = car.get("color", car_color)
	refresh_car_stats()
	return ""


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(str(item))
	return out


func go_to_saved_scene(tree: SceneTree) -> void:
	var path := current_scene_path
	if path.is_empty() or not ResourceLoader.exists(path):
		path = SCENE_GARAGE
	tree.change_scene_to_file(path)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", _get_fullscreen())
	cfg.set_value("audio", "master_db", AudioServer.get_bus_volume_db(0))
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if cfg.has_section_key("display", "fullscreen"):
		var fs: bool = cfg.get_value("display", "fullscreen")
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
		)
	if cfg.has_section_key("audio", "master_db"):
		AudioServer.set_bus_volume_db(0, float(cfg.get_value("audio", "master_db")))
	if cfg.has_section_key("audio", "music_enabled"):
		music_enabled = bool(cfg.get_value("audio", "music_enabled"))


func toggle_music() -> void:
	set_music_enabled(not music_enabled)


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	save_settings()
	update_music()


func update_music() -> void:
	var scene_path := current_scene_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var loaded := tree.current_scene.scene_file_path
		if not loaded.is_empty():
			scene_path = loaded
	var track := _track_for_scene(scene_path)
	if not music_enabled or track.is_empty():
		if _music_player != null:
			_music_player.stop()
		_music_track = ""
		return
	if _music_track == track and _music_player.playing:
		return
	var stream := load(track)
	if stream == null:
		push_warning("Music track missing: " + track)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_player.stream = stream
	_music_player.play()
	_music_track = track


func _track_for_scene(path: String) -> String:
	match path:
		SCENE_GARAGE:
			return MUSIC_GARAGE
		SCENE_RACE:
			return MUSIC_RACE
		_:
			return ""


func _get_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
