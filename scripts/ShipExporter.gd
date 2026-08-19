# res://scripts/ShipExporter.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# ShipExporter.gd - Wavefront ASCII .OBJ Export Pipeline
# ==============================================================================
# Exports generated 3D procedural biological ship meshes (ArrayMesh or MeshInstance3D)
# to ASCII Wavefront .obj file format. Includes vertex positions (v), normals (vn),
# texture UV coordinates (vt), and face index definitions (f).
# Ensures automatic directory creation (user://exports/ or custom paths).
# ==============================================================================

@tool
extends RefCounted
class_name ShipExporter

## Export a MeshInstance3D or ArrayMesh/Mesh object to an ASCII .obj file.
## Returns OK on success or an Error code on failure.
static func export_to_obj(
	target_mesh: Variant,
	file_path: String = "user://exports/ship_export.obj",
	use_global_transform: bool = true
) -> Error:
	var mesh: Mesh = null
	var transform: Transform3D = Transform3D.IDENTITY
	
	if target_mesh is MeshInstance3D:
		var instance: MeshInstance3D = target_mesh as MeshInstance3D
		mesh = instance.mesh
		if use_global_transform:
			transform = instance.global_transform
		else:
			transform = instance.transform
	elif target_mesh is Mesh:
		mesh = target_mesh as Mesh
	else:
		push_error("ShipExporter: Target object must be MeshInstance3D or Mesh.")
		return ERR_INVALID_PARAMETER

	if mesh == null:
		push_error("ShipExporter: Target mesh is null.")
		return ERR_INVALID_DATA

	var surface_count: int = mesh.get_surface_count()
	if surface_count == 0:
		push_error("ShipExporter: Target mesh has no surfaces to export.")
		return ERR_INVALID_DATA

	# Ensure export directory exists
	var dir_path: String = file_path.get_base_dir()
	if not dir_path.is_empty():
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			push_error("ShipExporter: Failed to create export directory: '%s' (Error %d)" % [dir_path, dir_err])
			return dir_err

	# Open target file for writing
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		push_error("ShipExporter: Failed to open file for writing: '%s' (Error %d)" % [file_path, err])
		return err

	# Write ASCII OBJ Header
	file.store_line("# ==============================================================================")
	file.store_line("# BioGenesis-X Wavefront OBJ Ship Export")
	file.store_line("# Exported at: %s" % Time.get_datetime_string_from_system())
	file.store_line("# Surfaces: %d" % surface_count)
	file.store_line("# ==============================================================================\n")

	var global_vertex_offset: int = 1
	var global_uv_offset: int = 1
	var global_normal_offset: int = 1

	var total_vertices: int = 0
	var total_faces: int = 0

	# Process each surface in the mesh
	for s in range(surface_count):
		file.store_line("# Surface %d" % s)
		file.store_line("o Ship_Surface_%d" % s)

		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

		if vertices.is_empty():
			continue

		var has_normals: bool = (normals.size() == vertices.size())
		var has_uvs: bool = (uvs.size() == vertices.size())

		# 1. Write Vertices (v)
		var v_buffer: PackedStringArray = PackedStringArray()
		v_buffer.resize(vertices.size())
		for i in range(vertices.size()):
			var pos: Vector3 = transform * vertices[i]
			v_buffer[i] = "v %.6f %.6f %.6f" % [pos.x, pos.y, pos.z]
		file.store_string("\n".join(v_buffer) + "\n")
		total_vertices += vertices.size()

		# 2. Write Texture UV Coordinates (vt)
		if has_uvs:
			var vt_buffer: PackedStringArray = PackedStringArray()
			vt_buffer.resize(uvs.size())
			for i in range(uvs.size()):
				vt_buffer[i] = "vt %.6f %.6f" % [uvs[i].x, uvs[i].y]
			file.store_string("\n".join(vt_buffer) + "\n")

		# 3. Write Normals (vn)
		if has_normals:
			var det: float = transform.basis.determinant()
			var normal_basis: Basis = transform.basis.inverse().transposed() if not is_zero_approx(det) else Basis.IDENTITY
			var vn_buffer: PackedStringArray = PackedStringArray()
			vn_buffer.resize(normals.size())
			for i in range(normals.size()):
				var n: Vector3 = (normal_basis * normals[i]).normalized()
				vn_buffer[i] = "vn %.6f %.6f %.6f" % [n.x, n.y, n.z]
			file.store_string("\n".join(vn_buffer) + "\n")

		# 4. Write Faces (f)
		file.store_line("s 1") # Enable smooth shading group
		var f_buffer: PackedStringArray = PackedStringArray()

		if indices.size() > 0:
			# Indexed mesh surface
			var triangle_count: int = indices.size() / 3
			f_buffer.resize(triangle_count)
			var valid_face_count: int = 0
			for t in range(triangle_count):
				var i1: int = indices[t * 3]
				var i2: int = indices[t * 3 + 1]
				var i3: int = indices[t * 3 + 2]

				if i1 < 0 or i1 >= vertices.size() or i2 < 0 or i2 >= vertices.size() or i3 < 0 or i3 >= vertices.size():
					continue

				var v1: int = global_vertex_offset + i1
				var v2: int = global_vertex_offset + i2
				var v3: int = global_vertex_offset + i3

				if has_uvs and has_normals:
					var vt1: int = global_uv_offset + i1
					var vt2: int = global_uv_offset + i2
					var vt3: int = global_uv_offset + i3
					var vn1: int = global_normal_offset + i1
					var vn2: int = global_normal_offset + i2
					var vn3: int = global_normal_offset + i3
					f_buffer[valid_face_count] = "f %d/%d/%d %d/%d/%d %d/%d/%d" % [v1, vt1, vn1, v2, vt2, vn2, v3, vt3, vn3]
				elif has_normals:
					var vn1: int = global_normal_offset + i1
					var vn2: int = global_normal_offset + i2
					var vn3: int = global_normal_offset + i3
					f_buffer[valid_face_count] = "f %d//%d %d//%d %d//%d" % [v1, vn1, v2, vn2, v3, vn3]
				elif has_uvs:
					var vt1: int = global_uv_offset + i1
					var vt2: int = global_uv_offset + i2
					var vt3: int = global_uv_offset + i3
					f_buffer[valid_face_count] = "f %d/%d %d/%d %d/%d" % [v1, vt1, v2, vt2, v3, vt3]
				else:
					f_buffer[valid_face_count] = "f %d %d %d" % [v1, v2, v3]
				valid_face_count += 1
			f_buffer.resize(valid_face_count)
			total_faces += valid_face_count
		else:
			# Non-indexed mesh surface
			var triangle_count: int = vertices.size() / 3
			f_buffer.resize(triangle_count)
			for t in range(triangle_count):
				var i1: int = t * 3
				var i2: int = t * 3 + 1
				var i3: int = t * 3 + 2

				var v1: int = global_vertex_offset + i1
				var v2: int = global_vertex_offset + i2
				var v3: int = global_vertex_offset + i3

				if has_uvs and has_normals:
					var vt1: int = global_uv_offset + i1
					var vt2: int = global_uv_offset + i2
					var vt3: int = global_uv_offset + i3
					var vn1: int = global_normal_offset + i1
					var vn2: int = global_normal_offset + i2
					var vn3: int = global_normal_offset + i3
					f_buffer[t] = "f %d/%d/%d %d/%d/%d %d/%d/%d" % [v1, vt1, vn1, v2, vt2, vn2, v3, vt3, vn3]
				elif has_normals:
					var vn1: int = global_normal_offset + i1
					var vn2: int = global_normal_offset + i2
					var vn3: int = global_normal_offset + i3
					f_buffer[t] = "f %d//%d %d//%d %d//%d" % [v1, vn1, v2, vn2, v3, vn3]
				elif has_uvs:
					var vt1: int = global_uv_offset + i1
					var vt2: int = global_uv_offset + i2
					var vt3: int = global_uv_offset + i3
					f_buffer[t] = "f %d/%d %d/%d %d/%d" % [v1, vt1, v2, vt2, v3, vt3]
				else:
					f_buffer[t] = "f %d %d %d" % [v1, v2, v3]
			total_faces += triangle_count

		file.store_string("\n".join(f_buffer) + "\n\n")

		# Advance global offsets for next surface
		global_vertex_offset += vertices.size()
		if has_uvs:
			global_uv_offset += uvs.size()
		if has_normals:
			global_normal_offset += normals.size()

	file.close()

	print("ShipExporter: Successfully exported mesh to '%s' (%d vertices, %d faces)." % [
		file_path, total_vertices, total_faces
	])
	return OK

## Non-static helper instance method
func export_ship(target: Variant, path: String = "user://exports/ship_export.obj") -> Error:
	return ShipExporter.export_to_obj(target, path)
