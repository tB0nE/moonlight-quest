extends Node3D

@onready var moon = $MoonlightStream
@onready var screen_mesh = $MeshInstance3D
@onready var ui_panel_3d = %UIPanel3D
@onready var ui_viewport = %UIViewport
@onready var stream_viewport = %StreamViewport
@onready var stream_target = %StreamTarget
@onready var detection_viewport = %DetectionViewport
@onready var detection_target = %DetectionTarget
@onready var welcome_viewport = %WelcomeViewport
@onready var config_mgr = MoonlightConfigManager.new()
@onready var comp_mgr = MoonlightComputerManager.new()
@onready var xr_origin = $XROrigin3D
@onready var xr_camera = $XROrigin3D/XRCamera3D
@onready var mouse_raycast = %RayCast3D
@onready var hand_raycast = %HandRayCast
@onready var right_hand = %RightHand
@onready var left_hand = %LeftHand
@onready var audio_player = %StreamAudioPlayer
@onready var world_env = $WorldEnvironment

var current_host_id: int = -1
var is_streaming: bool = false
var stereo_mode: int = 0
var is_xr_active: bool = false
var was_clicking: bool = false
var was_right_clicking: bool = false
var right_click_cooldown: float = 0.0
var _was_b_pressed: bool = false
var mouse_captured_by_stream: bool = false
var suppress_input_frames: int = 0
var auto_detect_enabled: bool = false
var auto_detect_timer: float = 0.0
var auto_detect_running: bool = false
var detection_history: Array = []
var mouse_sensitivity: float = 0.002
var grabbed_node: Node3D = null
var grab_distance: float = 0.0
var grab_depth: float = 0.0
var grab_offset: Vector3 = Vector3.ZERO
var grabbed_bar: MeshInstance3D = null
var grab_start_hand_pos: Vector3 = Vector3.ZERO
var grab_start_node_pos: Vector3 = Vector3.ZERO
var grab_forward: Vector3 = Vector3.FORWARD
var grab_start_hand_basis: Basis = Basis()
var grab_start_node_basis: Basis = Basis()
var grab_start_node_euler: Vector3 = Vector3.ZERO
var stats_timer: float = 0.0
var stats_fps: float = 0.0
var stats_frame_times: Array = []
var stats_network_events: int = 0
var passthrough_mode: int = 0
var passthrough_labels: Array = ["On", "Off", "Starfield"]
var ui_visible: bool = false
var bezel_enabled: bool = true
var bezel_mesh: MeshInstance3D
var curvature: int = 0
var curvature_labels: Array = ["Flat", "Slight Curve", "Curved"]
var _mesh_size: Vector2 = Vector2(3.2, 1.8)
var stream_fps: int = 60
var host_resolution: Vector2i = Vector2i(1920, 1080)
var resolution_idx: int = -1
var resolutions: Array = [Vector2i(-1, -1), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
var resolution_labels: Array = ["Auto", "1080p", "1440p", "4K"]

var corner_handles: Array = []
var grabbed_corner_idx: int = -1
var corner_anchor_world: Vector3 = Vector3.ZERO

var stream_manager: StreamManager
var xr_interaction: XRInteraction
var input_handler: InputHandler
var ui_controller: UIController
var auto_detect: AutoDetect
var depth_estimator: DepthEstimatorModule

var _log_lines: PackedStringArray = []
var _ui_host_label: Label
var _ui_status_label: Label
var _ui_pt_btn: Button
var _ui_curve_btn: Button
var _ui_bezel_btn: Button
var _ui_mode_btn: Button
var _ui_res_btn: Button
var _ui_fps_btn: Button
var _ui_exit_btn: Button

var _btn_style: StyleBoxFlat
var _btn_hover: StyleBoxFlat

func _log(msg: String):
	_log_lines.append(msg)
	push_warning("NF: %s" % msg)
	var f = FileAccess.open("user://debug.log", FileAccess.WRITE)
	if f:
		for line in _log_lines:
			f.store_line(line)
		f.close()

func _build_ui():
	ui_panel_3d.mesh.size = Vector2(1.6, 0.7)
	var root = %UIRoot
	for child in root.get_children():
		if child.name != "IPInput" and child.name != "Numpad":
			child.queue_free()

	_btn_style = StyleBoxFlat.new()
	_btn_style.bg_color = Color(1, 1, 1, 0.06)
	_btn_style.border_color = Color(1, 1, 1, 0.1)
	_btn_style.set_border_width_all(1)
	_btn_style.set_corner_radius_all(12)
	_btn_style.set_content_margin_all(10)

	_btn_hover = StyleBoxFlat.new()
	_btn_hover.bg_color = Color(1, 1, 1, 0.12)
	_btn_hover.border_color = Color(1, 1, 1, 0.2)
	_btn_hover.set_border_width_all(1)
	_btn_hover.set_corner_radius_all(12)
	_btn_hover.set_content_margin_all(10)

	var panel_bg = StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.06, 0.06, 0.1, 0.92)
	panel_bg.set_corner_radius_all(24)
	panel_bg.set_content_margin_all(0)
	panel_bg.border_color = Color(1, 1, 1, 0.08)
	panel_bg.set_border_width_all(1)

	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", panel_bg)
	root.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.add_theme_constant_override("separation", 0)
	vbox.add_child(top_row)

	var host_spacer = HBoxContainer.new()
	host_spacer.name = "HostSpacer"
	host_spacer.add_theme_constant_override("separation", 4)
	var host_margin = HBoxContainer.new()
	host_margin.add_theme_constant_override("separation", 0)
	host_margin.custom_minimum_size = Vector2(14, 0)
	host_spacer.add_child(host_margin)
	_ui_host_label = Label.new()
	_ui_host_label.name = "HostLabel"
	_ui_host_label.add_theme_font_size_override("font_size", 14)
	_ui_host_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_ui_host_label.custom_minimum_size = Vector2(0, 52)
	_ui_host_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	host_spacer.add_child(_ui_host_label)
	top_row.add_child(host_spacer)

	var center_spacer = Control.new()
	center_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(center_spacer)

	var brand = Label.new()
	brand.name = "Brand"
	brand.text = "Nightfall"
	brand.add_theme_font_size_override("font_size", 16)
	brand.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(brand)

	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(right_spacer)

	_ui_exit_btn = Button.new()
	_ui_exit_btn.name = "ExitBtn"
	_ui_exit_btn.text = "Exit"
	_ui_exit_btn.add_theme_font_size_override("font_size", 13)
	_ui_exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_ui_exit_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var exit_style = _btn_style.duplicate()
	exit_style.content_margin_left = 16
	exit_style.content_margin_right = 16
	exit_style.content_margin_top = 6
	exit_style.content_margin_bottom = 6
	var exit_hover = _btn_hover.duplicate()
	exit_hover.content_margin_left = 16
	exit_hover.content_margin_right = 16
	exit_hover.content_margin_top = 6
	exit_hover.content_margin_bottom = 6
	exit_hover.bg_color = Color(0.86, 0.2, 0.2, 0.3)
	exit_hover.border_color = Color(0.86, 0.2, 0.2, 0.5)
	_ui_exit_btn.add_theme_stylebox_override("normal", exit_style)
	_ui_exit_btn.add_theme_stylebox_override("hover", exit_hover)
	_ui_exit_btn.add_theme_stylebox_override("pressed", exit_hover)
	var exit_margin = MarginContainer.new()
	exit_margin.add_theme_constant_override("margin_right", 8)
	exit_margin.add_child(_ui_exit_btn)
	top_row.add_child(exit_margin)

	var center_row = HBoxContainer.new()
	center_row.name = "CenterRow"
	center_row.add_theme_constant_override("separation", 16)
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var center_vpad = VBoxContainer.new()
	center_vpad.add_theme_constant_override("separation", 0)
	var cpad_top = Control.new()
	cpad_top.custom_minimum_size = Vector2(0, 6)
	center_vpad.add_child(cpad_top)
	center_vpad.add_child(center_row)
	var cpad_bot = Control.new()
	cpad_bot.custom_minimum_size = Vector2(0, 6)
	center_vpad.add_child(cpad_bot)
	vbox.add_child(center_vpad)

	_ui_pt_btn = _make_option_btn("Passthrough", "On")
	center_row.add_child(_ui_pt_btn)
	_ui_curve_btn = _make_option_btn("Curve", "Flat")
	center_row.add_child(_ui_curve_btn)
	_ui_bezel_btn = _make_option_btn("Bezel", "On")
	center_row.add_child(_ui_bezel_btn)

	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(gap)

	var bottom_row = HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.add_theme_constant_override("separation", 16)
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bottom_row)

	_ui_mode_btn = _make_option_btn("Mode", "2D")
	bottom_row.add_child(_ui_mode_btn)
	_ui_res_btn = _make_option_btn("Resolution", "Auto")
	bottom_row.add_child(_ui_res_btn)
	_ui_fps_btn = _make_option_btn("Refresh", "60Hz")
	bottom_row.add_child(_ui_fps_btn)

	_ui_status_label = Label.new()
	_ui_status_label.name = "StatusLabel"
	_ui_status_label.text = "Ready"
	_ui_status_label.add_theme_font_size_override("font_size", 12)
	_ui_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	_ui_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_status_label.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(_ui_status_label)

	_ui_exit_btn.pressed.connect(func(): get_tree().quit())
	_ui_pt_btn.button_down.connect(func(): _toggle_passthrough())
	_ui_curve_btn.button_down.connect(func(): _cycle_curvature())
	_ui_bezel_btn.button_down.connect(func(): _toggle_bezel())
	_ui_mode_btn.button_down.connect(func(): ui_controller.on_sbs_toggled())
	_ui_res_btn.button_down.connect(func(): _cycle_resolution())
	_ui_fps_btn.button_down.connect(func(): _cycle_fps())

