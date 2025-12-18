extends Node3D

var http_client: S57HTTPClient
var ui_canvas: CanvasLayer
var ui: Control
var terrain_generator: TerrainGenerator
var camera_controller: CameraController
var ship_manager: ShipManager
var main_camera: Camera3D

var current_map_data: Dictionary = {}
var current_scale: int = 1000
var current_environment: Node3D

var is_ship_mode: bool = false # Mod takibi

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
	# Serbest Kamera
	main_camera = Camera3D.new()
	main_camera.name = "MainCamera"
	main_camera.position = Vector3(0, 200, 400)
	main_camera.rotation_degrees = Vector3(-30, 0, 0)
	main_camera.far = 20000.0 
	add_child(main_camera)
	
	camera_controller = CameraController.new()
	camera_controller.camera = main_camera
	add_child(camera_controller)
	
	terrain_generator = TerrainGenerator.new()
	add_child(terrain_generator)
	
	ship_manager = ShipManager.new(terrain_generator)
	add_child(ship_manager)

func load_maps_list():
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
	ui.show_loading_status("Generating 3D environment...")
	call_deferred("generate_3d_environment")

func generate_3d_environment():
	if current_environment:
		current_environment.queue_free()
	
	current_environment = terrain_generator.generate_3d_environment(current_map_data, current_scale)
	add_child(current_environment)
	
	position_camera_for_map()
	hide_ui_show_3d()
	
	# Gemi yerleştirmeyi başlat
	ship_manager.start_ship_placement(main_camera, current_environment)

func position_camera_for_map():
	if not main_camera: return
	var terrain = current_map_data.get("terrain", {})
	var seaare_polygon = terrain.get("seaare_polygon", [])
	if seaare_polygon.size() > 0:
		var center = Vector3.ZERO
		for point in seaare_polygon:
			var godot_pos = MapManager.api_to_godot_coordinates(point, current_scale)
			center += Vector3(godot_pos.x, 0, godot_pos.z)
		center /= seaare_polygon.size()
		main_camera.position = Vector3(center.x, 50, center.z + 50)
		main_camera.look_at(center, Vector3.UP)
	else:
		main_camera.position = Vector3(0, 50, 50)
		main_camera.look_at(Vector3.ZERO, Vector3.UP)

func hide_ui_show_3d():
	ui_canvas.visible = false
	camera_controller.set_process(true)
	camera_controller.set_physics_process(true)

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
			
	# --- "O" TUŞU İLE KAMERA DEĞİŞTİRME ---
	if event is InputEventKey and event.pressed and event.keycode == KEY_O:
		toggle_camera_mode()

func toggle_camera_mode():
	# Gemi yoksa veya hala yerleştiriyorsak geçiş yapma
	if not ship_manager.current_ship or ship_manager.is_placing_mode:
		print("HATA: Gemi henüz hazır değil!")
		return

	is_ship_mode = !is_ship_mode
	
	var ship = ship_manager.current_ship
	
	# Geminin içindeki child node'ları bul
	var ship_cam = ship.get_node_or_null("ChaseCamera")
	var ship_controller = ship.get_node_or_null("ShipController")
	
	if is_ship_mode:
		print("Mod: GEMİ KONTROLÜ")
		
		#Serbest kamerayı kapat
		camera_controller.set_physics_process(false)
		camera_controller.set_process(false)
		main_camera.current = false
		
		#Gemiye geç
		if ship_cam:
			ship_cam.current = true
		
		if ship_controller:
			ship_controller.is_active = true
			
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	else:
		print("Mod: SERBEST KAMERA")
		
		#Gemiyi boşa al 
		if ship_controller:
			ship_controller.is_active = false
			
		#Serbest kameraya dön
		if ship_cam:
			ship_cam.current = false
			
		main_camera.current = true
		
		camera_controller.set_physics_process(true)
		camera_controller.set_process(true)
