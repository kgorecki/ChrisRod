extends Control

const IDLE_RPM := 600.0
const METER_MAX := 7000.0
const CRUISE_START := 2800.0
const CRUISE_END := 3200.0

var _rpm: float = IDLE_RPM
var _shift_start: float = 5500.0
var _redline: float = 6500.0
var _critical: float = 6700.0
var _blown: bool = false
var _pulse: float = 0.0


func set_reading(rpm: float, shift_start: float, redline: float, critical: float, blown: bool) -> void:
	_rpm = rpm
	_shift_start = shift_start
	_redline = redline
	_critical = critical
	_blown = blown
	queue_redraw()


func _process(delta: float) -> void:
	if _blown or _rpm >= _shift_start:
		_pulse += delta * (8.0 if _rpm >= _critical or _blown else 5.0)
	else:
		_pulse = 0.0
	if _rpm >= _shift_start or _blown:
		queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.78)
	var radius := minf(size.x, size.y) * 0.46
	var start_ang := deg_to_rad(200.0)
	var sweep := deg_to_rad(220.0)

	draw_circle(center + Vector2(2, 3), radius + 8.0, Color(0, 0, 0, 0.35))
	draw_circle(center, radius + 6.0, Color(0.08, 0.08, 0.09, 0.88))

	_draw_zone(center, radius, start_ang, sweep, 0.0, _shift_start, Color(0.18, 0.55, 0.28, 0.85))
	_draw_zone(center, radius, start_ang, sweep, CRUISE_START, CRUISE_END, Color(0.22, 0.62, 0.78, 0.95))
	_draw_zone(center, radius, start_ang, sweep, _shift_start, _redline, Color(0.92, 0.72, 0.12, 0.95))
	_draw_zone(center, radius, start_ang, sweep, _redline, _critical, Color(0.92, 0.28, 0.08, 0.95))
	_draw_zone(center, radius, start_ang, sweep, _critical, METER_MAX, Color(0.55, 0.04, 0.06, 0.95))

	draw_arc(center, radius, start_ang, start_ang + sweep, 48, Color(0.75, 0.76, 0.78, 0.7), 2.2, true)

	var font := get_theme_default_font()
	for thousand in range(0, 8):
		var rpm := float(thousand) * 1000.0
		var t := clampf(rpm / METER_MAX, 0.0, 1.0)
		var ang := start_ang + sweep * t
		var dir := Vector2.from_angle(ang)
		var outer := center + dir * radius
		var inner := center + dir * (radius - (10.0 if thousand % 2 == 0 else 6.0))
		draw_line(inner, outer, Color(0.88, 0.88, 0.9, 0.9), 2.0, true)
		if thousand % 2 == 0:
			var label_pos := center + dir * (radius - 22.0) - Vector2(5, 6)
			draw_string(font, label_pos, str(thousand), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.92, 0.9))

	var cruise_ang := start_ang + sweep * ((CRUISE_START + CRUISE_END) * 0.5 / METER_MAX)
	var cruise_dir := Vector2.from_angle(cruise_ang)
	draw_string(
		font,
		center + cruise_dir * (radius + 2.0) + Vector2(-22, 2),
		"CRUISE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color(0.65, 0.88, 1.0, 0.9)
	)

	var shift_ang := start_ang + sweep * clampf(_shift_start / METER_MAX, 0.0, 1.0)
	var shift_dir := Vector2.from_angle(shift_ang)
	var flash := 0.55 + 0.45 * absf(sin(_pulse))
	var shift_color := Color(1.0, 0.86, 0.2, flash)
	draw_string(
		font,
		center + shift_dir * (radius + 4.0) + Vector2(-18, -2),
		"SHIFT",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		shift_color
	)

	var crit_ang := start_ang + sweep * clampf(_critical / METER_MAX, 0.0, 1.0)
	var crit_dir := Vector2.from_angle(crit_ang)
	draw_string(
		font,
		center + crit_dir * (radius + 2.0) + Vector2(-10, 10),
		"X",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(1.0, 0.2, 0.15, 0.95)
	)

	var needle_rpm := IDLE_RPM if _blown else _rpm
	var needle_t := clampf(needle_rpm / METER_MAX, 0.0, 1.0)
	var needle_ang := start_ang + sweep * needle_t
	var needle_col := Color(0.95, 0.95, 0.97, 1)
	if _blown:
		needle_col = Color(0.35, 0.08, 0.08, 1)
	elif _rpm >= _critical:
		needle_col = Color(1.0, 0.18, 0.12, 1)
	elif _rpm >= _redline:
		needle_col = Color(1.0, 0.45, 0.12, 1)
	elif _rpm >= _shift_start:
		needle_col = Color(1.0, 0.85, 0.2, 1)
	draw_line(center, center + Vector2.from_angle(needle_ang) * (radius - 16.0), needle_col, 3.2, true)
	draw_circle(center, 7.0, Color(0.18, 0.18, 0.2, 1))
	draw_circle(center, 3.0, needle_col)

	var readout := "BLOWN" if _blown else "%d" % int(_rpm)
	var readout_size := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(
		font,
		center + Vector2(-readout_size.x * 0.5, 22.0),
		readout,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color(1.0, 0.25, 0.2, 1) if _blown or _rpm >= _critical else Color(0.92, 0.92, 0.94, 0.95)
	)
	draw_string(font, center + Vector2(-16, 38.0), "RPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.72, 0.8))


func _draw_zone(
	center: Vector2,
	radius: float,
	start_ang: float,
	sweep: float,
	from_rpm: float,
	to_rpm: float,
	color: Color
) -> void:
	var a0 := start_ang + sweep * clampf(from_rpm / METER_MAX, 0.0, 1.0)
	var a1 := start_ang + sweep * clampf(to_rpm / METER_MAX, 0.0, 1.0)
	if a1 <= a0:
		return
	draw_arc(center, radius - 8.0, a0, a1, 28, color, 12.0, true)
