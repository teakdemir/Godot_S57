# Godot_S57
S-57 Maritime Chart 3D Visualization System
A real-time 3D visualization system for S-57 nautical charts, converting International Hydrographic Organization (IHO) maritime data into interactive 3D environments using Python, PostgreSQL, and Godot Engine.
Overview
This project transforms S-57 electronic navigational chart (ENC) data into explorable 3D maritime environments. The system analyzes S-57 chart files, stores maritime objects in a PostgreSQL database, and renders them as navigable 3D scenes with proper scaling and geographic accuracy.
Architecture
Backend (Python)

s57_analyzer.py: Parses S-57 files using GDAL/OGR, extracts maritime features
json_ext.py: Exports database content to Godot-optimized JSON format
server.py: FastAPI REST API for data access
Database: PostgreSQL + PostGIS with single-table architecture

Frontend (Godot 4.x)

Main.gd: Scene orchestration and API integration
TerrainGenerator.gd: Procedural 3D environment generation
CameraController.gd: WASD navigation with mouse look
MapManager.gd: Coordinate conversion and dynamic scaling system
