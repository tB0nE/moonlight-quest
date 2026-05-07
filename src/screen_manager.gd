class_name ScreenManager
extends RefCounted

var main: Node3D

func _init(owner: Node3D):
	main = owner

func create_corner_handles():
	var offsets = [
		Vector2(-0.5, 0.5),
		Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5),
		Vector2(0.5, -0.5),
	]
	var mesh_size = main._mesh_size
	for i in range(4):
		var handle = MeshInstance3D.new()
		handle.name = "Corner%d" % i
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0.01)
		var h_bar = MeshInstance3D.new()
		h_bar.name = "HBar"
		var h_mesh = BoxMesh.new()
		h_mesh.size = Vector3(0.15, 0.008, 0.008)
		h_bar.mesh = h_mesh
		h_bar.material_override = mat.duplicate()
		h_bar.position = Vector3(-offsets[i].x * 0.15, 0, 0)
		var v_bar = MeshInstance3D.new()
		v_bar.name = "VBar"
		var v_mesh = BoxMesh.new()
		v_mesh.size = Vector3(0.008, 0.15, 0.008)
		v_bar.mesh = v_mesh
		v_bar.material_override = mat.duplicate()
		v_bar.position = Vector3(0, -offsets[i].y * 0.15, 0)
		var area = Area3D.new()
		area.collision_layer = 2
		var shape = CollisionShape3D.new()
		var col = BoxShape3D.new()
		col.size = Vector3(0.2, 0.2, 0.1)
		shape.shape = col
		shape.position = Vector3(0, 0, 0)
		area.add_child(shape)
		handle.add_child(h_bar)
		handle.add_child(v_bar)
		handle.add_child(area)
		handle.position = Vector3(offsets[i].x * (mesh_size.x + 0.08), offsets[i].y * (mesh_size.y + 0.08), 0)
		main.screen_mesh.add_child(handle)
		main.corner_handles.append(handle)

func update_corner_positions():
	var mesh_size = main._mesh_size
	var corner_z = 0.0
	var extra_out = 0.0
	if main.curvature > 0:
		var radius = 10.0 if main.curvature == 1 else 4.0
		var angle = mesh_size.x / radius
		var half_angle = angle * 0.5
		var chord_half = sin(half_angle) * radius
		var extra = chord_half - mesh_size.x * 0.5
		if main.curvature == 2:
			extra += 0.12
		else:
			extra += 0.08
		extra_out = extra
		corner_z = -(cos(half_angle) * radius - radius) - 0.02
	var offsets = [
		Vector2(-0.5, 0.5),
		Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5),
		Vector2(0.5, -0.5),
	]
	for i in range(4):
		var cx = offsets[i].x * (mesh_size.x + 0.08)
		if main.curvature > 0:
			var radius = 10.0 if main.curvature == 1 else 4.0
			var half_angle = mesh_size.x / radius * 0.5
			var a = -half_angle if offsets[i].x < 0 else half_angle
			cx = sin(a) * radius
			cx += -extra_out if offsets[i].x < 0 else extra_out
		main.corner_handles[i].position = Vector3(cx, offsets[i].y * (mesh_size.y + 0.08), corner_z)
	main.get_node("%ScreenGrabBar").position.y = -mesh_size.y / 2.0 - 0.08

func create_bezel():
	main.bezel_mesh = MeshInstance3D.new()
	main.bezel_mesh.name = "Bezel"
	var bezel_quad = QuadMesh.new()
	main.bezel_mesh.mesh = bezel_quad
	var bezel_mat = StandardMaterial3D.new()
	bezel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bezel_mat.albedo_color = Color(0, 0, 0, 1)
	main.bezel_mesh.material_override = bezel_mat
	main.bezel_mesh.position = Vector3(0, 0, -0.005)
	main.screen_mesh.add_child(main.bezel_mesh)
	update_bezel_size()

