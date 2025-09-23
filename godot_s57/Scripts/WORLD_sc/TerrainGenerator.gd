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
	if seaare_polygon.size() > 0:
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
	
	# Convert API coordinates to Godot coordinates
	var vertices = PackedVector3Array()
	for point in seaare_polygon:
		var godot_pos = MapManager.api_to_godot_coordinates(point, scale)
		vertices.append(Vector3(godot_pos.x, 0.0, godot_pos.z))
	
	# Create mesh arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Simple quad mesh for sea surface (if 4 points)
	if vertices.size() == 4:
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
		# Create basic blue water material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.3, 0.6, 0.8)
		material.metallic = 0.2
		material.roughness = 0.1
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = material
	
	print("Sea surface created: " + str(vertices.size()) + " vertices")
	return mesh_instance

# Generate harbors using prefab system
func generate_harbors_with_prefabs(harbors: Array, scale: int) -> Node3D:
	var harbors_parent = Node3D.new()
	harbors_parent.name = "Harbors"
	
	# Load harbor prefab
	var harbor_prefab = load(HARBOR_PREFAB)
	if not harbor_prefab:
		print("Warning: Harbor prefab not found at " + HARBOR_PREFAB)
		return harbors_parent
	
	for i in range(harbors.size()):
		var harbor_data = harbors[i]
		var harbor_instance = create_harbor_from_prefab(harbor_prefab, harbor_data, scale, i)
		harbors_parent.add_child(harbor_instance)
	
	print("Harbors created: " + str(harbors.size()) + " prefab instances")
	return harbors_parent

# Create harbor instance from prefab
func create_harbor_from_prefab(prefab: PackedScene, harbor_data: Dictionary, scale: int, index: int) -> Node3D:
	# Instantiate prefab
	var harbor_instance = prefab.instantiate()
	harbor_instance.name = "Harbor_" + str(index)
	
	# Get position from harbor data
	var position = harbor_data.get("position", {})
	var godot_pos = MapManager.api_to_godot_coordinates(position, scale)
	
	# Set position (Y slightly above sea level)
	harbor_instance.position = Vector3(godot_pos.x, 5, godot_pos.z)
	
	# Optional: Add harbor info as metadata
	var attributes = harbor_data.get("attributes", {})
	var harbor_name = attributes.get("name", "Harbor_" + str(index))
	harbor_instance.set_meta("harbor_name", harbor_name)
	harbor_instance.set_meta("harbor_data", harbor_data)
	
	return harbor_instance
