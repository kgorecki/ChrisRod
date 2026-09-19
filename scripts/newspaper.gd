extends Control

@onready var _cash: Label = %CashLabel
@onready var _parts_list: VBoxContainer = %PartsList
@onready var _cars_list: VBoxContainer = %CarsList
@onready var _status: Label = %StatusLabel


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_NEWSPAPER
	GameState.update_music()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_cash.text = "Cash on hand: $%d" % GameState.money
	_rebuild_parts()
	_rebuild_cars()


func _rebuild_parts() -> void:
	for child in _parts_list.get_children():
		child.queue_free()
	_parts_list.add_child(_heading("TRANSMISSIONS"))
	for box in GameState.GEARBOXES:
		_parts_list.add_child(_make_gearbox_card(box))
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
	var price := int(part.get("price", 0))
	var box := _card()
	box.add_child(_heading(str(part.get("name", "Part"))))
	box.add_child(_body("+%d hp   +%d km/h" % [int(part.get("hp", 0)), int(part.get("vmax", 0))]))
	var btn := _ink_button()
	if owned:
		btn.text = "Installed"
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
		btn.text = "Installed"
		btn.disabled = true
	elif owned:
		btn.text = "Bolt it on"
		btn.pressed.connect(_on_buy_gearbox.bind(gearbox_id))
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


func _on_buy_gearbox(gearbox_id: String) -> void:
	var already_owned := GameState.owns_gearbox(gearbox_id)
	var err := GameState.buy_or_equip_gearbox(gearbox_id)
	if err.is_empty():
		if already_owned:
			_status.text = "Swapped the box. Ratios are live."
		else:
			_status.text = "New gearbox is in. Watch the shift points."
	else:
		_status.text = err
	_refresh()


func _on_buy_part(part_id: String) -> void:
	var err := GameState.buy_part(part_id)
	if err.is_empty():
		_status.text = "Bolt it on — the spec sheet is updated."
	else:
		_status.text = err
	_refresh()


func _on_buy_car(car_id: String) -> void:
	var err := GameState.buy_or_select_car(car_id)
	if err.is_empty():
		_status.text = "It's yours. Check the garage."
	else:
		_status.text = err
	_refresh()


func _on_back_pressed() -> void:
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
