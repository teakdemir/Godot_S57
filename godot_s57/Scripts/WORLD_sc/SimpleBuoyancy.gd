extends Node

var body: RigidBody3D

@export var water_height: float = 0.0
@export var buoyancy_force: float = 1000.0
@export var water_drag: float = 0.1
@export var water_angular_drag: float = 0.5

#hcıyatmaz
@export var stability_force: float = 8000.0 

func _ready():
	if get_node(".") is RigidBody3D:
		body = get_node(".")
	elif get_parent() is RigidBody3D:
		body = get_parent()
	
	if body:
	
		# Gemi hızlıysa duvarın içinden ışınlanmasını engeller
		body.continuous_cd = true 
		print("BUOYANCY: Gemi bulundu. CCD ve Stabilite aktif.")

func _physics_process(_delta):
	if not body: return

	var depth = water_height - body.global_position.y
	
	if depth > 0:
		# Kaldırma
		var lift_force = Vector3.UP * buoyancy_force * depth
		body.apply_central_force(lift_force)
		
		# Sürtünme
		body.linear_velocity *= (1.0 - water_drag)
		body.angular_velocity *= (1.0 - water_angular_drag)
		
		# Gemiyi dik tutmaya çalışır
		var current_up = body.global_transform.basis.y
		var target_up = Vector3.UP
		var torque_dir = current_up.cross(target_up)
		body.apply_torque(torque_dir * stability_force)
