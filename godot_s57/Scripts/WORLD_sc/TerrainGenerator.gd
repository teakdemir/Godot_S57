class_name TerrainGenerator
extends Node

# --- SABİTLER ---
const SEA_FLOOR_MATERIAL := "res://Materials/WORLD_mat/SeaFloorMaterial.tres"
const SEA_SURFACE_MATERIAL := "res://Materials/WORLD_mat/SeaMaterial.tres"
const SEA_FLOOR_DEPTH_SCALE := 2.0
const SEA_FLOOR_DEPTH_MULTIPLIER := 2.0
const SEA_BOUNDARY_EXPANSION_FACTOR := 1.0
const MAP_EXTENSION_FACTOR := 1.2

const COASTLINE_MATERIAL := "res://Materials/WORLD_mat/CoastlineMaterial.tres"
const COASTLINE_Y_OFFSET := 0.05
const MAX_POINTS_PER_COASTLINE_MESH := 512
const COASTLINE_HALF_WIDTH := 0.8
const COASTLINE_CREST_HEIGHT_DEFAULT := 0.8
const LAND_MATERIAL := "res://Materials/WORLD_mat/LandMaterial.tres"
const LAND_Y_OFFSET := 0.03
const LAND_BASE_HEIGHT_MIN_M := 1.5
const LAND_BASE_HEIGHT_MAX_M := 15.0
const LAND_SLOPE_RATIO_DEFAULT := 0.12
const LAND_EDGE_BLEND_M_DEFAULT := 60.0
const LAND_HEIGHT_MULTIPLIER := 1.6
const LAND_HEIGHT_EXTRA_M := 4.0
const LAND_COLUMN_DEPTH_M := 18.0
const LAND_COLUMN_MODE := true
const BARRIER_HEIGHT := 200.0
const BARRIER_DEPTH_OFFSET := -100.0
const BARRIER_COLOR_BOTTOM := Color(0.08, 0.15, 0.23, 0.65)
const BARRIER_COLOR_TOP := Color(0.2, 0.28, 0.36, 0.0)
const SEA_SURFACE_THICKNESS := 0.5
const SEA_SURFACE_LEVEL_M := 0.0
const DEFAULT_LAND_BOTTOM_OFFSET := -2.0

const SeaGeneratorModule := preload("res://Scripts/WORLD_sc/generators/SeaGenerator.gd")
const LandGeneratorModule := preload("res://Scripts/WORLD_sc/generators/LandGenerator.gd")
const ObjectGeneratorModule := preload("res://Scripts/WORLD_sc/generators/ObjectGenerator.gd")
const BoundaryGeneratorModule := preload("res://Scripts/WORLD_sc/generators/BoundaryGenerator.gd")

const OBJECT_DEFINITIONS := {
	"hrbfac": {
		"prefab": "res://prefab/objects/harbours/harbour.tscn",
		"material": "res://materials/WORLD_mat/HarborMaterial.tres",
		"material_node": "harbour",
		"scale": Vector3(5, 5, 5),
		"y_offset": 1.5
	},
	"bridge": {
		"prefab": "res://prefab/objects/bridges/bridge.tscn",
		"span_axis": "x",
		"native_length": 10.0
	},
	"lights": {
		"prefab": "res://prefab/objects/navigation/ligths/ligth.tscn"
	},
	"obstrn": {
		"prefab": "res://prefab/objects/hazards/obstrn/obstrn.tscn"
	},
	"uwtroc": {
		"prefab": "res://prefab/objects/hazards/uwtroc/uwtroc.tscn"
	},
	"wrecks": {
		"prefab": "res://prefab/objects/hazards/wrecks/wreck.tscn"
	}
}

var _prefab_cache: Dictionary = {}
var _material_cache: Dictionary = {}

var _sea_generator: SeaGenerator
var _land_generator: LandGenerator
var _object_generator: ObjectGenerator
var _boundary_generator: BoundaryGenerator

