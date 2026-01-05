extends Node

var body: RigidBody3D
var ros_throttle: float = 0.0
var ros_steering: float = 0.0	

# --- AYARLAR ---
@export var water_height: float = 0.0
@export var buoyancy_force: float = 1000.0
@export var water_drag: float = 0.01      
@export var water_angular_drag: float = 0.1
@export var stability_force: float = 8000.0 

@export var engine_power: float = 600.0 
@export var turn_torque: float = 150.0  
@export var lateral_drag: float = 0.95 

func _ready():
	if get_node(".") is RigidBody3D: body = get_node(".")
	elif get_parent() is RigidBody3D: body = get_parent()
	
	if body:
		body.continuous_cd = true
		# Sadece başlangıçta bir kez bilgi verir, sonra susar.
		print("🚢 GEMİ HAZIR. Kütle: ", body.mass, " | Güç: ", engine_power)

func _physics_process(delta):
	if not body: return
	
	# --- Debug Print Satırı SİLİNDİ ---

	var depth = water_height - body.global_position.y
	if depth > 0:
		body.apply_central_force(Vector3.UP * buoyancy_force * depth)
		
		# --- ZIPLAMA ÖNLEYİCİ ---
		if abs(body.linear_velocity.y) > 0.5:
			body.linear_velocity.y *= 0.90
		
		body.linear_velocity *= (1.0 - water_drag * delta * 10.0)
		body.angular_velocity *= (1.0 - water_angular_drag * delta * 10.0)
		
		var torque_dir = body.global_transform.basis.y.cross(Vector3.UP)
		body.apply_torque(torque_dir * stability_force)
		
		var right = body.global_transform.basis.x
		body.linear_velocity -= right * body.linear_velocity.dot(right) * lateral_drag

	# Hareket Uygulama (Sessiz Mod)
	if abs(ros_throttle) > 0.0001:
		body.apply_central_force(-body.global_transform.basis.z * ros_throttle * engine_power)
		
	if abs(ros_steering) > 0.0001:
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)
