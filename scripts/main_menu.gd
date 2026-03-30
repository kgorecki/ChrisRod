extends Control


func _on_new_game_pressed() -> void:
	GameState.new_game()
	GameState.current_scene_path = GameState.SCENE_GARAGE
	# Validate target scene before changing to get a clearer error message.
	var path := GameState.SCENE_GARAGE
	if not ResourceLoader.exists(path):
		_set_status("Scene missing: %s" % path)
		push_error("Scene missing: %s" % path)
		return
	# Diagnostic: log resource info before attempting scene change
	var exists_res := ResourceLoader.exists(path)
	var abs_path := ProjectSettings.globalize_path(path)
	var file_exists := FileAccess.file_exists(abs_path)
	var packed := ResourceLoader.load(path)
	print("[main_menu] Scene diagnostics: path=%s, exists_res=%s, abs_path=%s, file_exists=%s, packed=%s" % [path, exists_res, abs_path, file_exists, packed])
	var cls := "(no class)"
	if packed != null:
		if packed is Resource:
			cls = packed.get_class()
	print("[main_menu] PackedScene class: %s" % cls)

	# Directly ask the SceneTree to change scenes. change_scene_to_file returns an Error code.
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		_set_status("Could not change to scene: %s (err=%d)" % [path, err])
		push_error("change_scene_to_file failed for %s (err=%d)" % [path, err])
		return


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
	get_tree().change_scene_to_file("res://scenes/settings.tscn")


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
