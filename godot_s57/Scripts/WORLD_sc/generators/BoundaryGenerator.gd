extends RefCounted

class_name BoundaryGenerator

var owner: TerrainGenerator

func _init(owner_ref) -> void:
	owner = owner_ref

# SEAARE poligonundan yari saydam sinir mesh'i olusturur.
func build_boundary(sea_polygon: Array, scale: int) -> Node3D:
	if sea_polygon.is_empty():
		return null

	var sanitized: Array = owner._sanitize_sea_polygon(sea_polygon)
	if sanitized.size() < 3:
		return null

	var world_points: Array = []
	for point_variant in sanitized:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict or point_dict.is_empty():
			continue
		var api_coords := {
			"x": float(point_dict.get("x", 0.0)),
			"y": 0.0,
			"z": float(point_dict.get("z", 0.0))
		}
		var world := MapManager.api_to_godot_coordinates(api_coords, scale)
		world_points.append(Vector3(world.x, 0.0, world.z))
	if world_points.size() < 3:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collision_faces := PackedVector3Array()

	for idx in range(world_points.size()):
		var next := (idx + 1) % world_points.size()
		var base_a: Vector3 = world_points[idx]
		var base_b: Vector3 = world_points[next]
		
		# Sabitleri TerrainGenerator'dan alıyoruz
		var bottom_a: Vector3 = base_a + Vector3(0, owner.BARRIER_DEPTH_OFFSET, 0)
		var bottom_b: Vector3 = base_b + Vector3(0, owner.BARRIER_DEPTH_OFFSET, 0)
		var top_a: Vector3 = base_a + Vector3(0, owner.BARRIER_HEIGHT, 0)
		var top_b: Vector3 = base_b + Vector3(0, owner.BARRIER_HEIGHT, 0)

		# Saydamlık 
		st.set_color(owner.BARRIER_COLOR_BOTTOM)
		st.add_vertex(bottom_a)
		st.set_color(owner.BARRIER_COLOR_BOTTOM)
		st.add_vertex(bottom_b)
		st.set_color(owner.BARRIER_COLOR_TOP)
		st.add_vertex(top_b)

		st.set_color(owner.BARRIER_COLOR_BOTTOM)
		st.add_vertex(bottom_a)
		st.set_color(owner.BARRIER_COLOR_TOP)
		st.add_vertex(top_b)
		st.set_color(owner.BARRIER_COLOR_TOP)
		st.add_vertex(top_a)

		# Duvarın iki tarafı da çarpışır olsun
		# İç
		collision_faces.append_array([
			bottom_a, bottom_b, top_b,
			bottom_a, top_b, top_a
		])
		#Dış
		collision_faces.append_array([
			bottom_a, top_b, bottom_b,
			bottom_a, top_a, top_b
		])

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.vertex_color_use_as_alpha = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED # Görsel olarak da iki yüzü göster

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BoundaryFade"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material

	var boundary_root := Node3D.new()
	boundary_root.name = "Boundary"
	boundary_root.add_child(mesh_instance)

	var static_body := StaticBody3D.new()
	static_body.name = "BoundaryCollider"
	var collision_shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(collision_faces)
	collision_shape.shape = concave
	static_body.add_child(collision_shape)
	boundary_root.add_child(static_body)

	return boundary_root
