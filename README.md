# ORHUN: Autonomous Marine Simulation Platform 🚢

**ORHUN** is a high-fidelity simulation environment and validation platform designed for Unmanned Surface Vehicles (USVs). It bridges the gap between static navigational data and dynamic robotics by integrating **Real-world S-57 Electronic Navigational Charts (ENC)** with the **Godot Engine** and **ROS 2**.

The project aims to provide a risk-free, cost-effective "Digital Twin" environment to benchmark path planning, obstacle avoidance, and autonomous navigation algorithms before physical sea trials.

---

## 🎥 Preview & Demo

[![ORHUN Demo](https://img.youtube.com/vi/KFsBebyY78U/0.jpg)](https://www.youtube.com/watch?v=KFsBebyY78U)

---

## 🚀 Key Features

* **Real-World Map Integration:** Automatic generation of 3D marine environments using parsed S-57 Electronic Navigational Charts.
* **High-Fidelity Physics:** Custom-built buoyancy, hydrodynamics, and water resistance physics tailored for USV dynamics in Godot Engine 4.
* **ROS 2 Integration:** Full compatibility with Robot Operating System (ROS 2) and Nav2 Stack for autonomous navigation.
* **Sensor Simulation:** Real-time simulation of Lidar (RayCast3D), Depth Cameras, and IMU data sent to ROS 2 via WebSockets.
* **Dual Operation Modes:**
    * **Autonomous Mode:** Controlled by ROS 2 algorithms (Bendy Ruler, etc.).
    * **Cinematic/Manual Mode:** WASD keyboard control with smoothed physics for testing and video demonstrations.

---

## 🛠️ Methods & Technologies

The project utilizes a modern tech stack divided into Server (Data) and Client (Simulation) components.

### 🔹 ORHUN Server (Backend & Data)
* **Python 3.x & FastAPI:** High-performance REST API.
* **PostgreSQL & PostGIS:** Spatial database for managing complex S-57 map data.
* **GDAL/OGR:** Library used for parsing and analyzing raw Electronic Navigational Charts (ENC).
* **Docker:** Containerization of database and backend services.

### 🔹 ORHUN Client (Simulation & Control)
* **Godot Engine 4:** Primary simulation environment and 3D visualization.
* **ROS 2 (Robot Operating System):** Middleware for robotics control and state estimation.
* **WebSockets:** Real-time communication bridge between Godot physics and ROS 2 nodes.
* **Gazebo & RViz2:** Used for sensor fusion debugging and algorithm validation.

---

## 🏗️ Architecture Overview

1.  **Map Generation:** The Server parses S-57 files, stores geospatial data in PostGIS, and serves it to the Client.
2.  **Environment Creation:** Godot instantiates the 3D world (coastlines, buoys, depth data) based on the fetched coordinates.
3.  **Simulation Loop:**
    * **Sensors:** Godot simulates Lidar rays and sends point cloud data to ROS 2.
    * **Decision:** ROS 2 (Nav2) processes the map, plans a path, and sends velocity commands (`cmd_vel`).
    * **Action:** Godot applies forces/torque to the USV based on received commands, calculating buoyancy and drag.

---

## 🎮 Installation & Usage

### Prerequisites
* [Godot Engine 4.x](https://godotengine.org/)
* [Docker Desktop](https://www.docker.com/) (for Backend)
* [ROS 2 (Humble/Iron)](https://docs.ros.org/en/humble/) (for Autonomous Mode)

### 1. Setup Backend (Server)
```bash
cd ORHUN-Server
docker-compose up --build
# The API will be available at http://localhost:8000
```
### 2.Run Simulation (Client)
Open Godot Engine 4.

Import the project.godot file from the ORHUN-Client folder.

Select Mode:

For Autonomous Mode: Ensure RosManager is active and ROS 2 nodes are running.

For Manual/Video Mode: Enable offline_test_mode in the Ship inspector to control via WASD.

Press F5 to start the simulation.

🤝 Contributing
This project is developed using the Agile methodology. Contributions are welcome! Please open an issue to discuss proposed changes or submit a Pull Request.

📜 License
MIT License

Developed for Advanced Maritime Robotics Research.
