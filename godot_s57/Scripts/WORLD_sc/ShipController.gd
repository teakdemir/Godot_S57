extends RigidBody3D

# --- MEVCUT AYARLARIN ---
@export var engine_power = 500.0
@export var turn_torque = 200.0

# --- OTONOM SÜRÜŞ DEĞİŞKENLERİ ---
var autonomous_mode: bool = true # Başlangıçta ROS kontrol etsin
var ros_throttle: float = 0.0    # -1.0 (Geri) ... 1.0 (İleri)
var ros_steering: float = 0.0    # -1.0 (Sağ) ... 1.0 (Sol)

func _physics_process(delta):
	var throttle_input = 0.0
	var steer_input = 0.0
	
	# --- MOD SEÇİMİ ---
	if autonomous_mode:
		# ROS'tan gelen emirleri uygula
		throttle_input = ros_throttle
		steer_input = ros_steering
		
		# Acil Durum: Space tuşuna basarsan kontrolü geri al
		if Input.is_action_pressed("ui_accept"): 
			autonomous_mode = false
			print("⚠️ MANUEL KONTROL (WASD) DEVRALINDI!")
	else:
		# Manuel Kontrol (WASD)
		throttle_input = Input.get_axis("ui_down", "ui_up")
		steer_input = Input.get_axis("ui_right", "ui_left")
		
		# Tekrar Otonoma geçmek için 'R' tuşu
		if Input.is_key_pressed(KEY_R):
			autonomous_mode = true
			print("🤖 OTONOM MOD AKTİF (ROS Kontrolünde)")

	# --- FİZİK UYGULAMA ---
	if abs(throttle_input) > 0.01:
		# NOT: Modelin yönüne göre -basis.z veya basis.z olabilir. Ters giderse eksiyi sil.
		apply_central_force(-basis.z * throttle_input * engine_power)
		
	if abs(steer_input) > 0.01:
		apply_torque(Vector3.UP * steer_input * turn_torque)
