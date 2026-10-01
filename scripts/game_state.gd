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
const DEFAULT_CAR_ID := "sr1-corvette-1956"
const MAX_OWNED_CARS := 16
const DEFAULT_TANK_L := 60.0
const FUEL_L_PER_KM := 5.0
const FUEL_PRICE_PER_L := 2
const PLAYER_CAR_FILE := "res://assets/cars/sr1-corvette-1956.car"
const PARTS_REGISTER := "res://assets/parts/parts.register"
const _CarFile := preload("res://scripts/car_file.gd")
const _PartsRegister := preload("res://scripts/parts_register.gd")

const RACE_DRAG := "drag"
const RACE_ROAD := "road"
const QUARTER_MILE_M := 402.336
const ROAD_RACE_LENGTH_M := QUARTER_MILE_M * 6.0

## Display name of the player's car.
var car_name: String = "Corvette 1956"
## Current paint color for the active car.
var car_color: Color = Color(0.78, 0.14, 0.14, 1.0)
## Fuel in the active car's tank, in liters.
var fuel: float = DEFAULT_TANK_L
## Fixed stats (km/h and hp) for UI until tuning exists.
var vmax_kmh: float = 220.0
var engine_power_hp: float = 280.0

## Last scene to restore (garage, opponent_select, race).
var current_scene_path: String = SCENE_GARAGE
## Selected opponent id for the next race (0..2).
var selected_opponent_id: int = 0
## `RACE_DRAG` (straight quarter mile) or `RACE_ROAD` (turning course).
var selected_race_type: String = RACE_DRAG
## The direct-speed driving model from before the tire simulation.
var arcade_drive: bool = true

## Whether background music is on. Persisted in settings; also toggled by the garage radio.
var music_enabled: bool = true

## Cash on hand for classifieds (parts and used cars).
var money: int = 2500
## Id of the car currently in the garage.
var current_car_id: String = DEFAULT_CAR_ID
var owned_car_ids: Array[String] = [DEFAULT_CAR_ID]
var owned_part_ids: Array[String] = []
var equipped_part_ids: Array[String] = []
var owned_gearbox_ids: Array[String] = ["gb_auto3"]
var equipped_gearbox_id: String = "gb_auto3"
var owned_engine_ids: Array[String] = ["v8-283"]
var equipped_engine_id: String = "v8-283"
var owned_wheel_ids: Array[String] = ["wheel-c1"]
var equipped_wheel_id: String = "wheel-c1"
## Paint, fuel, and mounted parts for each owned car. The fields above mirror the active car.
var car_records: Dictionary = {}
## Parsed `PLAYER_CAR_FILE`. Empty sections mean the file failed to load.
var car_spec: Dictionary = {}
## Paint for each listing during the current newspaper visit.
var newspaper_colors: Dictionary = {}

## Opponent presets for selection and race AI.
## Scales are relative to the player's current effective vmax and 24 m/s² launch.
const OPPONENTS: Array[Dictionary] = [
	{"id": 0, "name": "Rival Nova", "accel_scale": 0.28, "vmax_scale": 0.86, "shift_time": 0.40},
	{"id": 1, "name": "Street Hawk", "accel_scale": 0.34, "vmax_scale": 0.94, "shift_time": 0.28},
	{"id": 2, "name": "Night Runner", "accel_scale": 0.26, "vmax_scale": 0.89, "shift_time": 0.36},
]

const DEFAULT_GEARBOX_ID := "gb_auto3"

## Filled from `parts.register` at startup. The newspaper sells these lists.
var PARTS: Array[Dictionary] = []
var GEARBOXES: Array[Dictionary] = []
var ENGINES: Array[Dictionary] = []
var WHEELS: Array[Dictionary] = []