func _make_option_btn(label_text: String, value_text: String) -> Button:
	var btn = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var val = Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(val)
	btn.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_theme_stylebox_override("normal", _btn_style)
	btn.add_theme_stylebox_override("hover", _btn_hover)
	var pressed_style = _btn_hover.duplicate()
	pressed_style.bg_color = Color(1, 1, 1, 0.18)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.custom_minimum_size = Vector2(120, 52)
	return btn

func _update_option_btn(btn: Button, value: String):
	for child in btn.get_children():
		if child is VBoxContainer:
			var labels = child.get_children()
			if labels.size() >= 2:
				labels[1].text = value

func _update_host_label():
	var ip = %IPInput.text
	var host_name = ""
	for h in config_mgr.get_hosts():
		if h.has("localaddress") and h.localaddress == ip:
			host_name = h.name if h.has("name") else ""
			break
	if _ui_host_label:
		_ui_host_label.text = host_name if not host_name.is_empty() else ip

func _save_state():
	var save = ConfigFile.new()
	save.set_value("screen", "pos_x", screen_mesh.global_position.x)
	save.set_value("screen", "pos_y", screen_mesh.global_position.y)
	save.set_value("screen", "pos_z", screen_mesh.global_position.z)
	save.set_value("screen", "rot_x", screen_mesh.rotation.x)
	save.set_value("screen", "rot_y", screen_mesh.rotation.y)
	save.set_value("screen", "size_x", _mesh_size.x)
	save.set_value("screen", "size_y", _mesh_size.y)
	save.set_value("screen", "bezel", bezel_enabled)
	save.set_value("screen", "curvature", curvature)
	save.set_value("screen", "passthrough", passthrough_mode)
	if is_xr_active and xr_camera:
		var ui_offset = ui_panel_3d.global_position - xr_camera.global_position
		save.set_value("ui", "offset_x", ui_offset.x)
		save.set_value("ui", "offset_y", ui_offset.y)
		save.set_value("ui", "offset_z", ui_offset.z)
		save.set_value("ui", "rot_y", ui_panel_3d.rotation.y - xr_camera.rotation.y)
	save.save("user://app_state.cfg")
	_save_host_state()

