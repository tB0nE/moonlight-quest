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
var mdns

func _get_mdns():
	if not mdns and ClassDB.class_exists("MoonlightMDNS"):
		mdns = ClassDB.instantiate("MoonlightMDNS")
	return mdns
@onready var xr_origin = $XROrigin3D
@onready var xr_camera = $XROrigin3D/XRCamera3D
@onready var mouse_raycast = %RayCast3D
@onready var hand_raycast = %HandRayCast
@onready var right_hand = %RightHand
@onready var left_hand = %LeftHand
@onready var audio_player = %StreamAudioPlayer
@onready var world_env = $WorldEnvironment

var current_host_id: int = -1
var _last_hostname: String = ""
var _selected_app_id: int = 881448767
var _selected_app_idx: int = 0
var _available_apps: Array = []
var _welcome_screen: String = "welcome"
var _pair_pin: String = ""
var _connecting_ip: String = ""
var _restarting_stream: bool = false
var is_streaming: bool = false
var stereo_mode: int = 0
var is_xr_active: bool = false
var was_clicking: bool = false
var was_right_clicking: bool = false
var right_click_cooldown: float = 0.0
var _was_b_pressed: bool = false
var _was_a_pressed: bool = false
var _startup_reposition: bool = true
var mouse_captured_by_stream: bool = false
var suppress_input_frames: int = 0
var auto_detect_enabled: bool = false
var auto_detect_timer: float = 0.0
var auto_detect_running: bool = false
var detection_history: Array = []
var mouse_sensitivity: float = 0.002
var grabbed_node: Node3D = null
var grab_distance: float = 0.0
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
var render_mode: int = 0
var render_mode_labels: Array = ["Normal", "Smooth", "Softer", "Softest"]
var _xr_base_render_scale: float = 1.0
var _mesh_size: Vector2 = Vector2(3.2, 1.8)
var stream_fps: int = 60
var host_resolution: Vector2i = Vector2i(1920, 1080)
var resolution_idx: int = -1
var resolutions: Array = [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
var resolution_labels: Array = ["1080p", "1440p", "4K"]

var corner_handles: Array = []
var grabbed_corner_idx: int = -1
var corner_anchor_world: Vector3 = Vector3.ZERO

var stream_manager: StreamManager
var xr_interaction: XRInteraction
var input_handler: InputHandler
var ui_controller: UIController
var auto_detect: AutoDetect
var depth_estimator: DepthEstimatorModule
var virtual_keyboard: VirtualKeyboard

var _log_lines: PackedStringArray = []
var _ui_viewport_size := Vector2i(450, 245)
var _ui_mesh_size := Vector2(0.9, 0.49)
var _ui_host_label: Label
var _ui_status_label: Label
var _ui_pt_btn: Button
var _ui_curve_btn: Button
var _ui_bezel_btn: Button
var _ui_mode_btn: Button
var _ui_res_btn: Button
var _ui_fps_btn: Button
var _ui_render_btn: Button
var _ui_exit_btn: Button
var _ui_disconnect_btn: Button
var _ui_close_btn: Button

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
	ui_panel_3d.mesh.size = _ui_mesh_size
	ui_viewport.size = _ui_viewport_size
	var col_shape = ui_panel_3d.get_node("Area3D/CollisionShape3D")
	if col_shape and col_shape.shape:
		col_shape.shape.size = Vector3(_ui_mesh_size.x, _ui_mesh_size.y, 0.01)
	var root = %UIRoot
	for child in root.get_children():
		if child.name != "IPInput" and child.name != "Numpad":
			child.queue_free()

	_btn_style = StyleBoxFlat.new()
	_btn_style.bg_color = Color(1, 1, 1, 0.06)
	_btn_style.set_corner_radius_all(10)
	_btn_style.set_content_margin_all(8)

	_btn_hover = StyleBoxFlat.new()
	_btn_hover.bg_color = Color(1, 1, 1, 0.12)
	_btn_hover.set_corner_radius_all(10)
	_btn_hover.set_content_margin_all(8)

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
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.add_theme_constant_override("separation", 0)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	_ui_host_label = Label.new()
	_ui_host_label.name = "HostLabel"
	_ui_host_label.add_theme_font_size_override("font_size", 13)
	_ui_host_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_ui_host_label.custom_minimum_size = Vector2(0, 30)
	_ui_host_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_host_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var host_pad = Control.new()
	host_pad.custom_minimum_size = Vector2(12, 0)
	host_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(host_pad)
	top_row.add_child(_ui_host_label)

	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(left_spacer)

	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(right_spacer)

	_ui_exit_btn = Button.new()
	_ui_exit_btn.text = "Exit"
	_ui_exit_btn.focus_mode = Control.FOCUS_NONE
	_ui_exit_btn.custom_minimum_size = Vector2(50, 18)
	_ui_exit_btn.add_theme_font_size_override("font_size", 11)
	_ui_exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_ui_exit_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var exit_style = _btn_style.duplicate()
	exit_style.content_margin_left = 14
	exit_style.content_margin_right = 14
	exit_style.content_margin_top = 2
	exit_style.content_margin_bottom = 2
	exit_style.set_corner_radius_all(0)
	exit_style.set_corner_radius(CORNER_BOTTOM_LEFT, 10)
	var exit_hover = _btn_hover.duplicate()
	exit_hover.content_margin_left = 14
	exit_hover.content_margin_right = 14
	exit_hover.content_margin_top = 2
	exit_hover.content_margin_bottom = 2
	exit_hover.set_corner_radius_all(0)
	exit_hover.set_corner_radius(CORNER_BOTTOM_LEFT, 10)
	_ui_exit_btn.add_theme_stylebox_override("normal", exit_style)
	_ui_exit_btn.add_theme_stylebox_override("hover", exit_hover)
	_ui_exit_btn.add_theme_stylebox_override("pressed", exit_hover)
	top_row.add_child(_ui_exit_btn)

	_ui_disconnect_btn = Button.new()
	_ui_disconnect_btn.text = "Disconnect"
	_ui_disconnect_btn.focus_mode = Control.FOCUS_NONE
	_ui_disconnect_btn.custom_minimum_size = Vector2(70, 18)
	_ui_disconnect_btn.add_theme_font_size_override("font_size", 11)
	_ui_disconnect_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_ui_disconnect_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var disc_style = _btn_style.duplicate()
	disc_style.content_margin_left = 10
	disc_style.content_margin_right = 10
	disc_style.content_margin_top = 2
	disc_style.content_margin_bottom = 2
	disc_style.set_corner_radius_all(0)
	var disc_hover = _btn_hover.duplicate()
	disc_hover.content_margin_left = 10
	disc_hover.content_margin_right = 10
	disc_hover.content_margin_top = 2
	disc_hover.content_margin_bottom = 2
	disc_hover.set_corner_radius_all(0)
	_ui_disconnect_btn.add_theme_stylebox_override("normal", disc_style)
	_ui_disconnect_btn.add_theme_stylebox_override("hover", disc_hover)
	_ui_disconnect_btn.add_theme_stylebox_override("pressed", disc_hover)
	_ui_disconnect_btn.visible = false
	top_row.add_child(_ui_disconnect_btn)

	_ui_close_btn = Button.new()
	_ui_close_btn.text = "\u2715"
	_ui_close_btn.focus_mode = Control.FOCUS_NONE
	_ui_close_btn.custom_minimum_size = Vector2(30, 18)
	_ui_close_btn.add_theme_font_size_override("font_size", 11)
	_ui_close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_ui_close_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var close_style = _btn_style.duplicate()
	close_style.content_margin_left = 10
	close_style.content_margin_right = 10
	close_style.content_margin_top = 2
	close_style.content_margin_bottom = 2
	close_style.set_corner_radius_all(0)
	close_style.set_corner_radius(CORNER_TOP_RIGHT, 10)
	var close_hover = _btn_hover.duplicate()
	close_hover.content_margin_left = 10
	close_hover.content_margin_right = 10
	close_hover.content_margin_top = 2
	close_hover.content_margin_bottom = 2
	close_hover.bg_color = Color(0.86, 0.2, 0.2, 0.3)
	close_hover.set_corner_radius_all(0)
	close_hover.set_corner_radius(CORNER_TOP_RIGHT, 10)
	_ui_close_btn.add_theme_stylebox_override("normal", close_style)
	_ui_close_btn.add_theme_stylebox_override("hover", close_hover)
	_ui_close_btn.add_theme_stylebox_override("pressed", close_hover)
	top_row.add_child(_ui_close_btn)

	var top_margin = Control.new()
	top_margin.custom_minimum_size = Vector2(0, 12)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_margin)

	var center_row = HBoxContainer.new()
	center_row.name = "CenterRow"
	center_row.add_theme_constant_override("separation", 12)
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(center_row)

	_ui_pt_btn = _make_option_btn("Passthrough", "On")
	center_row.add_child(_ui_pt_btn)
	_ui_curve_btn = _make_option_btn("Curve", "Flat")
	center_row.add_child(_ui_curve_btn)
	_ui_bezel_btn = _make_option_btn("Bezel", "On")
	center_row.add_child(_ui_bezel_btn)

	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(gap)

	var bottom_row = HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.add_theme_constant_override("separation", 12)
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bottom_row)

	_ui_mode_btn = _make_option_btn("Mode", "2D")
	bottom_row.add_child(_ui_mode_btn)
	_ui_res_btn = _make_option_btn("Resolution", "Auto")
	bottom_row.add_child(_ui_res_btn)
	_ui_fps_btn = _make_option_btn("Refresh", "60Hz")
	bottom_row.add_child(_ui_fps_btn)

	var render_row = HBoxContainer.new()
	render_row.name = "RenderRow"
	render_row.add_theme_constant_override("separation", 12)
	render_row.alignment = BoxContainer.ALIGNMENT_CENTER
	render_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	render_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	render_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(render_row)

	_ui_render_btn = _make_option_btn("Render", "Normal")
	render_row.add_child(_ui_render_btn)

	_ui_status_label = Label.new()
	_ui_status_label.name = "StatusLabel"
	_ui_status_label.text = "Ready"
	_ui_status_label.add_theme_font_size_override("font_size", 11)
	_ui_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	_ui_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_status_label.custom_minimum_size = Vector2(0, 28)
	_ui_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_ui_status_label)

	_ui_exit_btn.button_down.connect(func(): get_tree().quit())
	_ui_disconnect_btn.button_down.connect(func():
		moon.stop_play_stream()
		is_streaming = false
		_ui_disconnect_btn.visible = false
		_set_ui_visible(false)
		screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()
		audio_player.stop()
		_update_welcome_info()
	)
	_ui_close_btn.button_down.connect(func(): _set_ui_visible(false))
	_ui_disconnect_btn.visible = is_streaming
	_ui_pt_btn.button_down.connect(func(): _toggle_passthrough())
	_ui_curve_btn.button_down.connect(func(): _cycle_curvature())
	_ui_bezel_btn.button_down.connect(func(): _toggle_bezel())
	_ui_mode_btn.button_down.connect(func(): ui_controller.on_sbs_toggled())
	_ui_res_btn.button_down.connect(func(): _cycle_resolution())
	_ui_fps_btn.button_down.connect(func(): _cycle_fps())
	_ui_render_btn.button_down.connect(func(): _cycle_render_mode())

	_update_host_label()

