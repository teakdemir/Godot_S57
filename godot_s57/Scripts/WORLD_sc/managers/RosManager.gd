extends Node3D

# IP ADRESİ (ROS Cihazı) --> sena // Benim mobilveri IP
@export var socket_url: String = "ws://192.168.98.206:9090" 

# AYARLAR
@export var publish_rate: float = 10.0
@export var lidar_range: float = 50.0 
@export var num_rays: int = 72 

var socket = WebSocketPeer.new()
var rays: Array[RayCast3D] = []
var last_publish_time = 0.0
var is_connected = false

# Parent (Gemi) erişimi
@onready var ship_body: RigidBody3D = get_parent()
# Controller erişimi
@onready var controller = ship_body 

func _ready():
	print("📡 ROS: Bağlantı kuruluyor... Hedef: ", socket_url)
	socket.connect_to_url(socket_url)
	_setup_lidar()

func _setup_lidar():
	for i in range(num_rays):
		var ray = RayCast3D.new()
		add_child(ray)
		# Lidar konumu (Gemi merkezinden 3 metre yukarıda)
		ray.position = Vector3(0, 3.0, 0)
		ray.target_position = Vector3(lidar_range, 0, 0)
		ray.rotation_degrees.y = i * (360.0 / float(num_rays))
		ray.enabled = true
		rays.append(ray)

func _process(delta):
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			_on_connection_success()
			
		while socket.get_available_packet_count():
			var packet = socket.get_packet().get_string_from_utf8()
			_handle_incoming(packet)
			
		last_publish_time += delta
		if last_publish_time >= (1.0 / publish_rate):
			_publish_data()
			last_publish_time = 0.0
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			print("❌ ROS: Bağlantı koptu!")
			is_connected = false

func _on_connection_success():
	print("✅ ROS: BAĞLANTI BAŞARILI! (IP: 192.168.98.206)")
	is_connected = true
	# Dinle (Subscribe)
	var sub_msg = {"op": "subscribe", "topic": "/cmd_vel", "type": "geometry_msgs/msg/Twist"}
	socket.send_text(JSON.stringify(sub_msg))
	# Yayınla (Advertise)
	socket.send_text(JSON.stringify({"op": "advertise", "topic": "/odom", "type": "nav_msgs/msg/Odometry"}))
	socket.send_text(JSON.stringify({"op": "advertise", "topic": "/scan", "type": "sensor_msgs/msg/LaserScan"}))

func _publish_data():
	var time = Time.get_unix_time_from_system()
	var secs = int(time)
	var nsecs = int((time - secs) * 1e9)
	
	var pos = ship_body.global_position
	var rot = ship_body.global_transform.basis.get_rotation_quaternion()
	var lin_vel = ship_body.linear_velocity
	var ang_vel = ship_body.angular_velocity
	
	# ODOMETRY VERİSİ
	var odom_msg = {
		"op": "publish",
		"topic": "/odom",
		"msg": {
			"header": { "stamp": { "sec": secs, "nanosec": nsecs }, "frame_id": "odom" },
			"child_frame_id": "base_link",
			"pose": { "pose": {
				"position": { "x": -pos.z, "y": -pos.x, "z": pos.y },
				"orientation": { "x": rot.x, "y": rot.z, "z": -rot.y, "w": rot.w }
			}},
			"twist": { "twist": {
				"linear": { "x": lin_vel.length(), "y": 0.0, "z": 0.0 },
				"angular": { "x": 0.0, "y": 0.0, "z": ang_vel.y }
			}}
		}
	}
	socket.send_text(JSON.stringify(odom_msg))
	
	# LIDAR VERİSİ
	var ranges = []
	for ray in rays:
		if ray.is_colliding():
			ranges.append(ray.global_position.distance_to(ray.get_collision_point()))
		else:
			ranges.append(lidar_range + 1.0)
			
	var scan_msg = {
		"op": "publish",
		"topic": "/scan",
		"msg": {
			"header": { "stamp": { "sec": secs, "nanosec": nsecs }, "frame_id": "base_link" },
			"angle_min": 0.0,
			"angle_max": 2.0 * PI,
			"angle_increment": (2.0 * PI) / float(num_rays),
			"range_min": 0.5,
			"range_max": lidar_range,
			"ranges": ranges
		}
	}
	socket.send_text(JSON.stringify(scan_msg))

func _handle_incoming(json_str):
	var json = JSON.new()
	if json.parse(json_str) == OK:
		var data = json.get_data()
		if data.has("topic") and data["topic"] == "/cmd_vel":
			var msg = data["msg"]
			controller.ros_throttle = clamp(msg["linear"]["x"], -1.0, 1.0)
			controller.ros_steering = clamp(msg["angular"]["z"], -1.0, 1.0)
