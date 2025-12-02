extends Node

@onready var body: RigidBody3D = get_parent()

# --- HIZ VE DÖNÜŞ AYARLARI ---
# W-S Hızı: 2000'den 800'e indirdik (Daha yavaş gitsin)
@export var engine_power: float = 800.0

# A-D Dönüşü: 500'den 3000'e çıkardık (Daha keskin dönsün)
@export var turn_torque: float = 3000.0

@export var is_active: bool = false

func _physics_process(delta):
	if not is_active or not body: return
	
	# YÖN DÜZELTMESİ (X EKSENİ KORUNDU)
	# Gemi modelin yan durduğu için X eksenini ileri kabul ediyoruz.
	var forward_dir = -body.global_transform.basis.x
	
	# --- MOTOR ---
	if Input.is_key_pressed(KEY_W):
		body.apply_central_force(forward_dir * engine_power)
		
	if Input.is_key_pressed(KEY_S):
		# Geri vites biraz daha yavaş olsun (Yarısı kadar)
		body.apply_central_force(-forward_dir * (engine_power * 0.5))

	# --- DÜMEN ---
	if Input.is_key_pressed(KEY_A):
		body.apply_torque(Vector3.UP * turn_torque)
		
	if Input.is_key_pressed(KEY_D):
		body.apply_torque(Vector3.UP * -turn_torque)
