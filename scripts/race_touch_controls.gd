extends Control

## On-screen race controls for phones: wheel on the left, pedals on the right.

const _NARROW_WIDTH := 900.0

var _wheel: _SteeringWheel
var _accel: _Pedal
var _brake: _Pedal
var _shift_up: _ShiftPaddle
var _shift_down: _ShiftPaddle
var _shift_up_queued: bool = false
var _shift_down_queued: bool = false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_controls()
	_refresh_layout()
	_refresh_visible()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func get_steer() -> float:
	if not visible or _wheel == null:
		return 0.0
	return _wheel.get_steer()


func is_throttle_down() -> bool:
	return visible and _accel != null and _accel.is_held()


func is_brake_down() -> bool:
	return visible and _brake != null and _brake.is_held()


func pop_shift_up() -> bool:
	if not visible or _shift_up_queued == false:
		return false
	_shift_up_queued = false
	return true


func pop_shift_down() -> bool:
	if not visible or _shift_down_queued == false:
		return false
	_shift_down_queued = false
	return true


func _on_viewport_size_changed() -> void:
	_refresh_layout()
	_refresh_visible()


func _refresh_visible() -> void:
	var result := get_parent().get_node_or_null("ResultPanel") as CanvasItem
	if result != null and result.visible:
		visible = false
		return
	visible = _is_mobile_view()
	var hint := get_parent().get_node_or_null("Panel/Margin/VBox/HintLabel") as CanvasItem
	if hint != null:
		hint.visible = not visible
	_refresh_shift_visible()


func _is_mobile_view() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	var vs := get_viewport().get_visible_rect().size
	var narrow := vs.x <= _NARROW_WIDTH or vs.x < vs.y
	if DisplayServer.is_touchscreen_available() and narrow:
		return true
	return vs.x <= _NARROW_WIDTH


func _build_controls() -> void:
	_wheel = _SteeringWheel.new()
	_wheel.name = "SteeringWheel"
	add_child(_wheel)

	_brake = _Pedal.new()
	_brake.name = "BrakePedal"
	_brake.setup("BRAKE", Color(0.72, 0.16, 0.14, 1.0))
	add_child(_brake)

	_accel = _Pedal.new()
	_accel.name = "AccelPedal"
	_accel.setup("GAS", Color(0.18, 0.62, 0.28, 1.0))
	add_child(_accel)

	_shift_down = _ShiftPaddle.new()
	_shift_down.name = "ShiftDown"
	_shift_down.setup("–", Color(0.72, 0.55, 0.18, 1.0))
	_shift_down.pressed.connect(func() -> void: _shift_down_queued = true)
	add_child(_shift_down)

	_shift_up = _ShiftPaddle.new()
	_shift_up.name = "ShiftUp"
	_shift_up.setup("+", Color(0.72, 0.55, 0.18, 1.0))
	_shift_up.pressed.connect(func() -> void: _shift_up_queued = true)
	add_child(_shift_up)
	_refresh_shift_visible()


func _refresh_layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var scale := clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.5, 1.2)
	var margin := 20.0 * scale

	var wheel_size := 220.0 * scale
	_wheel.position = Vector2(margin, vs.y - margin - wheel_size)
	_wheel.size = Vector2(wheel_size, wheel_size)

	var pedal_w := 92.0 * scale
	var pedal_h := 168.0 * scale
	var gap := 14.0 * scale
	var accel_w := 108.0 * scale
	var accel_h := 188.0 * scale

	_accel.position = Vector2(vs.x - margin - accel_w, vs.y - margin - accel_h)
	_accel.size = Vector2(accel_w, accel_h)
	_brake.position = Vector2(vs.x - margin - accel_w - gap - pedal_w, vs.y - margin - pedal_h)
	_brake.size = Vector2(pedal_w, pedal_h)

	var paddle := 56.0 * scale
	var paddle_gap := 10.0 * scale
	_shift_down.position = Vector2(margin, _wheel.position.y - paddle_gap - paddle)
	_shift_down.size = Vector2(paddle, paddle)
	_shift_up.position = Vector2(margin + paddle + paddle_gap, _wheel.position.y - paddle_gap - paddle)
	_shift_up.size = Vector2(paddle, paddle)


