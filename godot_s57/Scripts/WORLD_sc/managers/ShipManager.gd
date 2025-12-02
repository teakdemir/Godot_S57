extends Node
class_name ShipManager

const SHIP_PREFAB_PATH = "res://prefab/objects/Ship/Ship.tscn"

var terrain_generator: TerrainGenerator
var current_ship: Node3D # Hata almamak için Node3D yaptık
var is_placing_mode: bool = false
var main_camera: Camera3D

func _init(terrain_gen_ref: TerrainGenerator):
	terrain_generator = terrain_gen_ref

func _ready():
	set_process_input(true)
	set_process(true)

# Main.gd'den çağrılan fonksiyon
func start_ship_placement(camera: Camera3D, parent_node: Node3D):
	main_camera = camera
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if current_ship and is_instance_valid(current_ship):
		current_ship.queue_free()

	var ship_scene = load(SHIP_PREFAB_PATH)
	if ship_scene:
		current_ship = ship_scene.instantiate()
		current_ship.name = "PlayerShip"
		
		if parent_node:
			parent_node.add_child(current_ship)
		else:
			terrain_generator.add_child(current_ship)
			
		# Fiziği dondur 
		var body = _get_rigidbody(current_ship)
		if body:
			body.freeze = true
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			# Çarpışmayı kapat ki yerleştirirken etrafa takılmasın
			body.collision_layer = 0 
			body.collision_mask = 0
			
		is_placing_mode = true
		print("SHIP MANAGER: Mouse placement started. Click to drop the ship.")
	else:
		print("SHIP MANAGER: Error! Ship prefab not found.")

func _process(_delta):
	# Mouse takibi
	if is_placing_mode and is_instance_valid(current_ship) and main_camera:
		var mouse_pos = filter_mouse_position_on_water()
		if mouse_pos != Vector3.ZERO:
			# Gemiyi suyun 2 metre üzerinde tut
			current_ship.global_position = mouse_pos + Vector3(0, 2.0, 0)

func _input(event):
	# Sol tıklandığında gemiyi bırak
	if is_placing_mode and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			drop_ship()

func drop_ship():
	if is_instance_valid(current_ship):
		var body = _get_rigidbody(current_ship)
		if body:
			# 1. Hızı Sıfırla
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			
			# 2. Çarpışmaları Aç
			body.collision_layer = 1
			body.collision_mask = 1
			
			# 3. Fiziği Serbest Bırak
			body.freeze = false
		
		is_placing_mode = false
		
		# başla
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		print("SHIP MANAGER: Ship dropped into physics simulation.")
func _get_rigidbody(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node
	for child in node.get_children():
		if child is RigidBody3D:
			return child
	return null

func filter_mouse_position_on_water() -> Vector3:
	var mouse_pos_2d = get_viewport().get_mouse_position()
	var ray_origin = main_camera.project_ray_origin(mouse_pos_2d)
	var ray_normal = main_camera.project_ray_normal(mouse_pos_2d)
	
	# Deniz seviyesi (Y=0) düzlemi
	var sea_plane = Plane(Vector3.UP, 0.0)
	var intersection = sea_plane.intersects_ray(ray_origin, ray_normal)
	
	if intersection:
		return intersection
	else:
		return Vector3.ZERO
