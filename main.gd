extends Node3D

@onready var screen_mesh = $MeshInstance3D
@onready var ui_panel_3d = %UIPanel3D
@onready var ui_viewport = %UIViewport
@onready var stream_viewport = %StreamViewport
@onready var stream_target = %StreamTarget
@onready var detection_viewport = %DetectionViewport
@onready var detection_target = %DetectionTarget
@onready var welcome_viewport = %WelcomeViewport
@onready var config_mgr = NightfallConfigManager.new()
@onready var comp_mgr = NightfallComputerManager.new()
var mdns
var stream_backend: StreamBackend

func _get_mdns():
	if not mdns and ClassDB.class_exists("MdnsBrowser"):
		mdns = ClassDB.instantiate("MdnsBrowser")
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
var _auto_connect: bool = false
var _restarting_stream: bool = false
var is_streaming: bool = false
var sbs_mode: int = 0
var ai_3d_mode: int = 0
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
var curvature: int = 2
var curvature_labels: Array = ["Flat", "Slight Curve", "Curved"]
var smooth_mode: int = 0
var sharpen_mode: int = 0
var smooth_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%"]
var sharpen_labels: Array = ["0%", "10%", "20%", "30%", "40%", "50%"]
var _xr_base_render_scale: float = 1.0
var _xr_render_width: int = 1680
var _mesh_size: Vector2 = Vector2(3.2, 1.8)
var stream_fps: int = 60
var host_resolution: Vector2i = Vector2i(1920, 1080)
var resolution_idx: int = 1
var resolutions: Array = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1600, 1200), Vector2i(3440, 1440)]
var resolution_labels: Array = ["720", "HD", "2K", "4K", "4:3", "21:9"]
var double_h: bool = false
var bitrate_idx: int = -1
var bitrates: Array = [5, 10, 15, 20, 30, 40, 50, 60, 80, 100, 120]
var bitrate_labels: Array = ["Auto", "5", "10", "15", "20", "30", "40", "50", "60", "80", "100", "120"]
var display_refresh_rate: float = 72.0

var cursor_mode: int = 1
var cursor_labels: Array = ["Circle", "Pointer"]
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

var comp_cylinder: Node3D = null
var comp_layer: Node3D = null
var comp_cursor: Node3D = null
var comp_ui: Node3D = null
var comp_kb: Node3D = null
var comp_viewport: SubViewport = null
var comp_cursor_viewport: SubViewport = null
var comp_yuv_rect: ColorRect = null
var comp_shader_mat: ShaderMaterial = null
var use_comp_layer: bool = false
var comp_layer_available: bool = false
var _screen_mesh_saved_mat: Material = null
var _ui_saved_mat: Material = null
var _kb_saved_mat: Material = null

var _log_lines: PackedStringArray = []
var _ui_viewport_size := Vector2i(520, 260)
var _ui_mesh_size := Vector2(1.04, 0.52)
var _ui_host_label: Label
var _ui_status_label: Label
var _ui_pt_btn: Button
var _ui_curve_btn: Button
var _ui_bezel_btn: Button
var _ui_sbs_btn: Button
var _ui_3d_btn: Button
var _ui_res_btn: Button
var _ui_fps_btn: Button
var _ui_bitrate_btn: Button
var _ui_wide_btn: Button
var _ui_render_btn: Button
var _ui_sharpen_btn: Button
var _ui_cursor_btn: Button
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

