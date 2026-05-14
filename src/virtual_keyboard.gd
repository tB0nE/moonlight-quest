class_name VirtualKeyboard
extends Node3D

var main: Node3D
var viewport: SubViewport
var mesh_instance: MeshInstance3D
var area: Area3D
var collision_shape: CollisionShape3D
var grab_bar: MeshInstance3D
var grab_bar_area: Area3D
var mesh_size := Vector2(0.8, 0.28)
var viewport_size := Vector2i(1600, 560)
var _kb_root: Control
var _key_data: Array = []
var _held_keys: Dictionary = {}
var _shift_on: bool = false
var _ctrl_on: bool = false
var _alt_on: bool = false
var _caps_on: bool = false

var _KEY_ROWS = [
	[{"k": KEY_ESCAPE, "l": "Esc", "w": 1.5}, {"k": KEY_F1, "l": "F1"}, {"k": KEY_F2, "l": "F2"}, {"k": KEY_F3, "l": "F3"}, {"k": KEY_F4, "l": "F4"}, {"k": KEY_F5, "l": "F5"}, {"k": KEY_F6, "l": "F6"}, {"k": KEY_F7, "l": "F7"}, {"k": KEY_F8, "l": "F8"}, {"k": KEY_F9, "l": "F9"}, {"k": KEY_F10, "l": "F10"}, {"k": KEY_F11, "l": "F11"}, {"k": KEY_F12, "l": "F12"}, {"k": KEY_DELETE, "l": "Del", "w": 1.5}],
	[{"k": KEY_QUOTELEFT, "l": "`"}, {"k": KEY_1, "l": "1"}, {"k": KEY_2, "l": "2"}, {"k": KEY_3, "l": "3"}, {"k": KEY_4, "l": "4"}, {"k": KEY_5, "l": "5"}, {"k": KEY_6, "l": "6"}, {"k": KEY_7, "l": "7"}, {"k": KEY_8, "l": "8"}, {"k": KEY_9, "l": "9"}, {"k": KEY_0, "l": "0"}, {"k": KEY_MINUS, "l": "-"}, {"k": KEY_EQUAL, "l": "="}, {"k": KEY_BACKSPACE, "l": "Bksp", "w": 2.0}],
	[{"k": KEY_TAB, "l": "Tab", "w": 1.5}, {"k": KEY_Q, "l": "Q"}, {"k": KEY_W, "l": "W"}, {"k": KEY_E, "l": "E"}, {"k": KEY_R, "l": "R"}, {"k": KEY_T, "l": "T"}, {"k": KEY_Y, "l": "Y"}, {"k": KEY_U, "l": "U"}, {"k": KEY_I, "l": "I"}, {"k": KEY_O, "l": "O"}, {"k": KEY_P, "l": "P"}, {"k": KEY_BRACKETLEFT, "l": "["}, {"k": KEY_BRACKETRIGHT, "l": "]"}, {"k": KEY_BACKSLASH, "l": "\\", "w": 1.5}],
	[{"k": KEY_CAPSLOCK, "l": "Caps", "w": 1.75}, {"k": KEY_A, "l": "A"}, {"k": KEY_S, "l": "S"}, {"k": KEY_D, "l": "D"}, {"k": KEY_F, "l": "F"}, {"k": KEY_G, "l": "G"}, {"k": KEY_H, "l": "H"}, {"k": KEY_J, "l": "J"}, {"k": KEY_K, "l": "K"}, {"k": KEY_L, "l": "L"}, {"k": KEY_SEMICOLON, "l": ";"}, {"k": KEY_APOSTROPHE, "l": "'"}, {"k": KEY_ENTER, "l": "Enter", "w": 2.25}],
	[{"k": KEY_SHIFT, "l": "Shift", "w": 2.25, "mod": "shift"}, {"k": KEY_Z, "l": "Z"}, {"k": KEY_X, "l": "X"}, {"k": KEY_C, "l": "C"}, {"k": KEY_V, "l": "V"}, {"k": KEY_B, "l": "B"}, {"k": KEY_N, "l": "N"}, {"k": KEY_M, "l": "M"}, {"k": KEY_COMMA, "l": ","}, {"k": KEY_PERIOD, "l": "."}, {"k": KEY_SLASH, "l": "/"}, {"k": KEY_SHIFT, "l": "Shift", "w": 2.75, "mod": "shift"}],
	[{"k": KEY_CTRL, "l": "Ctrl", "w": 1.5, "mod": "ctrl"}, {"k": KEY_ALT, "l": "Alt", "w": 1.5, "mod": "alt"}, {"k": KEY_META, "l": "Super", "w": 1.5}, {"k": KEY_SPACE, "l": "Space", "w": 6.0}, {"k": KEY_META, "l": "Super", "w": 1.5}, {"k": KEY_ALT, "l": "Alt", "w": 1.5, "mod": "alt"}, {"k": KEY_CTRL, "l": "Ctrl", "w": 1.5, "mod": "ctrl"}],
]

func _init(owner: Node3D):
	main = owner