func _init() -> void:
	_sea_generator = SeaGeneratorModule.new(self)
	_land_generator = LandGeneratorModule.new(self)
	_object_generator = ObjectGeneratorModule.new(self)
	_boundary_generator = BoundaryGeneratorModule.new(self)

# --- ANA FONKSİYON ---
func generate_3d_environment(map_data: Dictionary, scale: int) -> Node3D:
	var environment_root := Node3D.new()
	environment_root.name = "MapEnvironment"

	# 1. Verileri Çek
	var terrain: Dictionary = map_data.get("terrain", {}) as Dictionary
	
	# Deniz poligonlarını hazırla
	var seaare_polygon: Array = []
	if terrain:
		var seaare_variant = terrain.get("seaare_polygon", [])
		if seaare_variant is Array:
			seaare_polygon = seaare_variant

	var sea_polygons: Array = []
	if terrain:
		var sea_polygons_variant = terrain.get("sea_polygons", [])
		if sea_polygons_variant is Array:
			for polygon_variant in sea_polygons_variant:
				if polygon_variant is Array:
					sea_polygons.append(polygon_variant)
	
	if sea_polygons.is_empty() and not seaare_polygon.is_empty():
		sea_polygons.append(seaare_polygon)

	# Temizleme ve Genişletme işlemleri (Deniz için)
	var base_sea_polygons := _sanitize_polygon_collection(sea_polygons)
	var extended_sea_polygons := _expand_polygon_collection(base_sea_polygons, MAP_EXTENSION_FACTOR)
	
	if extended_sea_polygons.is_empty():
		if not seaare_polygon.is_empty():
			extended_sea_polygons = [seaare_polygon]
		else:
			return environment_root # Veri yoksa çık

	# Sınır duvarı için orijinal (delinmemiş) halini sakla
	var boundary_base_polygon: Array = []
	if not base_sea_polygons.is_empty():
		boundary_base_polygon = base_sea_polygons[0].duplicate(true)
	
	# 2. Kara Poligonlarını Hazırla
	var land_polygons_data: Array = []
	if terrain:
		var land_variant = terrain.get("land_polygons", [])
		if land_variant is Array:
			land_polygons_data = land_variant
	
	# Karayı genişlet
	var extended_land_polygons_data := _land_generator.extend_land_polygons(land_polygons_data, MAP_EXTENSION_FACTOR)

	# 3. CLIPPING İŞLEMİ
	# Denizden karayı çıkarıp "Delikli Deniz" elde ediyoruz.
	var clipped_sea_polygons = _clip_land_from_sea(extended_sea_polygons, extended_land_polygons_data)

	# Diğer verileri çek
	var nav_objects: Dictionary = map_data.get("navigation_objects", {}) as Dictionary
	var depth_areas: Array = []
	if terrain: 
		depth_areas = terrain.get("depth_areas", [])
	
	var coastline_data: Array = []
	if terrain:
		coastline_data = terrain.get("coastlines", [])

	print("Generating 3D environment (WITH CLIPPING):")
	print("- Final Sea Patches: " + str(clipped_sea_polygons.size()))

	# 4. İnşa Etme (Build)
	
	# Deniz yüzeyi için 'clipped_sea_polygons' kullanıyoruz (Karanın altı boş)
	var sea_surface: Node3D = _sea_generator.build_surface(clipped_sea_polygons, boundary_base_polygon, depth_areas, scale)
	if sea_surface:
		environment_root.add_child(sea_surface)

	# Deniz tabanı (Sea Floor) delinmemeli, orijinal boundary kullanıyoruz
	var sea_floor: MeshInstance3D = _sea_generator.build_seafloor(depth_areas, boundary_base_polygon, scale)
	if sea_floor:
		environment_root.add_child(sea_floor)

	# Kara parçalarını oluştur
	var land_root: Node3D = _land_generator.build_landmasses(extended_land_polygons_data, scale)
	if land_root:
		environment_root.add_child(land_root)

	# Kıyıları oluştur
	var coastline_root: Node3D = _land_generator.build_coastlines(coastline_data, scale)
	if coastline_root:
		environment_root.add_child(coastline_root)

	# Sınırları oluştur
	var boundary_root: Node3D = _boundary_generator.build_boundary(boundary_base_polygon, scale)
	if boundary_root:
		environment_root.add_child(boundary_root)

	# Objeleri oluştur
	var navigation_root: Node3D = _object_generator.build_navigation_objects(nav_objects, scale)
	if navigation_root:
		environment_root.add_child(navigation_root)

	return environment_root