func _make_option_btn(label_text: String, value_text: String) -> Button:
	var btn = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = label_text + "\n" + value_text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_stylebox_override("normal", _btn_style)
	btn.add_theme_stylebox_override("hover", _btn_hover)
	var pressed_style = _btn_hover.duplicate()
	pressed_style.bg_color = Color(1, 1, 1, 0.18)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.custom_minimum_size = Vector2(100, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return btn

func _update_option_btn(btn: Button, value: String):
	var parts = btn.text.split("\n")
	if parts.size() >= 2:
		btn.text = parts[0] + "\n" + value

func _update_host_label():
	if not is_streaming:
		if _ui_host_label:
			_ui_host_label.text = "Not connected"
		return
	if _ui_host_label:
		if not _last_hostname.is_empty():
			_ui_host_label.text = _last_hostname
		else:
			var ip = %IPInput.text
			var host_name = ""
			for h in config_mgr.get_hosts():
				if h.has("localaddress") and h.localaddress == ip:
					var hname = h.get("hostname", "")
					if hname != ip and not hname.is_empty():
						host_name = hname
					break
			_ui_host_label.text = host_name if not host_name.is_empty() else ip

func _build_welcome_ui():
	var root = welcome_viewport.get_node("WelcomeRoot")
	for child in root.get_children():
		child.queue_free()

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.12, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var screens = Node.new()
	screens.name = "Screens"
	root.add_child(screens)

	_build_welcome_screen(screens)
	_build_server_screen(screens)
	_build_ip_screen(screens)
	_build_pin_screen(screens)

	_show_welcome_screen("welcome")

func _build_welcome_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "WelcomeScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 60)
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var title = Label.new()
	title.text = "Nightfall"
	title.add_theme_font_size_override("font_size", 96)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Moonlight Streaming for Quest"
	subtitle.add_theme_font_size_override("font_size", 32)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(subtitle)

	var mid_spacer = Control.new()
	mid_spacer.custom_minimum_size = Vector2(0, 40)
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(mid_spacer)

	var server_info = VBoxContainer.new()
	server_info.add_theme_constant_override("separation", 8)
	server_info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	server_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(server_info)

	var host_label = Label.new()
	host_label.name = "WelcomeHostName"
	host_label.add_theme_font_size_override("font_size", 40)
	host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	server_info.add_child(host_label)

	var ip_label = Label.new()
	ip_label.name = "WelcomeHostIP"
	ip_label.add_theme_font_size_override("font_size", 24)
	ip_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	server_info.add_child(ip_label)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 30)
	btn_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(btn_spacer)

	var connect_btn = Button.new()
	connect_btn.name = "WelcomeConnect"
	connect_btn.custom_minimum_size = Vector2(400, 90)
	connect_btn.add_theme_font_size_override("font_size", 36)
	connect_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	connect_btn.text = "Connect"
	screen.add_child(connect_btn)

	var spacer1 = Control.new()
	spacer1.name = "Spacer1"
	spacer1.custom_minimum_size = Vector2(0, 20)
	spacer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(spacer1)

	var app_btn = Button.new()
	app_btn.name = "WelcomeAppBtn"
	app_btn.custom_minimum_size = Vector2(400, 70)
	app_btn.add_theme_font_size_override("font_size", 28)
	app_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	app_btn.text = "App: Desktop"
	app_btn.visible = false
	screen.add_child(app_btn)

	var spacer2 = Control.new()
	spacer2.name = "Spacer2"
	spacer2.custom_minimum_size = Vector2(0, 20)
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(spacer2)

	var change_btn = Button.new()
	change_btn.name = "WelcomeChangeServer"
	change_btn.custom_minimum_size = Vector2(400, 70)
	change_btn.add_theme_font_size_override("font_size", 28)
	change_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	change_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change_btn.text = "Select Server"
	change_btn.visible = false
	screen.add_child(change_btn)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	spacer3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(spacer3)

	var exit_btn = Button.new()
	exit_btn.name = "WelcomeExit"
	exit_btn.custom_minimum_size = Vector2(400, 70)
	exit_btn.add_theme_font_size_override("font_size", 28)
	exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	exit_btn.text = "Exit"
	screen.add_child(exit_btn)

	var bottom_pad = Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 30)
	bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_pad)

	connect_btn.pressed.connect(func():
		var btn_text = connect_btn.text
		if btn_text == "Pair" or btn_text == "Select Server":
			_show_welcome_screen("server")
		else:
			connect_btn.text = "Connecting..."
			connect_btn.disabled = true
			stream_manager.on_pair_pressed()
	)
	change_btn.pressed.connect(func(): _show_welcome_screen("server"))
	app_btn.button_down.connect(func(): _cycle_app())
	exit_btn.pressed.connect(func(): get_tree().quit())

