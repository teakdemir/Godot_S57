extends Node

var body: RigidBody3D
var ros_throttle: float = 0.0
var ros_steering: float = 0.0	

#TEMEL AYARLAR
@export var water_height: float = 0.0
@export var buoyancy_force: float = 15000.0

#FİZİK KATSAYILARI
@export var bounce_damp: float = 2.0      # Zıplama Önleyici Sertliği
@export var lateral_drag: float = 4.0     
@export var water_drag: float = 1.0       # Genel Su Sürtünmesi
@export var idle_drag: float = 2.0        # Gaz kesildiğinde ekstra frenleme
@export var angular_drag: float = 0.1 
@export var brake_power: float = 2.0      # Hız Limiti Frenleme Gücü
@export var max_speed: float = 5.0        # Maksimum Hız (m/s)

#MOTOR VE DÜMEN
@export var stability_force: float = 2000.0   # Hacıyatmaz 
@export var engine_power: float = 2000.0      # Motor İtiş Gücü
@export var turn_torque: float = 1200.0       # Dönüş Torku 

func _ready():
	# RigidBody'yi bul 
	if get_node(".") is RigidBody3D: body = get_node(".")
	elif get_parent() is RigidBody3D: body = get_parent()
	
	if body:
		body.continuous_cd = true
		print("🚢 GEMİ FİZİĞİ: SAKİN SÜRÜŞ MODU.")
		
		# Havadaki Sürtünmeler (Sudan fırlarsa uzaya gitmesin)
		body.linear_damp = 0.0   
		body.angular_damp = 0.0  
		
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
		
		#Yanlama ve Genel Su Direnci
		var horizontal_velocity = body.linear_velocity * Vector3(1, 0, 1)
		body.apply_central_force(-horizontal_velocity * water_drag * body.mass)
		
		var sideways_velocity = body.linear_velocity.dot(right_dir)
		body.apply_central_force(-right_dir * sideways_velocity * lateral_drag * body.mass)

		# Hacı Yatmaz
		var torque_dir = body.global_transform.basis.y.cross(Vector3.UP)
		var final_stability = (torque_dir * stability_force).limit_length(stability_force * 0.5)
		body.apply_torque(final_stability)

	# --- İLERİ HAREKET VE FRENLEME ---
	if abs(ros_throttle) > 0.05:
		# Gaz veriliyorsa ileri it
		body.apply_central_force(forward_dir * ros_throttle * engine_power)
	else:
		# GAZ KESİLDİ
		var horizontal_velocity = body.linear_velocity * Vector3(1, 0, 1)
		if horizontal_velocity.length() > 0.1:
			# Ekstra sürtünme uygula (Motor kompresyonu gibi)
			body.apply_central_force(-horizontal_velocity * idle_drag * body.mass)
			
			# Hız çok düşükse tamamen durdur (Kaymayı bitir)
			if horizontal_velocity.length() < 0.5:
				body.linear_velocity.x = move_toward(body.linear_velocity.x, 0, 0.1)
				body.linear_velocity.z = move_toward(body.linear_velocity.z, 0, 0.1)

	# --- AKILLI DÖNÜŞ SİSTEMİ (REVIZE EDILDI) ---
	if abs(ros_steering) > 0.1:
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)
		# Dönerken DAHA FAZLA sönümleme (0.05 -> 0.20)
		# Bu, geminin aşırı hızla dönmesini ve savrulmasını engeller.
		body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, 0.20)
	else:
		# Dümen bırakıldı, dönmeyi ZORLA durdur
		var current_rot_speed = body.angular_velocity.y
		if abs(current_rot_speed) > 0.01:
			var counter_torque = -current_rot_speed * turn_torque * 2.0 
			body.apply_torque(Vector3.UP * counter_torque)
			body.angular_velocity.y = lerp(body.angular_velocity.y, 0.0, 0.2)

	#Hız limiti
	if body.linear_velocity.length() > max_speed:
		var current_speed = body.linear_velocity.length()
		var excessive_speed = current_speed - max_speed
		# Limiti aşan miktar kadar ters kuvvet uygula 
		var brake_force = -body.linear_velocity.normalized() * excessive_speed * brake_power * body.mass
		body.apply_central_force(brake_force)
