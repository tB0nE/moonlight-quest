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
	main._log("[STREAM] Starting stream host_id=%d app_id=%d res=%dx%d@%d" % [host_id, app_id, w, h, main.stream_fps])
	bitrate = 20000
	if w >= 3840:
		bitrate = 80000
	elif w >= 2560:
		bitrate = 40000
	if main.use_nightfall_v2:
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
		main._log("[STREAM] v2 establish_stream called")
	else:
		main.stream_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var stream_cfg = MoonlightStreamConfigurationResource.new()
		stream_cfg.set_width(w)
		stream_cfg.set_height(h)
		stream_cfg.set_fps(main.stream_fps)
		stream_cfg.set_bitrate(bitrate)
		var stream_opts = MoonlightAdditionalStreamOptions.new()
		stream_opts.set_disable_hw_acceleration(false)
		stream_opts.set_disable_audio(false)
		stream_opts.set_disable_video(false)
		stream_opts.set_video_codec(0)
		main.moon.set_render_target(main.stream_target)
		main.moon.start_play_stream(host_id, app_id, stream_cfg, stream_opts)
		main._log("[STREAM] v1 start_play_stream called (%dx%d@%d %dMbps)" % [w, h, main.stream_fps, bitrate])
		await main.get_tree().create_timer(0.1).timeout
		bind_texture()

func _on_v2_launch_response(response: Dictionary):
	if response.get("status", "") != "success":
		main._log("[STREAM] v2 launch failed: %s" % response.get("message", "unknown"))
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

	var rikey_raw = response.get("rikey_raw", PackedByteArray())
	if rikey_raw.size() == 16:
		stream_config["remote_input_aes_key"] = rikey_raw
		var iv = PackedByteArray()
		iv.resize(16)
		iv.fill(0)
		stream_config["remote_input_aes_iv"] = iv

	var ip = response.get("ip", "")
	_b().start_stream_v2(ip, server_info, stream_config, false)
	main._log("[STREAM] v2 start_stream called (%dx%d@%d %dMbps)" % [w, h, fps, br])

func resize_stream_viewport(w: int, h: int):
	main.stream_viewport.size = Vector2i(w, h)
	main.stream_target.custom_minimum_size = Vector2(w, h)
	if _v2_yuv_rect:
		_v2_yuv_rect.custom_minimum_size = Vector2(w, h)
	main._log("[STREAM] Viewport resized to %dx%d" % [w, h])

func on_pair_pressed():
	var ip = main.get_node("%IPInput").text
	main.get_node("%Numpad").visible = false
	if ip.is_empty(): ip = "127.0.0.1"
	var save = ConfigFile.new()
	save.set_value("connection", "ip", ip)
	save.save("user://last_connection.cfg")
	if _b().get_config_manager():
		_b().get_config_manager().load_config()
	await main.host_discovery.query_host_resolution(ip)
	var paired_host_id = -1
	for h in _b().get_hosts():
		if h.has("localaddress") and h.localaddress == ip:
			paired_host_id = h.id
			break
	if paired_host_id != -1:
		main.current_host_id = paired_host_id
		main._ui_status_label.text = "Already paired, starting stream..."
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

func setup_audio():
	if main.use_nightfall_v2:
		return
	var audio_stream = _b().get_audio_stream()
	if audio_stream:
		main.audio_player.stream = audio_stream
		main.audio_player.play()
		print("Audio Stream Started")

func bind_texture():
	var stream_tex = main.stream_viewport.get_texture()
	main.detection_target.texture = stream_tex
	if main.depth_estimator:
		main.depth_estimator.bind_stream_texture()
	if main.use_nightfall_v2:
		_setup_v2_yuv_rect()
	else:
		if main.is_streaming:
			main.screen_mesh.material_override.set_shader_parameter("main_texture", stream_tex)
			printerr("[NF-RENDER] bind_texture V1: set main_texture vp_mode=%d" % main.stream_viewport.render_target_update_mode)
	var ui_tex = main.ui_viewport.get_texture()
	main.ui_panel_3d.material_override.albedo_texture = ui_tex

func _setup_v2_yuv_rect():
	if _v2_yuv_rect:
		return
	var mat = _b().get_shader_material()
	if not mat:
		main._log("[STREAM] v2: no shader material from TextureUploader yet")
		return
	_v2_yuv_rect = ColorRect.new()
	_v2_yuv_rect.name = "V2YuvRect"
	_v2_yuv_rect.material = mat
	_v2_yuv_rect.anchors_preset = Control.PRESET_FULL_RECT
	_v2_yuv_rect.custom_minimum_size = Vector2(main.stream_viewport.size)
	main.stream_target.visible = false
	main.stream_viewport.add_child(_v2_yuv_rect)
	main._log("[STREAM] v2: YUV ColorRect added to StreamViewport")

func teardown_v2_yuv_rect():
	if _v2_yuv_rect:
		_v2_yuv_rect.queue_free()
		_v2_yuv_rect = null
	main.stream_target.visible = true

func update_stats():
	if not main.is_streaming:
		return
	var decoder = _b().get_decoder_name()
	if decoder.is_empty():
		return
	var vw = _b().get_video_width()
	var vh = _b().get_video_height()
	var hw = "HW" if _b().is_hw_decode() else "SW"
	var ip = main.get_node("%IPInput").text
	var ip_display = ip if not ip.is_empty() else "?"
	var dropped = _b().get_frames_dropped()
	var latency_ms = _b().get_last_frame_latency() / 1000.0
	main._ui_status_label.text = "%s \u2022 %dx%d %s \u2022 %.0ffps \u2022 %.0fms" % [ip_display, vw, vh, hw, main.stats_fps, latency_ms]
	if dropped > 0:
		main._ui_status_label.text += " \u2022 drop:%d" % dropped
