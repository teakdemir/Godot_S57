extends Node

var body: RigidBody3D

@export var water_height: float = 0.0
@export var buoyancy_force: float = 1000.0  # Varsayılanı 10.000 yaptık
@export var water_drag: float = 1
@export var water_angular_drag: float = 0.5


func _ready():
	# RigidBody'yi bul
	if get_node(".") is RigidBody3D:
		body = get_node(".")
	elif get_parent() is RigidBody3D:
		body = get_parent()
	
	if body:
		print("--- BUOYANCY BAŞLADI ---")
		print("Gemi Kütlesi (Mass): ", body.mass, " kg")
		print("Gemi Ağırlığı (Gravity): ", body.mass * 9.8, " Newton")
		print("Kaldırma Çarpanı: ", buoyancy_force)
		print("------------------------")
	else:
		printerr("HATA: RigidBody bulunamadı!")

func _physics_process(_delta):
	if not body: return

	# Geminin merkez noktasının yüksekliği
	var height = body.global_position.y
	var depth = water_height - height
	
	# Sadece suyun altındaysa kuvvet uygula
	if depth > 0:
		var lift_force = Vector3.UP * buoyancy_force * depth
		
		body.apply_central_force(lift_force)
		
		# Sürtünme
		body.linear_velocity *= (1.0 - water_drag)
		body.angular_velocity *= (1.0 - water_angular_drag)
		
		# --- DEBUG: Her 60 frame'de bir (yaklaşık 1 sn) durum raporu ver ---
		if Engine.get_physics_frames() % 60 == 0:
			print("Durum: SU ALTINDA | Derinlik: %.2f m | Uygulanan Kaldırma: %.2f N | Batan Ağırlık: %.2f N" % [depth, lift_force.y, body.mass * 9.8])
	
	# Su üstündeyse sadece debug yaz
	elif Engine.get_physics_frames() % 60 == 0:
		# print("Durum: SU ÜSTÜNDE | Yükseklik: %.2f m" % height)
		pass
