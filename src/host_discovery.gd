class_name HostDiscovery
extends RefCounted

var main: Node3D
var http_request: HTTPRequest

func _init(owner: Node3D):
	main = owner

func query_host_resolution(ip: String):
	if http_request == null:
		http_request = HTTPRequest.new()
		http_request.timeout = 5.0
		main.add_child(http_request)
		http_request.request_completed.connect(on_serverinfo_response)
	var url = "http://%s:47989/serverinfo" % ip
	main._log("[RES] Querying host resolution: %s" % url)
	var err = http_request.request(url)
	main._log("[RES] HTTP request error: %d (OK=%d)" % [err, OK])
	await main.get_tree().create_timer(5.0).timeout
	if main.resolution_idx == -1 and main.host_resolution == Vector2i(1920, 1080):
		main._log("[RES] HTTP failed, trying comp_mgr")
		try_comp_mgr_resolution()
	main._log("[RES] Final resolution: %dx%d" % [main.host_resolution.x, main.host_resolution.y])

func try_comp_mgr_resolution():
	var hosts = main.stream_backend.get_config_manager().get_hosts()
	main._log("[RES] comp_mgr hosts count: %d" % hosts.size())
	for h in hosts:
		main._log("[RES] host: id=%d name=%s" % [h.id if h.has("id") else -1, h.name if h.has("name") else "?"])
		if h.has("localaddress") and h.localaddress != "":
			main._log("[RES] Found host with address: %s" % h.localaddress)

func on_serverinfo_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	main._log("[RES] Response: result=%d code=%d body_len=%d" % [_result, code, body.size()])
	if code != 200 or body.size() == 0:
		main._log("[RES] serverinfo request failed (result=%d code=%d)" % [_result, code])
		return
	var xml = body.get_string_from_utf8()
	main._log("[RES] serverinfo full XML: %s" % xml)
	var display_data = extract_display_info(xml)
	var hostname = extract_hostname(xml)
	if not hostname.is_empty():
		main._last_hostname = hostname
	if display_data != Vector2i.ZERO:
		if main.resolution_idx == -1:
			main.host_resolution = display_data
		main._log("[RES] Detected host resolution: %dx%d" % [display_data.x, display_data.y])
		main._ui_status_label.text = "Host: %dx%d" % [display_data.x, display_data.y]
	else:
		main._log("[RES] Could not detect resolution from XML, using default 1920x1080")

func extract_display_info(xml: String) -> Vector2i:
	if xml.find("<Display0>") == -1 and xml.find("<display0>") == -1:
		main._log("[RES] No Display0 tag in XML, cannot auto-detect resolution")
		return Vector2i.ZERO
	var display_idx = 0
	while true:
		var tag_open = "<Display%d>" % display_idx
		var start = xml.find(tag_open)
		if start == -1:
			break
		start += tag_open.length()
		var tag_close = "</Display%d>" % display_idx
		var end = xml.find(tag_close, start)
		if end == -1:
			break
		var value = xml.substr(start, end - start).strip_edges()
		main._log("[RES] Display%d raw: '%s'" % [display_idx, value])
		var parts = value.split("x")
		if parts.size() >= 2:
			var w = parts[0].to_int()
			var h = parts[1].to_int()
			if w > 0 and h > 0:
				return Vector2i(w, h)
		display_idx += 1
	return Vector2i.ZERO

func extract_hostname(xml: String) -> String:
	var tag = "<hostname>"
	var start = xml.find(tag)
	if start == -1:
		return ""
	start += tag.length()
	var end = xml.find("</hostname>", start)
	if end == -1:
		return ""
	return xml.substr(start, end - start).strip_edges()
