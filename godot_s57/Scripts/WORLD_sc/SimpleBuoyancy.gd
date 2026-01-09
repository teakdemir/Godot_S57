extends Node

var body: RigidBody3D
var ros_throttle: float = 0.0
var ros_steering: float = 0.0	

# --- TEMEL AYARLAR ---
@export var water_height: float = 0.0
@export var buoyancy_force: float = 15000.0

# --- FİZİK KATSAYILARI ---
@export var bounce_damp: float = 2.0      # Dikey Zıplama Önleyici
@export var lateral_drag: float = 3.0     # Yan Kayma Direnci (Bunu biraz artırdım)
@export var water_drag: float = 1.0       # [YENİ] Genel Su Sürtünmesi (İleri/Geri direnci)
@export var angular_drag: float = 0.1     # [YENİ] Dönüş Sönümleme (0.0 - 1.0 arası)

@export var max_speed: float = 5.0        
@export var brake_power: float = 2.0      

# --- MOTOR ---
@export var stability_force: float = 2000.0   
@export var engine_power: float = 2000.0      # Direnç eklediğimiz için motoru güçlendirdim (Eski: 1000)
@export var turn_torque: float = 800.0        # Dönüş torkunu da artırdım (Eski: 500)

func _ready():
	if get_node(".") is RigidBody3D: body = get_node(".")
	elif get_parent() is RigidBody3D: body = get_parent()
	
	if body:
		body.continuous_cd = true
		print("🚢 GEMİ FİZİĞİ: BENDY RULER UYUMLU MOD.")
		
		body.linear_damp = 0.0   
		body.angular_damp = 0.0
		
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
	
	# Eksen Tanımları (-X İleri, +Z Sağ)
	var forward_dir = -body.global_transform.basis.x 
	var right_dir = body.global_transform.basis.z    
	
	if depth > 0:
		#KALDIRMA KUVVETİ
		body.apply_central_force(Vector3.UP * buoyancy_force * depth)
		
		#DİKEY AMORTİSÖR (Zıplama Önleyici)
		var vertical_speed = body.linear_velocity.y
		body.apply_central_force(Vector3.UP * -vertical_speed * bounce_damp * body.mass)
		
		# SU DİRENCİ & YANAL DİRENÇ
		var horizontal_velocity = body.linear_velocity * Vector3(1, 0, 1)
		
		#Su Sürtünmesi
		body.apply_central_force(-horizontal_velocity * water_drag * body.mass)
		
		#kaymasın
		var sideways_speed = body.linear_velocity.dot(right_dir)
		body.apply_central_force(-right_dir * sideways_speed * lateral_drag * body.mass)

		# Geminin fırıldak gibi dönmesini engeller.
		body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, angular_drag)

		#STABİLİTE
		var torque_dir = body.global_transform.basis.y.cross(Vector3.UP)
		var final_stability = (torque_dir * stability_force).limit_length(stability_force * 0.5)
		body.apply_torque(final_stability)

	# İleri İtiş
	if abs(ros_throttle) > 0.05:
		body.apply_central_force(forward_dir * ros_throttle * engine_power)

	# Dönüş
	if abs(ros_steering) > 0.05:
		body.apply_torque(Vector3.UP * ros_steering * turn_torque)

	#Hız limiti
	if body.linear_velocity.length() > max_speed:
		var current_speed = body.linear_velocity.length()
		var excessive_speed = current_speed - max_speed
		var brake_force = -body.linear_velocity.normalized() * excessive_speed * brake_power * body.mass
		body.apply_central_force(brake_force)