func _save_host_state():
	var ip = %IPInput.text
	if ip.is_empty():
		return
	var save = ConfigFile.new()
	save.load("user://host_state.cfg")
	save.set_value(ip, "fps", stream_fps)
	save.set_value(ip, "resolution_idx", resolution_idx)
	save.set_value(ip, "stereo_mode", stereo_mode)
	save.save("user://host_state.cfg")

func _load_host_state(ip: String):
	if ip.is_empty():
		return
	var save = ConfigFile.new()
	if save.load("user://host_state.cfg") != OK:
		return
	if not save.has_section(ip):
		return
	stream_fps = save.get_value(ip, "fps", 60)
	resolution_idx = save.get_value(ip, "resolution_idx", -1)
	stereo_mode = save.get_value(ip, "stereo_mode", 0)
	screen_mesh.material_override.set_shader_parameter("stereo_mode", stereo_mode)
	var mode_names = ["2D", "SBS Stretch", "SBS Crop", "AI 3D"]
	_update_option_btn(_ui_mode_btn, mode_names[stereo_mode])
	_update_option_btn(_ui_fps_btn, "%dHz" % stream_fps)
	_update_option_btn(_ui_res_btn, resolution_labels[resolution_idx])
	if depth_estimator:
		depth_estimator.set_enabled(stereo_mode == 3)

