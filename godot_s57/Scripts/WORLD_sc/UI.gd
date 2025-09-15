# res://scripts/WORLD_sc/UI.gd
extends Control

signal map_selected(map_id: int)
signal refresh_requested

@onready var map_dropdown: OptionButton = $MainMargin/VBoxContainer/HBoxContainer/MapDropdown
@onready var load_button: Button = $MainMargin/VBoxContainer/HBoxContainer2/LoadButton
@onready var refresh_button: Button = $MainMargin/VBoxContainer/HBoxContainer2/RefreshButton
@onready var info_label: RichTextLabel = $MainMargin/VBoxContainer/InfoArea/InfoLabel

var available_maps: Array[MapData.ChartInfo] = []
var selected_map_id: int = -1

func _ready():
	# Null check before connecting
	if map_dropdown:
		map_dropdown.item_selected.connect(_on_map_selected)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	
	# Safe text assignment
	if info_label:
		info_label.text = "Maritime Chart Analyzer Ready"
	
	if load_button:
		load_button.disabled = true

func populate_maps(maps_data: Array):
	if not map_dropdown or not info_label:
		return
		
	available_maps.clear()
	map_dropdown.clear()
	
	for map_data in maps_data:
		var chart_info = MapData.ChartInfo.new(map_data)
		available_maps.append(chart_info)
		
		var display_text = chart_info.map_name + " | " + str(int(chart_info.seaare_area_km2)) + "km²"
		map_dropdown.add_item(display_text)
		map_dropdown.set_item_metadata(map_dropdown.get_item_count() - 1, chart_info.id)
	
	info_label.text = "Found " + str(available_maps.size()) + " maps. Select one to load."
	if load_button:
		load_button.disabled = available_maps.is_empty()

func _on_map_selected(index: int):
	if not info_label or not load_button:
		return
		
	if index >= 0 and index < available_maps.size():
		selected_map_id = map_dropdown.get_item_metadata(index)
		var selected_chart = available_maps[index]
		
		var info_text = "Selected: " + selected_chart.map_name + "\n"
		info_text += "Sea Area: " + str(selected_chart.seaare_area_km2) + " km²\n"
		info_text += "Objects: " + str(selected_chart.total_objects)
		
		info_label.text = info_text
		load_button.disabled = false

func _on_load_pressed():
	if selected_map_id > 0 and info_label and load_button:
		info_label.text += "\n\nLoading map..."
		load_button.disabled = true
		map_selected.emit(selected_map_id)

func _on_refresh_pressed():
	if info_label and map_dropdown and load_button:
		info_label.text = "Refreshing maps list..."
		map_dropdown.clear()
		load_button.disabled = true
		refresh_requested.emit()

func show_loading_status(message: String):
	if info_label:
		info_label.text += "\n" + message

func show_error(error_message: String):
	if info_label and load_button:
		info_label.text += "\nError: " + error_message
		load_button.disabled = false
