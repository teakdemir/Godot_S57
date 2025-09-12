# res://scripts/WORLD_sc/HTTPClient.gd
class_name S57HTTPClient  # ← Changed name
extends Node

signal request_completed(data: Dictionary)
signal request_failed(error: String)

var http_request: HTTPRequest

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func test_connection():
	"""Sadece API'ye bağlanabilir miyiz test et"""
	print("Testing API connection...")
	http_request.request("http://localhost:8000/health")

func get_maps_list():
	"""Map listesini getir"""
	print("Getting maps list...")
	http_request.request("http://localhost:8000/api/maps")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("Response code: " + str(response_code))
	
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		
		if parse_result == OK:
			var data = json.get_data()
			print("✅ API Response: ", data)
			request_completed.emit(data)
		else:
			print("❌ JSON Parse failed")
			request_failed.emit("JSON parse error")
	else:
		print("❌ HTTP Error: " + str(response_code))
		request_failed.emit("HTTP " + str(response_code))