func update_bezel_size():
	if not main.bezel_mesh:
		return
	var mesh_size = main._mesh_size
	var bezel_pad = 0.04
	var bezel_size = mesh_size + Vector2(bezel_pad, bezel_pad)
	if main.curvature == 0:
		var bezel_quad = QuadMesh.new()
		bezel_quad.size = bezel_size
		main.bezel_mesh.mesh = bezel_quad
		main.bezel_mesh.position = Vector3(0, 0, -0.005)
	else:
		var radius = 10.0 if main.curvature == 1 else 4.0
		var subdivide = 32
		var v_subdivide = 16
		var angle = bezel_size.x / radius
		var verts = PackedVector3Array()
		var uvs = PackedVector2Array()
		var indices = PackedInt32Array()
		for j in range(subdivide + 1):
			for i in range(v_subdivide + 1):
				var t = float(j) / subdivide
				var u = float(i) / v_subdivide
				var a = -angle * 0.5 + angle * t
				var x = sin(a) * radius
				var z = -(cos(a) * radius - radius) - 0.005
				var y = (u - 0.5) * bezel_size.y
				verts.append(Vector3(x, y, z))
				uvs.append(Vector2(t, 1.0 - u))
		var cols = v_subdivide + 1
		for j in range(subdivide):
			for i in range(v_subdivide):
				var idx = j * cols + i
				indices.append(idx)
				indices.append(idx + 1)
				indices.append(idx + cols)
				indices.append(idx + 1)
				indices.append(idx + cols + 1)
				indices.append(idx + cols)
		var arr = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		var arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		main.bezel_mesh.mesh = arr_mesh
		main.bezel_mesh.position = Vector3.ZERO

func toggle_bezel():
	main.bezel_enabled = not main.bezel_enabled
	if main.bezel_mesh:
		main.bezel_mesh.visible = main.bezel_enabled
	main.ui_controller.update_option_btn(main._ui_bezel_btn, "On" if main.bezel_enabled else "Off")
	main.state_manager.save_state()

func cycle_curvature():
	main.curvature = (main.curvature + 1) % 3
	apply_curvature()
	main.ui_controller.update_option_btn(main._ui_curve_btn, main.curvature_labels[main.curvature])
	main.state_manager.save_state()

func apply_curvature():
	var mesh_size = main._mesh_size
	if main.curvature == 0:
		var quad = QuadMesh.new()
		quad.size = mesh_size
		main.screen_mesh.mesh = quad
		update_shader_for_mesh(mesh_size)
		set_screen_collision_flat(mesh_size)
		return
	var subdivide = 32
	var v_subdivide = 16
	var radius = 10.0 if main.curvature == 1 else 4.0
	var angle = mesh_size.x / radius
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for j in range(subdivide + 1):
		for i in range(v_subdivide + 1):
			var t = float(j) / subdivide
			var u = float(i) / v_subdivide
			var a = -angle * 0.5 + angle * t
			var x = sin(a) * radius
			var z = -(cos(a) * radius - radius)
			var y = (u - 0.5) * mesh_size.y
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(t, 1.0 - u))
	var cols = v_subdivide + 1
	for j in range(subdivide):
		for i in range(v_subdivide):
			var idx = j * cols + i
			indices.append(idx)
			indices.append(idx + 1)
			indices.append(idx + cols)
			indices.append(idx + 1)
			indices.append(idx + cols + 1)
			indices.append(idx + cols)
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	main.screen_mesh.mesh = arr_mesh
	update_shader_for_mesh(mesh_size)
	set_screen_collision_curved(verts, indices)

func update_shader_for_mesh(mesh_size: Vector2):
	set_screen_collision_flat(mesh_size)
	update_corner_positions()
	if main.bezel_mesh:
		update_bezel_size()

func set_screen_collision_flat(mesh_size: Vector2):
	var col_shape = main.screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if not col_shape:
		return
	var box = BoxShape3D.new()
	box.size = Vector3(mesh_size.x, mesh_size.y, 0.01)
	col_shape.shape = box

func set_screen_collision_curved(verts: PackedVector3Array, indices: PackedInt32Array):
	var col_shape = main.screen_mesh.get_node_or_null("Area3D/CollisionShape3D")
	if not col_shape:
		return
	var faces = PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(verts[indices[i]])
		faces.append(verts[indices[i + 1]])
		faces.append(verts[indices[i + 2]])
	var concave = ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	col_shape.shape = concave
