class_name StreamBackend
extends RefCounted

enum Backend { V1, V2 }

var backend: int = Backend.V1
var _v1: Node = null
var _v2: Node = null

var config_mgr: RefCounted = null
var comp_mgr: RefCounted = null

signal log_message(msg: String)
signal connection_started
signal connection_terminated(err, msg)
signal pair_completed(success: bool, msg: String)

func _init(v1_node: Node, v2_node: Node):
	_v1 = v1_node
	_v2 = v2_node

func set_backend(b: int):
	backend = b

func _b() -> Node:
	if backend == Backend.V2:
		return _v2
	return _v1

func set_config_manager(cm: RefCounted):
	config_mgr = cm
	if backend == Backend.V2 and _v2:
		var nf_cm = _v2.get_config_manager()
		if nf_cm:
			nf_cm.load_config()
	else:
		if _v1:
			_v1.set_config_manager(cm)

func set_computer_manager(cm: RefCounted):
	comp_mgr = cm

func get_config_manager() -> RefCounted:
	if backend == Backend.V2 and _v2:
		var nf_cm = _v2.get_config_manager()
		return nf_cm
	return config_mgr

func get_computer_manager() -> RefCounted:
	if backend == Backend.V2 and _v2:
		var nf_cm = _v2.get_computer_manager()
		return nf_cm
	return comp_mgr

func get_hosts() -> Array:
	var cm = get_config_manager()
	if cm:
		return cm.get_hosts()
	return []

func get_apps(host_id: int) -> Array:
	var cm = get_config_manager()
	if cm:
		return cm.get_apps(host_id)
	return []

func start_pair(ip: String, port: int = 47989) -> String:
	var cm = get_computer_manager()
	if cm:
		return cm.start_pair(ip, port)
	return ""

func get_app_list(host_id: int, callback: Callable):
	var cm = get_computer_manager()
	if cm:
		cm.get_app_list(host_id, callback)

func set_render_target(target: SubViewport):
	if backend == Backend.V1 and _v1:
		_v1.set_render_target(target)

func start_play_stream(host_id: int, app_id: int, stream_cfg: Resource, stream_opts: Resource):
	if backend == Backend.V1 and _v1:
		_v1.start_play_stream(host_id, app_id, stream_cfg, stream_opts)

func establish_stream(host_id: int, app_id: int, options: Dictionary, callback: Callable):
	var cm = get_computer_manager()
	if cm:
		cm.establish_stream(host_id, app_id, options, callback)

func start_stream_v2(host: String, server_info: Dictionary, stream_config: Dictionary, disable_hw: bool = false):
	if backend == Backend.V2 and _v2:
		_v2.start_stream(host, server_info, stream_config, disable_hw)

func stop_play_stream():
	if backend == Backend.V1 and _v1:
		_v1.stop_play_stream()
	elif backend == Backend.V2 and _v2:
		_v2.stop_stream()

func is_streaming() -> bool:
	if backend == Backend.V1 and _v1:
		return _v1.is_streaming_active if _v1.has_method("is_streaming_active") else false
	elif backend == Backend.V2 and _v2:
		return _v2.get_state() == 2
	return false

func get_audio_stream():
	if backend == Backend.V1 and _v1:
		return _v1.get_audio_stream()
	return null

func send_mouse_position_event(x: int, y: int, ref_w: int, ref_h: int):
	if backend == Backend.V1 and _v1:
		_v1.send_mouse_position_event(x, y, ref_w, ref_h)
	elif backend == Backend.V2 and _v2:
		_v2.get_input_bridge().send_mouse_position(x, y, ref_w, ref_h)

func send_mouse_move_event(dx: int, dy: int):
	if backend == Backend.V1 and _v1:
		_v1.send_mouse_move_event(dx, dy)
	elif backend == Backend.V2 and _v2:
		_v2.get_input_bridge().send_mouse_move(dx, dy)

func send_mouse_button_event(action: int, button: int):
	if backend == Backend.V1 and _v1:
		_v1.send_mouse_button_event(action, button)
	elif backend == Backend.V2 and _v2:
		if action == 7:
			_v2.get_input_bridge().send_mouse_button_pressed(button)
		else:
			_v2.get_input_bridge().send_mouse_button_released(button)

func send_keyboard_event(keycode: int, action: int, modifiers: int):
	if backend == Backend.V1 and _v1:
		_v1.send_keyboard_event(keycode, action, modifiers)
	elif backend == Backend.V2 and _v2:
		_v2.get_input_bridge().send_keyboard_event(keycode, action, modifiers)

