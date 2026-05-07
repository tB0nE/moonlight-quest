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
var stream_backend: StreamBackend
var use_nightfall_v2: bool = false

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
var has_depth_model_v2: bool = false
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
var smooth_mode: int = 0
var sharpen_mode: int = 0
var depth_mode: int = 0
var parallax_mode: int = 0
var smooth_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%"]
var sharpen_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%"]
var depth_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"]
var parallax_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"]
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
var welcome_screen: WelcomeScreen
var screen_manager: ScreenManager
var settings_controller: SettingsController
var state_manager: StateManager
var host_discovery: HostDiscovery

var _log_lines: PackedStringArray = []
var _ui_viewport_size := Vector2i(520, 260)
var _ui_mesh_size := Vector2(1.04, 0.52)
var _ui_host_label: Label
var _ui_status_label: Label
var _ui_pt_btn: Button
var _ui_curve_btn: Button
var _ui_bezel_btn: Button
var _ui_mode_btn: Button
var _ui_res_btn: Button
var _ui_fps_btn: Button
var _ui_render_btn: Button
var _ui_sharpen_btn: Button
var _ui_backend_btn: Button
var _ui_depth_btn: Button
var _ui_parallax_btn: Button
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

func _flush_log():
	var f = FileAccess.open("user://debug.log", FileAccess.WRITE)
	if f:
		for line in _log_lines:
			f.store_line(line)
		f.close()

func exit_app():
	get_tree().quit()

func disconnect_stream():
	stream_backend.stop_play_stream()

func _on_stream_started():
	is_streaming = true
	_ui_status_label.text = "Connecting..."
	ui_controller.update_host_label()
	welcome_screen.reset_connect_button()
	if _ui_disconnect_btn: _ui_disconnect_btn.visible = true
	_log("[STREAM] Connection started!")
	stream_manager.bind_texture()
	if not use_nightfall_v2:
		screen_mesh.material_override.set_shader_parameter("main_texture", stream_viewport.get_texture())
	else:
		screen_mesh.material_override.set_shader_parameter("main_texture", stream_viewport.get_texture())
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stream_manager.setup_audio()
	ui_visible = false
	_set_ui_visible(false)
	var starfield = get_node_or_null("Starfield")
	if starfield:
		starfield.emitting = false
		starfield.visible = false

func _on_stream_terminated(msg: String):
	if _restarting_stream:
		_restarting_stream = false
		return
	is_streaming = false
	_ui_status_label.text = "Disconnected: " + str(msg)
	if _ui_disconnect_btn: _ui_disconnect_btn.visible = false
	_log("[STREAM] Connection terminated: %s" % str(msg))
	if use_nightfall_v2:
		stream_manager.teardown_v2_yuv_rect()
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
	if mouse_captured_by_stream:
		input_handler.release_stream_mouse()
	audio_player.stop()
	_set_ui_visible(false)
	welcome_screen.reset_connect_button()
	var starfield = get_node_or_null("Starfield")
	if starfield and passthrough_mode == 2:
		starfield.emitting = true
		starfield.visible = true
	welcome_screen.update_welcome_info()
	stream_manager.resize_stream_viewport(1920, 1080)

