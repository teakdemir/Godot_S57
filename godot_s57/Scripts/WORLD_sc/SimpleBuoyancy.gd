extends Node

var body: RigidBody3D

# --- AYARLAR ---
@export var water_height: float = 0.0
@export var buoyancy_force: float = 1000.0
@export var water_drag: float = 0.05       # Düz sürtünmeyi biraz azalttım (daha akıcı olsun)
@export var water_angular_drag: float = 0.5
@export var stability_force: float = 8000.0 

@export var engine_power: float = 50000.0 
@export var turn_torque: float = 20000.0  

@export var lateral_drag: float = 0.95 

# Ros değişkenleri
var ros_throttle: float = 0.0
var ros_steering: float = 0.0

func _ready():
	if get_node(".") is RigidBody3D:
		body = get_node(".")
	elif get_parent() is RigidBody3D:
		body = get_parent()
	
	if body:
		body.continuous_cd = true 
		print("BUOYANCY: Gemi hazır. Yanal sürtünme aktif.")

func _physics_process(delta):
	if not body: return
	
	var depth = water_height - body.global_position.y
	
	if depth > 0:
		# Kaldırma Kuvveti
		var lift_force = Vector3.UP * buoyancy_force * depth
		body.apply_central_force(lift_force)
		
		# Genel Sürtünme (Yavaşlatma)
		body.linear_velocity *= (1.0 - water_drag * delta * 10.0) # Delta ile çarptım ki FPS'den etkilenmesin
		body.angular_velocity *= (1.0 - water_angular_drag * delta * 10.0)
		
		# Hacıyatmaz (Dik durma)
		var current_up = body.global_transform.basis.y
		var target_up = Vector3.UP
		var torque_dir = current_up.cross(target_up)
		body.apply_torque(torque_dir * stability_force)
		
		_prevent_sliding()

	# İleri/Geri Gaz
	if abs(ros_throttle) > 0.01:
		var forward_dir = -body.global_transform.basis.z
		body.apply_central_force(forward_dir * ros_throttle * engine_power)
		
	# Sağa/Sola Dümen
	if abs(ros_steering) > 0.01:
		# Dönüş Torku
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)

func _prevent_sliding():
	# Geminin sağ vektörü (Local X)
	var right_dir = body.global_transform.basis.x
	
	# Geminin şu anki hızının ne kadarı sağa/sola doğru? (Dot Product)
	var sideways_velocity = body.linear_velocity.dot(right_dir)
	
	body.linear_velocity -= right_dir * sideways_velocity * lateral_drag
