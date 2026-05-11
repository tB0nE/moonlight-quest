class_name StateManager
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

func save_state():
	var save = ConfigFile.new()
	save.set_value("screen", "size_x", main._mesh_size.x)
	save.set_value("screen", "size_y", main._mesh_size.y)
	save.set_value("screen", "bezel", main.bezel_enabled)
	save.set_value("screen", "curvature", main.curvature)
	save.set_value("screen", "passthrough", main.passthrough_mode)
	save.set_value("screen", "smooth_mode", main.smooth_mode)
	save.set_value("screen", "sharpen_mode", main.sharpen_mode)
	save.set_value("screen", "cursor_mode", main.cursor_mode)
	save.save("user://app_state.cfg")
	save_host_state()

func save_host_state():
	var ip = main.get_node("%IPInput").text
	if ip.is_empty():
		return
	var save = ConfigFile.new()
	save.load("user://host_state.cfg")
	save.set_value(ip, "fps", main.stream_fps)
	save.set_value(ip, "resolution_idx", main.resolution_idx)
	save.set_value(ip, "sbs_mode", main.sbs_mode)
	save.set_value(ip, "ai_3d_mode", main.ai_3d_mode)
	save.save("user://host_state.cfg")

func load_host_state(ip: String):
	if ip.is_empty():
		return
	var save = ConfigFile.new()
	if save.load("user://host_state.cfg") != OK:
		return
	if not save.has_section(ip):
		return
	main.stream_fps = save.get_value(ip, "fps", 60)
	main.resolution_idx = save.get_value(ip, "resolution_idx", -1)
	if save.has_section_key(ip, "sbs_mode"):
		main.sbs_mode = clampi(save.get_value(ip, "sbs_mode", 0), 0, 2)
		main.ai_3d_mode = clampi(save.get_value(ip, "ai_3d_mode", 0), 0, 1)
	elif save.has_section_key(ip, "stereo_mode"):
		var old = clampi(save.get_value(ip, "stereo_mode", 0), 0, 4)
		if old <= 2:
			main.sbs_mode = old
			main.ai_3d_mode = 0
		else:
			main.sbs_mode = 0
			main.ai_3d_mode = 1
	main.screen_mesh.material_override.set_shader_parameter("stereo_mode", main.settings_controller.get_stereo_mode())
	main.ui_controller.update_option_btn(main._ui_sbs_btn, main.settings_controller.sbs_labels[main.sbs_mode])
	main.ui_controller.update_option_btn(main._ui_3d_btn, main.settings_controller.ai_3d_labels[main.ai_3d_mode])
	main.ui_controller.update_3d_btn_state()
	main.ui_controller.update_option_btn(main._ui_fps_btn, "%dHz" % main.stream_fps)
	if main.resolution_idx == -1:
		main.ui_controller.update_option_btn(main._ui_res_btn, "Auto")
	else:
		main.resolution_idx = clampi(main.resolution_idx, 0, main.resolutions.size() - 1)
		main.host_resolution = main.resolutions[main.resolution_idx]
		main.ui_controller.update_option_btn(main._ui_res_btn, main.resolution_labels[main.resolution_idx])
	if main.depth_estimator:
		main.depth_estimator.set_enabled(main.settings_controller.get_stereo_mode() >= 3)
	main.settings_controller.apply_stereo()

func load_state():
	var save = ConfigFile.new()
	if save.load("user://app_state.cfg") != OK:
		return

	main.bezel_enabled = save.get_value("screen", "bezel", true)
	main.curvature = save.get_value("screen", "curvature", 0)
	main.passthrough_mode = save.get_value("screen", "passthrough", 0)
	main.smooth_mode = save.get_value("screen", "smooth_mode", save.get_value("screen", "render_mode", 0))
	main.sharpen_mode = save.get_value("screen", "sharpen_mode", 0)
	main.cursor_mode = save.get_value("screen", "cursor_mode", 0)
	if save.has_section_key("screen", "size_x"):
		main._mesh_size = Vector2(save.get_value("screen", "size_x"), save.get_value("screen", "size_y"))
		if main._mesh_size.x > 0.1 and main._mesh_size.y > 0.1:
			if main.curvature == 0:
				main.screen_mesh.mesh.size = main._mesh_size
				main.screen_manager.set_screen_collision_flat(main._mesh_size)
			else:
				main.screen_manager.apply_curvature()
			main.screen_manager.update_corner_positions()
	if main.bezel_mesh:
		main.bezel_mesh.visible = main.bezel_enabled
	main.ui_controller.update_option_btn(main._ui_bezel_btn, "On" if main.bezel_enabled else "Off")
	main.ui_controller.update_option_btn(main._ui_curve_btn, main.curvature_labels[clampi(main.curvature, 0, main.curvature_labels.size() - 1)])
	main.ui_controller.update_option_btn(main._ui_pt_btn, main.passthrough_labels[clampi(main.passthrough_mode, 0, main.passthrough_labels.size() - 1)])
	main.ui_controller.update_option_btn(main._ui_render_btn, main.smooth_labels[clampi(main.smooth_mode, 0, main.smooth_labels.size() - 1)])
	main.ui_controller.update_option_btn(main._ui_sharpen_btn, main.sharpen_labels[clampi(main.sharpen_mode, 0, main.sharpen_labels.size() - 1)])
	main.ui_controller.update_option_btn(main._ui_cursor_btn, main.cursor_labels[clampi(main.cursor_mode, 0, main.cursor_labels.size() - 1)])
	main.screen_manager.update_bezel_size()
	main.settings_controller.apply_filter()