func _refresh_shift_visible() -> void:
	var show_paddles := visible and not bool(GameState.get_equipped_gearbox().get("automatic", false))
	if _shift_up != null:
		_shift_up.visible = show_paddles
	if _shift_down != null:
		_shift_down.visible = show_paddles


class _SteeringWheel extends Control:
	const MAX_ANGLE := 1.74532925 ## 100 degrees
	const RETURN_SPEED := 12.0

	var _grab_index: int = -1
	var _mouse_grabbed: bool = false
	var _grab_finger_angle: float = 0.0
	var _grab_wheel_angle: float = 0.0
	var _wheel_angle: float = 0.0
	var _steer: float = 0.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		focus_mode = FOCUS_NONE
		resized.connect(queue_redraw)
		set_process(false)

	func get_steer() -> float:
		return _steer

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed and not _is_grabbing():
				_begin_grab(st.index, false, st.position)
				accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if _grab_index >= 0:
				return
			if event.pressed and not _mouse_grabbed:
				_begin_grab(-1, true, event.position)
				accept_event()

	func _input(event: InputEvent) -> void:
		if not _is_grabbing():
			return
		if event is InputEventScreenDrag:
			var sd := event as InputEventScreenDrag
			if sd.index == _grab_index:
				_update_grab(_to_local_event(sd.position))
				get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if not st.pressed and st.index == _grab_index:
				_release()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _mouse_grabbed:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_update_grab(_to_local_event(event.position))
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed and _mouse_grabbed:
				_release()
				get_viewport().set_input_as_handled()

	func _process(delta: float) -> void:
		_wheel_angle = lerpf(_wheel_angle, 0.0, 1.0 - exp(-RETURN_SPEED * delta))
		if absf(_wheel_angle) < 0.01:
			_wheel_angle = 0.0
			set_process(false)
		_refresh_steer()
		queue_redraw()

	func _is_grabbing() -> bool:
		return _grab_index >= 0 or _mouse_grabbed

	func _begin_grab(index: int, mouse: bool, local_pos: Vector2) -> void:
		_grab_index = index
		_mouse_grabbed = mouse
		set_process(false)
		_grab_finger_angle = _angle_from_center(local_pos)
		_grab_wheel_angle = _wheel_angle
		set_process_input(true)
		queue_redraw()

	func _update_grab(local_pos: Vector2) -> void:
		var finger := _angle_from_center(local_pos)
		var delta := wrapf(finger - _grab_finger_angle, -PI, PI)
		_wheel_angle = clampf(_grab_wheel_angle + delta, -MAX_ANGLE, MAX_ANGLE)
		_refresh_steer()
		queue_redraw()

	func _release() -> void:
		_grab_index = -1
		_mouse_grabbed = false
		set_process_input(false)
		set_process(true)
		queue_redraw()

	func _refresh_steer() -> void:
		# Clockwise (positive angle) turns the car right, matching keyboard D/Right.
		var raw := -_wheel_angle / MAX_ANGLE
		_steer = 0.0 if absf(raw) < 0.06 else clampf(raw, -1.0, 1.0)

	func _to_local_event(viewport_pos: Vector2) -> Vector2:
		return make_canvas_position_local(viewport_pos)

	func _angle_from_center(local_pos: Vector2) -> float:
		var delta := local_pos - size * 0.5
		return atan2(delta.x, -delta.y)

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.48
		draw_circle(center + Vector2(3, 5), radius, Color(0, 0, 0, 0.32))
		draw_set_transform(center, _wheel_angle)
		draw_circle(Vector2.ZERO, radius, Color(0.10, 0.10, 0.11, 0.92))
		draw_arc(Vector2.ZERO, radius * 0.86, 0.0, TAU, 72, Color(0.16, 0.16, 0.17, 1), radius * 0.22, true)
		draw_arc(Vector2.ZERO, radius * 0.97, 0.0, TAU, 72, Color(0.62, 0.63, 0.66, 0.85), 2.4, true)
		draw_arc(Vector2.ZERO, radius * 0.74, 0.0, TAU, 72, Color(0.78, 0.79, 0.82, 0.7), 2.0, true)
		for i in 3:
			var spoke_angle := float(i) * TAU / 3.0 - PI * 0.5
			var tip := Vector2.from_angle(spoke_angle) * radius * 0.74
			draw_line(tip * 0.16, tip, Color(0.58, 0.59, 0.62, 0.95), radius * 0.11, true)
		draw_circle(Vector2.ZERO, radius * 0.20, Color(0.22, 0.22, 0.24, 1))
		draw_circle(Vector2.ZERO, radius * 0.09, Color(0.55, 0.16, 0.14, 1))
		draw_set_transform(Vector2.ZERO)


