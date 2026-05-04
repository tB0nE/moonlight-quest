class_name XRInteraction
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

func handle_pointer_interaction():
	var active_raycast = main.hand_raycast if main.is_xr_active else main.mouse_raycast

	if main.is_xr_active and main.is_streaming:
		var is_gripping = false
		if main.right_hand:
			is_gripping = main.right_hand.is_button_pressed("grip_click")
			if not is_gripping:
				is_gripping = main.right_hand.is_button_pressed("grip")
			if not is_gripping:
				is_gripping = main.right_hand.get_float("grip") > 0.2
		if is_gripping and not main.was_right_clicking and main.right_click_cooldown <= 0.0:
			if active_raycast.is_colliding() and active_raycast.get_collider().get_parent() == main.screen_mesh:
				var hit_pos = active_raycast.get_collision_point()
				var local_pos = main.screen_mesh.to_local(hit_pos)
				var ms = main._mesh_size
				var uv_x = 0.0
				var uv_y = clampf((ms.y * 0.5 - local_pos.y) / ms.y, 0.0, 1.0)
				if main.curvature == 0:
					uv_x = clampf((local_pos.x + ms.x * 0.5) / ms.x, 0.0, 1.0)
				else:
					var radius = 10.0 if main.curvature == 1 else 4.0
					var total_angle = ms.x / radius
					uv_x = clampf((asin(clampf(local_pos.x / radius, -1.0, 1.0)) + total_angle * 0.5) / total_angle, 0.0, 1.0)
				var host_x = int(uv_x * main.stream_viewport.size.x)
				var host_y = int(uv_y * main.stream_viewport.size.y)
				main.moon.send_mouse_position_event(host_x, host_y, main.stream_viewport.size.x, main.stream_viewport.size.y)
			main.moon.send_mouse_button_event(7, 3)
			main.was_right_clicking = true
			main.right_click_cooldown = 0.5
		elif not is_gripping and main.was_right_clicking:
			main.moon.send_mouse_button_event(8, 3)
			main.was_right_clicking = false

	main.get_node("%ScreenGrabBar").visible = true
	main.get_node("%MenuGrabBar").visible = true
	for ch in main.corner_handles:
		ch.visible = true

	if not main.grabbed_node and main.grabbed_corner_idx < 0:
		_set_grab_bar_color(main.get_node("%ScreenGrabBar"), Color.WHITE, 0.01)
		_set_grab_bar_color(main.get_node("%MenuGrabBar"), Color.WHITE, 0.01)
		for ch in main.corner_handles:
			_set_corner_color(ch, Color.WHITE, 0.0)
	elif main.grabbed_node and main.grabbed_bar:
		_set_grab_bar_color(main.grabbed_bar, Color.WHITE, 0.3)
	elif main.grabbed_corner_idx >= 0:
		_set_corner_color(main.corner_handles[main.grabbed_corner_idx], Color.WHITE, 0.3)

	var laser = main.get_node("%Laser")
	if active_raycast.is_colliding():
		var hit_dist = (active_raycast.get_collision_point() - active_raycast.global_position).length()
		laser.scale.y = hit_dist / 5.0
		laser.visible = true
		if main.contact_dot:
			main.contact_dot.global_position = active_raycast.get_collision_point()
			main.contact_dot.visible = true
	else:
		laser.scale.y = 1.0
		laser.visible = main.is_xr_active
		if main.contact_dot:
			main.contact_dot.visible = false

	if active_raycast.is_colliding():
		var collider = active_raycast.get_collider()
		var parent = collider.get_parent()

		if parent == main.get_node("%ScreenGrabBar") and parent != main.grabbed_bar:
			_set_grab_bar_color(parent, Color.WHITE, 0.1)
		if parent == main.get_node("%MenuGrabBar") and parent != main.grabbed_bar:
			_set_grab_bar_color(parent, Color.WHITE, 0.1)

		var is_now_clicking = main.right_hand.get_float("trigger") > 0.5 if main.is_xr_active else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

		if parent == main.ui_panel_3d:
			var hit_pos = active_raycast.get_collision_point()
			var local_pos = main.ui_panel_3d.to_local(hit_pos)
			var half_w = main._ui_mesh_size.x / 2.0
			var half_h = main._ui_mesh_size.y / 2.0
			var nx = (local_pos.x / half_w + 1.0) / 2.0
			var ny = 1.0 - (local_pos.y / half_h + 1.0) / 2.0
			var pixel_pos = Vector2(nx * main._ui_viewport_size.x, ny * main._ui_viewport_size.y)

			var motion = InputEventMouseMotion.new()
			motion.position = pixel_pos
			motion.global_position = pixel_pos
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT if is_now_clicking else 0
			main.ui_viewport.push_input(motion)

			if is_now_clicking and not main.was_clicking:
				_push_ui_click(pixel_pos, true)
				main.was_clicking = true
			elif not is_now_clicking and main.was_clicking:
				_push_ui_click(pixel_pos, false)
				main.was_clicking = false
			return

		elif parent == main.screen_mesh and not main.is_streaming:
			var hit_pos = active_raycast.get_collision_point()
			var local_pos = main.screen_mesh.to_local(hit_pos)
			var ms = main._mesh_size
			var uv_x = 0.0
			var uv_y = clampf((ms.y * 0.5 - local_pos.y) / ms.y, 0.0, 1.0)
			if main.curvature == 0:
				uv_x = clampf((local_pos.x + ms.x * 0.5) / ms.x, 0.0, 1.0)
			else:
				var radius = 10.0 if main.curvature == 1 else 4.0
				var total_angle = ms.x / radius
				uv_x = clampf((asin(clampf(local_pos.x / radius, -1.0, 1.0)) + total_angle * 0.5) / total_angle, 0.0, 1.0)
			var wv = main.welcome_viewport
			var pixel_pos = Vector2(uv_x * wv.size.x, uv_y * wv.size.y)

			var motion = InputEventMouseMotion.new()
			motion.position = pixel_pos
			motion.global_position = pixel_pos
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT if is_now_clicking else 0
			wv.push_input(motion)

			if is_now_clicking and not main.was_clicking:
				var ev = InputEventMouseButton.new()
				ev.position = pixel_pos
				ev.global_position = pixel_pos
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				wv.push_input(ev)
				main.was_clicking = true
			elif not is_now_clicking and main.was_clicking:
				var ev = InputEventMouseButton.new()
				ev.position = pixel_pos
				ev.global_position = pixel_pos
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = false
				wv.push_input(ev)
				main.was_clicking = false
			return

		elif parent == main.screen_mesh and main.is_streaming:
			var hit_pos = active_raycast.get_collision_point()
			var local_pos = main.screen_mesh.to_local(hit_pos)
			var ms = main._mesh_size
			var uv_x = 0.0
			var uv_y = clampf((ms.y * 0.5 - local_pos.y) / ms.y, 0.0, 1.0)
			if main.curvature == 0:
				uv_x = clampf((local_pos.x + ms.x * 0.5) / ms.x, 0.0, 1.0)
			else:
				var radius = 10.0 if main.curvature == 1 else 4.0
				var total_angle = ms.x / radius
				uv_x = clampf((asin(clampf(local_pos.x / radius, -1.0, 1.0)) + total_angle * 0.5) / total_angle, 0.0, 1.0)
			var host_x = int(uv_x * main.stream_viewport.size.x)
			var host_y = int(uv_y * main.stream_viewport.size.y)

			if main.is_xr_active:
				if is_now_clicking:
					main.moon.send_mouse_position_event(host_x, host_y, main.stream_viewport.size.x, main.stream_viewport.size.y)
					if is_now_clicking and not main.was_clicking:
						main.moon.send_mouse_button_event(7, 1)
						main.was_clicking = true
				elif main.was_clicking:
					main.moon.send_mouse_button_event(8, 1)
					main.was_clicking = false
			else:
				if is_now_clicking and not main.was_clicking:
					main.moon.send_mouse_position_event(host_x, host_y, main.stream_viewport.size.x, main.stream_viewport.size.y)
					main.suppress_input_frames = 3
					main.input_handler.capture_stream_mouse()
					main.was_clicking = true
			return

		var corner_idx = _get_corner_index(parent)
		if corner_idx >= 0:
			if is_now_clicking and main.grabbed_corner_idx < 0 and not main.grabbed_node:
				main.grabbed_corner_idx = corner_idx
				var opposite_idx = 3 - corner_idx
				var opposite = main.corner_handles[opposite_idx]
				main.corner_anchor_world = opposite.global_position
				_set_corner_color(parent, Color.WHITE, 0.3)
				main.was_clicking = true
			elif main.grabbed_corner_idx < 0 and corner_idx != main.grabbed_corner_idx:
				_set_corner_color(parent, Color.WHITE, 0.1)
			return

		elif parent == main.get_node("%ScreenGrabBar") or parent == main.get_node("%MenuGrabBar"):
			if is_now_clicking and not main.grabbed_node and main.grabbed_corner_idx < 0:
				main.grabbed_node = parent.get_parent()
				main.grabbed_bar = parent
				var grab_point = active_raycast.get_collision_point()
				main.grab_distance = (grab_point - active_raycast.global_position).length()
				main.grab_offset = main.grabbed_node.global_position - grab_point
				main.grab_start_hand_pos = active_raycast.global_position
				main.grab_start_node_pos = main.grabbed_node.global_position
				main.grab_forward = -active_raycast.global_transform.basis.z
				if main.is_xr_active:
					main.grab_start_hand_basis = active_raycast.global_transform.basis
					main.grab_start_node_basis = main.grabbed_node.global_transform.basis
					main.grab_start_node_euler = main.grabbed_node.rotation
				_set_grab_bar_color(parent, Color.WHITE, 0.3)
				main.was_clicking = true
			return

	elif main.was_clicking:
		main.was_clicking = false