# --- YARDIMCI FONKSİYONLAR ---

func _calculate_polygon_bounds(points: Array) -> Dictionary:
	if points.is_empty(): return {}
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for point_variant in points:
		var point: Dictionary = point_variant as Dictionary
		if point.is_empty(): continue
		var px: float = float(point.get("x", 0.0))
		var pz: float = float(point.get("z", 0.0))
		min_x = min(min_x, px)
		max_x = max(max_x, px)
		min_z = min(min_z, pz)
		max_z = max(max_z, pz)
	return {"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z}

func _load_prefab(path: String) -> PackedScene:
	if path.is_empty(): return null
	if not _prefab_cache.has(path):
		if not ResourceLoader.exists(path):
			_prefab_cache[path] = null
		else:
			var resource := load(path)
			if resource and resource is PackedScene:
				_prefab_cache[path] = resource
			else:
				_prefab_cache[path] = null
	return _prefab_cache[path]

func _load_material(path: String) -> Material:
	if path.is_empty(): return null
	if not _material_cache.has(path):
		_material_cache[path] = load(path)
	return _material_cache[path]

func _expand_polygon(points: Array, factor: float) -> Array:
	if factor <= 1.0: return points.duplicate(true)
	var sanitized := _sanitize_polygon(points)
	if sanitized.size() < 3: return sanitized
	var centroid := Vector2.ZERO
	for point_variant in sanitized:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict: continue
		centroid += Vector2(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)))
	centroid /= sanitized.size()
	var expanded: Array = []
	for point_variant in sanitized:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict: continue
		var original := Vector2(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)))
		var direction := original - centroid
		var scaled := centroid + direction * factor
		expanded.append({"x": scaled.x, "z": scaled.y})
	return expanded

func _add_quad_surface(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color_a: Color = Color(1, 1, 1, 1), color_b: Color = Color(1, 1, 1, 1), use_color: bool = true) -> void:
	if use_color: st.set_color(color_a)
	st.add_vertex(a)
	if use_color: st.set_color(color_b)
	st.add_vertex(b)
	if use_color: st.set_color(color_b)
	st.add_vertex(c)
	if use_color: st.set_color(color_a)
	st.add_vertex(a)
	if use_color: st.set_color(color_b)
	st.add_vertex(c)
	if use_color: st.set_color(color_a)
	st.add_vertex(d)

func _create_static_body_from_mesh(mesh: Mesh) -> StaticBody3D:
	if mesh == null: return null
	var shape := mesh.create_trimesh_shape()
	if shape == null: return null
	var body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body

func _meters_to_world_units(value_m: float, scale: int) -> float:
	return (value_m / 1000.0) * float(scale) * 0.1

func _meters_to_height_units(value_m: float) -> float:
	return value_m * 0.1

func _sanitize_polygon(points: Array) -> Array:
	var result: Array = []
	for point_variant in points:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict or point_dict.is_empty(): continue
		if not point_dict.has("x") or not point_dict.has("z"): continue
		result.append({"x": float(point_dict.get("x", 0.0)), "z": float(point_dict.get("z", 0.0))})
	if result.size() > 2:
		var first: Dictionary = result[0]
		var last: Dictionary = result[result.size() - 1]
		if abs(float(first.get("x", 0.0)) - float(last.get("x", 0.0))) < 0.0001 and abs(float(first.get("z", 0.0)) - float(last.get("z", 0.0))) < 0.0001:
			result.remove_at(result.size() - 1)
	return result

