extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")
const _CarVisual := preload("res://scenes/car_vehicle_visual.tscn")

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
@onready var _preview_overlay: Control = %PreviewOverlay
@onready var _preview_caption: Label = %PreviewCaption
@onready var _preview_frame: SubViewportContainer = %PreviewFrame
@onready var _preview_mount: Node3D = %PreviewMount
@onready var _preview_floor: MeshInstance3D = %Floor
@onready var _preview_camera: Camera3D = %PreviewCamera
@onready var _preview_back: Button = %PreviewBack

var _section: String = SECTION_INDEX
var _nav = _MenuNav.new()
var _preview_car_id: String = ""
var _preview_pivot: Node3D


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_NEWSPAPER
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_preview_camera.look_at_from_position(Vector3(5.6, 2.1, 8.2), Vector3(0.0, 0.8, 0.0))
	GameState.roll_newspaper_colors()
	_show_section(SECTION_INDEX)
	_refresh()


func _process(delta: float) -> void:
	if not _preview_overlay.visible or not _preview_frame.visible:
		return
	_preview_mount.rotate_y(delta * 0.35)


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
	box.set_meta(&"car_id", car_id)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_car_card_input.bind(car_id))
	if car_id == _preview_car_id:
		box.modulate = Color(0.96, 0.84, 0.58, 1)
	box.add_child(_heading(str(car.get("name", "Car"))))
	box.add_child(_body("%.0f km/h   %.0f hp" % [float(car.get("vmax", 0.0)), float(car.get("hp", 0.0))]))
	var btn := _ink_button()
	if current:
		btn.text = "In the garage"
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif owned:
		btn.text = "Pull into garage"
		btn.pressed.connect(_show_car_preview.bind(car_id))
		btn.pressed.connect(_on_buy_car.bind(car_id))
	elif GameState.owned_car_ids.size() >= GameState.MAX_OWNED_CARS:
		btn.text = "Garage is full"
		btn.disabled = true
	else:
		btn.text = "Buy — $%d" % price
		btn.disabled = GameState.money < price
		btn.pressed.connect(_show_car_preview.bind(car_id))
		btn.pressed.connect(_on_buy_car.bind(car_id))
	box.add_child(btn)
	return box


func _on_car_card_input(event: InputEvent, car_id: String) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_show_car_preview(car_id)


func _show_car_preview(car_id: String) -> void:
	if car_id == _preview_car_id:
		return
	_preview_car_id = car_id
	_tint_preview_card()
	var car: Dictionary = GameState.listing_by_id(GameState.USED_CARS, car_id)
	var car_name := str(car.get("name", "Car"))
	var path := str(car.get("car_file", ""))
	var paint := GameState.newspaper_color(car_id)
	_open_preview_overlay()
	if path.is_empty() or not FileAccess.file_exists(path):
		_preview_frame.visible = false
		_preview_caption.text = "%s — no photograph with this ad." % car_name
		return
	if _preview_pivot == null:
		var pivot := _CarVisual.instantiate() as Node3D
		if pivot == null or not pivot.has_method(&"prepare_preview"):
			_preview_frame.visible = false
			_preview_caption.text = "Couldn't open the photograph."
			return
		var prepared: Variant = pivot.call(&"prepare_preview", path, paint)
		if not bool(prepared):
			pivot.free()
			_preview_frame.visible = false
			_preview_caption.text = "%s — no photograph with this ad." % car_name
			return
		_preview_mount.add_child(pivot)
		_preview_pivot = pivot
	elif not bool(_preview_pivot.call(&"preview_listing", path, paint)):
		_preview_frame.visible = false
		_preview_caption.text = "%s — no photograph with this ad." % car_name
		return
	_preview_mount.rotation = Vector3.ZERO
	_seat_preview_car()
	_preview_frame.visible = true
	_preview_caption.text = car_name


func _seat_preview_car() -> void:
	if _preview_pivot == null or not _preview_pivot.has_method(&"align_wheels_to_floor"):
		return
	_preview_pivot.call(&"align_wheels_to_floor", _preview_floor)


func _open_preview_overlay() -> void:
	_preview_overlay.visible = true
	_wire_menu()


func _close_car_preview() -> void:
	if not _preview_overlay.visible:
		return
	_preview_overlay.visible = false
	_preview_car_id = ""
	_tint_preview_card()
	_wire_menu()


func _tint_preview_card() -> void:
	for child in _cars_list.get_children():
		if not child is Control:
			continue
		var card := child as Control
		if str(card.get_meta(&"car_id", "")) == _preview_car_id:
			card.modulate = Color(0.96, 0.84, 0.58, 1)
		else:
			card.modulate = Color.WHITE


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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06, 1))
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if not err.is_empty():
		_status.text = err
		_refresh()
		return
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _on_used_cars_tab_pressed() -> void:
	_show_section(SECTION_CARS)


func _on_auto_parts_tab_pressed() -> void:
	_show_section(SECTION_PARTS)


func _show_section(section: String) -> void:
	_section = section
	_index_section.visible = section == SECTION_INDEX
	_cars_section.visible = section == SECTION_CARS
	_parts_section.visible = section == SECTION_PARTS
	if section != SECTION_CARS:
		_preview_overlay.visible = false
		_preview_car_id = ""
	if section == SECTION_INDEX:
		_status.text = ""
		_back_button.text = "Fold it up — back to garage"
	else:
		_back_button.text = "Back to classifieds"
	_wire_menu()


func _wire_menu() -> void:
	var items: Array = []
	if _preview_overlay.visible:
		items = [_preview_back, _back_button]
	elif _section == SECTION_INDEX:
		items = [%UsedCarsCard, %AutoPartsCard, _back_button]
	elif _section == SECTION_CARS:
		items = _nav.collect_buttons(_cars_list)
		items.append(_back_button)
	else:
		items = _nav.collect_buttons(_parts_list)
		items.append(_back_button)
	_nav.setup(items)


func _on_back_pressed() -> void:
	if _preview_overlay.visible:
		_close_car_preview()
		return
	if _section != SECTION_INDEX:
		_show_section(SECTION_INDEX)
		return
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
