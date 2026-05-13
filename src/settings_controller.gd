class_name SettingsController
extends RefCounted

var main: Node3D
var _restart_pending: bool = false
var _restart_seq: int = 0

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
	if main.is_streaming:
		if mode > 0:
			main._switch_to_mesh_rendering()
		elif main.comp_layer_available:
			main._switch_to_comp_layer()

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

func cycle_cursor_mode():
	main.cursor_mode = (main.cursor_mode + 1) % main.cursor_labels.size()
	main.ui_controller.update_option_btn(main._ui_cursor_btn, main.cursor_labels[main.cursor_mode])
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
		mat.set_shader_parameter("sharpen", float(main.sharpen_mode) * 0.016)

func apply_display_refresh_rate():
	if not main.is_xr_active:
		return
	var interface = XRServer.find_interface("OpenXR")
	if not interface:
		return
	var target_hz: float = 72.0
	match main.stream_fps:
		30: target_hz = 72.0
		60: target_hz = 72.0
		90: target_hz = 90.0
		120: target_hz = 120.0
	var available = interface.get_available_display_refresh_rates()
	if available.is_empty():
		main._log("[REFRESH] No available refresh rates reported")
		main.display_refresh_rate = target_hz
		return
	var best: float = 0.0
	for rate in available:
		if rate >= target_hz and (best == 0.0 or rate < best):
			best = rate
	if best == 0.0:
		available.sort()
		best = available[available.size() - 1]
	interface.set_display_refresh_rate(best)
	main.display_refresh_rate = best
	main._log("[REFRESH] Set headset to %.0fHz (target %.0fHz for %dfps)" % [best, target_hz, main.stream_fps])

func cycle_fps():
	var rates = [30, 60, 90, 120]
	var idx = rates.find(main.stream_fps)
	main.stream_fps = rates[(idx + 1) % rates.size()]
	main.ui_controller.update_option_btn(main._ui_fps_btn, "%d" % main.stream_fps)
	main.state_manager.save_state()
	_schedule_stream_restart()

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
	update_wide_btn_label()
	main.state_manager.save_state()
	_schedule_stream_restart()

func cycle_bitrate():
	main.bitrate_idx += 1
	if main.bitrate_idx >= main.bitrate_labels.size():
		main.bitrate_idx = -1
	var label = main.bitrate_labels[main.bitrate_idx + 1] if main.bitrate_idx >= 0 else "Auto"
	main.ui_controller.update_option_btn(main._ui_bitrate_btn, label)
	main.state_manager.save_state()
	_schedule_stream_restart()

func cycle_double_h():
	main.double_h = not main.double_h
	update_wide_btn_label()
	main.state_manager.save_state()
	_schedule_stream_restart()

func _schedule_stream_restart():
	if not main.is_streaming or main.current_host_id < 0:
		return
	_restart_pending = true
	_restart_seq += 1
	var my_seq = _restart_seq
	await main.get_tree().create_timer(0.8).timeout
	if _restart_seq != my_seq:
		return
	_restart_pending = false
	main._log("[RESTART] Restarting stream")
	apply_display_refresh_rate()
	main._restarting_stream = true
	main.stream_backend.stop_play_stream()
	await main.get_tree().create_timer(0.5).timeout
	main.stream_manager.start_stream(main.current_host_id, main._selected_app_id)

func update_wide_btn_label():
	if main.double_h:
		var w = main.host_resolution.x * 2
		main.ui_controller.update_option_btn(main._ui_wide_btn, "%dx%d" % [w, main.host_resolution.y])
	else:
		main.ui_controller.update_option_btn(main._ui_wide_btn, "Off")