func _setup_comp_layer():
	if not ClassDB.class_exists("OpenXRCompositionLayerCylinder"):
		_log("[COMP] OpenXRCompositionLayerCylinder not available")
		return

	comp_cylinder = OpenXRCompositionLayerCylinder.new()
	comp_cylinder.name = "CompCylinderLayer"
	comp_cylinder.set_sort_order(1)
	comp_cylinder.set_enable_hole_punch(false)
	comp_cylinder.set_alpha_blend(true)
	comp_cylinder.visible = false
	xr_origin.add_child(comp_cylinder)
	if comp_cylinder.is_natively_supported():
		_log("[COMP] Cylinder layer natively supported")
	else:
		_log("[COMP] Cylinder layer NOT natively supported")

	comp_viewport = SubViewport.new()
	comp_viewport.name = "CompViewport"
	comp_viewport.disable_3d = true
	comp_viewport.transparent_bg = true
	comp_viewport.size = Vector2i(1920, 1080)
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(comp_viewport)

	comp_yuv_rect = ColorRect.new()
	comp_yuv_rect.name = "CompYuvRect"
	comp_yuv_rect.color = Color(0, 0, 0, 1)
	comp_yuv_rect.anchors_preset = 15
	comp_yuv_rect.anchor_right = 1.0
	comp_yuv_rect.anchor_bottom = 1.0
	comp_yuv_rect.grow_horizontal = 2
	comp_yuv_rect.grow_vertical = 2
	comp_viewport.add_child(comp_yuv_rect)

	var stream_rect = ColorRect.new()
	stream_rect.name = "CompStreamRect"
	stream_rect.anchors_preset = 15
	stream_rect.anchor_right = 1.0
	stream_rect.anchor_bottom = 1.0
	stream_rect.grow_horizontal = 2
	stream_rect.grow_vertical = 2
	comp_shader_mat = ShaderMaterial.new()
	comp_shader_mat.shader = load("res://src/shaders/yuv_display.gdshader")
	stream_rect.material = comp_shader_mat
	comp_yuv_rect.add_child(stream_rect)
	comp_yuv_rect = stream_rect

	comp_ui = OpenXRCompositionLayerQuad.new()
	comp_ui.name = "CompUILayer"
	comp_ui.set_sort_order(2)
	comp_ui.set_enable_hole_punch(false)
	comp_ui.set_alpha_blend(true)
	comp_ui.set_quad_size(_ui_mesh_size)
	comp_ui.visible = false
	xr_origin.add_child(comp_ui)
	comp_ui.set_layer_viewport(ui_viewport)
	_log("[COMP] UI composition layer created")

	comp_cursor = OpenXRCompositionLayerQuad.new()
	comp_cursor.name = "CompCursorLayer"
	comp_cursor.set_sort_order(3)
	comp_cursor.set_enable_hole_punch(false)
	comp_cursor.set_alpha_blend(true)
	comp_cursor.set_quad_size(Vector2(0.06, 0.08))
	comp_cursor.visible = false
	xr_origin.add_child(comp_cursor)

	comp_cursor_viewport = SubViewport.new()
	comp_cursor_viewport.name = "CompCursorViewport"
	comp_cursor_viewport.disable_3d = true
	comp_cursor_viewport.transparent_bg = true
	comp_cursor_viewport.size = Vector2i(64, 64)
	comp_cursor_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(comp_cursor_viewport)

	var cursor_rect = TextureRect.new()
	cursor_rect.name = "CursorTexture"
	cursor_rect.anchors_preset = 15
	cursor_rect.anchor_right = 1.0
	cursor_rect.anchor_bottom = 1.0
	cursor_rect.expand_mode = 1
	cursor_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_rect.texture = load("res://src/assets/mouse_pointer_01.png")
	comp_cursor_viewport.add_child(cursor_rect)

	comp_cursor.set_layer_viewport(comp_cursor_viewport)
	_log("[COMP] Cursor composition layer created")

	comp_kb = OpenXRCompositionLayerQuad.new()
	comp_kb.name = "CompKBLayer"
	comp_kb.set_sort_order(4)
	comp_kb.set_enable_hole_punch(false)
	comp_kb.set_alpha_blend(true)
	comp_kb.set_quad_size(virtual_keyboard.mesh_size)
	comp_kb.visible = false
	xr_origin.add_child(comp_kb)
	comp_kb.set_layer_viewport(virtual_keyboard.viewport)
	_log("[COMP] Keyboard composition layer created")

	comp_layer = comp_cylinder
	comp_layer.set_layer_viewport(comp_viewport)
	comp_layer_available = true
	_log("[COMP] Composition layer cylinder created")

func _update_comp_bezel():
	if not comp_yuv_rect:
		return
	if bezel_enabled and use_comp_layer:
		var px = 8
		comp_yuv_rect.offset_left = px
		comp_yuv_rect.offset_top = px
		comp_yuv_rect.offset_right = -px
		comp_yuv_rect.offset_bottom = -px
		comp_yuv_rect.anchor_left = 0.0
		comp_yuv_rect.anchor_top = 0.0
		comp_yuv_rect.anchor_right = 1.0
		comp_yuv_rect.anchor_bottom = 1.0
		comp_yuv_rect.anchors_preset = 0
	else:
		comp_yuv_rect.offset_left = 0
		comp_yuv_rect.offset_top = 0
		comp_yuv_rect.offset_right = 0
		comp_yuv_rect.offset_bottom = 0
		comp_yuv_rect.anchors_preset = 15

