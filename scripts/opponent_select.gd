extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")

var _hint: Label
var _drag_btn: Button
var _road_btn: Button
var _fuel_monitor: Control
var _fuel_message: Label
var _fuel_back: Button
var _nav = _MenuNav.new()


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_OPPONENT_SELECT
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hint = $Margin/VBox/Hint
	_build_race_type_row()
	_build_fuel_monitor()
	_refresh_race_type_ui()
	var list := %OpponentList as VBoxContainer
	for child in list.get_children():
		child.queue_free()
	var menu_items: Array = [_drag_btn, _road_btn]
	for i in range(GameState.OPPONENTS.size()):
		var opp: Dictionary = GameState.OPPONENTS[i]
		var btn := Button.new()
		btn.text = str(opp.get("name", "Opponent"))
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(_on_opponent_chosen.bind(i))
		list.add_child(btn)
		menu_items.append(btn)
	menu_items.append($Margin/VBox/BackButton)
	_nav.setup(menu_items)


func _unhandled_input(event: InputEvent) -> void:
	if _fuel_monitor != null and _fuel_monitor.visible and event.is_action_pressed(&"ui_cancel"):
		_hide_fuel_monitor()
		accept_event()
		return
	if _nav.handle_event(self, event):
		accept_event()


func _build_race_type_row() -> void:
	var vbox := $Margin/VBox as VBoxContainer
	var row := HBoxContainer.new()
	row.name = "RaceTypeRow"
	row.add_theme_constant_override("separation", 12)
	_drag_btn = Button.new()
	_drag_btn.custom_minimum_size = Vector2(180, 40)
	_drag_btn.pressed.connect(_on_race_type_chosen.bind(GameState.RACE_DRAG))
	_road_btn = Button.new()
	_road_btn.custom_minimum_size = Vector2(220, 40)
	_road_btn.pressed.connect(_on_race_type_chosen.bind(GameState.RACE_ROAD))
	row.add_child(_drag_btn)
	row.add_child(_road_btn)
	vbox.add_child(row)
	vbox.move_child(row, _hint.get_index() + 1)


func _on_race_type_chosen(race_type: String) -> void:
	GameState.selected_race_type = race_type
	_refresh_race_type_ui()


func _refresh_race_type_ui() -> void:
	var is_road := GameState.selected_race_type == GameState.RACE_ROAD
	_drag_btn.text = "Drag race ✓" if not is_road else "Drag race"
	_road_btn.text = "Road race ✓" if is_road else "Road race"
	var need := GameState.race_fuel_liters()
	var tank := "Tank %.0f L · this race uses about %.0f L." % [GameState.fuel, need]
	if is_road:
		_hint.text = "Road course — 2.4 km with turns. %s Pick a rival to start." % tank
	else:
		_hint.text = "Quarter mile drag. %s Pick a rival to start." % tank


func _on_opponent_chosen(index: int) -> void:
	if not GameState.has_fuel_for_race():
		_show_fuel_monitor()
		return
	GameState.selected_opponent_id = index
	GameState.current_scene_path = GameState.SCENE_RACE
	get_tree().change_scene_to_file(GameState.SCENE_RACE)


func _build_fuel_monitor() -> void:
	var root := Control.new()
	root.name = "FuelMonitor"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240.0
	panel.offset_top = -110.0
	panel.offset_right = 240.0
	panel.offset_bottom = 110.0
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 18)
	margin.add_theme_constant_override(&"margin_right", 18)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Low fuel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_fuel_message = Label.new()
	_fuel_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fuel_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_fuel_message)
	_fuel_back = Button.new()
	_fuel_back.text = "Back"
	_fuel_back.pressed.connect(_hide_fuel_monitor)
	box.add_child(_fuel_back)
	add_child(root)
	_fuel_monitor = root


func _show_fuel_monitor() -> void:
	var need := GameState.race_fuel_liters()
	_fuel_message.text = "The tank has %.0f L. This race needs %.0f L.\nFill it up in the garage first." % [GameState.fuel, need]
	_fuel_monitor.visible = true
	_nav.setup([_fuel_back])


func _hide_fuel_monitor() -> void:
	if _fuel_monitor == null:
		return
	_fuel_monitor.visible = false
	_restore_menu_nav()


func _restore_menu_nav() -> void:
	var menu_items: Array = [_drag_btn, _road_btn]
	var list := %OpponentList as VBoxContainer
	for child in list.get_children():
		if child is Button:
			menu_items.append(child)
	menu_items.append($Margin/VBox/BackButton)
	_nav.setup(menu_items)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