func send_scroll_event(clicks: int):
	if backend == Backend.V1 and _v1:
		_v1.send_scroll_event(clicks)
	elif backend == Backend.V2 and _v2:
		_v2.get_input_bridge().send_scroll(clicks)

func send_multi_controller_event(device: int, active_mask: int, buttons: int, lt: int, rt: int, lx: int, ly: int, rx: int, ry: int):
	if backend == Backend.V1 and _v1:
		_v1.send_multi_controller_event(device, active_mask, buttons, lt, rt, lx, ly, rx, ry)
	elif backend == Backend.V2 and _v2:
		_v2.get_input_bridge().send_multi_controller_event(device, active_mask, buttons, lt, rt, lx, ly, rx, ry)

func get_decoder_name() -> String:
	if backend == Backend.V1 and _v1 and _v1.has_method("get_decoder_name"):
		return _v1.get_decoder_name()
	elif backend == Backend.V2 and _v2:
		var d = _v2.get_decoder()
		if d:
			return d.get_decoder_name()
	return ""

func get_video_width() -> int:
	if backend == Backend.V1 and _v1:
		return _v1.get_video_width()
	elif backend == Backend.V2 and _v2:
		var d = _v2.get_decoder()
		if d:
			return d.get_video_width()
	return 0

func get_video_height() -> int:
	if backend == Backend.V1 and _v1:
		return _v1.get_video_height()
	elif backend == Backend.V2 and _v2:
		var d = _v2.get_decoder()
		if d:
			return d.get_video_height()
	return 0

func is_hw_decode() -> bool:
	if backend == Backend.V1 and _v1:
		return _v1.is_hw_decode()
	elif backend == Backend.V2 and _v2:
		var d = _v2.get_decoder()
		if d:
			return d.is_hw_decode()
	return false

func get_frames_dropped() -> int:
	if backend == Backend.V1 and _v1 and _v1.has_method("get_frames_dropped"):
		return _v1.get_frames_dropped()
	elif backend == Backend.V2 and _v2:
		return _v2.get_frames_dropped()
	return 0

func get_last_frame_latency() -> int:
	if backend == Backend.V1 and _v1 and _v1.has_method("get_last_frame_latency"):
		return _v1.get_last_frame_latency()
	elif backend == Backend.V2 and _v2:
		return _v2.get_last_frame_latency_us()
	return 0

func has_depth_model_v2() -> bool:
	if backend == Backend.V1 and _v1 and _v1.has_method("has_depth_model_v2"):
		return _v1.has_depth_model_v2()
	elif backend == Backend.V2 and _v2:
		var db = _v2.get_depth_bridge()
		if db:
			return db.has_depth_model_v2()
	return false

func set_depth_model(model_id: int):
	if backend == Backend.V1 and _v1 and _v1.has_method("set_depth_model"):
		_v1.set_depth_model(model_id)
	elif backend == Backend.V2 and _v2:
		var db = _v2.get_depth_bridge()
		if db:
			db.set_depth_model(model_id)

func submit_depth_frame(data: PackedByteArray, w: int, h: int):
	if backend == Backend.V1 and _v1 and _v1.has_method("submit_depth_frame"):
		_v1.submit_depth_frame(data, w, h)
	elif backend == Backend.V2 and _v2:
		var db = _v2.get_depth_bridge()
		if db:
			db.submit_depth_frame(data, w, h)

func get_depth_map() -> PackedByteArray:
	if backend == Backend.V1 and _v1 and _v1.has_method("get_depth_map"):
		return _v1.get_depth_map()
	elif backend == Backend.V2 and _v2:
		var db = _v2.get_depth_bridge()
		if db:
			return db.get_depth_map()
	return PackedByteArray()

func probe_video_format(codec_pref: int, disable_hw: bool) -> int:
	if backend == Backend.V2 and _v2:
		return _v2.probe_video_format(codec_pref, disable_hw)
	return 1

func get_shader_material():
	if backend == Backend.V2 and _v2:
		return _v2.get_shader_material()
	return null

func browse_mdns(timeout: float) -> Array:
	if backend == Backend.V2 and _v2:
		var mdns_browser = ClassDB.instantiate("MdnsBrowser")
		if mdns_browser:
			return mdns_browser.browse(timeout)
	if ClassDB.class_exists("MoonlightMDNS"):
		var mdns = ClassDB.instantiate("MoonlightMDNS")
		if mdns:
			return mdns.browse(timeout)
	return []
