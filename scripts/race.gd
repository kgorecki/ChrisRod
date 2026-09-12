extends Node3D

const QUARTER_MILE_M := 402.336

const COUNTDOWN_RED_S := 1.2
const COUNTDOWN_RED_ORANGE_S := 1.0
const COUNTDOWN_GREEN_VISIBLE_S := 0.55

## 0 = red only, 1 = red + orange, 2 = green (race running), 3 = lights hidden
var _countdown_phase: int = 0
var _phase_time: float = 0.0
var _race_started: bool = false

@onready var _player: CharacterBody3D = $PlayerCar
@onready var _opponent: CharacterBody3D = $OpponentCar
@onready var _hud_speed: Label = $RaceUI/Panel/Margin/VBox/SpeedLabel
@onready var _hud_dist: Label = $RaceUI/Panel/Margin/VBox/DistLabel
@onready var _hud_time: Label = $RaceUI/Panel/Margin/VBox/TimeLabel
@onready var _hud_opp: Label = $RaceUI/Panel/Margin/VBox/OppLabel
@onready var _result: Control = $RaceUI/ResultPanel
@onready var _result_text: Label = $RaceUI/ResultPanel/Panel/Margin/VBox/ResultLabel
@onready var _traffic: Control = $RaceUI/TrafficLights
@onready var _light_red: ColorRect = $RaceUI/TrafficLights/Center/HBox/LightRed
@onready var _light_orange: ColorRect = $RaceUI/TrafficLights/Center/HBox/LightOrange
@onready var _light_green: ColorRect = $RaceUI/TrafficLights/Center/HBox/LightGreen
@onready var _track: Node3D = $RaceTrack
@onready var _ground: StaticBody3D = $Ground
@onready var _finish: Area3D = $FinishLine

var _race_over: bool = false
var _is_road: bool = false
var _elapsed: float = 0.0

## Dim “off” lamp colors (same hue, low value).
const _DIM_RED := Color(0.12, 0.05, 0.05, 1)
const _DIM_ORANGE := Color(0.12, 0.08, 0.03, 1)
const _DIM_GREEN := Color(0.04, 0.1, 0.05, 1)
const _ON_RED := Color(1.0, 0.12, 0.12, 1)
const _ON_ORANGE := Color(1.0, 0.58, 0.08, 1)
const _ON_GREEN := Color(0.2, 0.95, 0.28, 1)


func _ready() -> void:
	GameState.current_scene_path = GameState.SCENE_RACE
	_is_road = GameState.selected_race_type == GameState.RACE_ROAD
	_setup_race_layout()
	_result.visible = false
	var i: int = clampi(GameState.selected_opponent_id, 0, GameState.OPPONENTS.size() - 1)
	var opp: Dictionary = GameState.OPPONENTS[i]
	_hud_opp.text = "Opponent: %s" % str(opp.get("name", "Rival"))
	_traffic.visible = true
	_refresh_traffic_lights()

	# Apply the player's selected paint color to the shared car visuals.
	var player_pivot := _player.get_node_or_null("CarPivot")
	if player_pivot != null and player_pivot.has_method(&"set_car_body_color"):
		player_pivot.set_car_body_color(GameState.car_color)
	# Defer so the MeshInstance child scripts have a chance
	# to populate `MeshInstance3D.mesh` before we inspect it.
	call_deferred(&"_debug_car_mesh_resource_load")
	call_deferred(&"_debug_car_mesh_instances")
	call_deferred(&"_align_race_cars_to_ground")


func is_race_started() -> bool:
	return _race_started


func get_race_track() -> Node:
	if _is_road and _track != null and _track.has_method(&"is_road_course") and _track.is_road_course():
		return _track
	return null


func _setup_race_layout() -> void:
	if not _is_road:
		return
	_ground.visible = false
	_ground.collision_layer = 0
	_ground.collision_mask = 0
	if _track.has_method(&"finish_basis"):
		_finish.global_transform = _track.finish_basis()
	var col := _finish.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var box := BoxShape3D.new()
		box.size = Vector3(42, 8, 5)
		col.shape = box


func _debug_car_mesh_instances() -> void:
	# Prints bounds and surface counts for each MeshInstance3D under player/opponent.
	# Wheels will also show up; the car body node is usually the one named `MeshInstance3D`.
	_debug_body_mesh_instances(_player, "player")
	_debug_body_mesh_instances(_opponent, "opponent")


func _debug_car_mesh_resource_load() -> void:
	# One-time check: whether Godot can actually load the STL import resource.
	var stl_path := "res://assets/vette-c1.stl"
	var exists_array_mesh := ResourceLoader.exists(stl_path, &"ArrayMesh")
	var loaded := ResourceLoader.load(stl_path)
	var loaded_type := "<null>"
	if loaded != null:
		loaded_type = loaded.get_class()

	print("[DEBUG CAR][race] ResourceLoader stl_path=", stl_path,
		" exists(ArrayMesh)=", exists_array_mesh,
		" loaded=", loaded != null,
		" loaded_type=", loaded_type)


