extends RigidBody3D

var is_active: bool = false # Kamera o tuşu için

# --- MOTOR AYARLARI ---
@export var engine_power = 500.0
@export var turn_torque = 200.0

# --- ROS / OTONOM DEĞİŞKENLERİ ---
var autonomous_mode: bool = true
var ros_throttle: float = 0.0
var ros_steering: float = 0.0

func _physics_process(delta):
	var throttle_input = 0.0
	var steer_input = 0.0
	
	# --- KONTROL MANTIĞI ---
	if autonomous_mode:
		# ROS'tan gelen veriyi uygula
		throttle_input = ros_throttle
		steer_input = ros_steering
		
		# Acil durum: Space tuşuna basarsan manuele geç (sadece gemi aktifse)
		if is_active and Input.is_action_pressed("ui_accept"): 
			autonomous_mode = false
			print("⚠️ MANUEL KONTROL (WASD) DEVRALINDI!")
			
	else:
		# Manuel Mod (Sadece kamera bu gemideyse çalışsın)
		if is_active:
			throttle_input = Input.get_axis("ui_down", "ui_up")
			steer_input = Input.get_axis("ui_right", "ui_left")
			
			# 'R' tuşuna basınca tekrar Otonoma (ROS'a) dön
			if Input.is_key_pressed(KEY_R):
				autonomous_mode = true
				print("🤖 OTONOM MOD AKTİF")

	# --- FİZİK KUVVETLERİ ---

	if abs(throttle_input) > 0.01:
		# Geminin baktığı yöne (-basis.z) doğru it
		apply_central_force(-global_transform.basis.z * throttle_input * engine_power)
		
	if abs(steer_input) > 0.01:
		# Sağa/Sola döndürme torku uygula
		apply_torque(Vector3.UP * steer_input * turn_torque)