class _Pedal extends Control:
	var _label_text: String = ""
	var _accent: Color = Color.WHITE
	var _held: bool = false
	var _grab_index: int = -1
	var _mouse_grabbed: bool = false

	func setup(text: String, accent: Color) -> void:
		_label_text = text
		_accent = accent

	func is_held() -> bool:
		return _held

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		focus_mode = FOCUS_NONE
		resized.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed and not _is_grabbing():
				_begin_grab(st.index, false)
				accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if _grab_index >= 0:
				return
			if event.pressed and not _mouse_grabbed:
				_begin_grab(-1, true)
				accept_event()

	func _input(event: InputEvent) -> void:
		if not _is_grabbing():
			return
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if not st.pressed and st.index == _grab_index:
				_release()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed and _mouse_grabbed:
				_release()
				get_viewport().set_input_as_handled()

	func _is_grabbing() -> bool:
		return _grab_index >= 0 or _mouse_grabbed

	func _begin_grab(index: int, mouse: bool) -> void:
		_grab_index = index
		_mouse_grabbed = mouse
		_held = true
		set_process_input(true)
		queue_redraw()

	func _release() -> void:
		_grab_index = -1
		_mouse_grabbed = false
		_held = false
		set_process_input(false)
		queue_redraw()

	func _draw() -> void:
		var sink := 7.0 if _held else 0.0
		var body := Rect2(Vector2(4, 6 + sink), size - Vector2(8, 12))
		draw_rect(Rect2(Vector2(6, 10), size - Vector2(8, 8)), Color(0, 0, 0, 0.28), true)
		var rubber := Color(0.14, 0.14, 0.15, 0.94)
		if _held:
			rubber = rubber.lerp(_accent, 0.45)
		draw_rect(body, rubber, true)
		var accent_bar := Rect2(body.position, Vector2(body.size.x, 10))
		draw_rect(accent_bar, _accent.darkened(0.15 if _held else 0.35), true)
		var ridge_count := 5
		for i in ridge_count:
			var y := body.position.y + 22.0 + float(i) * ((body.size.y - 40.0) / float(ridge_count - 1))
			draw_line(
				Vector2(body.position.x + 10, y),
				Vector2(body.end.x - 10, y),
				Color(0.08, 0.08, 0.09, 0.7),
				3.0,
				true
			)
		var font := get_theme_default_font()
		var font_size := clampi(int(minf(size.x, size.y) * 0.16), 12, 22)
		var text_size := font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_pos := Vector2(
			(size.x - text_size.x) * 0.5,
			body.position.y + body.size.y * 0.55 + text_size.y * 0.25
		)
		draw_string(font, text_pos + Vector2(1, 1), _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.45))
		draw_string(font, text_pos, _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.95, 0.93, 0.95))


class _ShiftPaddle extends Control:
	signal pressed

	var _label_text: String = ""
	var _accent: Color = Color.WHITE
	var _held: bool = false

	func setup(text: String, accent: Color) -> void:
		_label_text = text
		_accent = accent

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		focus_mode = FOCUS_NONE
		resized.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_held = true
				pressed.emit()
				queue_redraw()
				accept_event()
			else:
				_held = false
				queue_redraw()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_held = true
				pressed.emit()
				queue_redraw()
				accept_event()
			else:
				_held = false
				queue_redraw()

	func _draw() -> void:
		var body := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var fill := Color(0.16, 0.16, 0.18, 0.92)
		if _held:
			fill = fill.lerp(_accent, 0.5)
		draw_rect(Rect2(Vector2(4, 5), size - Vector2(6, 6)), Color(0, 0, 0, 0.28), true)
		draw_rect(body, fill, true)
		draw_rect(body, _accent.darkened(0.2), false, 2.0)
		var font := get_theme_default_font()
		var font_size := clampi(int(minf(size.x, size.y) * 0.42), 16, 28)
		var text_size := font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_pos := Vector2((size.x - text_size.x) * 0.5, (size.y + text_size.y) * 0.5 - 4.0)
		draw_string(font, text_pos, _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.95, 0.93, 0.95))
