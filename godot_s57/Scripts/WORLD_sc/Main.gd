# res://scripts/WORLD_sc/Main.gd
extends Node3D

var http_client: S57HTTPClient
var ui_canvas: CanvasLayer
var ui: Control

# Current map data
var current_map_data: Dictionary = {}
var current_scale: int = 1000

func _ready():
	print("S-57 Maritime Visualization Starting...")
	
	# HTTP client setup
	http_client = S57HTTPClient.new()
	http_client.name = "S57HTTPClient"
	add_child(http_client)
	
	# Create CanvasLayer for UI
	ui_canvas = CanvasLayer.new()
	ui_canvas.name = "UICanvas"
	add_child(ui_canvas)
	
	# Load UI scene and add to canvas
	ui = preload("res://scenes/WORLD/UI.tscn").instantiate()
	ui_canvas.add_child(ui)
	
	# Connect signals
	http_client.request_completed.connect(_on_api_success)
	http_client.request_failed.connect(_on_api_error)
	ui.map_selected.connect(_on_map_selected)
	ui.refresh_requested.connect(_on_refresh_maps)
	
	# Initial load
	load_maps_list()

func load_maps_list():
	print("Loading maps list...")
	http_client.get_maps_list()

func _on_api_success(data):
	print("API Response received")
	
	if data.has("status"):
		print("API Health OK, getting maps...")
		http_client.get_maps_list()
	elif typeof(data) == TYPE_ARRAY:
		print("Maps list received: " + str(data.size()) + " maps")
		ui.populate_maps(data)
	else:
		print("Map export data received")
		process_map_data(data)

func _on_api_error(error: String):
	print("API Error: " + error)
	ui.show_error(error)

func _on_map_selected(map_id: int):
	print("Loading map ID: " + str(map_id))
	ui.show_loading_status("Requesting map data...")
	load_map_export(map_id)

func _on_refresh_maps():
	print("Refreshing maps list...")
	load_maps_list()

func load_map_export(map_id: int):
	print("Loading map export for ID: " + str(map_id))
	ui.show_loading_status("Fetching map data from API...")
	
	# API export endpoint'ine request gönder
	var export_url = "http://localhost:8000/api/maps/" + str(map_id) + "/export"
	http_client.request_map_export(export_url)

func process_map_data(data: Dictionary):
	print("Processing map export data...")
	
	# Store current map data
	current_map_data = data
	
	# Extract world config
	var world_config = data.get("world_config", {})
	var coordinate_system = world_config.get("coordinate_system", {})
	
	# Calculate optimal scale
	var area_km2 = coordinate_system.get("area_km2", 0.0)
	current_scale = MapManager.calculate_optimal_scale(area_km2)
	
	print("Map area: " + str(area_km2) + " km²")
	print("Optimal scale: " + MapManager.get_scale_info(current_scale))
	
	# Calculate map bounds in Godot units
	var godot_bounds = MapManager.calculate_godot_bounds(world_config, current_scale)
	
	print("Godot map size: " + str(godot_bounds.width_godot) + "x" + str(godot_bounds.height_godot) + " units")
	
	# Extract terrain data
	var terrain = data.get("terrain", {})
	var seaare_polygon = terrain.get("seaare_polygon", [])
	var coastline_points = terrain.get("coastline_points", [])
	
	print("SEAARE points: " + str(seaare_polygon.size()))
	print("Coastline points: " + str(coastline_points.size()))
	
	# Extract navigation objects
	var nav_objects = data.get("navigation_objects", {})
	var structures = nav_objects.get("structures", [])
	
	print("Harbor structures: " + str(structures.size()))
	
	# Update UI with processed info
	ui.show_loading_status("Scale: " + MapManager.get_scale_info(current_scale))
	ui.show_loading_status("Map size: " + str(int(godot_bounds.width_godot)) + "x" + str(int(godot_bounds.height_godot)) + " units")
	ui.show_loading_status("SEAARE: " + str(seaare_polygon.size()) + " points")
	ui.show_loading_status("Harbors: " + str(structures.size()) + " structures")
	ui.show_loading_status("Ready for 3D terrain generation!")
	
	# Next: Step 4 will generate 3D terrain from this data

func _input(event):
	if event.is_action_pressed("ui_accept"):
		print("Manual refresh...")
		load_maps_list()
