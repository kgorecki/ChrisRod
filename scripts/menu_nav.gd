extends RefCounted

## Shared W/S and hover focus for menu controls. No extra cursor marker.

var items: Array[Control] = []
var index: int = 0


func setup(list: Array) -> void:
	_unwire()
	for entry in list:
		if entry is Control:
			items.append(entry)
	_wire()
	if not items.is_empty():
		select(clampi(index, 0, items.size() - 1))


func clear() -> void:
	_unwire()


func collect_buttons(root: Node) -> Array:
	var out: Array = []
	_collect_buttons(root, out, true)
	return out


func handle_event(host: Node, event: InputEvent) -> bool:
	if items.is_empty() or host == null:
		return false
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return false
	var viewport := host.get_viewport()
	if viewport != null:
		var focus := viewport.gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return false
	var code: Key = key.keycode
	if code == KEY_UP or code == KEY_W:
		move(-1)
		return true
	if code == KEY_DOWN or code == KEY_S:
		move(1)
		return true
	if code == KEY_LEFT or code == KEY_A:
		return _nudge_slider(-1.0)
	if code == KEY_RIGHT or code == KEY_D:
		return _nudge_slider(1.0)
	return false


func move(delta: int) -> void:
	if items.is_empty():
		return
	var start := index
	for _step in items.size():
		index = wrapi(index + delta, 0, items.size())
		if _can_focus(items[index]):
			select(index)
			return
	select(start)


func select(i: int) -> void:
	if items.is_empty():
		return
	index = clampi(i, 0, items.size() - 1)
	var item := items[index]
	if not is_instance_valid(item):
		return
	if not item.has_focus():
		item.grab_focus()


func _can_focus(item: Control) -> bool:
	if not is_instance_valid(item) or not item.visible:
		return false
	if item is BaseButton and (item as BaseButton).disabled:
		return false
	return true


func _nudge_slider(dir: float) -> bool:
	if items.is_empty():
		return false
	var item := items[index]
	if not item is Range:
		return false
	var slider := item as Range
	slider.value = clampf(slider.value + dir * slider.step, slider.min_value, slider.max_value)
	return true


func _wire() -> void:
	for i in items.size():
		var item := items[i]
		if not is_instance_valid(item):
			continue
		item.focus_mode = Control.FOCUS_ALL
		if item is BaseButton:
			item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_connect_self(item.mouse_entered, _on_item_hover.bind(item))
		_connect_self(item.focus_entered, _on_item_focus.bind(item))


func _unwire() -> void:
	for item in items:
		if not is_instance_valid(item):
			continue
		_disconnect_self(item.mouse_entered)
		_disconnect_self(item.focus_entered)
	items.clear()
	index = 0


func _connect_self(sig: Signal, cb: Callable) -> void:
	for conn in sig.get_connections():
		var existing: Callable = conn.callable
		if existing.get_object() == self:
			return
	sig.connect(cb)


func _disconnect_self(sig: Signal) -> void:
	for conn in sig.get_connections():
		var cb: Callable = conn.callable
		if cb.get_object() == self:
			sig.disconnect(cb)


func _on_item_hover(item: Control) -> void:
	var i := items.find(item)
	if i >= 0:
		select(i)


func _on_item_focus(item: Control) -> void:
	var i := items.find(item)
	if i >= 0:
		index = i


func _collect_buttons(node: Node, out: Array, is_root: bool) -> void:
	if node is Control and not is_root and not (node as Control).visible:
		return
	if node is BaseButton and (node as Control).is_visible_in_tree():
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out, false)
