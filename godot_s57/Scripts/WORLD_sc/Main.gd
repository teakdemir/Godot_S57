extends Node3D

var http_client: S57HTTPClient  #HTTPClient godotta zaten built-in class.

func _ready():
	print("🗺️ S-57 Maritime Visualization Starting...")
	
	# HTTP client setup
	http_client = S57HTTPClient.new()  
	http_client.name = "S57HTTPClient"
	add_child(http_client)
	
	# Connect signals
	http_client.request_completed.connect(_on_api_success)
	http_client.request_failed.connect(_on_api_error)
	
	# Test API connection
	test_api()

func test_api():
	print("🔗 Testing API connection...")
	http_client.test_connection()

func _on_api_success(data: Dictionary):
	print("✅ API Connection SUCCESS!")
	print("Data received: ", data)
	
	# Now test maps list
	print("🗺️ Getting maps list...")
	http_client.get_maps_list()

func _on_api_error(error: String):
	print("❌ API Connection FAILED: " + error)

func _input(event):
	if event.is_action_pressed("ui_accept"): 
		print("🔄 Retesting API...")
		test_api()
