extends Control

signal map_selected(map_id: int)
signal refresh_requested

@onready var map_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/SelectionContainer/OptionButton
@onready var load_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/LoadMap
@onready var refresh_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/Refresh
@onready var info_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/ScrollContainer/InfoLabel

var available_maps: Array[MapData.ChartInfo] = []
var selected_map_id: int = -1

func _ready():
	load_button.pressed.connect(_on_load_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	map_dropdown.item_selected.connect(_on_map_selected)
	
	load_button.disabled = true
	info_label.text = "Select a map to load..."

func populate_maps(maps_data: Array):
	available_maps.clear()
	map_dropdown.clear()
	
	for map_data in maps_data:
		var chart_info = MapData.ChartInfo.new(map_data)
		available_maps.append(chart_info)
		
		var display_text = chart_info.map_name + " (" + str(chart_info.seaare_area_km2) + " km²)"
		map_dropdown.add_item(display_text)
		map_dropdown.set_item_metadata(map_dropdown.get_item_count() - 1, chart_info.id)
	
	info_label.text = "Found " + str(available_maps.size()) + " maps. Select one to load."
	load_button.disabled = available_maps.is_empty()

func _on_map_selected(index: int):
	if index >= 0 and index < available_maps.size():
		selected_map_id = map_dropdown.get_item_metadata(index)
		var selected_chart = available_maps[index]
		
		info_label.text = "Selected: " + selected_chart.map_name + "\n"
		info_label.text += "SEAARE Area: " + str(selected_chart.seaare_area_km2) + " km²\n"
		info_label.text += "Objects: " + str(selected_chart.total_objects) + "\n"
		info_label.text += "Scale will be: " + calculate_scale_info(selected_chart.seaare_area_km2)
		
		load_button.disabled = false

func calculate_scale_info(seaare_area: float) -> String:
	if seaare_area < 100:
		return "1:500 (Coastal Detail)"
	elif seaare_area < 1000:
		return "1:1000 (Approach Chart)"
	elif seaare_area < 10000:
		return "1:2000 (Regional Chart)"
	else:
		return "1:5000 (General Chart)"

func _on_load_pressed():
	if selected_map_id > 0:
		info_label.text += "\n\nLoading map..."
		load_button.disabled = true
		map_selected.emit(selected_map_id)

func _on_refresh_pressed():
	info_label.text = "Refreshing maps list..."
	map_dropdown.clear()
	load_button.disabled = true
	refresh_requested.emit()

func show_loading_status(message: String):
	info_label.text += "\n" + message

func show_error(error_message: String):
	info_label.text += "\nError: " + error_message
	load_button.disabled = false
