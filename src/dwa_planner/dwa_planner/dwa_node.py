import rclpy
import math 
import random
from rclpy.node import Node
from geometry_msgs.msg import Twist, Point #Twist → Hız komutu (cmd_vel) mesajı: linear.x ve angular.z içerir.
from nav_msgs.msg import Odometry
from sensor_msgs.msg import LaserScan
from visualization_msgs.msg import Marker
from tf_transformations import euler_from_quaternion #IMU/odom oryantasyonunu Euler açılarına (yaw, pitch, roll) çevirir.

#NOT!!!!!!
#    ✔ Doğru model:

#       Infinite_path_generator → sadece yol üretir

#       Collision_checker → bu yol güvenli mi bakar

#       Choose_best_path → en iyi yolu seçer

#       Bu mimari DWA’nın orijinal tasarımıdır. 

#NOT2!!!!!
#       “LIDAR 360°’yi tarar, tarama bittikten sonra bize tek mesaj olarak verir.”

#State Info
goal_x = None #Target coordinates 
goal_y = None

odom_data = None
scan_data = None

goal_reached = False    #Default olarak false döndürür.

robot_length = 1.0
robot_width = 0.6
padding = 0.5


def goal_input():   
    global goal_x, goal_y, goal_reached #Globalde tanımlanan bu değişkenler burada değer alır.
    goal_x = float(input("X = "))
    goal_y = float(input("Y = "))
    goal_reached = False

#callbacks
def odom_callback(msg): #Yeni odom verisi geldiğinde eskisiyle değiştirir.
    global odom_data    
    odom_data = msg    

def scan_callback(msg): #Yeni scan verisi geldiğinde eskisiyle değiştirir.
    global scan_data
    scan_data = msg    


def get_robot_pose(): #Robotun anlık pozisyonunu ve yönelimini döndürür.
    if odom_data is None:
        return None, None, None
    
    x = odom_data.pose.pose.position.x
    y = odom_data.pose.pose.position.y

    orient = odom_data.pose.pose.orientation
    _,_, yaw = euler_from_quaternion([orient.x, orient.y, orient.z, orient.w])

    return x, y, yaw

def get_global_obstacles():
    global scan_data

    if scan_data is None:
        return []

    current_x, current_y, current_yaw = get_robot_pose()

    if current_x is None:
        return []
    
    obstacles = []
    for angle_index, r in enumerate(scan_data.ranges):
        if r == float('inf') or r >= scan_data.range_max:
            continue

        angle = scan_data.angle_min + angle_index * scan_data.angle_increment
        global_angle = current_yaw + angle

        obstacle_x = current_x + r * math.cos(global_angle)
        obstacle_y = current_y + r * math.sin(global_angle)

        obstacles.append((obstacle_x, obstacle_y))
    
    return obstacles

def footprint_collision_checker(path, obstacles):
    half_length = robot_length / 2 + padding
    half_width = robot_width / 2 + padding

    for (px, py, pyaw) in path:

        cos_y = math.cos(pyaw)
        sin_y = math.sin(pyaw)

        for (obstacle_x, obstacle_y) in obstacles:

            delta_x = obstacle_x - px
            delta_y = obstacle_y - py

            local_x = delta_x * cos_y + delta_y * sin_y
            local_y = -delta_x * sin_y + delta_y * cos_y

            if (-half_length <= local_x <= half_length and
                -half_width  <= local_y <= half_width):
                return False   # Çarpışma VAR

    # Hiçbir çarpışma olmadı → güvenli path
    return True

def infinite_path_generator(max_speed, max_turn, step_time, get_robot_pose):
    global goal_x, goal_y

    prediction_horizon = 20   
    steps = int(prediction_horizon / step_time) 

    while True:
        x, y, yaw = get_robot_pose()

        if x is None or y is None or yaw is None:
            yield 0.0, 0.0, [], 0.0
            continue
        
        angle_to_goal = math.atan2(goal_y - y, goal_x - x)

        angle_diff = angle_to_goal - yaw
        angle_diff = math.atan2(math.sin(angle_diff), math.cos(angle_diff))

        target_turn = angle_diff * 1.0
        random_turn = random.uniform(-max_turn * 0.3, max_turn * 0.3)
        turn_rate = target_turn + random_turn

        r = random.random() # 0 ile 1 arasında rastgele sayı üretir.

        if r < 0.5: #random
            speed = random.uniform(0, max_speed)
            turn_rate = random.uniform(-max_turn, max_turn)

        elif r < 0.8: #target oriented
            speed = max_speed
            turn_rate = max(-max_turn, min(max_turn, angle_diff))
            turn_rate += random.uniform(-0.2, 0.2)
        
        else: #straight
            speed = max_speed
            turn_rate = random.uniform(-0.05, 0.05)

        predicted_path = []
        cx, cy, cyaw = x, y, yaw

        for _ in range(1, steps):
            cyaw += turn_rate * step_time
            cyaw = (cyaw + math.pi) % (2 * math.pi) - math.pi

            cx += speed * math.cos(cyaw) * step_time
            cy += speed * math.sin(cyaw) * step_time

            predicted_path.append((cx, cy, cyaw))

        
        yield  speed, turn_rate, predicted_path, cyaw    #Fonksiyon her yield ile durur, sonra ihtiyaç olunca kaldığı yerden devam eder. Return'den farklıdır.

