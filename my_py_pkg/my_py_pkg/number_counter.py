#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from example_interfaces.msg import Int64

class number_counter(Node):

    def __init__(self):
        super().__init__("number_counter")
        self.counter_ = 0
        self.subscriber_ = self.create_subscription(Int64, "number", self.callback_number, 10)

        self.publisher_ = self.create_publisher(Int64, "number_count", 10)
        self.timer_ = self.create_timer(1.0, self.publish_count)
        self.get_logger().info("Started")
    
    def callback_number(self, msg: Int64):
        self.counter_ += 1

    def publish_count(self):
        msg1 = Int64()
        msg1.data = self.counter_
        self.publisher_.publish(msg1)

def main(args=None):
    rclpy.init(args=args)
    node = number_counter()
    rclpy.spin(node)
    rclpy.shutdown()

if __name__ == "__main__":
    main()
