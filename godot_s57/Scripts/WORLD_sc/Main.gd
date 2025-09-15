# res://scripts/WORLD_sc/Main.gd
extends Node3D

var http_client: S57HTTPClient
var ui_canvas: CanvasLayer
var ui: Control

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

func load_map_export(_map_id: int):
	print("Map export loading will be implemented in Step 3...")
	ui.show_loading_status("Map loading coming in Step 3...")

func process_map_data(_data: Dictionary):
	print("Map processing will be implemented in Step 3...")

func _input(event):
	if event.is_action_pressed("ui_accept"):
		print("Manual refresh...")
		load_maps_list()
