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
				if main.settings_controller.get_stereo_mode() >= 3:
					var shift = _compute_parallax_shift(uv_x)
					uv_x = clampf(uv_x - shift, 0.0, 1.0)
				var host_x = int(uv_x * main.stream_viewport.size.x)
				var host_y = int(uv_y * main.stream_viewport.size.y)
				main.stream_backend.send_mouse_position_event(host_x, host_y, main.stream_viewport.size.x, main.stream_viewport.size.y)
			main.stream_backend.send_mouse_button_event(7, 3)
			main.was_right_clicking = true
			main.right_click_cooldown = 0.5
		elif not is_gripping and main.was_right_clicking:
			main.stream_backend.send_mouse_button_event(8, 3)
			main.was_right_clicking = false

	main.get_node("%ScreenGrabBar").visible = true
	main.get_node("%MenuGrabBar").visible = true
	if main.virtual_keyboard:
		main.virtual_keyboard.grab_bar.visible = main.virtual_keyboard.visible
	for ch in main.corner_handles:
		ch.visible = true

	if not main.grabbed_node and main.grabbed_corner_idx < 0:
		_set_grab_bar_color(main.get_node("%ScreenGrabBar"), Color.WHITE, 0.01)
		_set_grab_bar_color(main.get_node("%MenuGrabBar"), Color.WHITE, 0.01)
		if main.virtual_keyboard and main.virtual_keyboard.visible:
			_set_grab_bar_color(main.virtual_keyboard.grab_bar, Color.WHITE, 0.01)
		for ch in main.corner_handles:
			_set_corner_color(ch, Color.WHITE, 0.0)
	elif main.grabbed_node and main.grabbed_bar:
		_set_grab_bar_color(main.grabbed_bar, Color.WHITE, 0.3)
	elif main.grabbed_corner_idx >= 0:
		_set_corner_color(main.corner_handles[main.grabbed_corner_idx], Color.WHITE, 0.3)

	var laser = main.get_node("%Laser")
	laser.visible = main.is_xr_active
	var on_screen = false
	if active_raycast.is_colliding():
		var hit_point = active_raycast.get_collision_point()
		var _col = active_raycast.get_collider()
		var _par = _col.get_parent() if _col else null
		on_screen = (_par == main.screen_mesh)
		if main.cursor_mode == 0 or not on_screen:
			if main.contact_dot:
				main.contact_dot.global_position = hit_point
				main.contact_dot.visible = true
			if main.pointer_cursor:
				main.pointer_cursor.visible = false
		else:
			if main.pointer_cursor:
				main.pointer_cursor.global_position = hit_point
				var to_cam = (main.xr_camera.global_position - hit_point).normalized()
				main.pointer_cursor.look_at(main.pointer_cursor.global_position + to_cam, Vector3.UP)
				main.pointer_cursor.rotate_object_local(Vector3.UP, PI)
				var face = -main.pointer_cursor.global_transform.basis.z
				var right = main.pointer_cursor.global_transform.basis.x
				var up = main.pointer_cursor.global_transform.basis.y
				main.pointer_cursor.global_position = hit_point + face * 0.002 + right * 0.03 - up * 0.04
				main.pointer_cursor.visible = true
			if main.contact_dot:
				main.contact_dot.visible = false
	else:
		if main.contact_dot:
			main.contact_dot.visible = false
		if main.pointer_cursor:
			main.pointer_cursor.visible = false

	if active_raycast.is_colliding():
		var collider = active_raycast.get_collider()
		var parent = collider.get_parent()

		if parent == main.get_node("%ScreenGrabBar") and parent != main.grabbed_bar:
			_set_grab_bar_color(parent, Color.WHITE, 0.1)
		if parent == main.get_node("%MenuGrabBar") and parent != main.grabbed_bar:
			_set_grab_bar_color(parent, Color.WHITE, 0.1)
		if main.virtual_keyboard and main.virtual_keyboard.grab_bar and parent == main.virtual_keyboard.grab_bar and parent != main.grabbed_bar:
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

		if main.virtual_keyboard and main.virtual_keyboard.visible and parent == main.virtual_keyboard.mesh_instance:
			var hit_pos = active_raycast.get_collision_point()
			var local_pos = main.virtual_keyboard.mesh_instance.to_local(hit_pos)
			var half_w = main.virtual_keyboard.mesh_size.x / 2.0
			var half_h = main.virtual_keyboard.mesh_size.y / 2.0
			var nx = (local_pos.x / half_w + 1.0) / 2.0
			var ny = 1.0 - (local_pos.y / half_h + 1.0) / 2.0
			var pixel_pos = Vector2(nx * main.virtual_keyboard.viewport_size.x, ny * main.virtual_keyboard.viewport_size.y)
			main.virtual_keyboard.handle_pointer(pixel_pos, is_now_clicking, main.was_clicking)
			if is_now_clicking:
				main.was_clicking = true
			else:
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
			if main.settings_controller.get_stereo_mode() >= 3:
				var shift = _compute_parallax_shift(uv_x)
				uv_x = clampf(uv_x - shift, 0.0, 1.0)
			var host_x = int(uv_x * main.stream_viewport.size.x)
			var host_y = int(uv_y * main.stream_viewport.size.y)

			if main.is_xr_active:
				if is_now_clicking:
					main.stream_backend.send_mouse_position_event(host_x, host_y, main.stream_viewport.size.x, main.stream_viewport.size.y)
					if is_now_clicking and not main.was_clicking:
						main.stream_backend.send_mouse_button_event(7, 1)
						main.was_clicking = true
				elif main.was_clicking:
					main.stream_backend.send_mouse_button_event(8, 1)
					main.was_clicking = false
			else:
				if is_now_clicking and not main.was_clicking:
					main.stream_backend.send_mouse_position_event(host_x, host_y, main.stream_viewport.size.x, main.stream_viewport.size.y)
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

		elif parent == main.get_node("%ScreenGrabBar") or parent == main.get_node("%MenuGrabBar") or (main.virtual_keyboard and parent == main.virtual_keyboard.grab_bar):
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
		if main.is_streaming:
			main.stream_backend.send_mouse_button_event(8, 1)
		main.was_clicking = false

