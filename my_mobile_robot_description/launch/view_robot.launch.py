from launch import LaunchDescription #ROS 2'de bir launch dosyası tanımlamak için gereken temel sınıf.
from launch_ros.actions import Node #Belirli bir ROS 2 paketinin içindeki paylaşılan dizini bulur.
from ament_index_python.packages import get_package_share_directory
from launch.substitutions import Command
import os

def generate_launch_description(): #Bu fonksiyon, ROS 2'nin çağırdığı fonksiyondur. İçinde başlatılacak tüm node'lar tanımlanır.
    robot_desc_path = os.path.join( #robot_desc_path değişkeni, Xacro dosyasının tam yolunu tutar.
        get_package_share_directory('my_mobile_robot_description'), 
        'urdf',
        'robot.urdf.xacro'
    )

    return LaunchDescription([  #ROS 2’ye bu node’ları başlatmasını söyleyen tanım bloğu.
        Node( #Xacro/URDF modelinden joint state’leri okuyup tf transformasyonları üretir. (örneğin base_link → lidar_link)
            package = 'robot_state_publisher',
            executable='robot_state_publisher',
            name = 'robot_state_publisher',
            parameters=[{'robot_description': Command(['xacro ', robot_desc_path])}]  
        ),

        Node(
            package='joint_state_publisher',
            executable='joint_state_publisher',
            name='joint_state_publisher'
        ),


        Node(   #RViz2 uygulamasını başlatır
            package='rviz2',
            executable='rviz2', 
            name='rviz2',
            arguments=['-d', os.path.join(
                get_package_share_directory('my_mobile_robot_description'),
                'rviz', 'view_config.rviz'
            )]
        )
    ])