def choose_best_path(node, possible_paths, get_robot_pose, global_obstacles): 
    global goal_x, goal_y, goal_reached, scan_data

    x, y, yaw = get_robot_pose()

    if x is None or y is None or yaw is None:
        return 0.0, 0.0, []
    
    distance_to_goal = math.hypot(goal_x - x, goal_y - y)

    if distance_to_goal < 0.1:
        if not goal_reached:
            goal_reached = True
            node.get_logger().info(f"Goal reached at ({goal_x}, {goal_y}).")
        return 0.0, 0.0, [], yaw
    
    best_score = float('-inf')
    best_speed, best_turn = 0.0, 0.0
    best_path = []
    best_end_yaw = 0.0

    for speed, turn, path, end_yaw in possible_paths:

        #----Collision Score----
        if not footprint_collision_checker(path,global_obstacles):
            continue

        #----Goal Distance Score----
        end_x, end_y, _ = path[-1]
        goal_dist_score = -math.hypot(goal_x - end_x, goal_y - end_y)

        #----Heading Score----        
        angle_to_goal = math.atan2(goal_y - y, goal_x - x)

        angle_diff = angle_to_goal - end_yaw
        angle_diff = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
        heading_score = -abs(angle_diff) 

        #----Smoothness Score----
        smoothness_score = -abs(turn) 

        #----Clearance Score----
        min_obstacle_distance = float('inf')

        for path_x, path_y, _ in path:
            for obstacle_x, obstacle_y in global_obstacles:

                distance = math.hypot(obstacle_x - path_x, obstacle_y - path_y)

                if distance < min_obstacle_distance:
                    min_obstacle_distance = distance

        if min_obstacle_distance < 0.45:
            clearance_score = -10.0    
        elif min_obstacle_distance < 0.8:
            clearance_score = (min_obstacle_distance - 0.45) * 2.0
        else:
            clearance_score = 1.5

        #----Velocity Score----
        MAX_SPEED = 0.15
        velocity_score = speed / MAX_SPEED

        total_score = (goal_dist_score * 5.0) + (heading_score * 1.5) + (smoothness_score * 1.0) + (clearance_score * 3.0) + (velocity_score * 3.0)

        if total_score > best_score:
            best_score = total_score
            best_speed, best_turn, best_path, best_end_yaw= speed, turn, path, end_yaw

    #Wall Following / Bug Algorithm)
    #Robot duvarla karşılaştığında (Local Minima), gerçek hedefi (Goal) görmezden geliriz. Bunun yerine, duvarın bittiği yönde (veya en boş alanda) sanal bir hedef (subgoal) belirleriz. DWA, bu sanal hedefe gitmek için duvarın kenarından sürer.
    if best_score == float('-inf'):
        node.get_logger().warn("Local Minima! No valid path. Switching to Recovery Planner.")
        
        return 0.0, 0.0, [], yaw
    return best_speed, best_turn, best_path, best_end_yaw
       
def movement_loop(node, cmd_publisher, path_publisher, max_speed, max_turn, step_time):
    #her movement_loop döngüsünde yalnızca tek bir LaserScan mesajından gelen veri (scan_data) kullanılır.
    global goal_reached, escape_turn, in_escape, last_escape_turn
    
    if odom_data is None or scan_data is None or goal_reached:
        return
    
    global_obstacles = get_global_obstacles()

    path_generator = infinite_path_generator(max_speed, max_turn, step_time, get_robot_pose)
    
    possible_paths = [next(path_generator) for _ in range(400)]

    best_speed, best_turn, best_path , _ = choose_best_path(node, possible_paths, get_robot_pose, global_obstacles)

    cmd = Twist()
    cmd.linear.x = best_speed
    cmd.angular.z = best_turn
    cmd_publisher.publish(cmd)

    marker = Marker()
    marker.header.frame_id = "odom"
    marker.type = Marker.LINE_STRIP
    marker.action = Marker.ADD
    marker.scale.x = 0.03
    marker.color.r = 1.0
    marker.color.a = 1.0

    for px, py, _ in best_path:
        p = Point()
        p.x = px
        p.y = py
        marker.points.append(p)

    path_publisher.publish(marker)

def main():
    rclpy.init()
    node = Node('dwa_planner')

    goal_input()

    node.create_subscription(Odometry, '/odom', odom_callback, 10) #Odometry mesaj tipinde /odom topic'i dinlenecek. Her veri geldiğinde call_back çağrılacak.
    node.create_subscription(LaserScan, '/scan', scan_callback, 10) #LaserScan mesaj tipinde /scan topic'i dinlenecek. Her veri geldiğinde call_back çağrılacak.
    
    cmd_publisher = node.create_publisher(Twist, '/cmd_vel', 10)  #Twist mesaj tipinde /cmd_vel topic'ine veri gönderilecek.
    path_publisher = node.create_publisher(Marker, '/visual_paths', 10) #Marker mesaj tipinde /visual_paths topic'ine veri gönderilecek.

    max_speed = 0.15 
    max_turn = 0.8
    step_time = 0.1
    
    node.create_timer(step_time, lambda: movement_loop(node, cmd_publisher, path_publisher, max_speed, max_turn, step_time)) 
    #Her 0.1 saniyede:

        #movement_loop çağrılır

        #Robotun mevcut odom ve scan verileri alınır

        #DWA hesaplaması yapılır

        #En iyi hız ve dönüş seçilir

        #/cmd_vel ve /visual_paths güncellenir

    rclpy.spin(node) 

    node.destroy_node() 
    
    rclpy.shutdown() 
    
if __name__ == '__main__': 
  main()