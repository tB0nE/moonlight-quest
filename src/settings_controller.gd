class_name SettingsController
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

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

func cycle_depth_mode():
	main.depth_mode = (main.depth_mode + 1) % main.depth_labels.size()
	main.ui_controller.update_option_btn(main._ui_depth_btn, main.depth_labels[main.depth_mode])
	apply_depth()
	main.state_manager.save_state()

func cycle_parallax_mode():
	main.parallax_mode = (main.parallax_mode + 1) % main.parallax_labels.size()
	main.ui_controller.update_option_btn(main._ui_parallax_btn, main.parallax_labels[main.parallax_mode])
	apply_parallax()
	main.state_manager.save_state()

func apply_depth():
	var mat = main.screen_mesh.material_override
	if mat:
		var t = float(main.depth_mode) / 10.0
		mat.set_shader_parameter("depth_gain", 1.0 + t * 3.6)

func apply_parallax():
	var mat = main.screen_mesh.material_override
	if mat:
		var t = float(main.parallax_mode) / 10.0
		mat.set_shader_parameter("parallax_depth", 0.5 + t * 0.6)

func get_stereo_mode_count() -> int:
	return 5 if main.has_depth_model_v2 else 4

func get_stereo_mode_names() -> Array:
	return ["2D", "SBS Stretch", "SBS Crop", "AI 3D", "AI 3D v2"] if main.has_depth_model_v2 else ["2D", "SBS Stretch", "SBS Crop", "AI 3D"]

func set_depth_model(mode: int):
	main.stream_backend.set_depth_model(1 if mode == 4 else 0)

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
