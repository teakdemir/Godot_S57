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
	
	setup_http_client()
	setup_ui()
	setup_3d_components()
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
	camera.position = Vector3(0, 200, 400)
	camera.rotation_degrees = Vector3(-30, 0, 0)
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
	directional_light.rotation_degrees = Vector3(-45, -30, 0)
	directional_light.light_energy = 1.0
	add_child(directional_light)

func load_maps_list():
	print("Loading maps list...")
	http_client.get_maps_list()

func _on_api_success(data):
	if data.has("status"):
		http_client.get_maps_list()
	elif typeof(data) == TYPE_ARRAY:
		ui.populate_maps(data)
	else:
		process_map_data(data)

func _on_api_error(error: String):
	print("API Error: " + error)
	ui.show_error(error)

func _on_map_selected(map_id: int):
	ui.show_loading_status("Requesting map data...")
	load_map_export(map_id)

func _on_refresh_maps():
	load_maps_list()

func load_map_export(map_id: int):
	var export_url = "http://localhost:8000/api/maps/" + str(map_id) + "/export"
	http_client.request_map_export(export_url)

func process_map_data(data: Dictionary):
	current_map_data = data
	
	var world_config = data.get("world_config", {})
	var coordinate_system = world_config.get("coordinate_system", {})
	var area_km2 = coordinate_system.get("area_km2", 0.0)
	current_scale = MapManager.calculate_optimal_scale(area_km2)
	
	print("Map area: " + str(area_km2) + " km²")
	print("Optimal scale: " + MapManager.get_scale_info(current_scale))
	
	ui.show_loading_status("Generating 3D environment...")
	generate_3d_environment()

func generate_3d_environment():
	if current_environment:
		current_environment.queue_free()
	
	current_environment = terrain_generator.generate_3d_environment(current_map_data, current_scale)
	add_child(current_environment)
	
	position_camera_for_map()
	hide_ui_show_3d()

func position_camera_for_map():
	var camera = camera_controller.camera
	if not camera:
		return
	
	var terrain = current_map_data.get("terrain", {})
	var seaare_polygon = terrain.get("seaare_polygon", [])
	
	if seaare_polygon.size() > 0:
		var center = Vector3.ZERO
		for point in seaare_polygon:
			var godot_pos = MapManager.api_to_godot_coordinates(point, current_scale)
			center += Vector3(godot_pos.x, 0, godot_pos.z)
		center /= seaare_polygon.size()
		
		camera.position = Vector3(center.x, 200, center.z + 400)
		camera.look_at(center, Vector3.UP)
	else:
		camera.position = Vector3(0, 200, 400)
		camera.look_at(Vector3.ZERO, Vector3.UP)

func hide_ui_show_3d():
	ui_canvas.visible = false
	camera_controller.set_process(true)
	camera_controller.set_physics_process(true)
	
	print("3D environment ready!")
	print("Controls: Right-click capture, WASD move, scroll altitude, ESC return to UI")

func show_ui_hide_3d():
	ui_canvas.visible = true
	camera_controller.set_process(false)
	camera_controller.set_physics_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	camera_controller.is_mouse_captured = false

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if ui_canvas.visible:
			hide_ui_show_3d()
		else:
			show_ui_hide_3d()
		return
	
	if event.is_action_pressed("ui_accept") and ui_canvas.visible:
		load_maps_list()