func _load_state():
	var save = ConfigFile.new()
	if save.load("user://app_state.cfg") != OK:
		return
	if save.has_section_key("screen", "pos_x"):
		screen_mesh.global_position = Vector3(
			save.get_value("screen", "pos_x"),
			save.get_value("screen", "pos_y"),
			save.get_value("screen", "pos_z"))
		screen_mesh.rotation.x = save.get_value("screen", "rot_x", 0.0)
		screen_mesh.rotation.y = save.get_value("screen", "rot_y", 0.0)
	bezel_enabled = save.get_value("screen", "bezel", true)
	curvature = save.get_value("screen", "curvature", 0)
	passthrough_mode = save.get_value("screen", "passthrough", 0)
	if save.has_section_key("screen", "size_x"):
		_mesh_size = Vector2(save.get_value("screen", "size_x"), save.get_value("screen", "size_y"))
		if _mesh_size.x > 0.1 and _mesh_size.y > 0.1:
			if curvature == 0:
				screen_mesh.mesh.size = _mesh_size
			else:
				_apply_curvature()
			var col_shape = screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
			if col_shape:
				col_shape.shape.size = Vector3(_mesh_size.x, _mesh_size.y, 0.01)
			update_corner_positions()
	if bezel_mesh:
		bezel_mesh.visible = bezel_enabled
	_update_option_btn(_ui_bezel_btn, "On" if bezel_enabled else "Off")
	_update_option_btn(_ui_curve_btn, curvature_labels[curvature])
	_update_option_btn(_ui_pt_btn, passthrough_labels[passthrough_mode])
	_update_bezel_size()
	if save.has_section_key("ui", "offset_x") and is_xr_active and xr_camera:
		ui_panel_3d.global_position = xr_camera.global_position + Vector3(
			save.get_value("ui", "offset_x"),
			save.get_value("ui", "offset_y"),
			save.get_value("ui", "offset_z"))
		ui_panel_3d.rotation.y = xr_camera.rotation.y + save.get_value("ui", "rot_y", 0.0)

func _flush_log():
	var f = FileAccess.open("user://debug.log", FileAccess.WRITE)
	if f:
		for line in _log_lines:
			f.store_line(line)
		f.close()