func _build_server_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "ServerScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var heading = Label.new()
	heading.text = "Select Server"
	heading.add_theme_font_size_override("font_size", 48)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	var list_spacer = Control.new()
	list_spacer.custom_minimum_size = Vector2(0, 40)
	list_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(list_spacer)

	var server_list = VBoxContainer.new()
	server_list.name = "ServerList"
	server_list.add_theme_constant_override("separation", 12)
	server_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	server_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(server_list)

	var discover_list = VBoxContainer.new()
	discover_list.name = "DiscoverList"
	discover_list.add_theme_constant_override("separation", 8)
	discover_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	discover_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(discover_list)

	var scan_btn = Button.new()
	scan_btn.name = "ScanBtn"
	scan_btn.custom_minimum_size = Vector2(400, 70)
	scan_btn.add_theme_font_size_override("font_size", 28)
	scan_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
	scan_btn.text = "Scan Network"
	scan_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(scan_btn)

	var add_btn = Button.new()
	add_btn.name = "AddServerBtn"
	add_btn.custom_minimum_size = Vector2(400, 80)
	add_btn.add_theme_font_size_override("font_size", 36)
	add_btn.text = "+"
	add_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(add_btn)

	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_spacer)

	var exit_btn = Button.new()
	exit_btn.custom_minimum_size = Vector2(300, 60)
	exit_btn.add_theme_font_size_override("font_size", 28)
	exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	exit_btn.text = "Exit"
	screen.add_child(exit_btn)

	var back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(300, 60)
	back_btn.add_theme_font_size_override("font_size", 28)
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(back_btn)

	add_btn.pressed.connect(func(): _show_welcome_screen("ip"))
	scan_btn.pressed.connect(func(): _browse_mdns())
	back_btn.pressed.connect(func(): _show_welcome_screen("welcome"))
	exit_btn.pressed.connect(func(): get_tree().quit())