func _ready():
	OS.set_environment("CURL_CA_BUNDLE", "/system/etc/security/cacerts/")
	OS.set_environment("SSL_CERT_FILE", "/system/etc/security/cacerts/")
	_log("=== Nightfall started ===")
	Engine.max_fps = 0

	stream_manager = StreamManager.new(self)
	xr_interaction = XRInteraction.new(self)
	input_handler = InputHandler.new(self)
	ui_controller = UIController.new(self)
	auto_detect = AutoDetect.new(self)
	depth_estimator = DepthEstimatorModule.new(self)
	welcome_screen = WelcomeScreen.new(self)
	screen_manager = ScreenManager.new(self)
	settings_controller = SettingsController.new(self)
	state_manager = StateManager.new(self)
	host_discovery = HostDiscovery.new(self)

	depth_estimator.setup()
	if stereo_mode >= settings_controller.get_stereo_mode_count():
		stereo_mode = 0

	virtual_keyboard = VirtualKeyboard.new(self)
	add_child(virtual_keyboard)
	virtual_keyboard.build()

	%ScreenGrabBar.material_override = %ScreenGrabBar.material_override.duplicate()
	%MenuGrabBar.material_override = %MenuGrabBar.material_override.duplicate()
	_mesh_size = screen_mesh.mesh.size
	screen_manager.create_corner_handles()
	screen_manager.create_bezel()
	_create_contact_dot()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_load_controller_models()

	ui_controller.build_ui()
	welcome_screen.build_welcome_ui()

	%IPInput.gui_input.connect(func(e): ui_controller.on_ipinput_gui_input(e))
	ui_controller.setup_numpad()

	comp_mgr.set_config_manager(config_mgr)
	var v2_node = null
	if ClassDB.class_exists("NightfallStream"):
		v2_node = NightfallStream.new()
		add_child(v2_node)
	stream_backend = StreamBackend.new(moon, v2_node)
	var cfg_save = ConfigFile.new()
	if cfg_save.load("user://app_state.cfg") == OK:
		use_nightfall_v2 = cfg_save.get_value("stream", "use_nightfall_v2", false)
	if use_nightfall_v2 and not v2_node:
		use_nightfall_v2 = false
		_log("[STREAM] Nightfall V2 requested but extension not loaded, falling back to V1")
	stream_backend.set_backend(StreamBackend.Backend.V2 if use_nightfall_v2 else StreamBackend.Backend.V1)
	stream_backend.set_config_manager(config_mgr)
	stream_backend.set_computer_manager(comp_mgr)
	has_depth_model_v2 = stream_backend.has_depth_model_v2()
	comp_mgr.pair_completed.connect(func(s, m): stream_manager.on_pair_completed(s, m))
	if use_nightfall_v2 and v2_node:
		v2_node.stream_started.connect(func():
			_on_stream_started()
		)
		v2_node.stream_terminated.connect(func(err_code):
			_on_stream_terminated(str(err_code))
		)
	else:
		moon.log_message.connect(func(msg):
			if "dropped" in msg or "Unrecoverable" in msg or "Waiting for IDR" in msg:
				stats_network_events += 1
		)
		moon.connection_started.connect(func():
			_on_stream_started()
		)
		moon.connection_terminated.connect(func(_err, msg):
			_on_stream_terminated(str(msg))
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

		state_manager.load_state()

		if passthrough_mode > 0:
			var saved_pt = passthrough_mode
			passthrough_mode = 0
			for i in range(saved_pt):
				settings_controller.toggle_passthrough()

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
			state_manager.load_host_state(saved_ip)
			for h in config_mgr.get_hosts():
				if h.has("localaddress") and h.localaddress == saved_ip:
					current_host_id = h.id
					break
			ui_controller.update_host_label()
			welcome_screen.update_welcome_info()

	stream_manager.bind_texture()
	screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
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
		state_manager.save_state()

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
			var cam_pos = xr_camera.global_position
			var ui_to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
			ui_panel_3d.rotation.y = atan2(ui_to_cam.x, ui_to_cam.z)
			if _ui_has_saved_offset:
				ui_panel_3d.global_position = screen_mesh.global_position + screen_mesh.global_transform.basis * _ui_saved_offset
		var scr_basis = screen_mesh.global_transform.basis.inverse()
		_ui_saved_offset = scr_basis * (ui_panel_3d.global_position - screen_mesh.global_position)
		_ui_saved_rot_y = ui_panel_3d.rotation.y - screen_mesh.global_rotation.y
		_ui_has_saved_offset = true

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
	particles.amount = 80
	particles.lifetime = 30.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 10
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
	var star_shader = load("res://src/shaders/star.gdshader")
	var star_mat = ShaderMaterial.new()
	star_mat.shader = star_shader
	star_mat.render_priority = -128
	star_mesh.material = star_mat
	particles.draw_pass_1 = star_mesh
	particles.sorting_offset = -100.0
	particles.position = xr_camera.global_position
	add_child(particles)
