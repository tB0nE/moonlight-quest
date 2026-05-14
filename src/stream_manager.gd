class_name StreamManager
extends RefCounted

var main: Node3D
var bitrate: int = 20000
var _v2_yuv_rect: ColorRect = null

func _init(owner: Node3D):
	main = owner

func _b() -> StreamBackend:
	return main.stream_backend

func start_stream(host_id: int, app_id: int):
	var w = main.host_resolution.x
	var h = main.host_resolution.y
	if main.double_h:
		w *= 2
	main._log("[STREAM] Starting stream host_id=%d app_id=%d res=%dx%d@%d" % [host_id, app_id, w, h, main.stream_fps])
	if main.bitrate_idx >= 0:
		bitrate = main.bitrates[main.bitrate_idx] * 1000
	else:
		bitrate = _auto_bitrate(w, h)
	resize_stream_viewport(w, h)
	var options = {}
	options["width"] = w
	options["height"] = h
	options["fps"] = main.stream_fps
	options["bitrate"] = bitrate
	options["packet_size"] = 1024
	options["streaming_remotely"] = 2
	options["surroundAudioInfo"] = 0xCA0203
	main._ui_status_label.text = "Launching stream..."
	_b().establish_stream(host_id, app_id, options, _on_v2_launch_response)
	main._log("[STREAM] establish_stream called")

func _on_v2_launch_response(response: Dictionary):
	if response.get("status", "") != "success":
		main._log("[STREAM] Launch failed: %s" % response.get("message", "unknown"))
		main._ui_status_label.text = "Launch failed: " + str(response.get("message", "unknown"))
		return

	var server_info = {}
	server_info["server_codec_mode_support"] = response.get("server_codec_mode_support", 0)
	server_info["rtsp_session_url"] = response.get("session_url", "")
	server_info["server_app_version"] = response.get("app_version", "")
	server_info["server_gfe_version"] = response.get("gfe_version", "")

	var w = response.get("width", 1920)
	var h = response.get("height", 1080)
	var fps = response.get("fps", 60)
	var br = response.get("bitrate", 20000)

	var stream_config = {}
	stream_config["width"] = w
	stream_config["height"] = h
	stream_config["fps"] = fps
	stream_config["bitrate"] = br
	stream_config["packet_size"] = response.get("packet_size", 1024)
	stream_config["streaming_remotely"] = response.get("streaming_remotely", 2)
	stream_config["audio_configuration"] = response.get("audio_configuration", 0x0302CA)
	stream_config["supported_video_formats"] = _b().probe_video_format(0, false)
	stream_config["color_space"] = 1
	stream_config["color_range"] = 0
	stream_config["encryption_flags"] = 0xFFFFFFFF
	stream_config["client_refresh_rate_x100"] = int(main.display_refresh_rate * 100)

	var rikey_raw = response.get("rikey_raw", PackedByteArray())
	var rikeyid = response.get("rikeyid", 0)
	if rikey_raw.size() == 16:
		stream_config["remote_input_aes_key"] = rikey_raw
		var iv = PackedByteArray()
		iv.resize(16)
		iv.fill(0)
		iv[0] = (rikeyid >> 24) & 0xFF
		iv[1] = (rikeyid >> 16) & 0xFF
		iv[2] = (rikeyid >> 8) & 0xFF
		iv[3] = rikeyid & 0xFF
		stream_config["remote_input_aes_iv"] = iv

	var ip = response.get("ip", "")
	_b().start_stream_v2(ip, server_info, stream_config, false)
	main._log("[STREAM] start_stream called (%dx%d@%d %dMbps)" % [w, h, fps, br])

func _auto_bitrate(w: int, h: int) -> int:
	var pixels = w * h
	if pixels >= 3840 * 2160:
		return 80000
	elif pixels >= 2560 * 1440:
		return 40000
	elif pixels >= 3440 * 1440:
		return 50000
	elif pixels >= 1920 * 1080:
		return 20000
	elif pixels >= 1600 * 1200:
		return 20000
	else:
		return 10000

func resize_stream_viewport(w: int, h: int):
	main.stream_viewport.size = Vector2i(w, h)
	main.stream_target.custom_minimum_size = Vector2(w, h)
	if _v2_yuv_rect:
		_v2_yuv_rect.custom_minimum_size = Vector2(w, h)
	if main.comp_viewport:
		main.comp_viewport.size = Vector2i(w, h)
	main._comp_base_size = Vector2i(w, h)
	if main.comp_layer and main.comp_layer is OpenXRCompositionLayerQuad:
		main.comp_layer.set_quad_size(main._mesh_size)
	main.screen_manager.resize_screen_to_aspect(w, h)
	if main._xr_render_width > 0:
		var scale = float(w) / float(main._xr_render_width)
		main.screen_mesh.material_override.set_shader_parameter("blur_scale", scale)
	main._log("[STREAM] Viewport resized to %dx%d (blur_scale=%.2f)" % [w, h, float(w) / float(main._xr_render_width) if main._xr_render_width > 0 else 1.0])

