extends RefCounted

# Navigasyon objelerinin prefab tabanli uretiminden sorumludur.
class_name ObjectGenerator

var owner: TerrainGenerator

func _init(owner_ref) -> void:
	owner = owner_ref

# JSON'dan gelen tum navigasyon objelerini prefab olarak sahneye ekler.
func build_navigation_objects(nav_objects: Dictionary, scale: int) -> Node3D:
	if nav_objects.is_empty():
		return null

	var root := Node3D.new()
	root.name = "NavigationObjects"
	var placed: int = 0

	for category in nav_objects.keys():
		var entries_variant = nav_objects.get(category, [])
		if not (entries_variant is Array):
			continue
		var entries: Array = entries_variant
		for obj_variant in entries:
			var obj_dict: Dictionary = obj_variant as Dictionary
			if obj_dict.is_empty():
				continue
			var instance: Node3D = _instantiate_navigation_object(obj_dict, scale)
			if instance:
				root.add_child(instance)
				placed += 1

	if placed == 0:
		root.queue_free()
		return null

	return root

# --- Yardimcilar -------------------------------------------------------------

# Tekil bir objeyi prefab tanimina gore instantiate eder.
func _instantiate_navigation_object(obj_data: Dictionary, scale: int) -> Node3D:
	var obj_type := String(obj_data.get("type", "")).strip_edges().to_lower()
	if obj_type.is_empty():
		return null

	var definition: Dictionary = owner.OBJECT_DEFINITIONS.get(obj_type, {}) as Dictionary
	var instance: Node3D = null

	if not definition.is_empty():
		var prefab_path := String(definition.get("prefab", ""))
		var prefab: PackedScene = owner._load_prefab(prefab_path)
		if prefab:
			instance = prefab.instantiate()

	if instance == null:
		return null
	instance.name = obj_data.get("id", obj_type.capitalize())

	var position_dict: Dictionary = obj_data.get("position", {}) as Dictionary
	if not position_dict or position_dict.is_empty():
		return null

	var horizontal: Vector3 = MapManager.api_to_godot_coordinates(position_dict, scale)
	var y_value := horizontal.y
	var y_offset := 0.0
	if not definition.is_empty() and definition.has("y_offset"):
		y_offset = float(definition["y_offset"])

	instance.position = Vector3(horizontal.x, y_value + y_offset, horizontal.z)

	if not definition.is_empty() and definition.has("scale"):
		instance.scale = definition["scale"]

	if not definition.is_empty():
		_apply_definition_materials(instance, definition)

	return instance

# Objeye ozel materyal ve hedef node secimini uygular.
func _apply_definition_materials(instance: Node3D, definition: Dictionary) -> void:
	if not definition.has("material"):
		return

	var target: Node = instance
	var material_node := String(definition.get("material_node", ""))
	if not material_node.is_empty():
		if instance.has_node(material_node):
			target = instance.get_node(material_node)
		else:
			var found := instance.find_child(material_node, true, false)
			if found:
				target = found

	if target and target is MeshInstance3D:
		var material: Material = owner._load_material(String(definition["material"]))
		if material:
			(target as MeshInstance3D).material_override = material

# Prefab bulunamadiginda basit silindir marker olusturur.
