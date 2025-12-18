extends Node

@onready var body: RigidBody3D = get_parent()

# hız ayar
@export var engine_power: float = 800.0

# keskin dönsün istersen bu sayıyı yükselt
@export var turn_torque: float = 3000.0

@export var is_active: bool = false

func _physics_process(delta):
	if not is_active or not body: return
	
	# Gemi modelin yan durduğu için X eksenini ileri kabul ediyoruz.
	var forward_dir = -body.global_transform.basis.x
	
	# --- MOTOR ---
	if Input.is_key_pressed(KEY_W):
		body.apply_central_force(forward_dir * engine_power)
		
	if Input.is_key_pressed(KEY_S):
		# Geri vites biraz daha yavaş olsun (Yarısı kadar)
		body.apply_central_force(-forward_dir * (engine_power * 0.5))

	# dümen
	if Input.is_key_pressed(KEY_A):
		body.apply_torque(Vector3.UP * turn_torque)
		
	if Input.is_key_pressed(KEY_D):
		body.apply_torque(Vector3.UP * -turn_torque)