func _ready():
	OS.set_environment("CURL_CA_BUNDLE", "/system/etc/security/cacerts/")
	OS.set_environment("SSL_CERT_FILE", "/system/etc/security/cacerts/")
	_log("=== Nightfall started ===")
	Engine.max_fps = 60

	stream_manager = StreamManager.new(self)
	xr_interaction = XRInteraction.new(self)
	input_handler = InputHandler.new(self)
	ui_controller = UIController.new(self)
	auto_detect = AutoDetect.new(self)
	depth_estimator = DepthEstimatorModule.new(self)
	depth_estimator.setup()

	%ScreenGrabBar.material_override = %ScreenGrabBar.material_override.duplicate()
	%MenuGrabBar.material_override = %MenuGrabBar.material_override.duplicate()
	_mesh_size = screen_mesh.mesh.size
	_create_corner_handles()
	_create_bezel()
	_create_contact_dot()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_load_controller_models()

	_build_ui()

	%WelcomeConnect.pressed.connect(func():
		%WelcomeConnect.text = "Connecting..."
		%WelcomeConnect.disabled = true
		stream_manager.on_pair_pressed()
	)
	%WelcomeOptions.pressed.connect(func(): _toggle_ui())
	%IPInput.gui_input.connect(func(e): ui_controller.on_ipinput_gui_input(e))
	ui_controller.setup_numpad()

	comp_mgr.set_config_manager(config_mgr)
	moon.set_config_manager(config_mgr)
	comp_mgr.pair_completed.connect(func(s, m): stream_manager.on_pair_completed(s, m))
	moon.log_message.connect(func(msg):
		if "dropped" in msg or "Unrecoverable" in msg or "Waiting for IDR" in msg:
			stats_network_events += 1
	)

	moon.connection_started.connect(func():
		is_streaming = true
		_ui_status_label.text = "Connecting..."
		_update_host_label()
		_log("[STREAM] Connection started!")
		stream_manager.bind_texture()
		screen_mesh.material_override.set_shader_parameter("main_texture", stream_viewport.get_texture())
		stream_manager.setup_audio()
		ui_visible = false
		ui_panel_3d.visible = false
		var starfield = get_node_or_null("Starfield")
		if starfield:
			starfield.emitting = false
			starfield.visible = false
	)
	moon.connection_terminated.connect(func(_err, msg):
		is_streaming = false
		_ui_status_label.text = "Disconnected: " + str(msg)
		_log("[STREAM] Connection terminated: %s" % str(msg))
		screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()
		audio_player.stop()
		ui_visible = false
		ui_panel_3d.visible = false
		var starfield = get_node_or_null("Starfield")
		if starfield and passthrough_mode == 2:
			starfield.emitting = true
			starfield.visible = true
		%WelcomeConnect.text = "Connect"
		%WelcomeConnect.disabled = false
	)

	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.is_initialized():
		var render_size = interface.get_render_target_size()
		_log("[XR] OpenXR render target: %dx%d" % [render_size.x, render_size.y])
		_log("[XR] Blend modes: %s" % str(interface.get_supported_environment_blend_modes()))

		get_viewport().transparent_bg = true
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND

		get_viewport().size = render_size
		get_viewport().use_xr = true
		is_xr_active = true
		stereo_mode = 0
		passthrough_mode = 0

		_create_starfield()

		await get_tree().create_timer(0.5).timeout
		_reposition_screen_and_ui()
		screen_mesh.visible = false
		await get_tree().process_frame
		screen_mesh.visible = true

		_load_state()

		if passthrough_mode > 0:
			var saved_pt = passthrough_mode
			passthrough_mode = 0
			for i in range(saved_pt):
				_toggle_passthrough()

		ui_visible = false
		ui_panel_3d.visible = false
	else:
		is_xr_active = false
		stereo_mode = 0

	var save = ConfigFile.new()
	if save.load("user://last_connection.cfg") == OK:
		var saved_ip = save.get_value("connection", "ip", "")
		if saved_ip != "":
			%IPInput.text = saved_ip
			%WelcomeLastIP.text = "Last: %s" % saved_ip
			_load_host_state(saved_ip)
			_update_host_label()

	stream_manager.bind_texture()
	screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
	ui_controller.update_ui()
	ui_controller.update_stereo_shader()

	Input.joy_connection_changed.connect(func(device, connected):
		_on_joy_changed(device, connected)
	)

func _on_joy_changed(device: int, connected: bool):
	pass

func _process(delta):
	if Engine.get_frames_drawn() % 120 == 0:
		_flush_log()

	if is_xr_active:
		var b_pressed = right_hand.is_button_pressed("by_button")
		if b_pressed and not _was_b_pressed:
			_toggle_ui()
		_was_b_pressed = b_pressed

	if right_click_cooldown > 0.0:
		right_click_cooldown -= delta

	if Input.is_action_just_pressed("ui_focus_next"):
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()

	if Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()

	if not mouse_captured_by_stream:
		xr_interaction.handle_pointer_interaction()

	xr_interaction.handle_scroll()

	var starfield = get_node_or_null("Starfield")
	if starfield and is_xr_active:
		starfield.global_position = xr_camera.global_position

	auto_detect.process(delta)

	if depth_estimator:
		depth_estimator.process(delta)

	if is_streaming:
		stats_frame_times.append(delta)
		stats_timer += delta
		if stats_timer >= 0.5:
			var avg = 0.0
			for t in stats_frame_times:
				avg += t
			if stats_frame_times.size() > 0:
				avg /= stats_frame_times.size()
			stats_fps = 1.0 / avg if avg > 0 else 0.0
			stream_manager.update_stats()
			stats_timer = 0.0
			stats_frame_times.clear()

	if grabbed_node:
		xr_interaction.handle_grab()

	if grabbed_corner_idx >= 0:
		xr_interaction.handle_corner_resize()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_state()

func _input(event):
	input_handler.handle_input(event)

func _toggle_ui():
	ui_visible = not ui_visible
	ui_panel_3d.visible = ui_visible

