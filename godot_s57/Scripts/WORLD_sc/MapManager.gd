# res://scripts/WORLD_sc/MapManager.gd
class_name MapManager
extends Node

# Static scale calculation
static func calculate_optimal_scale(seaare_area_km2: float) -> int:
	if seaare_area_km2 < 100.0:
		return 500    # Coastal Detail
	elif seaare_area_km2 < 1000.0:
		return 1000   # Approach Chart
	elif seaare_area_km2 < 10000.0:
		return 2000   # Regional Chart
	else:
		return 5000   # General Chart

# Static scale info text
static func get_scale_info(scale: int) -> String:
	match scale:
		500:
			return "1:500 (Coastal Detail)"
		1000:
			return "1:1000 (Approach Chart)"
		2000:
			return "1:2000 (Regional Chart)"
		5000:
			return "1:5000 (General Chart)"
		_:
			return "1:" + str(scale) + " (Custom)"

# Convert API coordinates to Godot coordinates
static func api_to_godot_coordinates(api_coords: Dictionary, scale: float) -> Vector3:
	return Vector3(
		api_coords.get("x", 0.0) / scale,
		api_coords.get("y", 0.0) / scale,
		api_coords.get("z", 0.0) / scale
	)

# Calculate map bounds in Godot units
static func calculate_godot_bounds(world_config: Dictionary, scale: float) -> Dictionary:
	var coordinate_system = world_config.get("coordinate_system", {})
	var bounds = coordinate_system.get("bounds", {})

	var min_lat = bounds.get("min_lat", 0.0)
	var max_lat = bounds.get("max_lat", 0.0)
	var min_lon = bounds.get("min_lon", 0.0)
	var max_lon = bounds.get("max_lon", 0.0)

	var lat_range_m = (max_lat - min_lat) * 111320.0
	var lon_range_m = (max_lon - min_lon) * 111320.0

	return {
		"width_godot": lon_range_m / scale,
		"height_godot": lat_range_m / scale,
		"area_km2": coordinate_system.get("area_km2", 0.0)
	}
