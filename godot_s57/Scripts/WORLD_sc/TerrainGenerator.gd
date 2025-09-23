# res://scripts/WORLD_sc/TerrainGenerator.gd
class_name TerrainGenerator
extends Node

# Prefab paths
const HARBOR_PREFAB = "res://prefab/objects/harbours/harbour.tscn"

# Generate complete 3D environment from map data
func generate_3d_environment(map_data: Dictionary, scale: int) -> Node3D:
	var environment_root = Node3D.new()
	environment_root.name = "MapEnvironment"
	
	# Extract data
	var terrain = map_data.get("terrain", {})
	var seaare_polygon = terrain.get("seaare_polygon", [])
	var nav_objects = map_data.get("navigation_objects", {})
	var harbors = nav_objects.get("structures", [])
	
	print("Generating 3D environment:")
	print("- SEAARE points: " + str(seaare_polygon.size()))
	print("- Harbor count: " + str(harbors.size()))
	print("- Scale: 1:" + str(scale))
	
	# Generate sea surface
	var sea_surface = generate_sea_surface(seaare_polygon, scale)
	environment_root.add_child(sea_surface)
	
	# Generate harbors using prefabs
	if harbors.size() > 0:
		var harbors_node = generate_harbors_with_prefabs(harbors, scale)
		environment_root.add_child(harbors_node)
	
	return environment_root

# Generate sea surface from SEAARE polygon
func generate_sea_surface(seaare_polygon: Array, scale: int) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "SeaSurface"
	
	print("DEBUG: SEAARE polygon data: ", seaare_polygon)
	print("DEBUG: Scale factor: ", scale)
	
	# Convert API coordinates to Godot coordinates
	var vertices = PackedVector3Array()
	for point in seaare_polygon:
		var godot_pos = MapManager.api_to_godot_coordinates(point, scale)
		print("DEBUG: API point: ", point, " -> Godot: ", godot_pos)
		vertices.append(Vector3(godot_pos.x, 0.0, godot_pos.z))
	
	print("DEBUG: Final vertices: ", vertices)
	
	# Calculate bounds size
	var bounds_size = 0.0
	if vertices.size() >= 2:
		bounds_size = vertices[0].distance_to(vertices[2]) if vertices.size() >= 4 else vertices[0].distance_to(vertices[1])
	
	print("DEBUG: Sea bounds size: ", bounds_size)
	
	# Create mesh arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Create larger sea if bounds are too small or data is insufficient
	if bounds_size < 10.0 or vertices.size() != 4:
		print("DEBUG: Creating large default sea surface")
		# Create 4km x 4km sea surface
		vertices = PackedVector3Array([
			Vector3(-2000, 0, -2000),
			Vector3(2000, 0, -2000), 
			Vector3(2000, 0, 2000),
			Vector3(-2000, 0, 2000)
		])
	
	# Create triangles from quad
	var indices = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	# Calculate normals
	var normals = PackedVector3Array()
	for i in vertices.size():
		normals.append(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	
	# Create and apply mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	# Apply sea material
	var sea_material = load("res://materials/WORLD_mat/SeaMaterial.tres")
	if sea_material:
		mesh_instance.material_override = sea_material
	else:
		var material = StandardMaterial3D.new()
		material.albedo_color = Color("#1a4d80")
		material.metallic = 0.2
		material.roughness = 0.1
		mesh_instance.material_override = material
	
	print("Sea surface created with ", vertices.size(), " vertices")
	return mesh_instance

# Generate harbors using prefab system
func generate_harbors_with_prefabs(harbors: Array, scale: int) -> Node3D:
	var harbors_parent = Node3D.new()
	harbors_parent.name = "Harbors"
	
	# Load harbor prefab
	var harbor_prefab = load(HARBOR_PREFAB)
	if not harbor_prefab:
		print("Warning: Harbor prefab not found at " + HARBOR_PREFAB)
		print("Creating basic harbor objects instead")
		return generate_basic_harbors(harbors, scale)
	
	for i in range(harbors.size()):
		var harbor_data = harbors[i]
		var harbor_instance = create_harbor_from_prefab(harbor_prefab, harbor_data, scale, i)
		harbors_parent.add_child(harbor_instance)
	
	print("Harbors created: " + str(harbors.size()) + " prefab instances")
	return harbors_parent

# Create harbor instance from prefab
func create_harbor_from_prefab(prefab: PackedScene, harbor_data: Dictionary, scale: int, index: int) -> Node3D:
	var harbor_instance = prefab.instantiate()
	harbor_instance.name = "Harbor_" + str(index)
	
	var position = harbor_data.get("position", {})
	var godot_pos = MapManager.api_to_godot_coordinates(position, scale)
	
	print("DEBUG: Harbor ", index, " API pos: ", position, " -> Godot: ", godot_pos)
	
	# Set position and SCALE
	harbor_instance.position = Vector3(godot_pos.x, 5, godot_pos.z)
	harbor_instance.scale = Vector3(10, 10, 10)  # Make harbors 10x bigger
	
	# Apply material to harbor mesh if found
	var mesh_node = harbor_instance.find_child("harbour")
	if mesh_node and mesh_node is MeshInstance3D:
		var harbor_material = load("res://materials/WORLD_mat/HarborMaterial.tres")
		if harbor_material:
			mesh_node.material_override = harbor_material
		else:
			var material = StandardMaterial3D.new()
			material.albedo_color = Color("#8b4513")
			material.roughness = 0.8
			mesh_node.material_override = material
	
	print("DEBUG: Harbor placed at: ", harbor_instance.position, " with scale: ", harbor_instance.scale)
	
	return harbor_instance

# Fallback: Generate basic harbors if prefab fails
func generate_basic_harbors(harbors: Array, scale: int) -> Node3D:
	var harbors_parent = Node3D.new()
	harbors_parent.name = "BasicHarbors"
	
	for i in range(harbors.size()):
		var harbor_data = harbors[i]
		var harbor_node = create_basic_harbor(harbor_data, scale, i)
		harbors_parent.add_child(harbor_node)
	
	print("Basic harbors created: " + str(harbors.size()) + " objects")
	return harbors_parent

# Create basic harbor object
func create_basic_harbor(harbor_data: Dictionary, scale: int, index: int) -> Node3D:
	var harbor_group = Node3D.new()
	harbor_group.name = "Harbor_" + str(index)
	
	var position = harbor_data.get("position", {})
	var godot_pos = MapManager.api_to_godot_coordinates(position, scale)
	
	# Create harbor mesh (box)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "harbour"
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(50, 20, 50)  # Large harbor building
	mesh_instance.mesh = box_mesh
	
	# Apply material
	var harbor_material = load("res://materials/WORLD_mat/HarborMaterial.tres")
	if harbor_material:
		mesh_instance.material_override = harbor_material
	else:
		var material = StandardMaterial3D.new()
		material.albedo_color = Color("#8b4513")
		material.roughness = 0.8
		mesh_instance.material_override = material
	
	mesh_instance.position = Vector3(0, 10, 0)  # Half height above ground
	harbor_group.add_child(mesh_instance)
	harbor_group.position = Vector3(godot_pos.x, 5, godot_pos.z)
	
	return harbor_group