func on_pair_pressed():
	var ip = main.get_node("%IPInput").text
	main.get_node("%Numpad").visible = false
	if ip.is_empty(): ip = "127.0.0.1"
	var save = ConfigFile.new()
	save.set_value("connection", "ip", ip)
	save.save("user://last_connection.cfg")
	if _b().get_config_manager():
		_b().get_config_manager().load_config()
	var paired_host_id = -1
	for h in _b().get_hosts():
		if h.has("localaddress") and h.localaddress == ip:
			paired_host_id = h.id
			break
	if paired_host_id != -1:
		main.current_host_id = paired_host_id
		main._ui_status_label.text = "Already paired, starting stream..."
		await main.host_discovery.query_host_resolution(ip)
		await start_stream(paired_host_id, main._selected_app_id)
	else:
		main._ui_status_label.text = "Pairing with " + ip + "..."
		main._log("[PAIR] Starting pair with %s:47989..." % ip)
		var pin = _b().start_pair(ip, 47989)
		main._log("[PAIR] start_pair returned: %s (type=%s)" % [str(pin), str(typeof(pin))])
		if str(pin) == "" or str(pin) == "0":
			main._ui_status_label.text = "Failed to connect to " + ip
			main._log("[PAIR] FAILED - no pin returned")
			return
		main._pair_pin = str(pin)
		main.welcome_screen.show_welcome_screen("pin")

func on_pair_completed(success: bool, _msg: String):
	main._log("[PAIR] pair_completed: success=%s msg=%s" % [str(success), str(_msg)])
	main._ui_status_label.text = "Pair " + ("OK" if success else "FAILED: " + str(_msg))
	if success:
		main._ui_status_label.text = "Pairing successful, starting stream..."
		if _b().get_config_manager():
			_b().get_config_manager().load_config()
		var ip = main.get_node("%IPInput").text
		for h in _b().get_hosts():
			if h.localaddress == ip:
				main.current_host_id = h.id
				await start_stream(h.id, main._selected_app_id)
				break

var _mdns_result: Array = []

func browse_mdns() -> Array:
	main._log("[mDNS] Starting browse...")
	_mdns_result = []
	var thread = Thread.new()
	thread.start(func():
		_mdns_result = _b().browse_mdns(3.0)
	)
	while thread.is_alive():
		await main.get_tree().create_timer(0.1).timeout
	thread.wait_to_finish()
	main._log("[mDNS] Found %d hosts" % _mdns_result.size())
	return _mdns_result

func bind_texture():
	var stream_tex = main.stream_viewport.get_texture()
	main.detection_target.texture = stream_tex
	if main.depth_estimator:
		main.depth_estimator.bind_stream_texture()
	_setup_v2_yuv_rect()
	var ui_tex = main.ui_viewport.get_texture()
	main.ui_panel_3d.material_override.albedo_texture = ui_tex

func _setup_v2_yuv_rect():
	if _v2_yuv_rect:
		return
	var mat = _b().get_shader_material()
	if not mat:
		main._log("[STREAM] No shader material from TextureUploader yet")
		return
	_v2_yuv_rect = ColorRect.new()
	_v2_yuv_rect.name = "V2YuvRect"
	_v2_yuv_rect.material = mat
	_v2_yuv_rect.anchors_preset = Control.PRESET_FULL_RECT
	_v2_yuv_rect.custom_minimum_size = Vector2(main.stream_viewport.size)
	main.stream_target.visible = false
	main.stream_viewport.add_child(_v2_yuv_rect)
	main._log("[STREAM] YUV ColorRect added to StreamViewport")

func teardown_v2_yuv_rect():
	if _v2_yuv_rect:
		_v2_yuv_rect.queue_free()
		_v2_yuv_rect = null
	main.stream_target.visible = true

func update_stats():
	if not main.is_streaming:
		return
	if not main._ui_status_label:
		return
	var vw = _b().get_video_width()
	var vh = _b().get_video_height()
	if vw == 0 or vh == 0:
		return
	var cur_size = main.stream_viewport.size
	if cur_size.x != vw or cur_size.y != vh:
		resize_stream_viewport(vw, vh)
	var hw = "HW" if _b().is_hw_decode() else "SW"
	var ip = main.get_node("%IPInput").text
	var ip_display = ip if not ip.is_empty() else "?"
	var dropped = _b().get_frames_dropped()
	var latency_ms = _b().get_last_frame_latency() / 1000.0
	var bitrate_mbps = bitrate / 1000.0
	var refresh_hz = main.display_refresh_rate
	var txt = ip_display + " \u2022 " + str(vw) + "x" + str(vh) + " " + str(main.stream_fps) + "fps " + str(int(bitrate_mbps)) + "Mbps " + hw
	txt += " \u2022 " + str(int(latency_ms)) + "ms"
	txt += " \u2022 " + str(int(refresh_hz)) + "Hz \u2022 " + str(int(main.stats_fps)) + "fps"
	if dropped > 0:
		txt += " \u2022 drop:" + str(dropped)
	main._ui_status_label.text = txt
