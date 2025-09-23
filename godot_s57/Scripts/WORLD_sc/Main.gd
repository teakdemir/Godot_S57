# res://scripts/WORLD_sc/Main.gd - Add UI hiding functionality
extends Node3D

var http_client: S57HTTPClient
var ui_canvas: CanvasLayer
var ui: Control
var terrain_generator: TerrainGenerator
var camera_controller: CameraController

# Current map data
var current_map_data: Dictionary = {}
var current_scale: int = 1000
var current_environment: Node3D

func _ready():
	print("S-57 Maritime Visualization Starting...")
	
	# Initialize components
	setup_http_client()
	setup_ui()
	setup_3d_components()
	
	# Initial load
	load_maps_list()

func setup_http_client():
	http_client = S57HTTPClient.new()
	http_client.name = "S57HTTPClient"
	add_child(http_client)
	
	http_client.request_completed.connect(_on_api_success)
	http_client.request_failed.connect(_on_api_error)

func setup_ui():
	ui_canvas = CanvasLayer.new()
	ui_canvas.name = "UICanvas"
	add_child(ui_canvas)
	
	ui = preload("res://scenes/WORLD/UI.tscn").instantiate()
	ui_canvas.add_child(ui)
	
	ui.map_selected.connect(_on_map_selected)
	ui.refresh_requested.connect(_on_refresh_maps)

func setup_3d_components():
	# Create camera
	var camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.position = Vector3(0, 100, 200)
	camera.rotation_degrees = Vector3(-20, 0, 0)
	add_child(camera)
	
	# Camera controller
	camera_controller = CameraController.new()
	camera_controller.camera = camera
	add_child(camera_controller)
	
	# Terrain generator
	terrain_generator = TerrainGenerator.new()
	add_child(terrain_generator)
	
	# Basic lighting
	var directional_light = DirectionalLight3D.new()
	directional_light.name = "Sun"
	directional_light.position = Vector3(0, 100, 0)
	directional_light.rotation_degrees = Vector3(-45, -45, 0)
	add_child(directional_light)

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
	
	var export_url = "http://localhost:8000/api/maps/" + str(map_id) + "/export"
	http_client.request_map_export(export_url)

func process_map_data(data: Dictionary):
	print("Processing map export data...")
	
	current_map_data = data
	
	# Extract world config
	var world_config = data.get("world_config", {})
	var coordinate_system = world_config.get("coordinate_system", {})
	
	# Calculate optimal scale
	var area_km2 = coordinate_system.get("area_km2", 0.0)
	current_scale = MapManager.calculate_optimal_scale(area_km2)
	
	print("Map area: " + str(area_km2) + " km²")
	print("Optimal scale: " + MapManager.get_scale_info(current_scale))
	
	# Update UI
	ui.show_loading_status("Scale: " + MapManager.get_scale_info(current_scale))
	ui.show_loading_status("Generating 3D environment...")
	
	# Generate 3D environment
	generate_3d_environment()

func generate_3d_environment():
	# Remove previous environment
	if current_environment:
		current_environment.queue_free()
	
	# Generate new environment
	current_environment = terrain_generator.generate_3d_environment(current_map_data, current_scale)
	add_child(current_environment)
	
	# Position camera appropriately
	position_camera_for_map()
	
	# HIDE UI AND SHOW 3D SCENE
	hide_ui_show_3d()

func position_camera_for_map():
	var camera = camera_controller.camera
	if not camera:
		return
	
	# Calculate map center and bounds
	var terrain = current_map_data.get("terrain", {})
	var seaare_polygon = terrain.get("seaare_polygon", [])
	
	if seaare_polygon.size() > 0:
		# Calculate center of SEAARE
		var center = Vector3.ZERO
		for point in seaare_polygon:
			var godot_pos = MapManager.api_to_godot_coordinates(point, current_scale)
			center += Vector3(godot_pos.x, 0, godot_pos.z)
		center /= seaare_polygon.size()
		
		# Position camera above center
		camera.position = Vector3(center.x, 100, center.z + 200)
		camera.look_at(center, Vector3.UP)

func hide_ui_show_3d():
	print("Switching to 3D view...")
	
	# Hide UI
	ui_canvas.visible = false
	
	# Enable camera controller
	camera_controller.set_process(true)
	camera_controller.set_physics_process(true)
	
	print("3D environment ready!")
	print("Controls:")
	print("- Right-click: Capture/release mouse")
	print("- WASD: Move camera")
	print("- Mouse scroll: Change altitude")
	print("- ESC: Return to map selection")

func show_ui_hide_3d():
	print("Returning to UI...")
	
	# Show UI
	ui_canvas.visible = true
	
	# Release mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	camera_controller.is_mouse_captured = false

func _input(event):
	# ESC to return to UI
	if event.is_action_pressed("ui_cancel"):
		if not ui_canvas.visible:
			show_ui_hide_3d()
		return
	
	# Manual refresh when UI is visible
	if event.is_action_pressed("ui_accept") and ui_canvas.visible:
		print("Manual refresh...")
		load_maps_list()