func build():
	viewport = SubViewport.new()
	viewport.name = "KBViewport"
	viewport.size = viewport_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_kb_root = Control.new()
	_kb_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kb_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_kb_root)

	var grab_bar = PanelContainer.new()
	grab_bar.name = "CompGrabBar"
	grab_bar.anchor_left = 0.3
	grab_bar.anchor_right = 0.7
	grab_bar.anchor_top = 0.0
	grab_bar.anchor_bottom = 0.0
	grab_bar.offset_top = 4
	grab_bar.offset_bottom = 14
	var grab_style = StyleBoxFlat.new()
	grab_style.bg_color = Color(1, 1, 1, 0.08)
	grab_style.set_corner_radius_all(4)
	grab_bar.add_theme_stylebox_override("panel", grab_style)
	grab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(grab_bar)

	var kb_bg = ColorRect.new()
	kb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kb_bg.color = Color(0.04, 0.04, 0.1, 0.85)
	kb_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_root.add_child(kb_bg)

	_build_keys()

	var quad = QuadMesh.new()
	quad.size = mesh_size
	quad.flip_faces = true
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "KBPanel"
	mesh_instance.mesh = quad
	var tex_mat = StandardMaterial3D.new()
	tex_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tex_mat.albedo_color = Color(1, 1, 1, 0.85)
	tex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tex_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tex_mat.albedo_texture = viewport.get_texture()
	mesh_instance.set_surface_override_material(0, tex_mat)
	mesh_instance.extra_cull_margin = 10.0
	add_child(mesh_instance)

	area = Area3D.new()
	area.name = "Area3D"
	area.collision_layer = 2
	mesh_instance.add_child(area)
	var shape = BoxShape3D.new()
	shape.size = Vector3(mesh_size.x, mesh_size.y, 0.02)
	collision_shape = CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.position = Vector3(0, 0, 0.01)
	area.add_child(collision_shape)

	grab_bar = MeshInstance3D.new()
	grab_bar.name = "KBGrabBar"
	grab_bar.unique_name_in_owner = true
	var bar_mesh = CylinderMesh.new()
	bar_mesh.top_radius = 0.01
	bar_mesh.bottom_radius = 0.01
	bar_mesh.height = mesh_size.x * 0.6
	grab_bar.mesh = bar_mesh
	var bar_mat = StandardMaterial3D.new()
	bar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.albedo_color = Color(1, 1, 1, 0.01)
	grab_bar.material_override = bar_mat
	grab_bar.rotation_degrees = Vector3(0, 0, 90)
	grab_bar.position = Vector3(0.0, -mesh_size.y / 2.0 - 0.04, 0.0)
	grab_bar.visible = false
	add_child(grab_bar)

	grab_bar_area = Area3D.new()
	grab_bar_area.collision_layer = 2
	grab_bar.add_child(grab_bar_area)
	var bar_shape = BoxShape3D.new()
	bar_shape.size = Vector3(mesh_size.x * 0.15, 0.02, 0.02)
	var bar_cs = CollisionShape3D.new()
	bar_cs.shape = bar_shape
	grab_bar_area.add_child(bar_cs)

	visible = false
	grab_bar.visible = false
	if area:
		area.process_mode = Node.PROCESS_MODE_DISABLED
		area.monitorable = false
		area.monitoring = false

func _build_keys():
	var key_h = 72
	var gap = 6
	var start_y = 16
	var base_w = (viewport_size.x - 12 - gap * 14) / 15.0
	for row_idx in range(_KEY_ROWS.size()):
		var row = _KEY_ROWS[row_idx]
		var x = 12
		var y = start_y + row_idx * (key_h + gap)
		for key_idx in range(row.size()):
			var key_data = row[key_idx]
			var w_unit = key_data.get("w", 1.0)
			var btn_w = w_unit * base_w + (w_unit - 1.0) * gap
			var btn = Button.new()
			btn.name = "Key_%d_%d" % [row_idx, key_idx]
			btn.position = Vector2(x, y)
			btn.size = Vector2(btn_w, key_h)
			btn.text = key_data["l"]
			btn.add_theme_font_size_override("font_size", 24)
			btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
			btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
			var norm = _make_key_style(Color(0.2, 0.2, 0.22, 0.9), Color(0.35, 0.35, 0.38, 1.0))
			btn.add_theme_stylebox_override("normal", norm)
			var hover = _make_key_style(Color(0.3, 0.3, 0.35, 0.95), Color(0.5, 0.5, 0.55, 1.0))
			btn.add_theme_stylebox_override("hover", hover)
			var pressed = _make_key_style(Color(0.45, 0.5, 0.65, 1.0), Color(0.6, 0.65, 0.8, 1.0))
			btn.add_theme_stylebox_override("pressed", pressed)
			_kb_root.add_child(btn)
			_key_data.append({"btn": btn, "key": key_data["k"], "mod": key_data.get("mod", "")})
			x += btn_w + gap
	_apply_modifier_visuals()

func _make_key_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_bg_color(bg)
	s.set_border_width_all(0)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(4)
	return s