func _sanitize_polygon_collection(polygons: Array) -> Array:
	var sanitized_collection: Array = []
	for polygon_variant in polygons:
		if not (polygon_variant is Array): continue
		var sanitized := _sanitize_polygon(polygon_variant)
		if sanitized.size() >= 3: sanitized_collection.append(sanitized)
	return sanitized_collection

func _expand_polygon_collection(polygons: Array, factor: float) -> Array:
	if factor <= 1.0: return _sanitize_polygon_collection(polygons)
	var expanded_collection: Array = []
	for polygon_variant in polygons:
		if not (polygon_variant is Array): continue
		var sanitized := _sanitize_polygon(polygon_variant)
		var expanded := _expand_polygon(sanitized, factor)
		if expanded.size() >= 3: expanded_collection.append(expanded)
	return expanded_collection

func _sanitize_sea_polygon(points: Array) -> Array:
	return _sanitize_polygon(points)

# --- CLIPPING FONKSİYONLARI (Overlap Fix) ---

# Deniz poligonlarından kara poligonlarını çıkaran ana fonksiyon
func _clip_land_from_sea(sea_polygons: Array, land_data_entries: Array) -> Array:
	# 1. Tüm kara poligonlarını Geometry2D formatına (PackedVector2Array) çevir
	var land_shapes: Array[PackedVector2Array] = []
	
	# OVERLAP AYARI: Bu değer kadar denizi karanın içine sokacağız (Godot biriminde negatif offset)
	var clipping_offset = -0.2 
	
	for entry in land_data_entries:
		var land_dict = entry as Dictionary
		var polys = land_dict.get("polygons", [])
		for poly in polys:
			var sanitized = _sanitize_polygon(poly)
			# Karayı Geometry2D formatına al
			var original_poly = _dict_array_to_packed_vector2(sanitized)
			
			# Kara poligonunu biraz "büzüştür" (shrink).
			# Böylece biz denizden bu "küçülmüş" karayı kestiğimizde,
			# deniz aslında gerçek karanın birazcık altına girmiş olacak.
			var shrunk_polys = Geometry2D.offset_polygon(original_poly, clipping_offset)
			
			for shrunk_poly in shrunk_polys:
				if shrunk_poly.size() >= 3:
					land_shapes.append(shrunk_poly)
	
	# 2. Deniz poligonlarını işle
	var final_sea_polygons: Array = []
	
	for sea_poly_dict in sea_polygons:
		var sanitized_sea = _sanitize_polygon(sea_poly_dict)
		var sea_shape = _dict_array_to_packed_vector2(sanitized_sea)
		
		if sea_shape.size() < 3:
			continue
			
		# Bu deniz parçası üzerinde tüm kara parçalarını çıkar (Difference)
		var current_sea_pieces: Array[PackedVector2Array] = [sea_shape]
		
		for land_shape in land_shapes:
			var next_step_pieces: Array[PackedVector2Array] = []
			for sea_piece in current_sea_pieces:
				# Geometry2D.clip_polygons(A, B) -> A'dan B'yi çıkarır
				var clipped_result = Geometry2D.clip_polygons(sea_piece, land_shape)
				next_step_pieces.append_array(clipped_result)
			current_sea_pieces = next_step_pieces
		
		# Sonuçları Dictionary formatına geri çevirip listeye ekle
		for piece in current_sea_pieces:
			if piece.size() >= 3:
				final_sea_polygons.append(_packed_vector2_to_dict_array(piece))
				
	return final_sea_polygons

# Helper: [{'x': 1, 'z': 2}] -> PackedVector2Array([Vector2(1, 2)])
func _dict_array_to_packed_vector2(dict_array: Array) -> PackedVector2Array:
	var arr = PackedVector2Array()
	for p in dict_array:
		arr.append(Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0))))
	return arr

# Helper: PackedVector2Array -> [{'x': 1, 'z': 2}]
func _packed_vector2_to_dict_array(vec_arr: PackedVector2Array) -> Array:
	var arr = []
	for vec in vec_arr:
		arr.append({"x": vec.x, "z": vec.y}) # Dikkat: 2D'de Y olan, 3D'de Z'dir
	return arr