func _build_ip_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "IPScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var heading = Label.new()
	heading.text = "Enter Server IP"
	heading.add_theme_font_size_override("font_size", 48)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	var ip_spacer = Control.new()
	ip_spacer.custom_minimum_size = Vector2(0, 40)
	ip_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(ip_spacer)

	var ip_center = HBoxContainer.new()
	ip_center.alignment = BoxContainer.ALIGNMENT_CENTER
	ip_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(ip_center)

	var ip_input = LineEdit.new()
	ip_input.name = "IPField"
	ip_input.custom_minimum_size = Vector2(600, 80)
	ip_input.add_theme_font_size_override("font_size", 36)
	ip_input.placeholder_text = "e.g. 192.168.1.100"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_center.add_child(ip_input)

	var numpad_spacer = Control.new()
	numpad_spacer.custom_minimum_size = Vector2(0, 30)
	numpad_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(numpad_spacer)

	var numpad_center = CenterContainer.new()
	numpad_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(numpad_center)

	var numpad = GridContainer.new()
	numpad.name = "IPNumpad"
	numpad.columns = 3
	numpad.add_theme_constant_override("h_separation", 8)
	numpad.add_theme_constant_override("v_separation", 8)
	numpad_center.add_child(numpad)

	var keys = ["7","8","9","4","5","6","1","2","3",".","0","DEL"]
	for key in keys:
		var btn = Button.new()
		btn.text = key
		btn.custom_minimum_size = Vector2(120, 80)
		btn.add_theme_font_size_override("font_size", 36)
		numpad.add_child(btn)
		btn.pressed.connect(func():
			var text = ip_input.text
			if key == "DEL":
				if text.length() > 0:
					ip_input.text = text.substr(0, text.length() - 1)
			elif text.length() < 15:
				ip_input.text = text + key
		)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 30)
	btn_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(btn_spacer)

	var pair_btn = Button.new()
	pair_btn.name = "PairBtn"
	pair_btn.custom_minimum_size = Vector2(400, 90)
	pair_btn.add_theme_font_size_override("font_size", 36)
	pair_btn.text = "Pair"
	pair_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(pair_btn)

	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_spacer)

	var exit_btn = Button.new()
	exit_btn.custom_minimum_size = Vector2(300, 60)
	exit_btn.add_theme_font_size_override("font_size", 28)
	exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	exit_btn.text = "Exit"
	screen.add_child(exit_btn)

	var back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(300, 60)
	back_btn.add_theme_font_size_override("font_size", 28)
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(back_btn)

	pair_btn.pressed.connect(func():
		var ip = ip_input.text
		if ip.is_empty():
			return
		_connecting_ip = ip
		%IPInput.text = ip
		_start_pair(ip)
	)
	back_btn.pressed.connect(func(): _show_welcome_screen("server"))
	exit_btn.pressed.connect(func(): get_tree().quit())

