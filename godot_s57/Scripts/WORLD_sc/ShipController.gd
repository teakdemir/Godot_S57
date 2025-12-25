extends RigidBody3D

# --- MOTOR AYARLARI ---
@export var engine_power = 50000.0 # Gemiyi itmek için gereken güç (Ağırlığa göre artır)
@export var turn_torque = 20000.0  # Dönüş torku

# --- ROS KONTROL DEĞİŞKENLERİ ---
# Bu değişkenleri RosManager sürekli güncelleyecek
var ros_throttle: float = 0.0
var ros_steering: float = 0.0

func _physics_process(delta):
	# ROS'tan gelen değerler zaten -1.0 ile 1.0 arasında geliyor.
	# Direkt motor gücüyle çarpıp uyguluyoruz.
	
	# 1. İleri/Geri Hareketi
	if abs(ros_throttle) > 0.01:
		# Geminin baktığı yöne (-basis.z) kuvvet uygula
		apply_central_force(-global_transform.basis.z * ros_throttle * engine_power)
		
	# 2. Dönüş Hareketi
	if abs(ros_steering) > 0.01:
		# Y ekseni etrafında tork uygula
		apply_torque(Vector3.UP * ros_steering * turn_torque)

	# Not: Eğer gemi sonsuza kadar kayıyorsa Inspector'dan 
	# Linear Damping ve Angular Damping değerlerini artır (örn: 1.0 veya 2.0 yap).