func _update_cylinder_params():
	if not comp_cylinder:
		return
	var cam_to_screen = screen_mesh.global_position - xr_camera.global_position
	var view_dist = cam_to_screen.length()
	if view_dist < 0.5:
		view_dist = 3.0
	var radius = view_dist * 100.0
	if curvature == 1:
		radius = view_dist * 2.0
	elif curvature == 2:
		radius = view_dist * 1.0
	var screen_forward = -screen_mesh.global_transform.basis.z
	comp_cylinder.set_radius(radius)
	comp_cylinder.set_central_angle(_mesh_size.x / radius)
	comp_cylinder.set_aspect_ratio(_mesh_size.x / _mesh_size.y)
	comp_cylinder.global_position = screen_mesh.global_position - screen_forward * radius
	comp_cylinder.global_position.y = screen_mesh.global_position.y
	comp_cylinder.global_rotation.y = screen_mesh.global_rotation.y
	_log("[COMP] Cylinder params: radius=%.1f angle=%.3f aspect=%.2f curv=%d" % [radius, _mesh_size.x / radius, _mesh_size.x / _mesh_size.y, curvature])

func _make_screen_transparent():
	_screen_mesh_saved_mat = screen_mesh.material_override
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mesh.material_override = mat

func _make_ui_transparent():
	_ui_saved_mat = ui_panel_3d.material_override
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ui_panel_3d.material_override = mat

func _make_kb_transparent():
	if not virtual_keyboard:
		return
	_kb_saved_mat = virtual_keyboard.mesh_instance.material_override
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	virtual_keyboard.mesh_instance.material_override = mat

func _restore_screen_material():
	if _screen_mesh_saved_mat:
		screen_mesh.material_override = _screen_mesh_saved_mat
		_screen_mesh_saved_mat = null

func _restore_ui_material():
	if _ui_saved_mat:
		ui_panel_3d.material_override = _ui_saved_mat
		_ui_saved_mat = null

func _restore_kb_material():
	if _kb_saved_mat and virtual_keyboard:
		virtual_keyboard.mesh_instance.material_override = _kb_saved_mat
		_kb_saved_mat = null

func _update_cursor_layer():
	if not comp_cursor or not use_comp_layer or cursor_mode == 0:
		if comp_cursor:
			comp_cursor.visible = false
		return
	var active_raycast = hand_raycast if is_xr_active else mouse_raycast
	if active_raycast.is_colliding():
		var hit_point = active_raycast.get_collision_point()
		var to_cam = (xr_camera.global_position - hit_point).normalized()
		comp_cursor.global_position = hit_point + to_cam * 0.002
		comp_cursor.look_at(comp_cursor.global_position + to_cam, Vector3.UP)
		comp_cursor.rotate_object_local(Vector3.UP, PI)
		comp_cursor.visible = true
	else:
		comp_cursor.visible = false
	if comp_ui and comp_ui.visible:
		comp_ui.global_position = ui_panel_3d.global_position
		comp_ui.global_rotation = ui_panel_3d.global_rotation
	if comp_kb and virtual_keyboard and virtual_keyboard.visible:
		comp_kb.global_position = virtual_keyboard.global_position
		comp_kb.global_rotation = virtual_keyboard.global_rotation
		comp_kb.visible = true
	else:
		if comp_kb:
			comp_kb.visible = false

func exit_app():
	get_tree().quit()

func disconnect_stream():
	if current_host_id >= 0:
		stream_backend.cancel_host_stream(current_host_id)
	stream_backend.stop_play_stream()