func _build_pin_screen(parent: Node):
	var screen = VBoxContainer.new()
	screen.name = "PINScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 0)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	parent.add_child(screen)

	var top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(top_spacer)

	var heading = Label.new()
	heading.text = "Enter PIN on Host"
	heading.add_theme_font_size_override("font_size", 40)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(heading)

	var pin_spacer = Control.new()
	pin_spacer.custom_minimum_size = Vector2(0, 40)
	pin_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(pin_spacer)

	var pin_label = Label.new()
	pin_label.name = "PINLabel"
	pin_label.add_theme_font_size_override("font_size", 80)
	pin_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1, 1))
	pin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pin_label.text = "----"
	pin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(pin_label)

	var done_spacer = Control.new()
	done_spacer.custom_minimum_size = Vector2(0, 60)
	done_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(done_spacer)

	var done_btn = Button.new()
	done_btn.name = "DoneBtn"
	done_btn.custom_minimum_size = Vector2(400, 90)
	done_btn.add_theme_font_size_override("font_size", 36)
	done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	screen.add_child(done_btn)

	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bottom_spacer)

	var exit_btn = Button.new()
	exit_btn.custom_minimum_size = Vector2(300, 60)
	exit_btn.add_theme_font_size_override("font_size", 28)
	exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	exit_btn.text = "Exit"
	screen.add_child(exit_btn)

	done_btn.pressed.connect(func(): _show_welcome_screen("welcome"))
	exit_btn.pressed.connect(func(): get_tree().quit())

var _mdns_browsing: bool = false

func _show_welcome_screen(name: String):
	_welcome_screen = name
	var root = welcome_viewport.get_node("WelcomeRoot/Screens")
	for child in root.get_children():
		child.visible = false
	match name:
		"welcome":
			root.get_node_or_null("WelcomeScreen").visible = true
			_update_welcome_info()
		"server":
			root.get_node_or_null("ServerScreen").visible = true
			_populate_server_list()
		"ip":
			root.get_node_or_null("IPScreen").visible = true
		"pin":
			var pin_screen = root.get_node_or_null("PINScreen")
			if pin_screen:
				pin_screen.visible = true
			var pin_label = root.get_node_or_null("PINScreen/PINLabel")
			if pin_label:
				pin_label.text = _pair_pin if not _pair_pin.is_empty() else "----"

func _update_welcome_info():
	var root = welcome_viewport.get_node_or_null("WelcomeRoot")
	if not root:
		return
	var screens = root.get_node_or_null("Screens")
	if not screens:
		return
	var ws = screens.get_node_or_null("WelcomeScreen")
	if not ws:
		return
	var host_label = ws.get_node_or_null("WelcomeHostName")
	var ip_label = ws.get_node_or_null("WelcomeHostIP")
	var connect_btn = ws.get_node_or_null("WelcomeConnect")
	var app_btn = ws.get_node_or_null("WelcomeAppBtn")
	var change_btn = ws.get_node_or_null("WelcomeChangeServer")
	var spacer1 = ws.get_node_or_null("Spacer1")
	var spacer2 = ws.get_node_or_null("Spacer2")

	var saved_ip = %IPInput.text
	var has_saved = not saved_ip.is_empty()
	var has_hosts = config_mgr.get_hosts().size() > 0

	var host_name = _last_hostname
	if host_name.is_empty():
		for h in config_mgr.get_hosts():
			if h.has("localaddress") and h.localaddress == saved_ip:
				var hname = h.get("hostname", "")
				if hname != saved_ip and not hname.is_empty():
					host_name = hname
				break

	if has_saved:
		if connect_btn and connect_btn.text != "Connecting...":
			connect_btn.text = "Connect"
			connect_btn.disabled = false
		if not host_name.is_empty():
			if host_label: host_label.text = host_name
			if ip_label: ip_label.text = saved_ip
		else:
			if host_label: host_label.text = saved_ip
			if ip_label: ip_label.text = ""
		if app_btn: app_btn.visible = true
		if change_btn: change_btn.visible = true
		if spacer1: spacer1.visible = true
		if spacer2: spacer2.visible = true
		if current_host_id >= 0:
			_query_app_list()
		elif not _available_apps.is_empty():
			if app_btn: app_btn.text = "App: %s" % _available_apps[_selected_app_idx].get("name", "Desktop")
	elif has_hosts:
		if connect_btn: connect_btn.text = "Select Server"
		if host_label: host_label.text = ""
		if ip_label: ip_label.text = ""
		if app_btn: app_btn.visible = false
		if change_btn: change_btn.visible = false
		if spacer1: spacer1.visible = false
		if spacer2: spacer2.visible = false
	else:
		if connect_btn: connect_btn.text = "Pair"
		if host_label: host_label.text = ""
		if ip_label: ip_label.text = ""
		if app_btn: app_btn.visible = false
		if change_btn: change_btn.visible = false
		if spacer1: spacer1.visible = false
		if spacer2: spacer2.visible = false