func _align_race_cars_to_ground() -> void:
	var floor_mi: MeshInstance3D = $Ground/MeshInstance3D
	if _is_road and _track.has_method(&"get_road_mesh_instance"):
		var road_mi: MeshInstance3D = _track.get_road_mesh_instance()
		if road_mi != null:
			floor_mi = road_mi
	for car in [_player, _opponent]:
		var pivot: Node = car.get_node_or_null("CarPivot")
		if pivot != null and pivot.has_method(&"align_wheels_to_floor"):
			pivot.align_wheels_to_floor(floor_mi)


func _debug_body_mesh_instances(body: Node, label: String) -> void:
	if body == null:
		print("[DEBUG CAR][race] Missing body for ", label)
		return

	_debug_mesh_instances_recursive(body, label)


func _debug_mesh_instances_recursive(node: Node, label: String) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mesh := mi.mesh
			var surfaces := 0
			var resource_path := "<null>"
			if mesh != null:
				resource_path = mesh.resource_path
				if mesh.has_method(&"get_surface_count"):
					surfaces = mesh.get_surface_count()

			var aabb := mi.get_aabb() # local-space bounds
			var center_local := aabb.position + aabb.size * 0.5
			var center_world := mi.global_transform * center_local

			print("[DEBUG CAR][race] ", label, " node=", mi.get_path(), " visible=", mi.visible,
				" mesh_null=", mesh == null,
				" mesh_resource=", resource_path,
				" surface_count=", surfaces,
				" local_aabb_size=", aabb.size,
				" center_world=", center_world)
		_debug_mesh_instances_recursive(child, label)


func _process(delta: float) -> void:
	if _race_over:
		return
	if not _race_started:
		_advance_countdown(delta)
		return
	if _countdown_phase == 2:
		_phase_time += delta
		if _phase_time >= COUNTDOWN_GREEN_VISIBLE_S:
			_countdown_phase = 3
			_traffic.visible = false

	_elapsed += delta
	_hud_time.text = "Time: %.2f s" % _elapsed
	_hud_dist.text = "To finish: %.1f m" % _distance_to_finish()
	var spd: float = _player.get_forward_speed()
	_hud_speed.text = "Speed: %.0f km/h" % (spd * 3.6)
	_maybe_finish_by_progress()


func _advance_countdown(delta: float) -> void:
	_phase_time += delta
	if _countdown_phase == 0:
		if _phase_time >= COUNTDOWN_RED_S:
			_countdown_phase = 1
			_phase_time = 0.0
			_refresh_traffic_lights()
	elif _countdown_phase == 1:
		if _phase_time >= COUNTDOWN_RED_ORANGE_S:
			_countdown_phase = 2
			_phase_time = 0.0
			_race_started = true
			_refresh_traffic_lights()


func _refresh_traffic_lights() -> void:
	match _countdown_phase:
		0:
			_light_red.color = _ON_RED
			_light_orange.color = _DIM_ORANGE
			_light_green.color = _DIM_GREEN
		1:
			_light_red.color = _ON_RED
			_light_orange.color = _ON_ORANGE
			_light_green.color = _DIM_GREEN
		2, 3:
			_light_red.color = _DIM_RED
			_light_orange.color = _DIM_ORANGE
			_light_green.color = _ON_GREEN


func _on_finish_area_body_entered(body: Node3D) -> void:
	if _race_over or not _race_started:
		return
	if body == _player:
		_race_over = true
		_show_result(true)
	elif body == _opponent:
		_race_over = true
		_show_result(false)


func _distance_to_finish() -> float:
	if _is_road and _track.has_method(&"remaining_distance"):
		return _track.remaining_distance(_player.global_position)
	return maxf(0.0, QUARTER_MILE_M - _player.global_position.z)


func _maybe_finish_by_progress() -> void:
	if not _is_road or _race_over or _track == null:
		return
	var p_rem: float = _track.remaining_distance(_player.global_position)
	var o_rem := INF
	if _opponent.has_method(&"get_path_s"):
		o_rem = maxf(0.0, _track.get_length() - _opponent.get_path_s())
	if p_rem > 1.0 and o_rem > 1.0:
		return
	if p_rem <= o_rem:
		_on_finish_area_body_entered(_player)
	else:
		_on_finish_area_body_entered(_opponent)


func _show_result(player_won: bool) -> void:
	_result.visible = true
	if _is_road:
		if player_won:
			_result_text.text = "You finished the road course first — you win!"
		else:
			_result_text.text = "Your opponent reached the finish first — you lose."
	elif player_won:
		_result_text.text = "You crossed the quarter mile first — you win!"
	else:
		_result_text.text = "Your opponent reached the line first — you lose."


func _on_back_garage_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)
