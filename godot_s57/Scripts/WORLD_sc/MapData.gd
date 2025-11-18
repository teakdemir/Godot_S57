extends Node
# res://scripts/WORLD_sc/MapData.gd
class_name MapData

# Chart information from API
class ChartInfo:
	var id: int
	var map_name: String
	var area_km2: float
	var seaare_area_km2: float
	var total_objects: int
	var created_date: String
	
	func _init(data: Dictionary):
		id = int(data.get("id", 0))
		map_name = data.get("map_name", "Unknown")
		area_km2 = data.get("area_km2", 0.0)
		seaare_area_km2 = data.get("seaare_area_km2", 0.0)
		total_objects = int(data.get("total_object_count", 0))
		created_date = data.get("created_date", "")

# World coordinate system
class WorldConfig:
	var origin: Vector2
	var bounds: Dictionary
	var scale_factor: float
	var area_km2: float

# Terrain data for 3D generation
class TerrainData:
	var seaare_polygon: Array[Vector3]
	var coastline_points: Array[Vector3] 
	var harbor_objects: Array[Dictionary]

# Complete map export data
class MapExportData:
	var world_config: WorldConfig
	var terrain: TerrainData
	var navigation_objects: Dictionary
	
	func _init():
		world_config = WorldConfig.new()
		terrain = TerrainData.new()
		navigation_objects = {}
