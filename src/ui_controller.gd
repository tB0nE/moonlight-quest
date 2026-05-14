class_name UIController
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

func setup_numpad():
	var keys = ["7","8","9","4","5","6","1","2","3",".","0","DEL"]
	for key in keys:
		var btn = Button.new()
		btn.text = key
		btn.custom_minimum_size = Vector2(60, 35)
		btn.size_flags_stretch_ratio = 1.0
		btn.pressed.connect(on_numpad_key.bind(key))
		main.get_node("%Numpad").add_child(btn)

func on_numpad_key(key: String):
	if key == "DEL":
		var text = main.get_node("%IPInput").text
		if text.length() > 0:
			main.get_node("%IPInput").text = text.substr(0, text.length() - 1)
	elif main.get_node("%IPInput").text.length() < 15:
		main.get_node("%IPInput").text += key

func on_ipinput_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		main.get_node("%Numpad").visible = true

func on_sbs_toggled():
	main.auto_detect_enabled = false
	main.settings_controller.cycle_sbs_mode()

func on_ai_3d_toggled():
	main.auto_detect_enabled = false
	main.settings_controller.cycle_ai_3d_mode()

func update_stereo_shader():
	main.screen_mesh.material_override.set_shader_parameter("stereo_mode", main.settings_controller.get_stereo_mode())
	update_option_btn(main._ui_sbs_btn, main.settings_controller.sbs_labels[main.sbs_mode])
	update_option_btn(main._ui_3d_btn, main.settings_controller.ai_3d_labels[main.ai_3d_mode])
	update_3d_btn_state()

func update_3d_btn_state():
	if main._ui_3d_btn:
		var disabled = main.sbs_mode > 0
		main._ui_3d_btn.disabled = disabled
		main._ui_3d_btn.modulate.a = 0.3 if disabled else 1.0

func update_ui():
	main.get_node("%Crosshair").visible = (not main.is_xr_active and not main.mouse_captured_by_stream)
	main.get_node("%Laser").visible = main.is_xr_active