func handle_pointer(pixel_pos: Vector2, clicking: bool, was_clicking: bool):
	if not visible:
		return
	var ev_motion = InputEventMouseMotion.new()
	ev_motion.position = pixel_pos
	ev_motion.global_position = pixel_pos
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT if clicking else 0
	viewport.push_input(ev_motion)
	if clicking and not was_clicking:
		var ev = InputEventMouseButton.new()
		ev.position = pixel_pos
		ev.global_position = pixel_pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		viewport.push_input(ev)
		var key_code = _key_from_pos(pixel_pos)
		if key_code >= 0:
			_on_key_press(key_code)
	elif not clicking and was_clicking:
		var ev = InputEventMouseButton.new()
		ev.position = pixel_pos
		ev.global_position = pixel_pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = false
		viewport.push_input(ev)
		for kc in _held_keys.keys():
			_on_key_release(kc)
		_held_keys.clear()

func _key_from_pos(pixel_pos: Vector2) -> int:
	for kd in _key_data:
		var btn = kd["btn"]
		if pixel_pos.x >= btn.position.x and pixel_pos.x <= btn.position.x + btn.size.x \
			and pixel_pos.y >= btn.position.y and pixel_pos.y <= btn.position.y + btn.size.y:
			return kd["key"]
	return -1

func _on_key_press(key_code: int):
	if key_code == KEY_SHIFT:
		_shift_on = not _shift_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_SHIFT, 3 if _shift_on else 4, 0)
		if _shift_on:
			_held_keys[key_code] = true
		return
	if key_code == KEY_CTRL:
		_ctrl_on = not _ctrl_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_CTRL, 3 if _ctrl_on else 4, 0)
		if _ctrl_on:
			_held_keys[key_code] = true
		return
	if key_code == KEY_ALT:
		_alt_on = not _alt_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_ALT, 3 if _alt_on else 4, 0)
		if _alt_on:
			_held_keys[key_code] = true
		return
	if key_code == KEY_CAPSLOCK:
		_caps_on = not _caps_on
		_apply_modifier_visuals()
		main.stream_backend.send_keyboard_event(KEY_CAPSLOCK, 3, 0)
		main.stream_backend.send_keyboard_event(KEY_CAPSLOCK, 4, 0)
		return
	main.stream_backend.send_keyboard_event(key_code, 3, 0)
	_held_keys[key_code] = true

func _on_key_release(key_code: int):
	if key_code == KEY_SHIFT or key_code == KEY_CTRL or key_code == KEY_ALT:
		return
	main.stream_backend.send_keyboard_event(key_code, 4, 0)

func _apply_modifier_visuals():
	for kd in _key_data:
		var btn = kd["btn"]
		var mod = kd["mod"]
		var is_on = false
		if mod == "shift":
			is_on = _shift_on
		elif mod == "ctrl":
			is_on = _ctrl_on
		elif mod == "alt":
			is_on = _alt_on
		elif kd["key"] == KEY_CAPSLOCK:
			is_on = _caps_on
		else:
			continue
		var bg = Color(0.35, 0.45, 0.6, 1.0) if is_on else Color(0.2, 0.2, 0.22, 0.9)
		var border = Color(0.5, 0.6, 0.75, 1.0) if is_on else Color(0.35, 0.35, 0.38, 1.0)
		btn.add_theme_stylebox_override("normal", _make_key_style(bg, border))

var _saved_offset: Vector3 = Vector3.ZERO
var _saved_rot_y: float = 0.0
var _saved_rot_x: float = 0.0
var _has_saved_offset: bool = false

func toggle():
	var new_vis = not visible
	if new_vis:
		if _has_saved_offset:
			global_position = main.screen_mesh.global_position + main.screen_mesh.global_transform.basis * _saved_offset
			rotation.y = main.screen_mesh.global_rotation.y + _saved_rot_y
			rotation.x = _saved_rot_x
		else:
			var cam_pos = main.xr_camera.global_position
			var cam_fwd = -main.xr_camera.global_transform.basis.z
			global_position = cam_pos + cam_fwd * 1.0 + Vector3(0, -0.3, 0)
			var to_cam = (cam_pos - global_position).normalized()
			rotation = Vector3.ZERO
			rotation.y = atan2(to_cam.x, to_cam.z)
			rotation.x = -PI / 4.0
			_has_saved_offset = true
		_save_offset()
	visible = new_vis
	grab_bar.visible = new_vis
	if area:
		area.process_mode = Node.PROCESS_MODE_INHERIT if new_vis else Node.PROCESS_MODE_DISABLED
		area.monitorable = new_vis
		area.monitoring = new_vis
	if grab_bar_area:
		grab_bar_area.process_mode = Node.PROCESS_MODE_INHERIT if new_vis else Node.PROCESS_MODE_DISABLED
		grab_bar_area.monitorable = new_vis
		grab_bar_area.monitoring = new_vis

func _save_offset():
	var scr_basis = main.screen_mesh.global_transform.basis.inverse()
	_saved_offset = scr_basis * (global_position - main.screen_mesh.global_position)
	_saved_rot_y = rotation.y - main.screen_mesh.global_rotation.y
	_saved_rot_x = rotation.x
	_has_saved_offset = true
