extends Control

var _hint: Label
var _drag_btn: Button
var _road_btn: Button


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_OPPONENT_SELECT
	GameState.update_music()
	_hint = $Margin/VBox/Hint
	_build_race_type_row()
	_refresh_race_type_ui()
	var list := %OpponentList as VBoxContainer
	for child in list.get_children():
		child.queue_free()
	for i in range(GameState.OPPONENTS.size()):
		var opp: Dictionary = GameState.OPPONENTS[i]
		var btn := Button.new()
		btn.text = str(opp.get("name", "Opponent"))
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(_on_opponent_chosen.bind(i))
		list.add_child(btn)


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
	if is_road:
		_hint.text = "Road course — 2.4 km (6× a quarter mile) with turns. Pick a rival to start."
	else:
		_hint.text = "Quarter mile drag — pick a rival to start the race."


func _on_opponent_chosen(index: int) -> void:
	GameState.selected_opponent_id = index
	GameState.current_scene_path = GameState.SCENE_RACE
	get_tree().change_scene_to_file(GameState.SCENE_RACE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