func _bind_yuv_textures():
	var mat = stream_backend.get_shader_material()
	if not mat:
		_log("[YUV] No shader material from stream backend, using SubViewport path")
		var stream_tex = stream_viewport.get_texture()
		screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
		screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		_bind_comp_fallback_texture(stream_tex)
		return
	var tex_y = mat.get_shader_parameter("tex_y")
	var tex_u = mat.get_shader_parameter("tex_u")
	var tex_v = mat.get_shader_parameter("tex_v")
	var is_nv12_rd = mat.get_shader_parameter("is_nv12_rd")
	var is_semi_planar = mat.get_shader_parameter("is_semi_planar")
	var cmt = mat.get_shader_parameter("color_matrix_type")
	var cr = mat.get_shader_parameter("color_range")
	if tex_y:
		screen_mesh.material_override.set_shader_parameter("tex_y", tex_y)
		screen_mesh.material_override.set_shader_parameter("tex_u", tex_u)
		screen_mesh.material_override.set_shader_parameter("tex_v", tex_v)
		screen_mesh.material_override.set_shader_parameter("color_matrix_type", cmt)
		screen_mesh.material_override.set_shader_parameter("color_range", cr)
		var yuv_mode_val = 0
		if is_nv12_rd:
			yuv_mode_val = 1
		elif is_semi_planar:
			yuv_mode_val = 2
		else:
			yuv_mode_val = 3
		screen_mesh.material_override.set_shader_parameter("yuv_mode", yuv_mode_val)
		_log("[YUV] Direct YUV binding: mode=%d nv12_rd=%s semi_planar=%s" % [yuv_mode_val, str(is_nv12_rd), str(is_semi_planar)])
		_bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode_val, cmt, cr)
	else:
		var stream_tex = stream_viewport.get_texture()
		screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
		screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
		_log("[YUV] No Y textures, falling back to SubViewport path")
		_bind_comp_fallback_texture(stream_tex)

func _bind_comp_yuv_textures(tex_y, tex_u, tex_v, yuv_mode: int, cmt, cr):
	if not comp_shader_mat:
		return
	comp_shader_mat.set_shader_parameter("tex_y", tex_y)
	comp_shader_mat.set_shader_parameter("tex_u", tex_u)
	comp_shader_mat.set_shader_parameter("tex_v", tex_v)
	comp_shader_mat.set_shader_parameter("yuv_mode", yuv_mode)
	comp_shader_mat.set_shader_parameter("color_matrix_type", cmt)
	comp_shader_mat.set_shader_parameter("color_range", cr)
	_log("[COMP] YUV textures bound to composition layer shader (mode=%d)" % yuv_mode)

func _bind_comp_fallback_texture(stream_tex):
	if not comp_shader_mat:
		return
	comp_shader_mat.set_shader_parameter("main_texture", stream_tex)
	comp_shader_mat.set_shader_parameter("yuv_mode", 0)

func _on_stream_started():
	is_streaming = true
	_restarting_stream = false
	_ui_status_label.text = "Connecting..."
	ui_controller.update_host_label()
	welcome_screen.reset_connect_button()
	if _ui_disconnect_btn: _ui_disconnect_btn.visible = true
	_log("[STREAM] Connection started!")
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stream_manager.bind_texture()
	_bind_yuv_textures()
	_switch_to_comp_layer()
	ui_visible = false
	_set_ui_visible(false)
	var starfield = get_node_or_null("Starfield")
	if starfield:
		starfield.emitting = false
		starfield.visible = false

func _switch_to_comp_layer():
	if not comp_layer_available:
		use_comp_layer = false
		_log("[COMP] Not available, using mesh rendering")
		return
	if sbs_mode != 0 or ai_3d_mode != 0:
		use_comp_layer = false
		if comp_cylinder: comp_cylinder.visible = false
		_log("[COMP] Stereo mode active, using mesh rendering")
		return
	use_comp_layer = true
	if comp_cylinder:
		comp_layer = comp_cylinder
		comp_layer.set_layer_viewport(comp_viewport)
		comp_layer.visible = true
		_update_cylinder_params()
		_log("[COMP] Switched to composition layer (cylinder, curv=%d)" % curvature)
	else:
		comp_layer.set_layer_viewport(comp_viewport)
		comp_layer.visible = true
		_log("[COMP] Switched to composition layer (quad fallback)")
	comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_make_screen_transparent()
	bezel_mesh.visible = false
	_update_comp_bezel()

func _switch_to_mesh_rendering():
	use_comp_layer = false
	if comp_cylinder: comp_cylinder.visible = false
	if comp_ui: comp_ui.visible = false
	if comp_kb: comp_kb.visible = false
	if comp_cursor: comp_cursor.visible = false
	if comp_viewport:
		comp_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_restore_screen_material()
	_restore_ui_material()
	_restore_kb_material()
	bezel_mesh.visible = bezel_enabled

func _update_comp_layer_size():
	_update_cylinder_params()

