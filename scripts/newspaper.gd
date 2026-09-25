extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")

const SECTION_INDEX := "index"
const SECTION_CARS := "cars"
const SECTION_PARTS := "parts"

@onready var _cash: Label = %CashLabel
@onready var _parts_list: VBoxContainer = %PartsList
@onready var _cars_list: VBoxContainer = %CarsList
@onready var _status: Label = %StatusLabel
@onready var _index_section: VBoxContainer = %IndexSection
@onready var _cars_section: VBoxContainer = %CarsSection
@onready var _parts_section: VBoxContainer = %PartsSection
@onready var _back_button: Button = $Margin/VBox/BackButton

var _section: String = SECTION_INDEX
var _nav = _MenuNav.new()


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_NEWSPAPER
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_section(SECTION_INDEX)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_on_back_pressed()
		return
	if _nav.handle_event(self, event):
		accept_event()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	var code: Key = key.keycode
	if code == KEY_U or code == KEY_C:
		_show_section(SECTION_CARS)
		_mark_input_handled()
	elif code == KEY_P:
		_show_section(SECTION_PARTS)
		_mark_input_handled()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _refresh() -> void:
	_cash.text = "Cash on hand: $%d" % GameState.money
	_rebuild_parts()
	_rebuild_cars()
	_wire_menu()


func _rebuild_parts() -> void:
	for child in _parts_list.get_children():
		child.queue_free()
	_parts_list.add_child(_heading("ENGINES"))
	for engine in GameState.ENGINES:
		_parts_list.add_child(_make_engine_card(engine))
	_parts_list.add_child(_heading("TRANSMISSIONS"))
	for box in GameState.GEARBOXES:
		_parts_list.add_child(_make_gearbox_card(box))
	_parts_list.add_child(_heading("WHEELS"))
	for wheel in GameState.WHEELS:
		_parts_list.add_child(_make_wheel_card(wheel))
	_parts_list.add_child(_heading("ENGINE & CHASSIS"))
	for part in GameState.PARTS:
		_parts_list.add_child(_make_part_card(part))


func _rebuild_cars() -> void:
	for child in _cars_list.get_children():
		child.queue_free()
	for car in GameState.USED_CARS:
		_cars_list.add_child(_make_car_card(car))


func _make_part_card(part: Dictionary) -> Control:
	var part_id := str(part.get("id", ""))
	var owned := GameState.owns_part(part_id)
	var equipped := GameState.is_part_equipped(part_id)
	var price := int(part.get("price", 0))
	var box := _card()
	box.add_child(_heading(str(part.get("name", "Part"))))
	box.add_child(_body("+%d hp   +%d km/h" % [int(part.get("hp", 0)), int(part.get("vmax", 0))]))
	var btn := _ink_button()
	if equipped:
		btn.text = "On the car"
		btn.disabled = true
	elif owned:
		btn.text = "In spare parts"
		btn.disabled = true
	else:
		btn.text = "Buy — $%d" % price
		btn.disabled = GameState.money < price
		btn.pressed.connect(_on_buy_part.bind(part_id))
	box.add_child(btn)
	return box


func _make_gearbox_card(box: Dictionary) -> Control:
	var gearbox_id := str(box.get("id", ""))
	var equipped := GameState.equipped_gearbox_id == gearbox_id
	var owned := GameState.owns_gearbox(gearbox_id)
	var price := int(box.get("price", 0))
	var gears: Variant = box.get("ratios", [])
	var gear_count := 0
	if typeof(gears) == TYPE_ARRAY:
		gear_count = gears.size()
	var kind := "automatic" if bool(box.get("automatic", false)) else "manual"
	var top_pct := int(round(float(box.get("top_speed", 1.0)) * 100.0))
	var card := _card()
	card.add_child(_heading(str(box.get("name", "Gearbox"))))
	card.add_child(_body("%d gears · %s · top speed %d%%" % [gear_count, kind, top_pct]))
	card.add_child(_body("Ratios  %s" % GameState.gearbox_ratio_text(box)))
	var btn := _ink_button()
	if equipped:
		btn.text = "On the car"
		btn.disabled = true
	elif owned:
		btn.text = "In spare parts"
		btn.disabled = true
	else:
		btn.text = "Buy — $%d" % price
		btn.disabled = price > 0 and GameState.money < price
		btn.pressed.connect(_on_buy_gearbox.bind(gearbox_id))
	card.add_child(btn)
	return card


