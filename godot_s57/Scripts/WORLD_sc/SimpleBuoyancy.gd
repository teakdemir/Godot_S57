extends Node

var body: RigidBody3D

# --- SU VE DENGE AYARLARI ---
@export var water_height: float = 0.0
@export var buoyancy_force: float = 1000.0
@export var water_drag: float = 0.1
@export var water_angular_drag: float = 0.5
@export var stability_force: float = 8000.0 

# --- YENİ EKLENEN: MOTOR AYARLARI (ROS İÇİN) ---
@export var engine_power: float = 50000.0 # Gemiyi itme gücü (Gitmezse bunu artır)
@export var turn_torque: float = 20000.0  # Dönme gücü

# RosManager bu değişkenleri dışarıdan değiştirecek
var ros_throttle: float = 0.0
var ros_steering: float = 0.0

func _ready():
	# Scriptin bağlı olduğu node'u kontrol et
	if get_node(".") is RigidBody3D:
		body = get_node(".")
	elif get_parent() is RigidBody3D:
		body = get_parent()
	
	if body:
		# Gemi hızlıysa duvarın içinden ışınlanmasın (CCD)
		body.continuous_cd = true 
		print("BUOYANCY: Gemi bulundu. Motor, CCD ve Stabilite aktif.")

func _physics_process(_delta):
	if not body: return

	# 1. SU KALDIRMA KUVVETİ
	var depth = water_height - body.global_position.y
	
	if depth > 0:
		# Kaldırma
		var lift_force = Vector3.UP * buoyancy_force * depth
		body.apply_central_force(lift_force)
		
		# Sürtünme (Suda yavaşlama)
		body.linear_velocity *= (1.0 - water_drag)
		body.angular_velocity *= (1.0 - water_angular_drag)
		
		# Hacıyatmaz (Gemiyi dik tutma)
		var current_up = body.global_transform.basis.y
		var target_up = Vector3.UP
		var torque_dir = current_up.cross(target_up)
		body.apply_torque(torque_dir * stability_force)

	# 2. MOTOR HAREKETİ (ROS KOMUTLARI)
	# Suya değip değmediğine bakmaksızın motor çalışsın (veya istersen if depth > 0 içine alabilirsin)
	
	# İleri/Geri Gaz
	if abs(ros_throttle) > 0.01:
		# Geminin baktığı yöne (-basis.z) kuvvet uygula
		var forward_dir = -body.global_transform.basis.z
		body.apply_central_force(forward_dir * ros_throttle * engine_power)
		
	# Sağa/Sola Dümen
	if abs(ros_steering) > 0.01:
		# Y ekseni etrafında döndür
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)
