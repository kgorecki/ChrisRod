extends Node

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_GARAGE := "res://scenes/garage.tscn"
const SCENE_OPPONENT_SELECT := "res://scenes/opponent_select.tscn"
const SCENE_RACE := "res://scenes/race.tscn"

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

## Opponent presets for selection and race AI.
const OPPONENTS: Array[Dictionary] = [
	{"id": 0, "name": "Rival Nova", "accel": 12.0, "vmax": 58.0},
	{"id": 1, "name": "Street Hawk", "accel": 14.0, "vmax": 62.0},
	{"id": 2, "name": "Night Runner", "accel": 11.0, "vmax": 60.0},
]


func _ready() -> void:
	load_settings()


func new_game() -> void:
	car_name = "Basic Car 1"
	car_color = Color(0.15, 0.45, 0.85, 1.0)
	vmax_kmh = 220.0
	engine_power_hp = 280.0
	current_scene_path = SCENE_GARAGE
	selected_opponent_id = 0


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
	return true


func go_to_saved_scene(tree: SceneTree) -> void:
	var path := current_scene_path
	if path.is_empty() or not ResourceLoader.exists(path):
		path = SCENE_GARAGE
	tree.change_scene_to_file(path)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", _get_fullscreen())
	cfg.set_value("audio", "master_db", AudioServer.get_bus_volume_db(0))
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


func _get_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
