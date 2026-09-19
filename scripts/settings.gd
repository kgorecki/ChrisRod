extends Control


func _ready() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	%FullscreenCheck.button_pressed = fs
	%MasterSlider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	%MusicCheck.set_pressed_no_signal(GameState.music_enabled)
	GameState.update_music()


func _on_back_pressed() -> void:
	GameState.save_settings()
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)


func _on_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_music_toggled(pressed: bool) -> void:
	GameState.set_music_enabled(pressed)