func build_ui():
	main.ui_panel_3d.mesh.size = main._ui_mesh_size
	main.ui_viewport.size = main._ui_viewport_size
	var col_shape = main.ui_panel_3d.get_node("Area3D/CollisionShape3D")
	if col_shape and col_shape.shape:
		col_shape.shape.size = Vector3(main._ui_mesh_size.x, main._ui_mesh_size.y, 0.01)
	var root = main.get_node("%UIRoot")
	for child in root.get_children():
		if child.name != "IPInput" and child.name != "Numpad":
			child.queue_free()

	main._btn_style = StyleBoxFlat.new()
	main._btn_style.bg_color = Color(1, 1, 1, 0.06)
	main._btn_style.set_corner_radius_all(10)
	main._btn_style.set_content_margin_all(8)

	main._btn_hover = StyleBoxFlat.new()
	main._btn_hover.bg_color = Color(1, 1, 1, 0.12)
	main._btn_hover.set_corner_radius_all(10)
	main._btn_hover.set_content_margin_all(8)

	var panel_bg = StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.06, 0.06, 0.1, 0.92)
	panel_bg.set_corner_radius_all(16)

	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", panel_bg)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var brand = Label.new()
	brand.name = "Brand"
	brand.text = "Nightfall"
	brand.add_theme_font_size_override("font_size", 15)
	brand.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.anchor_left = 0.0
	brand.anchor_right = 1.0
	brand.anchor_top = 0.0
	brand.anchor_bottom = 0.0
	brand.offset_top = 0.0
	brand.offset_bottom = 30.0
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(brand)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 0)
	vbox.size_flags_vertical = Control.SIZE_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.add_theme_constant_override("separation", 0)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	main._ui_host_label = Label.new()
	main._ui_host_label.name = "HostLabel"
	main._ui_host_label.add_theme_font_size_override("font_size", 13)
	main._ui_host_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	main._ui_host_label.custom_minimum_size = Vector2(0, 30)
	main._ui_host_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main._ui_host_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var host_pad = Control.new()
	host_pad.custom_minimum_size = Vector2(12, 0)
	host_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(host_pad)
	top_row.add_child(main._ui_host_label)

	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(left_spacer)

	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(right_spacer)

	main._ui_exit_btn = Button.new()
	main._ui_exit_btn.text = "Exit"
	main._ui_exit_btn.focus_mode = Control.FOCUS_NONE
	main._ui_exit_btn.custom_minimum_size = Vector2(50, 18)
	main._ui_exit_btn.add_theme_font_size_override("font_size", 11)
	main._ui_exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	main._ui_exit_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var exit_style = main._btn_style.duplicate()
	exit_style.content_margin_left = 14
	exit_style.content_margin_right = 14
	exit_style.content_margin_top = 2
	exit_style.content_margin_bottom = 2
	exit_style.set_corner_radius_all(0)
	exit_style.set_corner_radius(CORNER_BOTTOM_LEFT, 10)
	var exit_hover = main._btn_hover.duplicate()
	exit_hover.content_margin_left = 14
	exit_hover.content_margin_right = 14
	exit_hover.content_margin_top = 2
	exit_hover.content_margin_bottom = 2
	exit_hover.set_corner_radius_all(0)
	exit_hover.set_corner_radius(CORNER_BOTTOM_LEFT, 10)
	main._ui_exit_btn.add_theme_stylebox_override("normal", exit_style)
	main._ui_exit_btn.add_theme_stylebox_override("hover", exit_hover)
	main._ui_exit_btn.add_theme_stylebox_override("pressed", exit_hover)
	top_row.add_child(main._ui_exit_btn)

	main._ui_disconnect_btn = Button.new()
	main._ui_disconnect_btn.text = "Disconnect"
	main._ui_disconnect_btn.focus_mode = Control.FOCUS_NONE
	main._ui_disconnect_btn.custom_minimum_size = Vector2(70, 18)
	main._ui_disconnect_btn.add_theme_font_size_override("font_size", 11)
	main._ui_disconnect_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	main._ui_disconnect_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var disc_style = main._btn_style.duplicate()
	disc_style.content_margin_left = 10
	disc_style.content_margin_right = 10
	disc_style.content_margin_top = 2
	disc_style.content_margin_bottom = 2
	disc_style.set_corner_radius_all(0)
	var disc_hover = main._btn_hover.duplicate()
	disc_hover.content_margin_left = 10
	disc_hover.content_margin_right = 10
	disc_hover.content_margin_top = 2
	disc_hover.content_margin_bottom = 2
	disc_hover.set_corner_radius_all(0)
	main._ui_disconnect_btn.add_theme_stylebox_override("normal", disc_style)
	main._ui_disconnect_btn.add_theme_stylebox_override("hover", disc_hover)
	main._ui_disconnect_btn.add_theme_stylebox_override("pressed", disc_hover)
	main._ui_disconnect_btn.visible = false
	top_row.add_child(main._ui_disconnect_btn)

	main._ui_close_btn = Button.new()
	main._ui_close_btn.text = "\u2715"
	main._ui_close_btn.focus_mode = Control.FOCUS_NONE
	main._ui_close_btn.custom_minimum_size = Vector2(30, 18)
	main._ui_close_btn.add_theme_font_size_override("font_size", 11)
	main._ui_close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	main._ui_close_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var close_style = main._btn_style.duplicate()
	close_style.content_margin_left = 10
	close_style.content_margin_right = 10
	close_style.content_margin_top = 2
	close_style.content_margin_bottom = 2
	close_style.set_corner_radius_all(0)
	close_style.set_corner_radius(CORNER_TOP_RIGHT, 10)
	var close_hover = main._btn_hover.duplicate()
	close_hover.content_margin_left = 10
	close_hover.content_margin_right = 10
	close_hover.content_margin_top = 2
	close_hover.content_margin_bottom = 2
	close_hover.bg_color = Color(0.86, 0.2, 0.2, 0.3)
	close_hover.set_corner_radius_all(0)
	close_hover.set_corner_radius(CORNER_TOP_RIGHT, 10)
	main._ui_close_btn.add_theme_stylebox_override("normal", close_style)
	main._ui_close_btn.add_theme_stylebox_override("hover", close_hover)
	main._ui_close_btn.add_theme_stylebox_override("pressed", close_hover)
	top_row.add_child(main._ui_close_btn)

	var top_margin = Control.new()
	top_margin.custom_minimum_size = Vector2(0, 22)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_margin)

	var row1 = HBoxContainer.new()
	row1.name = "Row1"
	row1.add_theme_constant_override("separation", 12)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row1)

	main._ui_pt_btn = make_option_btn("Passthrough", "On")
	row1.add_child(main._ui_pt_btn)
	main._ui_curve_btn = make_option_btn("Curve", "Flat")
	row1.add_child(main._ui_curve_btn)
	main._ui_bezel_btn = make_option_btn("Bezel", "On")
	row1.add_child(main._ui_bezel_btn)
	main._ui_cursor_btn = make_option_btn("Cursor", "Circle")
	row1.add_child(main._ui_cursor_btn)

	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(gap)

	var row2 = HBoxContainer.new()
	row2.name = "Row2"
	row2.add_theme_constant_override("separation", 12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row2)

	main._ui_res_btn = make_option_btn("Res", "HD")
	row2.add_child(main._ui_res_btn)
	main._ui_fps_btn = make_option_btn("FPS", "60")
	row2.add_child(main._ui_fps_btn)
	main._ui_bitrate_btn = make_option_btn("Mbit", "Auto")
	row2.add_child(main._ui_bitrate_btn)
	main._ui_render_btn = make_option_btn("Smooth", "0%")
	row2.add_child(main._ui_render_btn)

	var gap2 = Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(gap2)

	var row3 = HBoxContainer.new()
	row3.name = "Row3"
	row3.add_theme_constant_override("separation", 12)
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	row3.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row3.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row3)

	main._ui_wide_btn = make_option_btn("Wide", "Off")
	main._ui_wide_btn.disabled = true
	row3.add_child(main._ui_wide_btn)
	main._ui_sbs_btn = make_option_btn("SBS", "Off")
	row3.add_child(main._ui_sbs_btn)
	main._ui_3d_btn = make_option_btn("3D AI", "2D")
	row3.add_child(main._ui_3d_btn)
	main._ui_sharpen_btn = make_option_btn("Sharp", "0%")
	row3.add_child(main._ui_sharpen_btn)

	main._ui_status_label = Label.new()
	main._ui_status_label.name = "StatusLabel"
	main._ui_status_label.text = "Ready"
	main._ui_status_label.add_theme_font_size_override("font_size", 11)
	main._ui_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	main._ui_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main._ui_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main._ui_status_label.custom_minimum_size = Vector2(0, 28)
	main._ui_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(main._ui_status_label)

	var grab_bar = ColorRect.new()
	grab_bar.name = "CompGrabBar"
	grab_bar.color = Color(1, 1, 1, 1)
	grab_bar.custom_minimum_size = Vector2(0, 14)
	grab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grab_bar.material = ShaderMaterial.new()
	grab_bar.material.shader = preload("res://src/shaders/grab_bar.gdshader")
	grab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(grab_bar)

	var bottom_margin = Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 4)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bottom_margin)

	main._ui_exit_btn.button_down.connect(func(): main.exit_app())
	main._ui_disconnect_btn.button_down.connect(func(): main.disconnect_stream())
	main._ui_close_btn.button_down.connect(func(): main._toggle_ui())
	main._ui_disconnect_btn.visible = main.is_streaming
	main._ui_pt_btn.button_down.connect(func(): main.settings_controller.toggle_passthrough())
	main._ui_curve_btn.button_down.connect(func(): main.screen_manager.cycle_curvature())
	main._ui_bezel_btn.button_down.connect(func(): main.screen_manager.toggle_bezel())
	main._ui_sbs_btn.button_down.connect(func(): on_sbs_toggled())
	main._ui_3d_btn.button_down.connect(func(): on_ai_3d_toggled())
	main._ui_res_btn.button_down.connect(func(): main.settings_controller.cycle_resolution())
	main._ui_fps_btn.button_down.connect(func(): main.settings_controller.cycle_fps())
	main._ui_bitrate_btn.button_down.connect(func(): main.settings_controller.cycle_bitrate())
	main._ui_wide_btn.button_down.connect(func(): main.settings_controller.cycle_double_h())
	main._ui_render_btn.button_down.connect(func(): main.settings_controller.cycle_smooth_mode())
	main._ui_sharpen_btn.button_down.connect(func(): main.settings_controller.cycle_sharpen_mode())
	main._ui_cursor_btn.button_down.connect(func(): main.settings_controller.cycle_cursor_mode())

	update_host_label()

func make_option_btn(label_text: String, value_text: String) -> Button:
	var btn = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = label_text + "\n" + value_text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_stylebox_override("normal", main._btn_style)
	btn.add_theme_stylebox_override("hover", main._btn_hover)
	var pressed_style = main._btn_hover.duplicate()
	pressed_style.bg_color = Color(1, 1, 1, 0.18)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.custom_minimum_size = Vector2(100, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return btn

func update_option_btn(btn: Button, value: String):
	var parts = btn.text.split("\n")
	if parts.size() >= 2:
		btn.text = parts[0] + "\n" + value

func update_host_label():
	if not main.is_streaming:
		if main._ui_host_label:
			main._ui_host_label.text = "Not connected"
		return
	if main._ui_host_label:
		if not main._last_hostname.is_empty():
			main._ui_host_label.text = main._last_hostname
		else:
			var ip = main.get_node("%IPInput").text
			var host_name = ""
			for h in main.stream_backend.get_config_manager().get_hosts():
				if h.has("localaddress") and h.localaddress == ip:
					var hname = h.get("hostname", "")
					if hname != ip and not hname.is_empty():
						host_name = hname
					break
			main._ui_host_label.text = host_name if not host_name.is_empty() else ip