func _reset_connect_button():
	var root = welcome_viewport.get_node_or_null("WelcomeRoot")
	if not root:
		return
	var screens = root.get_node_or_null("Screens")
	if not screens:
		return
	var ws = screens.get_node_or_null("WelcomeScreen")
	if not ws:
		return
	var connect_btn = ws.get_node_or_null("WelcomeConnect")
	if connect_btn:
		connect_btn.text = "Connect"
		connect_btn.disabled = false

func _save_last_ip(ip: String):
	var save = ConfigFile.new()
	save.set_value("connection", "ip", ip)
	save.save("user://last_connection.cfg")

func _browse_mdns():
	if _mdns_browsing:
		return
	_mdns_browsing = true
	var ss = welcome_viewport.get_node_or_null("WelcomeRoot/Screens/ServerScreen")
	if not ss:
		_mdns_browsing = false
		return
	var discover_list = ss.get_node_or_null("DiscoverList")
	var scan_btn = ss.get_node_or_null("ScanBtn")
	if discover_list:
		for child in discover_list.get_children():
			child.queue_free()
	if scan_btn:
		scan_btn.text = "Scanning..."
		scan_btn.disabled = true
	var hosts = await stream_manager.browse_mdns()
	if discover_list:
		for child in discover_list.get_children():
			child.queue_free()
	if hosts.size() > 0 and discover_list:
		for host in hosts:
			var ip = host.get("ip", "")
			var friendly = host.get("friendly_name", host.get("instance", ip))
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(400, 60)
			btn.add_theme_font_size_override("font_size", 22)
			btn.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.text = friendly + "  " + ip
			var btn_style = StyleBoxFlat.new()
			btn_style.set_bg_color(Color(0.15, 0.18, 0.25, 0.9))
			btn_style.set_border_width_all(1)
			btn_style.set_border_color(Color(0.3, 0.4, 0.6, 0.8))
			btn_style.set_corner_radius_all(8)
			btn_style.set_content_margin_all(6)
			btn.add_theme_stylebox_override("normal", btn_style)
			var hover_style = btn_style.duplicate()
			hover_style.set_bg_color(Color(0.2, 0.25, 0.35, 1.0))
			btn.add_theme_stylebox_override("hover", hover_style)
			var press_style = btn_style.duplicate()
			press_style.set_bg_color(Color(0.3, 0.35, 0.5, 1.0))
			btn.add_theme_stylebox_override("pressed", press_style)
			btn.pressed.connect(func():
				%IPInput.text = ip
				_save_last_ip(ip)
				_load_host_state(ip)
				for h in config_mgr.get_hosts():
					if h.has("localaddress") and h.localaddress == ip:
						current_host_id = h.id
						break
				_show_welcome_screen("welcome")
			)
			discover_list.add_child(btn)
	if scan_btn:
		scan_btn.text = "Scan Network"
		scan_btn.disabled = false
	_mdns_browsing = false

func _populate_server_list():
	var screens = welcome_viewport.get_node("WelcomeRoot/Screens")
	var ss = screens.get_node("ServerScreen")
	var server_list = ss.get_node("ServerList")
	for child in server_list.get_children():
		child.queue_free()

	var hosts = config_mgr.get_hosts()
	for h in hosts:
		var ip = h.get("localaddress", "")
		var hname = h.get("hostname", "")
		if hname == ip:
			hname = ""
		var display = hname if not hname.is_empty() else ip
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(400, 80)
		btn.add_theme_font_size_override("font_size", 36)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.text = display
		server_list.add_child(btn)
		btn.pressed.connect(func():
			_connecting_ip = ip
			%IPInput.text = ip
			var paired = h.get("paired", false) if h.has("paired") else true
			if not paired:
				_start_pair(ip)
			else:
				_show_welcome_screen("welcome")
		)

func _start_pair(ip: String):
	%IPInput.text = ip
	_log("[PAIR] Starting pair with %s:47989..." % ip)
	var pin = comp_mgr.start_pair(ip, 47989)
	_log("[PAIR] start_pair returned: %s" % str(pin))
	if str(pin) == "" or str(pin) == "0":
		_log("[PAIR] FAILED - no pin returned")
		return
	_pair_pin = str(pin)
	_show_welcome_screen("pin")

func _cycle_app():
	if _available_apps.is_empty():
		return
	_selected_app_idx = (_selected_app_idx + 1) % _available_apps.size()
	_selected_app_id = _available_apps[_selected_app_idx].get("id", 881448767)
	var app_name = _available_apps[_selected_app_idx].get("name", "Desktop")
	var screens = welcome_viewport.get_node_or_null("WelcomeRoot/Screens")
	if not screens:
		return
	var app_btn = screens.get_node_or_null("WelcomeScreen/WelcomeAppBtn")
	if app_btn:
		app_btn.text = "App: %s" % app_name