func handle_grab():
	if not main.grabbed_node:
		return
	var active_raycast = main.hand_raycast if main.is_xr_active else main.mouse_raycast
	var hand_pos = active_raycast.global_position
	var hand_delta = hand_pos - main.grab_start_hand_pos
	var depth = hand_delta.dot(main.grab_forward) * main.grab_forward
	var lateral = hand_delta - depth
	main.grabbed_node.global_position = main.grab_start_node_pos + lateral * 6.0 + depth * 12.0
	var cam_pos = main.xr_camera.global_position
	main.grabbed_node.rotation.y = atan2(cam_pos.x - main.grabbed_node.global_position.x, cam_pos.z - main.grabbed_node.global_position.z)

	if main.grabbed_node == main.screen_mesh:
		if main.comp_quad:
			main.comp_quad.global_position = main.screen_mesh.global_position
			main.comp_quad.global_rotation = main.screen_mesh.global_rotation
		if main.comp_cylinder and main.comp_cylinder.visible:
			main.comp_cylinder.global_position = main.xr_camera.global_position
			main.comp_cylinder.global_position.y = main.screen_mesh.global_position.y
			main.comp_cylinder.global_rotation.y = main.screen_mesh.global_rotation.y

	if main.is_xr_active and main.grab_start_hand_basis != Basis():
		var hand_fwd = -active_raycast.global_transform.basis.z
		var hand_pitch = atan2(-hand_fwd.y, Vector2(hand_fwd.x, hand_fwd.z).length())
		var start_fwd = -main.grab_start_hand_basis.z
		var start_pitch = atan2(-start_fwd.y, Vector2(start_fwd.x, start_fwd.z).length())
		var pitch_delta = start_pitch - hand_pitch
		var euler = main.grabbed_node.rotation
		euler.x = main.grab_start_node_euler.x + pitch_delta * 0.66
		euler.z = 0.0
		if absf(euler.x) < 0.052:
			euler.x = 0.0
		main.grabbed_node.rotation = euler

	if main.grabbed_node == main.screen_mesh:
		if main.comp_quad:
			main.comp_quad.global_rotation = main.screen_mesh.global_rotation
		if main.comp_cylinder and main.comp_cylinder.visible:
			main.comp_cylinder.global_rotation.y = main.screen_mesh.global_rotation.y

	var still_clicking = main.right_hand.get_float("trigger") > 0.5 if main.is_xr_active else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not still_clicking:
		if main.grabbed_bar:
			_set_grab_bar_color(main.grabbed_bar, Color.WHITE, 0.01)
			main.grabbed_bar = null
		main.grabbed_node = null
		main.grab_start_hand_basis = Basis()
		main.grab_start_node_basis = Basis()
		main.grab_start_node_euler = Vector3.ZERO
		main.state_manager.save_state()

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

	var sv = main.stream_viewport.size
	var aspect = float(sv.x) / float(sv.y) if sv.y > 0 else 16.0 / 9.0
	var raw_w = 0.0
	if main.curvature == 0:
		raw_w = absf(local_hit.x) * 2.0
	else:
		var radius = 10.0 if main.curvature == 1 else 4.0
		var a = asin(clampf(local_hit.x / radius, -1.0, 1.0))
		raw_w = absf(a) * radius * 2.0
	var new_w = maxf(raw_w, 0.6)
	var new_h = new_w / aspect
	if new_h < 0.4:
		new_h = 0.4
		new_w = new_h * aspect

	main._mesh_size = Vector2(new_w, new_h)
	if main.curvature == 0:
		main.screen_mesh.mesh.size = Vector2(new_w, new_h)
	else:
		main.screen_manager.apply_curvature()

	var col_shape = main.screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if col_shape:
		if main.curvature == 0:
			var box = BoxShape3D.new()
			box.size = Vector3(new_w, new_h, 0.01)
			col_shape.shape = box
		else:
			var mesh = main.screen_mesh.mesh
			if mesh is ArrayMesh and mesh.get_surface_count() > 0:
				var arrays = mesh.surface_get_arrays(0)
				var verts = arrays[Mesh.ARRAY_VERTEX]
				var indices = arrays[Mesh.ARRAY_INDEX]
				var faces = PackedVector3Array()
				for i in range(0, indices.size(), 3):
					faces.append(verts[indices[i]])
					faces.append(verts[indices[i + 1]])
					faces.append(verts[indices[i + 2]])
				var concave = ConcavePolygonShape3D.new()
				concave.set_faces(faces)
				col_shape.shape = concave

	main.screen_manager.update_corner_positions()
	main.screen_manager.update_bezel_size()
	main._update_comp_layer_size()

	var still_clicking = main.right_hand.get_float("trigger") > 0.5 if main.is_xr_active else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not still_clicking:
		var handle = main.corner_handles[main.grabbed_corner_idx]
		_set_corner_color(handle, Color.WHITE, 0.01)
		main.grabbed_corner_idx = -1
		main.state_manager.save_state()

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

