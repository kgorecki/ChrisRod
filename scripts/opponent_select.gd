extends Control


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_OPPONENT_SELECT
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


func _on_opponent_chosen(index: int) -> void:
	GameState.selected_opponent_id = index
	GameState.current_scene_path = GameState.SCENE_RACE
	get_tree().change_scene_to_file(GameState.SCENE_RACE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)