func _toggle_passthrough():
	if not is_xr_active:
		return
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	passthrough_mode = (passthrough_mode + 1) % 3
	var starfield = get_node_or_null("Starfield")
	_log("[PT] mode=%d starfield=%s" % [passthrough_mode, str(starfield != null)])
	_flush_log()
	if passthrough_mode == 0:
		get_viewport().transparent_bg = true
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		if starfield: starfield.visible = false
	elif passthrough_mode == 1:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		world_env.environment.background_color = Color(0, 0, 0, 1)
		get_viewport().transparent_bg = false
		if starfield: starfield.visible = false
	else:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		world_env.environment.background_color = Color(0, 0, 0, 0)
		get_viewport().transparent_bg = false
		if starfield: starfield.visible = true
	_update_option_btn(_ui_pt_btn, passthrough_labels[passthrough_mode])
	_save_state()

func _cycle_fps():
	var rates = [60, 90, 120]
	var idx = rates.find(stream_fps)
	stream_fps = rates[(idx + 1) % rates.size()]
	_update_option_btn(_ui_fps_btn, "%dHz" % stream_fps)
	_save_state()
	if is_streaming and current_host_id >= 0:
		_log("[FPS] Restarting stream at %dHz" % stream_fps)
		moon.stop_play_stream()
		await get_tree().create_timer(0.5).timeout
		stream_manager.start_stream(current_host_id, 881448767)

func _cycle_resolution():
	resolution_idx += 1
	if resolution_idx >= resolutions.size():
		resolution_idx = -1
	if resolution_idx == -1:
		host_resolution = Vector2i(1920, 1080)
		_update_option_btn(_ui_res_btn, "Auto")
	else:
		host_resolution = resolutions[resolution_idx]
		_update_option_btn(_ui_res_btn, resolution_labels[resolution_idx])
	_save_state()
	if is_streaming and current_host_id >= 0:
		_log("[RES] Restarting stream at %dx%d" % [host_resolution.x, host_resolution.y])
		moon.stop_play_stream()
		await get_tree().create_timer(0.5).timeout
		stream_manager.start_stream(current_host_id, 881448767)

func _reposition_screen_and_ui():
	if not is_xr_active:
		return
	var cam_pos = xr_camera.global_position
	var cam_fwd = -xr_camera.global_transform.basis.z
	var cam_right = xr_camera.global_transform.basis.x
	screen_mesh.global_position = cam_pos + cam_fwd * 2.0 + Vector3(0, 0.3, 0)
	var screen_to_cam = (cam_pos - screen_mesh.global_position).normalized()
	screen_mesh.rotation = Vector3.ZERO
	screen_mesh.rotation.y = atan2(screen_to_cam.x, screen_to_cam.z)
	var ui_dir = (cam_fwd - cam_right).normalized()
	ui_panel_3d.global_position = cam_pos + ui_dir * 1.8
	ui_panel_3d.global_position.y -= 0.4
	var ui_to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
	ui_panel_3d.rotation = Vector3.ZERO
	ui_panel_3d.rotation.y = atan2(ui_to_cam.x, ui_to_cam.z)
	_log("[POS] Screen at %s, UI at %s, Cam at %s" % [str(screen_mesh.global_position), str(ui_panel_3d.global_position), str(cam_pos)])

func _create_corner_handles():
	var offsets = [
		Vector2(-0.5, 0.5),
		Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5),
		Vector2(0.5, -0.5),
	]
	var mesh_size = _mesh_size
	for i in range(4):
		var handle = MeshInstance3D.new()
		handle.name = "Corner%d" % i
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0.01)
		var h_bar = MeshInstance3D.new()
		h_bar.name = "HBar"
		var h_mesh = BoxMesh.new()
		h_mesh.size = Vector3(0.15, 0.008, 0.008)
		h_bar.mesh = h_mesh
		h_bar.material_override = mat.duplicate()
		h_bar.position = Vector3(-offsets[i].x * 0.15, 0, 0)
		var v_bar = MeshInstance3D.new()
		v_bar.name = "VBar"
		var v_mesh = BoxMesh.new()
		v_mesh.size = Vector3(0.008, 0.15, 0.008)
		v_bar.mesh = v_mesh
		v_bar.material_override = mat.duplicate()
		v_bar.position = Vector3(0, -offsets[i].y * 0.15, 0)
		var area = Area3D.new()
		area.collision_layer = 2
		var shape = CollisionShape3D.new()
		var col = BoxShape3D.new()
		col.size = Vector3(0.2, 0.2, 0.1)
		shape.shape = col
		shape.position = Vector3(0, 0, 0)
		area.add_child(shape)
		handle.add_child(h_bar)
		handle.add_child(v_bar)
		handle.add_child(area)
		handle.position = Vector3(offsets[i].x * (mesh_size.x + 0.08), offsets[i].y * (mesh_size.y + 0.08), 0)
		screen_mesh.add_child(handle)
		corner_handles.append(handle)

