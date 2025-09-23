# res://scripts/WORLD_sc/CameraController.gd
class_name CameraController
extends Node

@export var camera: Camera3D
@export var move_speed: float = 100.0
@export var mouse_sensitivity: float = 2.0
@export var zoom_speed: float = 20.0

var is_mouse_captured: bool = false

func _ready():
	if not camera:
		print("Warning: No camera assigned to CameraController")

func _input(event):
	# Right click to capture/release mouse
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			is_mouse_captured = !is_mouse_captured
			if is_mouse_captured:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Mouse scroll for altitude
	if Input.is_action_just_pressed("move_up"):
		camera.position.y += zoom_speed
	elif Input.is_action_just_pressed("move_down"):
		camera.position.y -= zoom_speed
		camera.position.y = max(camera.position.y, 5.0)
	
	# Mouse look (when captured)
	if event is InputEventMouseMotion and is_mouse_captured:
		camera.rotation_degrees.y -= event.relative.x * mouse_sensitivity * 0.1
		camera.rotation_degrees.x -= event.relative.y * mouse_sensitivity * 0.1
		camera.rotation_degrees.x = clamp(camera.rotation_degrees.x, -80, 80)

func _physics_process(delta):
	if not camera:
		return
	
	var input_vector = Vector2()
	
	# WASD movement using input map
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1
	if Input.is_action_pressed("move_forward"):
		input_vector.y -= 1
	if Input.is_action_pressed("move_back"):
		input_vector.y += 1
	
	# Fast movement with Shift
	var current_speed = move_speed
	if Input.is_action_pressed("move_fast"):
		current_speed *= 3.0
	
	# Move relative to camera's rotation
	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()
		
		var forward = -camera.transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		
		var right = camera.transform.basis.x
		right.y = 0
		right = right.normalized()
		
		var movement = (right * input_vector.x + forward * input_vector.y) * current_speed * delta
		camera.position += movement
