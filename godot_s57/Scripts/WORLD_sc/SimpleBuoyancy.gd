extends Node

var body: RigidBody3D
var ros_throttle: float = 0.0
var ros_steering: float = 0.0	

#TEMEL AYARLAR
@export var water_height: float = 0.0
@export var buoyancy_force: float = 15000.0

#FİZİK KATSAYILARI
@export var bounce_damp: float = 2.0      # Zıplama Önleyici Sertliği
@export var lateral_drag: float = 2.0     # Yan Kayma (Drift) Direnci
@export var brake_power: float = 2.0      # Hız Limiti Frenleme Gücü
@export var max_speed: float = 5.0        # Maksimum Hız (m/s)

#MOTOR VE DÜMEN
@export var stability_force: float = 2000.0   # Hacıyatmaz (Dik Durma) Gücü
@export var engine_power: float = 1000.0      # Motor İtiş Gücü
@export var turn_torque: float = 500.0        # Dönüş Torku

func _ready():
	# RigidBody'yi bul 
	if get_node(".") is RigidBody3D: body = get_node(".")
	elif get_parent() is RigidBody3D: body = get_parent()
	
	if body:
		body.continuous_cd = true
		print("🚢 GEMİ FİZİĞİ HAZIR. Eksen: -X İleri, +Z Sağ")
		
		# Havadaki Sürtünmeler (Sudan fırlarsa uzaya gitmesin)
		body.linear_damp = 0.5   
		body.angular_damp = 1.0  
		
		# Çarpışma Sinyalleri
		body.contact_monitor = true
		body.max_contacts_reported = 5
		if not body.body_entered.is_connected(_on_ship_collision):
			body.body_entered.connect(_on_ship_collision)

func _on_ship_collision(other_body):
	# Su objelerine çarpınca log basma
	var name_check = other_body.name.to_lower()
	if "water" in name_check or "sea" in name_check or "ocean" in name_check:
		return
	print("GEMİ ÇARPTI! -> ", other_body.name)

func _physics_process(delta):
	if not body: return
	
	var depth = water_height - body.global_position.y
	var forward_dir = -body.global_transform.basis.x  # İleri (-X)
	var right_dir = body.global_transform.basis.z     # Sağ (+Z)
	
	if depth > 0:
		#Kaldırma Kuvveti
		body.apply_central_force(Vector3.UP * buoyancy_force * depth)
		
		# Amortisör
		var vertical_speed = body.linear_velocity.y
		body.apply_central_force(Vector3.UP * -vertical_speed * bounce_damp * body.mass)
		
		#Yanlama
		var sideways_velocity = body.linear_velocity.dot(right_dir)
		body.apply_central_force(-right_dir * sideways_velocity * lateral_drag * body.mass)
		
		# Hacı Yatmaz
		var torque_dir = body.global_transform.basis.y.cross(Vector3.UP)
		var final_stability = (torque_dir * stability_force).limit_length(stability_force * 0.5)
		body.apply_torque(final_stability)
	# İleri İtiş
	if abs(ros_throttle) > 0.0001:
		# forward_dir yönüne itiyoruz
		body.apply_central_force(forward_dir * ros_throttle * engine_power)
		
	# Dönüş
	if abs(ros_steering) > 0.0001:
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)

	#Hız limiti
	if body.linear_velocity.length() > max_speed:
		var current_speed = body.linear_velocity.length()
		var excessive_speed = current_speed - max_speed
		# Limiti aşan miktar kadar ters kuvvet uygula 
		var brake_force = -body.linear_velocity.normalized() * excessive_speed * brake_power * body.mass
		body.apply_central_force(brake_force)