func _make_car_card(car: Dictionary) -> Control:
	var car_id := str(car.get("id", ""))
	var owned := GameState.owns_car(car_id)
	var current := GameState.current_car_id == car_id
	var price := int(car.get("price", 0))
	var box := _card()
	box.add_child(_heading(str(car.get("name", "Car"))))
	box.add_child(_body("%.0f km/h   %.0f hp" % [float(car.get("vmax", 0.0)), float(car.get("hp", 0.0))]))
	var btn := _ink_button()
	if current:
		btn.text = "In the garage"
		btn.disabled = true
	elif owned:
		btn.text = "Pull into garage"
		btn.pressed.connect(_on_buy_car.bind(car_id))
	else:
		btn.text = "Buy — $%d" % price
		btn.disabled = GameState.money < price
		btn.pressed.connect(_on_buy_car.bind(car_id))
	box.add_child(btn)
	return box


func _ink_button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.06, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.28, 0.26, 0.24, 1))
	return btn


func _card() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06, 1))
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.25, 0.22, 0.18, 1)
	return label


func _make_engine_card(engine: Dictionary) -> Control:
	return _make_swap_card(engine, GameState.equipped_engine_id, GameState.owns_engine(str(engine.get("id", ""))), "%.0f hp" % float(engine.get("hp", 0.0)), _on_buy_engine)


func _make_wheel_card(wheel: Dictionary) -> Control:
	return _make_swap_card(wheel, GameState.equipped_wheel_id, GameState.owns_wheel(str(wheel.get("id", ""))), "Grip %d" % int(wheel.get("grip", 3)), _on_buy_wheel)


func _make_swap_card(part: Dictionary, equipped_id: String, owned: bool, detail: String, handler: Callable) -> Control:
	var part_id := str(part.get("id", ""))
	var price := int(part.get("price", 0))
	var card := _card()
	card.add_child(_heading(str(part.get("name", "Part"))))
	card.add_child(_body(detail))
	var btn := _ink_button()
	if part_id == equipped_id:
		btn.text = "On the car"
		btn.disabled = true
	elif owned:
		btn.text = "In spare parts"
		btn.disabled = true
	else:
		btn.text = "Buy — $%d" % price
		btn.disabled = GameState.money < price
		btn.pressed.connect(handler.bind(part_id))
	card.add_child(btn)
	return card


func _on_buy_engine(engine_id: String) -> void:
	var err := GameState.buy_or_equip_engine(engine_id)
	_status.text = "Engine is in the spare parts folder." if err.is_empty() else err
	_refresh()


func _on_buy_wheel(wheel_id: String) -> void:
	var err := GameState.buy_or_equip_wheel(wheel_id)
	_status.text = "Wheels are in the spare parts folder." if err.is_empty() else err
	_refresh()


func _on_buy_gearbox(gearbox_id: String) -> void:
	var err := GameState.buy_or_equip_gearbox(gearbox_id)
	_status.text = "Gearbox is in the spare parts folder." if err.is_empty() else err
	_refresh()


func _on_buy_part(part_id: String) -> void:
	var err := GameState.buy_part(part_id)
	_status.text = "Part is in the spare parts folder." if err.is_empty() else err
	_refresh()


func _on_buy_car(car_id: String) -> void:
	var err := GameState.buy_or_select_car(car_id)
	if err.is_empty():
		_status.text = "It's yours. Check the garage."
	else:
		_status.text = err
	_refresh()


func _on_used_cars_tab_pressed() -> void:
	_show_section(SECTION_CARS)


func _on_auto_parts_tab_pressed() -> void:
	_show_section(SECTION_PARTS)


func _show_section(section: String) -> void:
	_section = section
	_index_section.visible = section == SECTION_INDEX
	_cars_section.visible = section == SECTION_CARS
	_parts_section.visible = section == SECTION_PARTS
	if section == SECTION_INDEX:
		_status.text = ""
		_back_button.text = "Fold it up — back to garage"
	else:
		_back_button.text = "Back to classifieds"
	_wire_menu()


func _wire_menu() -> void:
	var items: Array = []
	if _section == SECTION_INDEX:
		items = [%UsedCarsCard, %AutoPartsCard, _back_button]
	elif _section == SECTION_CARS:
		items = _nav.collect_buttons(_cars_list)
		items.append(_back_button)
	else:
		items = _nav.collect_buttons(_parts_list)
		items.append(_back_button)
	_nav.setup(items)


func _on_back_pressed() -> void:
	if _section != SECTION_INDEX:
		_show_section(SECTION_INDEX)
		return
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
