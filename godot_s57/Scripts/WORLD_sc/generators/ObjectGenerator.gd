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

	var base_scale := instance.scale
	if not definition.is_empty() and definition.has("scale"):
		base_scale = definition["scale"]
		instance.scale = base_scale

	if not definition.is_empty():
		_apply_definition_materials(instance, definition)

	if obj_type == "hrbfac":
		_align_with_water_heading(instance, obj_data)
	elif obj_type == "bridge":
		_configure_bridge_span(instance, obj_data, scale, definition, base_scale)

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

# Prefab bulunamadiginda basit silindir marker olusturur. --> kapalı şu an

func _align_with_water_heading(instance: Node3D, obj_data: Dictionary) -> void:
	var orientation_variant = obj_data.get("orientation", null)
	if not (orientation_variant is Dictionary):
		return
	var orientation: Dictionary = orientation_variant
	if not orientation.has("heading_deg"):
		return
	var heading_deg := float(orientation["heading_deg"])
	instance.rotation.y = deg_to_rad(heading_deg)

func _configure_bridge_span(
	instance: Node3D,
	obj_data: Dictionary,
	scale: int,
	definition: Dictionary,
	base_scale: Vector3
) -> void:
	var span_variant = obj_data.get("span", null)
	if not (span_variant is Dictionary):
		return
	var span: Dictionary = span_variant
	var start_variant = span.get("start")
	var end_variant = span.get("end")
	if not (start_variant is Dictionary) or not (end_variant is Dictionary):
		return

	var start_point: Vector3 = _span_point_to_world(start_variant, obj_data, scale)
	var end_point: Vector3 = _span_point_to_world(end_variant, obj_data, scale)
	var direction := end_point - start_point
	var horizontal := Vector2(direction.x, direction.z)
	if horizontal.length() <= 0.01:
		return

	var midpoint := (start_point + end_point) * 0.5
	instance.position = Vector3(midpoint.x, instance.position.y, midpoint.z)
	instance.rotation.y = atan2(direction.x, direction.z)

	var target_length := horizontal.length()
	var native_length := float(definition.get("native_length", 1.0))
	if native_length <= 0.001:
		native_length = 1.0
	var stretch_ratio := target_length / native_length

	var axis := String(definition.get("span_axis", "x")).to_lower()
	var new_scale := base_scale
	match axis:
		"x":
			new_scale.x = max(0.01, base_scale.x * stretch_ratio)
		"z":
			new_scale.z = max(0.01, base_scale.z * stretch_ratio)
		"y":
			new_scale.y = max(0.01, base_scale.y * stretch_ratio)
		_:
			new_scale.x = max(0.01, base_scale.x * stretch_ratio)
	instance.scale = new_scale

func _span_point_to_world(span_point: Dictionary, obj_data: Dictionary, scale: int) -> Vector3:
	var base_y := 0.0
	var position_variant = obj_data.get("position", null)
	if position_variant is Dictionary:
		base_y = float(position_variant.get("y", 0.0))
	var coords := {
		"x": span_point.get("x", 0.0),
		"y": base_y,
		"z": span_point.get("z", 0.0)
	}
	return MapManager.api_to_godot_coordinates(coords, scale) 
