class_name FreeCamera
extends Camera3D

@export var move_speed: float = 20.0
@export var vertical_speed: float = 12.0
@export var fast_multiplier: float = 2.0
@export var mouse_sensitivity: float = 0.15

var _yaw: float = 0.0
var _pitch: float = -45.0
var _target_center: Vector3 = Vector3.ZERO
var _target_distance: float = 60.0

func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    rotation_degrees = Vector3(_pitch, _yaw, 0.0)
    position = Vector3(0.0, _target_distance, _target_distance)

func snap_to(center: Vector3, distance: float) -> void:
    _target_center = center
    _target_distance = distance
    position = center + Vector3(0.0, distance, distance)
    look_at(center, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        _yaw -= event.relative.x * mouse_sensitivity
        _pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -89.0, 89.0)
        rotation_degrees = Vector3(_pitch, _yaw, 0.0)

    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    elif event.is_action_pressed("mouse_capture"):
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
    var direction := Vector3.ZERO
    if Input.is_action_pressed("move_forward"):
        direction -= transform.basis.z
    if Input.is_action_pressed("move_back"):
        direction += transform.basis.z
    if Input.is_action_pressed("move_left"):
        direction -= transform.basis.x
    if Input.is_action_pressed("move_right"):
        direction += transform.basis.x

    var translation := Vector3.ZERO
    if direction != Vector3.ZERO:
        var speed: float = move_speed
        if Input.is_action_pressed("move_fast"):
            speed *= fast_multiplier
        translation += direction.normalized() * speed * delta

    var vertical := 0.0
    if Input.is_action_pressed("move_up"):
        vertical += 1.0
    if Input.is_action_pressed("move_down"):
        vertical -= 1.0
    if vertical != 0.0:
        var v_speed: float = vertical_speed
        if Input.is_action_pressed("move_fast"):
            v_speed *= fast_multiplier
        translation += Vector3.UP * vertical * v_speed * delta

    if translation != Vector3.ZERO:
        translate(translation)
