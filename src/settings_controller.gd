class_name SettingsController
extends RefCounted

var main: Node3D

var sbs_labels: Array = ["Off", "Stretch", "Crop"]
var ai_3d_labels: Array = ["2D", "MiDaS"]

func _init(owner: Node3D):
	main = owner

func get_stereo_mode() -> int:
	if main.sbs_mode > 0:
		return main.sbs_mode
	if main.ai_3d_mode == 0:
		return 0
	elif main.ai_3d_mode == 1:
		return 3
	else:
		return 4

func cycle_sbs_mode():
	main.sbs_mode = (main.sbs_mode + 1) % 3
	main.ui_controller.update_option_btn(main._ui_sbs_btn, sbs_labels[main.sbs_mode])
	main.ui_controller.update_3d_btn_state()
	apply_stereo()
	main.state_manager.save_state()

func cycle_ai_3d_mode():
	if main.sbs_mode > 0:
		return
	main.ai_3d_mode = (main.ai_3d_mode + 1) % 2
	main.ui_controller.update_option_btn(main._ui_3d_btn, ai_3d_labels[main.ai_3d_mode])
	apply_stereo()
	main.state_manager.save_state()

func apply_stereo():
	var mode = get_stereo_mode()
	main.screen_mesh.material_override.set_shader_parameter("stereo_mode", mode)
	if main.depth_estimator:
		main.depth_estimator.set_enabled(mode >= 3)
	main.stream_backend.set_depth_model(1 if mode == 4 else 0)

func toggle_passthrough():
	if not main.is_xr_active:
		return
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	main.passthrough_mode = (main.passthrough_mode + 1) % 3
	var starfield = main.get_node_or_null("Starfield")
	main._log("[PT] mode=%d starfield=%s" % [main.passthrough_mode, str(starfield != null)])
	main._flush_log()
	if main.passthrough_mode == 0:
		main.get_viewport().transparent_bg = true
		main.world_env.environment.background_mode = Environment.BG_COLOR
		main.world_env.environment.background_color = Color(0, 0, 0, 0)
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		if starfield: starfield.visible = false
	elif main.passthrough_mode == 1:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		main.world_env.environment.background_color = Color(0, 0, 0, 1)
		main.get_viewport().transparent_bg = false
		if starfield: starfield.visible = false
	else:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		main.world_env.environment.background_color = Color(0, 0, 0, 0)
		main.get_viewport().transparent_bg = false
		if starfield: starfield.visible = true
	main.ui_controller.update_option_btn(main._ui_pt_btn, main.passthrough_labels[main.passthrough_mode])
	main.state_manager.save_state()

func cycle_smooth_mode():
	main.smooth_mode = (main.smooth_mode + 1) % main.smooth_labels.size()
	main.ui_controller.update_option_btn(main._ui_render_btn, main.smooth_labels[main.smooth_mode])
	apply_filter()
	main.state_manager.save_state()

func cycle_sharpen_mode():
	main.sharpen_mode = (main.sharpen_mode + 1) % main.sharpen_labels.size()
	main.ui_controller.update_option_btn(main._ui_sharpen_btn, main.sharpen_labels[main.sharpen_mode])
	apply_filter()
	main.state_manager.save_state()

func apply_filter():
	if not main.is_xr_active:
		return
	var mat = main.screen_mesh.material_override
	if mat:
		mat.set_shader_parameter("filter_mode", main.smooth_mode)
		mat.set_shader_parameter("sharpen", float(main.sharpen_mode) * 0.1)

func cycle_fps():
	var rates = [60, 90, 120]
	var idx = rates.find(main.stream_fps)
	main.stream_fps = rates[(idx + 1) % rates.size()]
	main.ui_controller.update_option_btn(main._ui_fps_btn, "%dHz" % main.stream_fps)
	main.state_manager.save_state()
	if main.is_streaming and main.current_host_id >= 0:
		main._log("[FPS] Restarting stream at %dHz" % main.stream_fps)
		main._restarting_stream = true
		main.stream_backend.stop_play_stream()
		await main.get_tree().create_timer(0.5).timeout
		main.stream_manager.start_stream(main.current_host_id, main._selected_app_id)

func cycle_resolution():
	main.resolution_idx += 1
	if main.resolution_idx >= main.resolutions.size():
		main.resolution_idx = -1
	if main.resolution_idx == -1:
		main.host_resolution = Vector2i(1920, 1080)
		main.ui_controller.update_option_btn(main._ui_res_btn, "Auto")
	else:
		main.host_resolution = main.resolutions[main.resolution_idx]
		main.ui_controller.update_option_btn(main._ui_res_btn, main.resolution_labels[main.resolution_idx])
	main.state_manager.save_state()
	if main.is_streaming and main.current_host_id >= 0:
		main._log("[RES] Restarting stream at %dx%d" % [main.host_resolution.x, main.host_resolution.y])
		main._restarting_stream = true
		main.stream_backend.stop_play_stream()
		await main.get_tree().create_timer(0.5).timeout
		main.stream_manager.start_stream(main.current_host_id, main._selected_app_id)
