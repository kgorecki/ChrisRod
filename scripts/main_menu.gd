extends Control

const _MenuNav := preload("res://scripts/menu_nav.gd")

var _nav = _MenuNav.new()


func _ready() -> void:
	GameState.update_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_nav.setup([
		$Margin/VBox/NewGameButton,
		$Margin/VBox/SaveGameButton,
		$Margin/VBox/LoadGameButton,
		$Margin/VBox/SettingsButton,
		$Margin/VBox/ExitButton,
	])


func _unhandled_input(event: InputEvent) -> void:
	if _nav.handle_event(self, event):
		accept_event()


func _on_new_game_pressed() -> void:
	GameState.new_game()
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _on_save_game_pressed() -> void:
	GameState.current_scene_path = _scene_path_for_save()
	if GameState.save_game():
		_set_status("Game saved.")
	else:
		_set_status("Could not save game.")


func _on_load_game_pressed() -> void:
	if not GameState.has_save_file():
		_set_status("No save file found.")
		return
	if GameState.load_game():
		_set_status("Game loaded.")
		GameState.go_to_saved_scene(get_tree())
	else:
		_set_status("Could not load save.")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_SETTINGS)


func _on_exit_pressed() -> void:
	get_tree().quit()


func _scene_path_for_save() -> String:
	var path := get_tree().current_scene.scene_file_path
	if path.is_empty():
		return GameState.SCENE_MAIN_MENU
	return path


func _set_status(text: String) -> void:
	var label := get_node_or_null("Margin/VBox/StatusLabel") as Label
	if label:
		label.text = text
