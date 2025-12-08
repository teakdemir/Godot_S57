import os
import xacro
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, ExecuteProcess
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import Node
from launch.substitutions import LaunchConfiguration
from ament_index_python.packages import get_package_share_directory

def generate_launch_description():

    robotXacroName = 'ship'
    namePackage ='ship_description'
    modelFileRelativePath = 'models/robot.xacro'
    worldFileRelativePath = 'worlds/wall.world'
    ekfFileRelativePath = 'config/ekf.yaml'
    use_sim_time = LaunchConfiguration('use_sim_time', default='true')
    rvizConfig = LaunchConfiguration('rvizconfig')

    pathModelFile = os.path.join(get_package_share_directory(namePackage), modelFileRelativePath)
    pathWorldFile = os.path.join(get_package_share_directory(namePackage), worldFileRelativePath)
    pathEkfFile = os.path.join(get_package_share_directory(namePackage), ekfFileRelativePath)
    robotDescription = xacro.process_file(pathModelFile).toxml()

    gazeboLaunch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(get_package_share_directory('gazebo_ros'),'launch', 'gazebo.launch.py')
            ), 
            launch_arguments={'world': pathWorldFile}.items()
            )

    spawnModelNode = Node(
        package='gazebo_ros',
        executable='spawn_entity.py',
        arguments=[
            '-topic', 'robot_description',
            '-entity', robotXacroName
        ],
        output='screen'
    )
      
    #Robot State Publisher
        #Reads the URDF
        #Calculates the TF chain of all the links and joints
        #Publishes that via ROS2 TF2 system

    robot_state_publisher = Node(
        package='robot_state_publisher',      # Hangi paketi çalıştıracağını söylüyor
        executable='robot_state_publisher',  # Hangi executable dosyası çalışacak
        name='robot_state_publisher',        # Node’un ROS 2 ismi
        output='screen',                      # Logları terminale yaz
        parameters=[{'robot_description': robotDescription,
            'use_sim_time': use_sim_time}]
    )

    robot_localization_node = Node(
        package='robot_localization', #ROS'un hazır paketi
        executable='ekf_node', #Hazır node
        name='ekf_node',
        output='screen',
        parameters=[pathEkfFile, {'use_sim_time': use_sim_time}]
)

    rviz_node = Node(
        package='rviz2',
        executable='rviz2',
        name='rviz2',
        output='screen',
        arguments=['-d', rvizConfig],
    )

    ld = LaunchDescription([
        DeclareLaunchArgument(
            'rvizconfig',
            default_value=os.path.join(get_package_share_directory(namePackage), 'rviz/ship.rviz'),
            description='Absolute path to rviz config file'
        )
    ])

    ld.add_action(gazeboLaunch)
    ld.add_action(spawnModelNode )
    ld.add_action(robot_state_publisher)
    ld.add_action(robot_localization_node)
    ld.add_action(rviz_node)
    return ld