func handle_grab():
	if not main.grabbed_node:
		return
	var active_raycast = main.hand_raycast if main.is_xr_active else main.mouse_raycast
	var hand_pos = active_raycast.global_position
	var hand_delta = hand_pos - main.grab_start_hand_pos
	var depth = hand_delta.dot(main.grab_forward) * main.grab_forward
	var lateral = hand_delta - depth
	main.grabbed_node.global_position = main.grab_start_node_pos + lateral * 4.0 + depth * 8.0
	var cam_pos = main.xr_camera.global_position
	main.grabbed_node.rotation.y = atan2(cam_pos.x - main.grabbed_node.global_position.x, cam_pos.z - main.grabbed_node.global_position.z)

	if main.is_xr_active and main.grab_start_hand_basis != Basis():
		var hand_basis = active_raycast.global_transform.basis
		var delta_rot = hand_basis * main.grab_start_hand_basis.inverse()
		var forward = delta_rot * main.grab_start_node_basis.z
		var pitch_delta = atan2(-forward.y, -forward.z) - atan2(-main.grab_start_node_basis.z.y, -main.grab_start_node_basis.z.z)
		var current_pitch = main.grab_start_node_euler.x + pitch_delta
		current_pitch *= 0.66
		main.grabbed_node.rotation.y = atan2(cam_pos.x - main.grabbed_node.global_position.x, cam_pos.z - main.grabbed_node.global_position.z)
		var euler = main.grabbed_node.rotation
		euler.x = current_pitch
		euler.z = 0.0
		if absf(euler.x) < 0.052:
			euler.x = 0.0
		main.grabbed_node.rotation = euler

	var still_clicking = main.right_hand.get_float("trigger") > 0.5 if main.is_xr_active else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not still_clicking:
		if main.grabbed_bar:
			_set_grab_bar_color(main.grabbed_bar, Color.WHITE, 0.01)
			main.grabbed_bar = null
		main.grabbed_node = null
		main.grab_start_hand_basis = Basis()
		main.grab_start_node_basis = Basis()
		main.grab_start_node_euler = Vector3.ZERO
		main._save_state()

