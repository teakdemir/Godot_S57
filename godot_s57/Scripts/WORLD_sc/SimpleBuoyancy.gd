extends Node

var body: RigidBody3D
var ros_throttle: float = 0.0
var ros_steering: float = 0.0	

# --- TEMEL AYARLAR ---
@export var water_height: float = 0.0
@export var buoyancy_force: float = 15000.0 # Kaldırma Kuvveti 

#bounce_damp = 2.0 ise, 1000kg gemiye 2000, 10kg gemiye 20 direnç uygular.

@export var bounce_damp: float = 2.0      # Dikey Sönümleme (Amortisör Sertliği)
@export var lateral_drag: float = 2.0     # Yan Kayma Direnci (Drift Önleyici)
@export var brake_power: float = 2.0      # Hız Limiti Frenleme Gücü

@export var max_speed: float = 5.0        # Maksimum Hız Limiti

# --- MOTOR VE DÜMEN ---
@export var stability_force: float = 2000.0   # Hacıyatmaz (Tork)
@export var engine_power: float = 1000.0      # Motor Gücü
@export var turn_torque: float = 500.0        # Dönüş Torku

func _ready():
	# Parent veya Self kontrolü
	if get_node(".") is RigidBody3D: body = get_node(".")
	elif get_parent() is RigidBody3D: body = get_parent()
	
	if body:
		body.continuous_cd = true
		print("🚢 GEMİ FİZİĞİ HAZIR. Mod: PRO PHYSICS (Mass-Scaled)")
		
		# Gemi sudan tamamen çıkarsa (zıplarsa) uzaya gitmesin diye
		body.linear_damp = 0.5   # Havadaki direnç
		body.angular_damp = 1.0  # Havadaki dönüş direnci
		
		# Çarpışma Ayarları
		body.contact_monitor = true
		body.max_contacts_reported = 5
		if not body.body_entered.is_connected(_on_ship_collision):
			body.body_entered.connect(_on_ship_collision)

func _on_ship_collision(other_body):
	var name_check = other_body.name.to_lower()
	if "water" in name_check or "sea" in name_check or "ocean" in name_check:
		return
	print("💥 GEMİ ÇARPTI! -> ", other_body.name)

func _physics_process(delta):
	if not body: return
	
	var depth = water_height - body.global_position.y

	if depth > 0:
		#KALDIRMA KUVVETİ
		body.apply_central_force(Vector3.UP * buoyancy_force * depth)
		
		#AMORTİSÖR
		# Formül: Hız * Katsayı * Kütle
		var vertical_speed = body.linear_velocity.y
		body.apply_central_force(Vector3.UP * -vertical_speed * bounce_damp * body.mass)
		
		#Yanlama
		var right_dir = body.global_transform.basis.x
		var sideways_velocity = body.linear_velocity.dot(right_dir)
		body.apply_central_force(-right_dir * sideways_velocity * lateral_drag * body.mass)
		
		#hacıyatmaz
		var torque_dir = body.global_transform.basis.y.cross(Vector3.UP)
		var final_stability = (torque_dir * stability_force).limit_length(stability_force * 0.5)
		body.apply_torque(final_stability)

	#İLERİ İTİŞ 
	if abs(ros_throttle) > 0.0001:
		body.apply_central_force(-body.global_transform.basis.z * ros_throttle * engine_power)
		
	#DÖNÜŞ
	if abs(ros_steering) > 0.0001:
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)

	#HIZ LİMİTİ (YUMUŞAK FREN) - MASS SCALED
	if body.linear_velocity.length() > max_speed:
		var current_speed = body.linear_velocity.length()
		var excessive_speed = current_speed - max_speed

		var brake_force = -body.linear_velocity.normalized() * excessive_speed * brake_power * body.mass
		body.apply_central_force(brake_force)