func _on_stream_terminated(msg: String):
	_log("[NF] _on_stream_terminated: auto=" + str(_auto_connect) + " restarting=" + str(_restarting_stream) + " msg=" + str(msg))
	if _auto_connect:
		_auto_connect = false
		return
	if _restarting_stream:
		is_streaming = false
		return
	is_streaming = false
	_ui_status_label.text = "Disconnected: " + str(msg)
	if _ui_disconnect_btn: _ui_disconnect_btn.visible = false
	_log("[STREAM] Connection terminated: %s" % str(msg))
	stream_manager.teardown_v2_yuv_rect()
	_restore_screen_material()
	screen_mesh.material_override.set_shader_parameter("yuv_mode", 0)
	screen_mesh.material_override.set_shader_parameter("tex_y", null)
	screen_mesh.material_override.set_shader_parameter("tex_u", null)
	screen_mesh.material_override.set_shader_parameter("tex_v", null)
	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	welcome_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_clear_comp_yuv_textures()
	comp_shader_mat.set_shader_parameter("main_texture", welcome_viewport.get_texture())
	comp_shader_mat.set_shader_parameter("yuv_mode", 0)
	if comp_layer_available and sbs_mode == 0 and ai_3d_mode == 0:
		_switch_to_comp_layer()
	else:
		screen_mesh.material_override.set_shader_parameter("main_texture", welcome_viewport.get_texture())
		_switch_to_mesh_rendering()
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

func _clear_comp_yuv_textures():
	if not comp_shader_mat:
		return
	comp_shader_mat.set_shader_parameter("tex_y", null)
	comp_shader_mat.set_shader_parameter("tex_u", null)
	comp_shader_mat.set_shader_parameter("tex_v", null)
	comp_shader_mat.set_shader_parameter("yuv_mode", 0)
	comp_shader_mat.set_shader_parameter("main_texture", null)

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
	sbs_mode = clampi(sbs_mode, 0, 2)
	ai_3d_mode = clampi(ai_3d_mode, 0, 1)

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
		v2_node = ClassDB.instantiate("NightfallStream")
		add_child(v2_node)
	stream_backend = StreamBackend.new(v2_node)
	stream_backend.set_config_manager(config_mgr)
	stream_backend.set_computer_manager(comp_mgr)
	if v2_node:
		v2_node.pair_completed.connect(func(s, m): stream_manager.on_pair_completed(s, m))
		v2_node.stream_started.connect(func():
			_on_stream_started()
		)
		v2_node.stream_terminated.connect(func(err_code, err_msg):
			_on_stream_terminated(err_msg)
		)
		v2_node.log_message.connect(func(msg):
			if "dropped" in msg or "Unrecoverable" in msg or "Waiting for IDR" in msg:
				stats_network_events += 1
		)

	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.is_initialized():
		var render_size = interface.get_render_target_size()
		_xr_render_width = int(render_size.x)
		_log("[XR] OpenXR render target: %dx%d" % [render_size.x, render_size.y])
		_log("[XR] Blend modes: %s" % str(interface.get_supported_environment_blend_modes()))

		get_viewport().transparent_bg = true
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND

		get_viewport().size = render_size
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_xr_base_render_scale = get_viewport().scaling_3d_scale
		is_xr_active = true
		sbs_mode = 0
		ai_3d_mode = 0
		passthrough_mode = 0

		settings_controller.apply_display_refresh_rate()

		_create_starfield()

		_setup_comp_layer()
		if comp_layer_available:
			comp_shader_mat.set_shader_parameter("main_texture", welcome_viewport.get_texture())
			comp_shader_mat.set_shader_parameter("yuv_mode", 0)
			comp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

		await get_tree().create_timer(0.5).timeout
		_reposition_screen_and_ui()

		screen_mesh.extra_cull_margin = 10.0
		ui_panel_3d.extra_cull_margin = 10.0

		state_manager.load_state()

		if comp_layer_available:
			_switch_to_comp_layer()

		if passthrough_mode > 0:
			var saved_pt = passthrough_mode
			passthrough_mode = 0
			for i in range(saved_pt):
				settings_controller.toggle_passthrough()

		ui_visible = false
		_set_ui_visible(false)
	else:
		is_xr_active = false
		sbs_mode = 0
		ai_3d_mode = 0

	config_mgr.load_config()
	var saved_ip = ""
	var save = ConfigFile.new()
	if save.load("user://last_connection.cfg") == OK:
		saved_ip = save.get_value("connection", "ip", "")
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
	var _wt = welcome_viewport.get_texture()

	stream_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ui_controller.update_ui()
	ui_controller.update_stereo_shader()

	if _auto_connect:
		var v2_cm = stream_backend.get_config_manager()
		if v2_cm:
			var v2_hosts = v2_cm.get_hosts()
			if v2_hosts.size() > 0:
				var h = v2_hosts[0]
				var host_ip = h.get("localaddress", "") if h.has("localaddress") else saved_ip
				var host_id = h.get("id", -1) if h.has("id") else -1
				if host_id != -1 and host_ip != "":
					current_host_id = host_id
					%IPInput.text = host_ip
					_log("[AUTO-CONNECT] Auto-connecting to host_id=%d ip=%s" % [host_id, host_ip])
					_auto_connect = false
					await get_tree().create_timer(1.0).timeout
					stream_manager.start_stream(host_id, _selected_app_id)

	Input.joy_connection_changed.connect(func(device, connected):
		_on_joy_changed(device, connected)
	)

	_post_ready_check.call_deferred()

