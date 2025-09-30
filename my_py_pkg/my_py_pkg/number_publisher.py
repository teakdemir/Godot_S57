#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from example_interfaces.msg import Int64

class number_publisher(Node):

    def __init__(self):
        super().__init__("number_publisher")
        self.publisher_ = self.create_publisher(Int64, "number", 10)
        self.get_logger().info("Started")
        self.timer_ = self.create_timer(1.0, self.publish_num)
        
    def publish_num(self):
        msg = Int64()
        msg.data = 31
        self.publisher_.publish(msg)

def main(args=None):
    rclpy.init(args=args)
    node = number_publisher()
    rclpy.spin(node)
    rclpy.shutdown()

if __name__ == "__main__":
    main()