const USED_CARS: Array[Dictionary] = [
	{"id": DEFAULT_CAR_ID, "name": "Corvette 1956", "price": 0, "vmax": 220.0, "hp": 280.0, "color": Color(0.78, 0.14, 0.14, 1.0), "car_file": PLAYER_CAR_FILE},
	{"id": "fairlane-1957", "name": "Fairlane 500", "price": 1050, "vmax": 185.0, "hp": 230.0, "color": Color(0.91, 0.89, 0.82, 1.0), "car_file": "res://assets/cars/fairlane-1957.car"},
	{"id": "corvette-1962", "name": "Corvette 1962", "price": 1500, "vmax": 220.0, "hp": 280.0, "color": Color(0.15, 0.45, 0.85, 1.0), "car_file": "res://assets/cars/corvette-1962-1.car"},
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
	load_parts_register()
	load_player_car()
	if not car_records.has(current_car_id):
		_sync_record_from_active()


func load_parts_register() -> void:
	var register: Dictionary = _PartsRegister.load_path(PARTS_REGISTER)
	var errors: Variant = register.get("errors", [])
	if typeof(errors) == TYPE_ARRAY:
		for err in errors:
			push_error(str(err))
	PARTS = _dict_list(register.get("parts", []))
	GEARBOXES = _dict_list(register.get("transmissions", []))
	ENGINES = _dict_list(register.get("engines", []))
	WHEELS = _dict_list(register.get("wheels", []))


func _dict_list(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return rows
	for item in value:
		if typeof(item) == TYPE_DICTIONARY:
			var row: Dictionary = item
			rows.append(row)
	return rows


func current_car_file_path() -> String:
	return car_file_path(current_car_id)


func car_file_path(car_id: String) -> String:
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	var path := str(car.get("car_file", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return PLAYER_CAR_FILE
	return path


func load_player_car() -> void:
	car_spec = _CarFile.load_path(current_car_file_path())
	var errors: Variant = car_spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY:
		for err in errors:
			push_error(str(err))
	_ensure_stock_fitment()


func _ensure_stock_fitment() -> void:
	var engine_id := str(get_stock_engine().get("id", equipped_engine_id))
	var wheel_id := equipped_wheel_id
	var wheels: Variant = car_spec.get("wheels", {})
	if typeof(wheels) == TYPE_DICTIONARY:
		wheel_id = str((wheels as Dictionary).get("part", wheel_id))
	if not engine_id.is_empty() and not owned_engine_ids.has(engine_id):
		owned_engine_ids.append(engine_id)
	if equipped_engine_id.is_empty() or listing_by_id(ENGINES, equipped_engine_id).is_empty():
		equipped_engine_id = engine_id
	if not wheel_id.is_empty() and not owned_wheel_ids.has(wheel_id):
		owned_wheel_ids.append(wheel_id)
	if equipped_wheel_id.is_empty() or listing_by_id(WHEELS, equipped_wheel_id).is_empty():
		equipped_wheel_id = wheel_id


func get_stock_engine() -> Dictionary:
	var engine: Variant = car_spec.get("engine", {})
	if typeof(engine) != TYPE_DICTIONARY:
		return {}
	return engine


func get_stock_transmission() -> Dictionary:
	var box: Variant = car_spec.get("transmission", {})
	if typeof(box) != TYPE_DICTIONARY:
		return {}
	return box


func new_game() -> void:
	car_name = "Corvette 1956"
	car_color = Color(0.78, 0.14, 0.14, 1.0)
	fuel = DEFAULT_TANK_L
	vmax_kmh = 220.0
	engine_power_hp = 280.0
	current_scene_path = SCENE_GARAGE
	selected_opponent_id = 0
	selected_race_type = RACE_DRAG
	money = 2500
	current_car_id = DEFAULT_CAR_ID
	owned_car_ids = [DEFAULT_CAR_ID]
	owned_part_ids.clear()
	equipped_part_ids.clear()
	owned_gearbox_ids.clear()
	owned_engine_ids.clear()
	owned_wheel_ids.clear()
	equipped_gearbox_id = DEFAULT_GEARBOX_ID
	equipped_engine_id = ""
	equipped_wheel_id = ""
	car_records.clear()
	car_records[DEFAULT_CAR_ID] = _make_car_record(DEFAULT_CAR_ID, car_color)
	_install_car(DEFAULT_CAR_ID)


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := {
		"version": 2,
		"car_name": car_name,
		"car_color": [car_color.r, car_color.g, car_color.b, car_color.a],
		"fuel": fuel,
		"cars": _cars_for_save(),
		"vmax_kmh": vmax_kmh,
		"engine_power_hp": engine_power_hp,
		"current_scene_path": current_scene_path,
		"selected_opponent_id": selected_opponent_id,
		"selected_race_type": selected_race_type,
		"money": money,
		"current_car_id": current_car_id,
		"owned_car_ids": owned_car_ids,
		"owned_part_ids": owned_part_ids,
		"equipped_part_ids": equipped_part_ids,
		"owned_gearbox_ids": owned_gearbox_ids,
		"equipped_gearbox_id": equipped_gearbox_id,
		"owned_engine_ids": owned_engine_ids,
		"equipped_engine_id": equipped_engine_id,
		"owned_wheel_ids": owned_wheel_ids,
		"equipped_wheel_id": equipped_wheel_id,
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
	fuel = float(d.get("fuel", DEFAULT_TANK_L))
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
	current_car_id = _migrate_car_id(str(d.get("current_car_id", current_car_id)))
	owned_car_ids = _string_array(d.get("owned_car_ids", owned_car_ids))
	for i in owned_car_ids.size():
		owned_car_ids[i] = _migrate_car_id(owned_car_ids[i])
	owned_part_ids = _string_array(d.get("owned_part_ids", owned_part_ids))
	if d.has("equipped_part_ids"):
		equipped_part_ids = _string_array(d.get("equipped_part_ids", []))
	else:
		equipped_part_ids = owned_part_ids.duplicate()
	owned_gearbox_ids = _string_array(d.get("owned_gearbox_ids", owned_gearbox_ids))
	equipped_gearbox_id = str(d.get("equipped_gearbox_id", equipped_gearbox_id))
	owned_engine_ids = _string_array(d.get("owned_engine_ids", owned_engine_ids))
	equipped_engine_id = str(d.get("equipped_engine_id", equipped_engine_id))
	owned_wheel_ids = _string_array(d.get("owned_wheel_ids", owned_wheel_ids))
	equipped_wheel_id = str(d.get("equipped_wheel_id", equipped_wheel_id))
	if owned_car_ids.is_empty():
		owned_car_ids = [DEFAULT_CAR_ID]
	if owned_gearbox_ids.is_empty():
		owned_gearbox_ids = [DEFAULT_GEARBOX_ID]
	if listing_by_id(GEARBOXES, equipped_gearbox_id).is_empty():
		equipped_gearbox_id = DEFAULT_GEARBOX_ID
	if not owns_gearbox(equipped_gearbox_id):
		owned_gearbox_ids.append(equipped_gearbox_id)
	_load_saved_cars(d)
	load_player_car()
	_sync_record_from_active()
	refresh_car_stats()
	return true


func roll_newspaper_colors() -> void:
	newspaper_colors.clear()
	for car in USED_CARS:
		var car_id := str(car.get("id", ""))
		if car_id.is_empty():
			continue
		newspaper_colors[car_id] = _random_paint()


func newspaper_color(car_id: String) -> Color:
	var rolled: Variant = newspaper_colors.get(car_id, null)
	if rolled is Color:
		return rolled
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	var listed: Variant = car.get("color", null)
	if listed is Color:
		return listed
	return car_color


func _random_paint() -> Color:
	return Color.from_hsv(randf(), randf_range(0.55, 0.95), randf_range(0.45, 0.92))


func listing_by_id(list: Array[Dictionary], item_id: String) -> Dictionary:
	for item in list:
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func owns_part(part_id: String) -> bool:
	return owned_part_ids.has(part_id)


func is_part_equipped(part_id: String) -> bool:
	return equipped_part_ids.has(part_id)


func owns_car(car_id: String) -> bool:
	return owned_car_ids.has(car_id)


func owns_gearbox(gearbox_id: String) -> bool:
	return owned_gearbox_ids.has(gearbox_id)


func owns_engine(engine_id: String) -> bool:
	return owned_engine_ids.has(engine_id)


func owns_wheel(wheel_id: String) -> bool:
	return owned_wheel_ids.has(wheel_id)


func get_equipped_engine() -> Dictionary:
	var engine: Dictionary = listing_by_id(ENGINES, equipped_engine_id)
	if engine.is_empty():
		return get_stock_engine()
	return engine


func get_equipped_wheel() -> Dictionary:
	var wheel: Dictionary = listing_by_id(WHEELS, equipped_wheel_id)
	if wheel.is_empty():
		return {}
	return wheel


func get_equipped_gearbox() -> Dictionary:
	var stock := get_stock_transmission()
	if equipped_gearbox_id == str(stock.get("id", "")) and not stock.is_empty():
		return stock
	var box: Dictionary = listing_by_id(GEARBOXES, equipped_gearbox_id)
	if box.is_empty():
		if not stock.is_empty():
			return stock
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
		car = listing_by_id(USED_CARS, DEFAULT_CAR_ID)
	car_name = str(car.get("name", car_name))
	vmax_kmh = float(car.get("vmax", vmax_kmh))
	engine_power_hp = float(car.get("hp", engine_power_hp))
	var engine := get_equipped_engine()
	if not engine.is_empty():
		if current_car_id == DEFAULT_CAR_ID:
			car_name = str(car_spec.get("name", car_name))
		vmax_kmh = float(engine.get("vmax", vmax_kmh))
		engine_power_hp = float(engine.get("hp", engine_power_hp))
	for part_id in equipped_part_ids:
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
		return "Already in spare parts."
	var price := int(part.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_part_ids.append(part_id)
	return ""


func equip_part(part_id: String) -> String:
	if not owns_part(part_id):
		return "That part is not in spare parts."
	if is_part_equipped(part_id):
		return "Already on the car."
	equipped_part_ids.append(part_id)
	_take_mount_from_other_cars("part", part_id)
	_sync_record_from_active()
	refresh_car_stats()
	return ""


func buy_or_equip_gearbox(gearbox_id: String) -> String:
	var box: Dictionary = listing_by_id(GEARBOXES, gearbox_id)
	if box.is_empty():
		return "That gearbox is not in the paper."
	if equipped_gearbox_id == gearbox_id:
		return "Already on the car."
	if owns_gearbox(gearbox_id):
		equipped_gearbox_id = gearbox_id
		_take_mount_from_other_cars("transmission", gearbox_id)
		_sync_record_from_active()
		refresh_car_stats()
		return ""
	var price := int(box.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_gearbox_ids.append(gearbox_id)
	return ""


func buy_or_equip_engine(engine_id: String) -> String:
	return _buy_or_equip(ENGINES, owned_engine_ids, engine_id, "engine")


func buy_or_equip_wheel(wheel_id: String) -> String:
	return _buy_or_equip(WHEELS, owned_wheel_ids, wheel_id, "wheel")


func _buy_or_equip(list: Array[Dictionary], owned: Array[String], part_id: String, label: String) -> String:
	var part: Dictionary = listing_by_id(list, part_id)
	if part.is_empty():
		return "That %s is not in the register." % label
	var equipped := equipped_engine_id if label == "engine" else equipped_wheel_id
	if equipped == part_id:
		return "Already on the car."
	if not owned.has(part_id):
		var price := int(part.get("price", 0))
		if money < price:
			return "Not enough cash."
		money -= price
		owned.append(part_id)
		return ""
	if label == "engine":
		equipped_engine_id = part_id
		_take_mount_from_other_cars("engine", part_id)
	else:
		equipped_wheel_id = part_id
		_take_mount_from_other_cars("wheels", part_id)
	_sync_record_from_active()
	refresh_car_stats()
	return ""


func set_car_color(next: Color) -> void:
	car_color = next
	_sync_record_from_active()


func set_fuel(amount: float) -> void:
	fuel = clampf(amount, 0.0, DEFAULT_TANK_L)
	_sync_record_from_active()


func race_length_m(race_type: String = "") -> float:
	var kind := selected_race_type if race_type.is_empty() else race_type
	if kind == RACE_ROAD:
		return ROAD_RACE_LENGTH_M
	return QUARTER_MILE_M


func race_fuel_liters(race_type: String = "") -> float:
	var liters := race_length_m(race_type) / 1000.0 * FUEL_L_PER_KM
	return maxf(round(liters), 1.0)


func has_fuel_for_race(race_type: String = "") -> bool:
	return fuel + 0.05 >= race_fuel_liters(race_type)


func consume_race_fuel(race_type: String = "") -> void:
	set_fuel(fuel - race_fuel_liters(race_type))


func refuel_price() -> int:
	var missing := DEFAULT_TANK_L - fuel
	if missing <= 0.05:
		return 0
	return maxi(int(ceil(missing * float(FUEL_PRICE_PER_L))), 1)


func refuel_tank() -> String:
	var price := refuel_price()
	if price <= 0:
		return "The tank is already full."
	if money < price:
		return "Not enough cash."
	money -= price
	set_fuel(DEFAULT_TANK_L)
	return ""


func buy_or_select_car(car_id: String) -> String:
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	if car.is_empty():
		return "That car is not listed."
	_sync_record_from_active()
	if current_car_id == car_id:
		return "Already in the garage."
	if owns_car(car_id):
		current_car_id = car_id
		_install_car(car_id)
		return ""
	if owned_car_ids.size() >= MAX_OWNED_CARS:
		return "The garage holds %d cars." % MAX_OWNED_CARS
	var price := int(car.get("price", 0))
	if money < price:
		return "Not enough cash."
	money -= price
	owned_car_ids.append(car_id)
	current_car_id = car_id
	car_records[car_id] = _make_car_record(car_id, newspaper_color(car_id))
	_install_car(car_id)
	return ""


func _install_car(car_id: String) -> void:
	_apply_fields_from_record(car_id)
	load_player_car()
	_sync_record_from_active()
	refresh_car_stats()


func _make_car_record(car_id: String, paint: Color) -> Dictionary:
	var engine_id := _stock_part_id(car_id, "engine")
	var gearbox_id := _stock_part_id(car_id, "transmission")
	var wheel_id := _stock_part_id(car_id, "wheels")
	if gearbox_id.is_empty():
		gearbox_id = DEFAULT_GEARBOX_ID
	_remember_stock_ids(engine_id, gearbox_id, wheel_id)
	var parts: Array[String] = []
	return {
		"color": paint,
		"fuel": DEFAULT_TANK_L,
		"engine_id": engine_id,
		"gearbox_id": gearbox_id,
		"wheel_id": wheel_id,
		"part_ids": parts,
	}


func _remember_stock_ids(engine_id: String, gearbox_id: String, wheel_id: String) -> void:
	if not engine_id.is_empty() and not owned_engine_ids.has(engine_id):
		owned_engine_ids.append(engine_id)
	if not gearbox_id.is_empty() and not owned_gearbox_ids.has(gearbox_id):
		owned_gearbox_ids.append(gearbox_id)
	if not wheel_id.is_empty() and not owned_wheel_ids.has(wheel_id):
		owned_wheel_ids.append(wheel_id)


func _stock_part_id(car_id: String, slot: String) -> String:
	var spec := _CarFile.load_path(car_file_path(car_id))
	var errors: Variant = spec.get("errors", [])
	if typeof(errors) == TYPE_ARRAY and not (errors as Array).is_empty():
		return ""
	if slot == "engine":
		var engine: Variant = spec.get("engine", {})
		if typeof(engine) == TYPE_DICTIONARY:
			return str((engine as Dictionary).get("id", ""))
		return ""
	if slot == "transmission":
		var box: Variant = spec.get("transmission", {})
		if typeof(box) == TYPE_DICTIONARY:
			return str((box as Dictionary).get("id", ""))
		return ""
	if slot == "wheels":
		var wheels: Variant = spec.get("wheels", {})
		if typeof(wheels) == TYPE_DICTIONARY:
			return str((wheels as Dictionary).get("part", ""))
	return ""


func _listed_color(car_id: String) -> Color:
	var car: Dictionary = listing_by_id(USED_CARS, car_id)
	var listed: Variant = car.get("color", null)
	if listed is Color:
		return listed
	return Color(0.78, 0.14, 0.14, 1.0)


func _sync_record_from_active() -> void:
	if current_car_id.is_empty():
		return
	var rec: Dictionary = {}
	var existing: Variant = car_records.get(current_car_id, null)
	if typeof(existing) == TYPE_DICTIONARY:
		rec = existing
	else:
		rec = _make_car_record(current_car_id, car_color)
	rec["color"] = car_color
	rec["fuel"] = fuel
	rec["engine_id"] = equipped_engine_id
	rec["gearbox_id"] = equipped_gearbox_id
	rec["wheel_id"] = equipped_wheel_id
	rec["part_ids"] = equipped_part_ids.duplicate()
	car_records[current_car_id] = rec


func _apply_fields_from_record(car_id: String) -> void:
	var existing: Variant = car_records.get(car_id, null)
	if typeof(existing) != TYPE_DICTIONARY:
		car_records[car_id] = _make_car_record(car_id, _listed_color(car_id))
	var rec: Dictionary = car_records[car_id]
	var paint: Variant = rec.get("color", car_color)
	if paint is Color:
		car_color = paint
	fuel = float(rec.get("fuel", DEFAULT_TANK_L))
	equipped_engine_id = str(rec.get("engine_id", equipped_engine_id))
	equipped_gearbox_id = str(rec.get("gearbox_id", equipped_gearbox_id))
	equipped_wheel_id = str(rec.get("wheel_id", equipped_wheel_id))
	equipped_part_ids = _string_array(rec.get("part_ids", []))


func _take_mount_from_other_cars(slot: String, part_id: String) -> void:
	if part_id.is_empty():
		return
	for raw_id in car_records.keys():
		var car_id := str(raw_id)
		if car_id == current_car_id:
			continue
		var stored: Variant = car_records[raw_id]
		if typeof(stored) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = stored
		if slot == "part":
			var kept: Array[String] = []
			for item in _string_array(rec.get("part_ids", [])):
				if item != part_id:
					kept.append(item)
			rec["part_ids"] = kept
			car_records[car_id] = rec
			continue
		var key := "engine_id"
		if slot == "transmission":
			key = "gearbox_id"
		elif slot == "wheels":
			key = "wheel_id"
		if str(rec.get(key, "")) != part_id:
			continue
		var stock := _stock_part_id(car_id, slot)
		if part_id == stock:
			continue
		rec[key] = stock
		car_records[car_id] = rec


func _cars_for_save() -> Dictionary:
	_sync_record_from_active()
	var out := {}
	for raw_id in car_records.keys():
		var stored: Variant = car_records[raw_id]
		if typeof(stored) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = stored
		var paint: Color = car_color
		var stored_paint: Variant = rec.get("color", null)
		if stored_paint is Color:
			paint = stored_paint
		out[str(raw_id)] = {
			"color": [paint.r, paint.g, paint.b, paint.a],
			"fuel": float(rec.get("fuel", fuel)),
			"engine_id": str(rec.get("engine_id", "")),
			"gearbox_id": str(rec.get("gearbox_id", "")),
			"wheel_id": str(rec.get("wheel_id", "")),
			"part_ids": _string_array(rec.get("part_ids", [])),
		}
	return out


func _load_saved_cars(d: Dictionary) -> void:
	car_records.clear()
	var saved: Variant = d.get("cars", null)
	if typeof(saved) == TYPE_DICTIONARY:
		var rows: Dictionary = saved
		for key in rows.keys():
			var row: Variant = rows[key]
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var car_id := _migrate_car_id(str(key))
			car_records[car_id] = _record_from_save(row)
	for car_id in owned_car_ids:
		if car_records.has(car_id):
			continue
		if car_id == current_car_id:
			car_records[car_id] = _record_from_active_snapshot()
		else:
			car_records[car_id] = _make_car_record(car_id, _listed_color(car_id))
	if not car_records.has(current_car_id):
		car_records[current_car_id] = _record_from_active_snapshot()
	_apply_fields_from_record(current_car_id)


func _record_from_save(row: Dictionary) -> Dictionary:
	return {
		"color": _color_from_save(row.get("color", null), car_color),
		"fuel": float(row.get("fuel", DEFAULT_TANK_L)),
		"engine_id": str(row.get("engine_id", "")),
		"gearbox_id": str(row.get("gearbox_id", "")),
		"wheel_id": str(row.get("wheel_id", "")),
		"part_ids": _string_array(row.get("part_ids", [])),
	}


func _record_from_active_snapshot() -> Dictionary:
	return {
		"color": car_color,
		"fuel": fuel,
		"engine_id": equipped_engine_id,
		"gearbox_id": equipped_gearbox_id,
		"wheel_id": equipped_wheel_id,
		"part_ids": equipped_part_ids.duplicate(),
	}


func _color_from_save(value: Variant, fallback: Color) -> Color:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 3:
		return fallback
	var nums: Array = value
	var a := 1.0
	if nums.size() >= 4:
		a = float(nums[3])
	return Color(float(nums[0]), float(nums[1]), float(nums[2]), a)


func _migrate_car_id(car_id: String) -> String:
	if car_id == "basic":
		return "corvette-1962"
	if car_id == "vette-1956":
		return DEFAULT_CAR_ID
	return car_id


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
	cfg.set_value("game", "arcade_drive", arcade_drive)
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
	if cfg.has_section_key("game", "arcade_drive"):
		arcade_drive = bool(cfg.get_value("game", "arcade_drive"))


func toggle_music() -> void:
	set_music_enabled(not music_enabled)


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	save_settings()
	update_music()


func set_arcade_drive(enabled: bool) -> void:
	arcade_drive = enabled
	save_settings()


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
	if path == SCENE_RACE:
		return MUSIC_RACE
	return MUSIC_GARAGE


func _get_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