func update_corner_positions():
	var mesh_size = _mesh_size
	var corner_z = 0.0
	var extra_out = 0.0
	if curvature > 0:
		var radius = 10.0 if curvature == 1 else 4.0
		var angle = mesh_size.x / radius
		var half_angle = angle * 0.5
		var chord_half = sin(half_angle) * radius
		var extra = chord_half - mesh_size.x * 0.5
		if curvature == 2:
			extra += 0.06
		else:
			extra += 0.04
		extra_out = extra
		corner_z = -(cos(half_angle) * radius - radius)
	var offsets = [
		Vector2(-0.5, 0.5),
		Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5),
		Vector2(0.5, -0.5),
	]
	for i in range(4):
		var cx = offsets[i].x * (mesh_size.x + 0.08)
		if curvature > 0:
			var radius = 10.0 if curvature == 1 else 4.0
			var half_angle = mesh_size.x / radius * 0.5
			var a = -half_angle if offsets[i].x < 0 else half_angle
			cx = sin(a) * radius
			cx += -extra_out if offsets[i].x < 0 else extra_out
		corner_handles[i].position = Vector3(cx, offsets[i].y * (mesh_size.y + 0.08), corner_z)
	%ScreenGrabBar.position.y = -mesh_size.y / 2.0 - 0.05

func _create_bezel():
	bezel_mesh = MeshInstance3D.new()
	bezel_mesh.name = "Bezel"
	var bezel_quad = QuadMesh.new()
	bezel_mesh.mesh = bezel_quad
	var bezel_mat = StandardMaterial3D.new()
	bezel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bezel_mat.albedo_color = Color(0, 0, 0, 1)
	bezel_mesh.material_override = bezel_mat
	bezel_mesh.position = Vector3(0, 0, -0.005)
	screen_mesh.add_child(bezel_mesh)
	_update_bezel_size()

func _update_bezel_size():
	if not bezel_mesh:
		return
	var mesh_size = _mesh_size
	var bezel_pad = 0.04
	var bezel_size = mesh_size + Vector2(bezel_pad, bezel_pad)
	if curvature == 0:
		var bezel_quad = QuadMesh.new()
		bezel_quad.size = bezel_size
		bezel_mesh.mesh = bezel_quad
		bezel_mesh.position = Vector3(0, 0, -0.005)
	else:
		var radius = 10.0 if curvature == 1 else 4.0
		var subdivide = 32
		var v_subdivide = 16
		var angle = bezel_size.x / radius
		var verts = PackedVector3Array()
		var uvs = PackedVector2Array()
		var indices = PackedInt32Array()
		for j in range(subdivide + 1):
			for i in range(v_subdivide + 1):
				var t = float(j) / subdivide
				var u = float(i) / v_subdivide
				var a = -angle * 0.5 + angle * t
				var x = sin(a) * radius
				var z = -(cos(a) * radius - radius) - 0.005
				var y = (u - 0.5) * bezel_size.y
				verts.append(Vector3(x, y, z))
				uvs.append(Vector2(t, 1.0 - u))
		var cols = v_subdivide + 1
		for j in range(subdivide):
			for i in range(v_subdivide):
				var idx = j * cols + i
				indices.append(idx)
				indices.append(idx + 1)
				indices.append(idx + cols)
				indices.append(idx + 1)
				indices.append(idx + cols + 1)
				indices.append(idx + cols)
		var arr = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		var arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		bezel_mesh.mesh = arr_mesh
		bezel_mesh.position = Vector3.ZERO

func _toggle_bezel():
	bezel_enabled = not bezel_enabled
	if bezel_mesh:
		bezel_mesh.visible = bezel_enabled
	_update_option_btn(_ui_bezel_btn, "On" if bezel_enabled else "Off")
	_save_state()

func _cycle_curvature():
	curvature = (curvature + 1) % 3
	_apply_curvature()
	_update_option_btn(_ui_curve_btn, curvature_labels[curvature])
	_save_state()