func _query_app_list():
	if current_host_id < 0:
		return
	comp_mgr.get_app_list(current_host_id, func(success: bool):
		if success:
			_available_apps = config_mgr.get_apps(current_host_id)
			if _available_apps.is_empty():
				_available_apps = [{"name": "Desktop", "id": 881448767}]
			_selected_app_idx = 0
			_selected_app_id = _available_apps[0].get("id", 881448767)
			var app_name = _available_apps[0].get("name", "Desktop")
			var screens = welcome_viewport.get_node_or_null("WelcomeRoot/Screens")
			if screens:
				var app_btn = screens.get_node_or_null("WelcomeScreen/WelcomeAppBtn")
				if app_btn:
					app_btn.text = "App: %s" % app_name
					app_btn.visible = true
	)

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
	save.set_value("screen", "render_mode", render_mode)
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
	stereo_mode = clampi(save.get_value(ip, "stereo_mode", 0), 0, 3)
	screen_mesh.material_override.set_shader_parameter("stereo_mode", stereo_mode)
	var mode_names = ["2D", "SBS Stretch", "SBS Crop", "AI 3D"]
	_update_option_btn(_ui_mode_btn, mode_names[stereo_mode])
	_update_option_btn(_ui_fps_btn, "%dHz" % stream_fps)
	if resolution_idx == -1:
		_update_option_btn(_ui_res_btn, "Auto")
	else:
		resolution_idx = clampi(resolution_idx, 0, resolutions.size() - 1)
		host_resolution = resolutions[resolution_idx]
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
	render_mode = save.get_value("screen", "render_mode", 0)
	if save.has_section_key("screen", "size_x"):
		_mesh_size = Vector2(save.get_value("screen", "size_x"), save.get_value("screen", "size_y"))
		if _mesh_size.x > 0.1 and _mesh_size.y > 0.1:
			if curvature == 0:
				screen_mesh.mesh.size = _mesh_size
				_set_screen_collision_flat(_mesh_size)
			else:
				_apply_curvature()
			update_corner_positions()
	if bezel_mesh:
		bezel_mesh.visible = bezel_enabled
	_update_option_btn(_ui_bezel_btn, "On" if bezel_enabled else "Off")
	_update_option_btn(_ui_curve_btn, curvature_labels[clampi(curvature, 0, curvature_labels.size() - 1)])
	_update_option_btn(_ui_pt_btn, passthrough_labels[clampi(passthrough_mode, 0, passthrough_labels.size() - 1)])
	_update_option_btn(_ui_render_btn, render_mode_labels[clampi(render_mode, 0, render_mode_labels.size() - 1)])
	_update_bezel_size()
	if save.has_section_key("ui", "offset_x") and is_xr_active and xr_camera:
		ui_panel_3d.global_position = xr_camera.global_position + Vector3(
			save.get_value("ui", "offset_x"),
			save.get_value("ui", "offset_y"),
			save.get_value("ui", "offset_z"))
		ui_panel_3d.rotation.y = xr_camera.rotation.y + save.get_value("ui", "rot_y", 0.0)
	_apply_render_mode()

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

	virtual_keyboard = VirtualKeyboard.new(self)
	add_child(virtual_keyboard)
	virtual_keyboard.build()

	%ScreenGrabBar.material_override = %ScreenGrabBar.material_override.duplicate()
	%MenuGrabBar.material_override = %MenuGrabBar.material_override.duplicate()
	_mesh_size = screen_mesh.mesh.size
	_create_corner_handles()
	_create_bezel()
	_create_contact_dot()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_load_controller_models()

	_build_ui()
	_build_welcome_ui()

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
		_reset_connect_button()
		if _ui_disconnect_btn: _ui_disconnect_btn.visible = true
		_log("[STREAM] Connection started!")
		stream_manager.bind_texture()
		screen_mesh.material_override.set_shader_parameter("main_texture", stream_viewport.get_texture())
		stream_manager.setup_audio()
		ui_visible = false
		_set_ui_visible(false)
		var starfield = get_node_or_null("Starfield")
		if starfield:
			starfield.emitting = false
			starfield.visible = false
	)
	moon.connection_terminated.connect(func(_err, msg):
		if _restarting_stream:
			_restarting_stream = false
			return
		is_streaming = false
		_ui_status_label.text = "Disconnected: " + str(msg)
		if _ui_disconnect_btn: _ui_disconnect_btn.visible = false
		_log("[STREAM] Connection terminated: %s" % str(msg))
		screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		if mouse_captured_by_stream:
			input_handler.release_stream_mouse()
		audio_player.stop()
		_set_ui_visible(false)
		_reset_connect_button()
		var starfield = get_node_or_null("Starfield")
		if starfield and passthrough_mode == 2:
			starfield.emitting = true
			starfield.visible = true
		_update_welcome_info()
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
		_xr_base_render_scale = get_viewport().scaling_3d_scale
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
		_set_ui_visible(false)
	else:
		is_xr_active = false
		stereo_mode = 0

	config_mgr.load_config()
	var save = ConfigFile.new()
	if save.load("user://last_connection.cfg") == OK:
		var saved_ip = save.get_value("connection", "ip", "")
		if saved_ip != "":
			%IPInput.text = saved_ip
			_load_host_state(saved_ip)
			for h in config_mgr.get_hosts():
				if h.has("localaddress") and h.localaddress == saved_ip:
					current_host_id = h.id
					break
			_update_host_label()
			_update_welcome_info()

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
		var a_pressed = right_hand.is_button_pressed("ax_button")
		if a_pressed and not _was_a_pressed:
			virtual_keyboard.toggle()
		_was_a_pressed = a_pressed
		if _startup_reposition:
			if xr_camera.global_position.length_squared() > 0.01:
				_reposition_screen_and_ui()
				_startup_reposition = false

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
	_set_ui_visible(ui_visible)
	if _ui_disconnect_btn:
		_ui_disconnect_btn.visible = is_streaming

var _ui_saved_offset: Vector3 = Vector3.ZERO
var _ui_saved_rot_y: float = 0.0
var _ui_has_saved_offset: bool = false

func _set_ui_visible(vis: bool):
	ui_panel_3d.visible = vis
	var area = ui_panel_3d.get_node_or_null("Area3D")
	if area:
		area.process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED
	if is_xr_active:
		if vis:
			if _ui_has_saved_offset:
				ui_panel_3d.global_position = screen_mesh.global_position + screen_mesh.global_transform.basis * _ui_saved_offset
				ui_panel_3d.rotation.y = screen_mesh.global_rotation.y + _ui_saved_rot_y
			else:
				var cam_pos = xr_camera.global_position
				var ui_to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
				ui_panel_3d.rotation.y = atan2(ui_to_cam.x, ui_to_cam.z)
		var scr_basis = screen_mesh.global_transform.basis.inverse()
		_ui_saved_offset = scr_basis * (ui_panel_3d.global_position - screen_mesh.global_position)
		_ui_saved_rot_y = ui_panel_3d.rotation.y - screen_mesh.global_rotation.y
		_ui_has_saved_offset = true

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

func _cycle_render_mode():
	render_mode = (render_mode + 1) % 4
	_update_option_btn(_ui_render_btn, render_mode_labels[render_mode])
	_apply_render_mode()
	_save_state()

func _apply_render_mode():
	if not is_xr_active:
		return
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	var mat = screen_mesh.material_override
	match render_mode:
		0:
			if mat: mat.set_shader_parameter("filter_mode", 0)
		1:
			if mat: mat.set_shader_parameter("filter_mode", 1)
		2:
			if mat: mat.set_shader_parameter("filter_mode", 2)
		3:
			if mat: mat.set_shader_parameter("filter_mode", 3)

func _cycle_fps():
	var rates = [60, 90, 120]
	var idx = rates.find(stream_fps)
	stream_fps = rates[(idx + 1) % rates.size()]
	_update_option_btn(_ui_fps_btn, "%dHz" % stream_fps)
	_save_state()
	if is_streaming and current_host_id >= 0:
		_log("[FPS] Restarting stream at %dHz" % stream_fps)
		_restarting_stream = true
		moon.stop_play_stream()
		await get_tree().create_timer(0.5).timeout
		stream_manager.start_stream(current_host_id, _selected_app_id)

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
		_restarting_stream = true
		moon.stop_play_stream()
		await get_tree().create_timer(0.5).timeout
		stream_manager.start_stream(current_host_id, _selected_app_id)

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
			extra += 0.12
		else:
			extra += 0.08
		extra_out = extra
		corner_z = -(cos(half_angle) * radius - radius) - 0.02
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
	%ScreenGrabBar.position.y = -mesh_size.y / 2.0 - 0.08

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
		_set_screen_collision_flat(mesh_size)
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
	_set_screen_collision_curved(verts, indices)

func _update_shader_for_mesh(mesh_size: Vector2):
	_set_screen_collision_flat(mesh_size)
	update_corner_positions()
	if bezel_mesh:
		_update_bezel_size()

func _set_screen_collision_flat(mesh_size: Vector2):
	var col_shape = screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if not col_shape:
		return
	var box = BoxShape3D.new()
	box.size = Vector3(mesh_size.x, mesh_size.y, 0.01)
	col_shape.shape = box

func _set_screen_collision_curved(verts: PackedVector3Array, indices: PackedInt32Array):
	var col_shape = screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if not col_shape:
		return
	var faces = PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(verts[indices[i]])
		faces.append(verts[indices[i + 1]])
		faces.append(verts[indices[i + 2]])
	var concave = ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	col_shape.shape = concave

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
	dot_mat.render_priority = 127
	dot_mat.no_depth_test = true
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
	star_mesh.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mesh.material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	star_mesh.material.no_depth_test = true
	particles.draw_pass_1 = star_mesh
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position
	add_child(particles)