func _post_ready_check():
	await get_tree().create_timer(0.5).timeout



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
	_update_cursor_layer()

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
	if ui_visible:
		if comp_ui:
			comp_ui.visible = true
			comp_ui.global_position = ui_panel_3d.global_position
			comp_ui.global_rotation = ui_panel_3d.global_rotation
		if use_comp_layer:
			_make_ui_transparent()
		else:
			var ui_tex = ui_viewport.get_texture()
			ui_panel_3d.material_override.albedo_texture = ui_tex
	else:
		if comp_ui:
			comp_ui.visible = false
		_restore_ui_material()
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
	if is_xr_active and vis:
		var cam_pos = xr_camera.global_position
		var ui_to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
		if _ui_has_saved_offset:
			ui_panel_3d.global_position = screen_mesh.global_position + screen_mesh.global_transform.basis * _ui_saved_offset
			ui_to_cam = (cam_pos - ui_panel_3d.global_position).normalized()
		ui_panel_3d.rotation.y = atan2(ui_to_cam.x, ui_to_cam.z)
		ui_panel_3d.rotation.x = -0.26
		_ui_has_saved_offset = true
	elif is_xr_active:
		var scr_basis = screen_mesh.global_transform.basis.inverse()
		_ui_saved_offset = scr_basis * (ui_panel_3d.global_position - screen_mesh.global_position)
		_ui_has_saved_offset = true

func _reposition_screen_and_ui():
	if not is_xr_active:
		return
	var cam_pos = xr_camera.global_position
	var cam_fwd = -xr_camera.global_transform.basis.z
	var cam_right = xr_camera.global_transform.basis.x
	var cam_yaw = atan2(-cam_fwd.x, -cam_fwd.z)
	var fwd_flat = Vector3(-sin(cam_yaw), 0, -cos(cam_yaw)).normalized()
	var right_flat = Vector3(cos(cam_yaw), 0, -sin(cam_yaw)).normalized()
	var floor_y = xr_origin.global_position.y
	screen_mesh.global_position = cam_pos + fwd_flat * 3.0
	screen_mesh.global_position.y = floor_y + 1.3
	screen_mesh.rotation = Vector3.ZERO
	screen_mesh.rotation.y = cam_yaw
	if comp_cylinder and comp_cylinder.visible:
		_update_cylinder_params()
	ui_panel_3d.global_position = cam_pos + fwd_flat * 1.5 - right_flat * 1.2
	ui_panel_3d.global_position.y = floor_y + 1.1
	ui_panel_3d.rotation = Vector3.ZERO
	ui_panel_3d.rotation.y = cam_yaw
	ui_panel_3d.rotation.x = -0.26
	_log("[POS] Screen at %s, UI at %s, Cam at %s floor_y=%s" % [str(screen_mesh.global_position), str(ui_panel_3d.global_position), str(cam_pos), str(floor_y)])

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
var pointer_cursor: MeshInstance3D

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

	pointer_cursor = MeshInstance3D.new()
	pointer_cursor.name = "PointerCursor"
	var ptr_mesh = QuadMesh.new()
	ptr_mesh.size = Vector2(0.06, 0.08)
	pointer_cursor.mesh = ptr_mesh
	var ptr_mat = StandardMaterial3D.new()
	ptr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ptr_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ptr_mat.render_priority = 127
	ptr_mat.no_depth_test = true
	ptr_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ptr_mat.albedo_texture = load("res://src/assets/mouse_pointer_01.png")
	ptr_mat.albedo_color = Color(1, 1, 1, 1.0)
	pointer_cursor.material_override = ptr_mat
	pointer_cursor.visible = false
	pointer_cursor.extra_cull_margin = 10.0
	add_child(pointer_cursor)

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