func _apply_curvature():
	var mesh_size = _mesh_size
	if curvature == 0:
		var quad = QuadMesh.new()
		quad.size = mesh_size
		screen_mesh.mesh = quad
		_update_shader_for_mesh(mesh_size)
		return
	var subdivide = 32
	var v_subdivide = 16
	var radius = 10.0 if curvature == 1 else 4.0
	var angle = mesh_size.x / radius
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for j in range(subdivide + 1):
		for i in range(v_subdivide + 1):
			var t = float(j) / subdivide
			var u = float(i) / v_subdivide
			var a = -angle * 0.5 + angle * t
			var x = sin(a) * radius
			var z = -(cos(a) * radius - radius)
			var y = (u - 0.5) * mesh_size.y
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(t, 1.0 - u))
	var cols = v_subdivide + 1
	for j in range(subdivide):
		for i in range(v_subdivide):
			var idx = j * cols + i
			indices.append(idx)
			indices.append(idx + 1)
			indices.append(idx + cols)
			indices.append(idx + 1)
			indices.append(idx + cols + 1)
			indices.append(idx + cols)
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	screen_mesh.mesh = arr_mesh
	_update_shader_for_mesh(mesh_size)

func _update_shader_for_mesh(mesh_size: Vector2):
	var col_shape = screen_mesh.get_node("Area3D/CollisionShape3D")
	if col_shape:
		col_shape.shape.size = Vector3(mesh_size.x, mesh_size.y, 0.01)
	update_corner_positions()
	if bezel_mesh:
		_update_bezel_size()

func _load_controller_models():
	var left_scene = load("res://models/controllers/MetaQuestTouchPlus_Left.fbx")
	var right_scene = load("res://models/controllers/MetaQuestTouchPlus_Right.fbx")
	if left_scene:
		var left_model = left_scene.instantiate()
		left_hand.add_child(left_model)
		left_model.scale = Vector3(1.0, 1.0, 1.0)
		left_model.rotation = Vector3(0, PI, 0)
		_apply_controller_textures(left_model, true)
	if right_scene:
		var right_model = right_scene.instantiate()
		right_hand.add_child(right_model)
		right_model.scale = Vector3(1.0, 1.0, 1.0)
		right_model.rotation = Vector3(0, PI, 0)
		_apply_controller_textures(right_model, false)

func _apply_controller_textures(node: Node, is_left: bool):
	var base_color_path = "res://models/controllers/textures/MetaQuestTouchPlus_Left_BaseColor.png" if is_left else "res://models/controllers/textures/MetaQuestTouchPlus_right_BaseColor.png"
	var base_tex = load(base_color_path)
	if not base_tex:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			for i in range(child.get_surface_override_material_count()):
				var mat = child.get_surface_override_material(i)
				if not mat:
					mat = child.mesh.surface_get_material(i) if child.mesh else null
				if mat is StandardMaterial3D:
					mat = mat.duplicate()
					mat.albedo_texture = base_tex
					child.set_surface_override_material(i, mat)
				elif mat is BaseMaterial3D:
					mat = mat.duplicate()
					mat.albedo_texture = base_tex
					child.set_surface_override_material(i, mat)
		_apply_controller_textures(child, is_left)

var contact_dot: MeshInstance3D

func _create_contact_dot():
	contact_dot = MeshInstance3D.new()
	contact_dot.name = "ContactDot"
	var dot_mesh = SphereMesh.new()
	dot_mesh.radius = 0.01
	dot_mesh.height = 0.02
	contact_dot.mesh = dot_mesh
	var dot_mat = StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1, 1, 1, 0.1)
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact_dot.material_override = dot_mat
	contact_dot.visible = false
	add_child(contact_dot)

func _create_starfield():
	var particles = GPUParticles3D.new()
	particles.name = "Starfield"
	particles.emitting = true
	particles.amount = 1000
	particles.lifetime = 30.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 15
	particles.local_coords = true
	particles.visible = (passthrough_mode == 2)
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(50, 50, 50)
	mat.particle_flag_disable_z = false
	mat.gravity = Vector3.ZERO
	var vel = mat.direction
	vel = Vector3(0, 0, 0)
	mat.direction = vel
	mat.spread = 0.0
	particles.process_material = mat
	var star_mesh = SphereMesh.new()
	star_mesh.radius = 0.05
	star_mesh.height = 0.1
	star_mesh.material = StandardMaterial3D.new()
	star_mesh.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mesh.material.albedo_color = Color.WHITE
	star_mesh.material.emission = Color.WHITE
	star_mesh.material.emission_energy = 2.0
	star_mesh.material.render_priority = -128
	star_mesh.material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	particles.draw_pass_1 = star_mesh
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position
	add_child(particles)