func handle_corner_resize():
	if main.grabbed_corner_idx < 0:
		return
	var active_raycast = main.hand_raycast if main.is_xr_active else main.mouse_raycast
	var ray_origin = active_raycast.global_position
	var ray_dir = -active_raycast.global_transform.basis.z

	var plane_normal = -main.screen_mesh.global_transform.basis.z
	var plane_point = main.screen_mesh.global_position
	var denom = ray_dir.dot(plane_normal)
	if absf(denom) < 0.0001:
		return
	var t = (plane_point - ray_origin).dot(plane_normal) / denom
	if t < 0:
		return
	var hit_world = ray_origin + ray_dir * t

	var local_hit = main.screen_mesh.to_local(hit_world)

	var aspect = 16.0 / 9.0
	var raw_w = absf(local_hit.x) * 2.0
	var new_w = maxf(raw_w, 0.6)
	var new_h = new_w / aspect
	if new_h < 0.4:
		new_h = 0.4
		new_w = new_h * aspect

	main._mesh_size = Vector2(new_w, new_h)
	if main.curvature == 0:
		main.screen_mesh.mesh.size = Vector2(new_w, new_h)
	else:
		main._apply_curvature()

	var col_shape = main.screen_mesh.get_node("Area3D/CollisionShape3D")
	if col_shape:
		col_shape.shape.size = Vector3(new_w, new_h, 0.01)

	main.update_corner_positions()
	main._update_bezel_size()

	var still_clicking = main.right_hand.get_float("trigger") > 0.5 if main.is_xr_active else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not still_clicking:
		var handle = main.corner_handles[main.grabbed_corner_idx]
		_set_corner_color(handle, Color.WHITE, 0.01)
		main.grabbed_corner_idx = -1
		main._save_state()

func _get_corner_index(node: Node) -> int:
	for i in range(main.corner_handles.size()):
		if node == main.corner_handles[i]:
			return i
	return -1

func _push_ui_click(pos: Vector2, pressed: bool):
	var event = InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	main.ui_viewport.push_input(event)

func _set_grab_bar_color(bar: MeshInstance3D, color: Color, alpha: float = 1.0):
	bar.material_override.albedo_color = Color(color.r, color.g, color.b, alpha)

func _set_corner_color(handle: MeshInstance3D, color: Color, alpha: float = 1.0):
	var c = Color(color.r, color.g, color.b, alpha)
	for child in handle.get_children():
		if child is MeshInstance3D:
			child.material_override.albedo_color = c

func handle_scroll():
	if not main.is_xr_active or not main.is_streaming:
		return
	var right_stick_y = 0.0
	if main.right_hand:
		right_stick_y = main.right_hand.get_vector2("primary").y
	if absf(right_stick_y) < 0.1:
		for pad in Input.get_connected_joypads():
			var val = Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
			if absf(val) > 0.1:
				right_stick_y = val
				break
	if absf(right_stick_y) > 0.3:
		var clicks = int(right_stick_y * 1.5)
		if clicks != 0:
			main.moon.send_scroll_event(clicks)
