extends Node3D
class_name TerrainGenerator

const WATER_LEVEL := 0.0
const DEFAULT_STRUCTURE_SIZE := Vector3(4.0, 6.0, 4.0)
const STRUCTURE_PREFAB_DIR := "res://prefab/objects"

var water_root: Node3D
var structure_root: Node3D
var water_material: StandardMaterial3D
var fallback_structure_material: StandardMaterial3D
var structure_prefabs: Dictionary = {}

var last_center: Vector3 = Vector3.ZERO
var last_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	_setup_containers()
	_setup_materials()
	_load_structure_prefabs()

func _setup_containers() -> void:
	if water_root == null:
		water_root = Node3D.new()
		water_root.name = "WaterRoot"
		add_child(water_root)

	if structure_root == null:
		structure_root = Node3D.new()
		structure_root.name = "StructureRoot"
		add_child(structure_root)

func _setup_materials() -> void:
	if water_material == null:
		water_material = StandardMaterial3D.new()
		water_material.albedo_color = Color(0.0, 0.3, 0.6, 0.8)
		water_material.metallic = 0.1
		water_material.roughness = 0.05
		water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_material.refraction_strength = 0.05

	if fallback_structure_material == null:
		fallback_structure_material = StandardMaterial3D.new()
		fallback_structure_material.albedo_color = Color(0.82, 0.82, 0.84, 1.0)
		fallback_structure_material.metallic = 0.15
		fallback_structure_material.roughness = 0.6

func _load_structure_prefabs() -> void:
	structure_prefabs.clear()

	if !DirAccess.dir_exists_absolute(STRUCTURE_PREFAB_DIR):
		push_warning("Prefab directory not found: %s" % STRUCTURE_PREFAB_DIR)
		return

	var dir := DirAccess.open(STRUCTURE_PREFAB_DIR)
	if dir == null:
		push_warning("Unable to open prefab directory: %s" % STRUCTURE_PREFAB_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue

		if file_name.ends_with(".tscn"):
			var path := "%s/%s" % [STRUCTURE_PREFAB_DIR, file_name]
			var scene := load(path)
			if scene is PackedScene:
				var key := file_name.get_basename().to_upper()
				structure_prefabs[key] = scene
			else:
				push_warning("Failed to load prefab at %s" % path)
		file_name = dir.get_next()
	dir.list_dir_end()

	if !structure_prefabs.has("HARBOUR"):
		push_warning("Harbour prefab not found in %s" % STRUCTURE_PREFAB_DIR)

func generate_phase_one(map_data: Dictionary, scale: float) -> void:
	print("[TerrainGenerator] Phase 1 start")
	_setup_containers()
	_clear_phase_one()

	var world_config: Dictionary = map_data.get("world_config", {})
	var terrain: Dictionary = map_data.get("terrain", {})
	var nav_objects: Dictionary = map_data.get("navigation_objects", {})

	var seaare_polygon: Array = terrain.get("seaare_polygon", [])
	_create_water_mesh(seaare_polygon, scale, world_config)

	var structures: Array = nav_objects.get("structures", [])
	print("[TerrainGenerator] Spawning %d harbor structures" % structures.size())
	_spawn_structures(structures, scale)
	print("[TerrainGenerator] Phase 1 finished")

func _clear_phase_one() -> void:
	_clear_children(water_root)
	_clear_children(structure_root)
	last_center = Vector3.ZERO
	last_size = Vector2.ZERO

func _clear_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()

func _create_water_mesh(points: Array, scale: float, world_config: Dictionary) -> void:
	var width: float = 0.0
	var depth: float = 0.0
	var center: Vector3 = Vector3.ZERO

	if points.is_empty():
		var bounds := MapManager.calculate_godot_bounds(world_config, scale)
		width = float(bounds.get("width_godot", 20.0))
		depth = float(bounds.get("height_godot", 20.0))
		center = Vector3.ZERO
	else:
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF

		for point_dict in points:
			var coords := MapManager.api_to_godot_coordinates({
				"x": float(point_dict.get("x", 0.0)),
				"y": 0.0,
				"z": float(point_dict.get("z", 0.0))
			}, scale)

			min_x = min(min_x, coords.x)
			max_x = max(max_x, coords.x)
			min_z = min(min_z, coords.z)
			max_z = max(max_z, coords.z)

		width = max(max_x - min_x, 0.1)
		depth = max(max_z - min_z, 0.1)
		center = Vector3(min_x + width * 0.5, 0.0, min_z + depth * 0.5)

	last_center = center
	last_size = Vector2(width, depth)

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(width, depth)

	var water_plane := MeshInstance3D.new()
	water_plane.name = "WaterPlane"
	water_plane.mesh = plane_mesh
	water_plane.material_override = water_material
	water_plane.position = center
	water_plane.position.y = WATER_LEVEL
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	water_root.add_child(water_plane)

func _spawn_structures(structures: Array, scale: float) -> void:
	for structure_data in structures:
		var instance := _create_structure_instance(structure_data, scale)
		if instance:
			structure_root.add_child(instance)

func _create_structure_instance(structure_data: Dictionary, scale: float) -> Node3D:
	var position := MapManager.api_to_godot_coordinates(structure_data.get("position", {}), scale)
	var target_height := _calculate_structure_height(structure_data, scale)
	var prefab := _get_prefab_for_structure(structure_data.get("type", ""))

	var instance: Node3D
	if prefab:
		instance = prefab.instantiate()
		if !(instance is Node3D):
			var wrapper := Node3D.new()
			wrapper.name = structure_data.get("id", "StructureWrapper")
			wrapper.add_child(instance)
			instance = wrapper
	else:
		instance = _create_fallback_structure()

	instance.name = structure_data.get("id", "Harbour")
	instance.position = Vector3(position.x, position.y, position.z)

	var base_height := DEFAULT_STRUCTURE_SIZE.y
	var scale_factor := target_height / base_height if base_height > 0.0 else 1.0
	if scale_factor <= 0.0:
		scale_factor = 1.0

	instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
	return instance

func _calculate_structure_height(structure_data: Dictionary, scale: float) -> float:
	var properties: Dictionary = structure_data.get("properties", {})
	var height_in_m := 8.0

	if properties.has("height") and properties["height"] != null:
		height_in_m = float(properties["height"])
	elif properties.has("vertical_clearance") and properties["vertical_clearance"] != null:
		height_in_m = float(properties["vertical_clearance"])

	return max(height_in_m / max(scale, 1.0), 1.0)

func _get_prefab_for_structure(structure_type: String) -> PackedScene:
	var key := structure_type.to_upper()
	if structure_prefabs.has(key):
		return structure_prefabs[key]
	if structure_prefabs.has("HARBOUR"):
		return structure_prefabs["HARBOUR"]
	return null

func _create_fallback_structure() -> Node3D:
	var root := Node3D.new()
	root.name = "HarbourFallback"

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = DEFAULT_STRUCTURE_SIZE
	mesh_instance.mesh = mesh
	mesh_instance.material_override = fallback_structure_material
	mesh_instance.position = Vector3(0, DEFAULT_STRUCTURE_SIZE.y * 0.5, 0)

	root.add_child(mesh_instance)
	return root

func get_last_center() -> Vector3:
	return last_center

func get_last_size() -> Vector2:
	return last_size