func _compute_parallax_shift(uv_x: float) -> float:
	if not main.depth_estimator or not main.depth_estimator.depth_texture:
		return 0.0
	var tex = main.depth_estimator.depth_texture
	var img = tex.get_image()
	if not img or img.is_empty():
		return 0.0
	var parallax = 0.042
	var half_parallax = parallax * 0.5
	var convergence = main.screen_mesh.material_override.get_shader_parameter("convergence")
	if convergence == null:
		convergence = 0.5
	var balance_shift = main.screen_mesh.material_override.get_shader_parameter("balance_shift")
	if balance_shift == null:
		balance_shift = 0.5
	var depth_x = int(clampf(uv_x - half_parallax, 0.0, 1.0) * (img.get_width() - 1))
	var depth_y = int(img.get_height() * 0.5)
	depth_x = clampi(depth_x, 0, img.get_width() - 1)
	depth_y = clampi(depth_y, 0, img.get_height() - 1)
	var depth = img.get_pixel(depth_x, depth_y).r
	var depth_diff = clampf(depth - convergence, -convergence, 1.0 - convergence)
	var dist_from_convergence = absf(depth - convergence)
	var zone_radius = 0.70
	var fade_multiplier = smoothstep(0.0, zone_radius, dist_from_convergence)
	depth_diff *= fade_multiplier
	var shift = parallax * depth_diff
	if (depth - convergence) < 0.0:
		shift *= (1.0 - balance_shift)
	else:
		shift *= balance_shift
	var h_dist = absf(uv_x - 0.5) * 2.0
	var vignette_start = 0.7
	var vignette = 1.0 - smoothstep(vignette_start, 1.0, pow(h_dist, 1.5))
	shift *= vignette
	return shift

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
			main.stream_backend.send_scroll_event(clicks)
