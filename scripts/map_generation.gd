class_name MapGeneration
extends Node3D

@export var grid: BaseGrid

@export_group("Tile Rendering")
## Vertical distance between stacked layers.
@export_range(0.1, 2.0) var layer_height: float = 0.5
## Maximum height a point can be set to.
@export_range(1, 5) var max_height: int = 3

## Height per subdivided grid point. 0 = water, 1+ = land/cliff.
var height_map: PackedInt32Array = PackedInt32Array()

## Per-quad tile layers. Each entry is an array of {layer: int, mesh_index: int}.
## mesh_index is a 4-bit marching-squares index (0–15).
var quad_tile_layers: Array[Array] = []

## Tile definitions. name_map supports future variations (picks first for now).
## index values are binary: each digit = one corner (1=land, 0=water).
const TILES: Array = [
	{"name_map": ["Water"], "index_map": [{"index": 0000, "rotation": 0}]},
	{"name_map": ["Dual_Grid_L_L_L_L"], "index_map": [{"index": 1111, "rotation": 0}]},
	{"name_map": ["Dual_Grid_L_W_W_W"], "index_map": [{"index": 1000, "rotation": 0}, {"index": 0100, "rotation": 1}, {"index": 0010, "rotation": 2}, {"index": 0001, "rotation": 3}]},
	{"name_map": ["Dual_Grid_L_L_L_W"], "index_map": [{"index": 1110, "rotation": 0}, {"index": 0111, "rotation": 1}, {"index": 1011, "rotation": 2}, {"index": 1101, "rotation": 3}]},
	{"name_map": ["Dual_Grid_L_L_W_W"], "index_map": [{"index": 1100, "rotation": 0}, {"index": 0110, "rotation": 1}, {"index": 0011, "rotation": 2}, {"index": 1001, "rotation": 3}]},
	{"name_map": ["Dual_Grid_L_W_L_W"], "index_map": [{"index": 1010, "rotation": 0}, {"index": 0101, "rotation": 1}]},
]

## Loaded tile scenes: scene_name -> PackedScene.
var _tile_scenes: Dictionary = {}
## Runtime lookup: marching-squares index (0-15) -> {scene_name: String, rotation: int}.
var _tile_lookup: Dictionary = {}
## Container node for placed tile instances.
var _tiles_container: Node3D
## Per-quad rotation offset to correct for non-uniform quad orientations.
var _quad_rotation_offsets: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_build_tile_lookup()
	_load_tile_scenes()
	await get_tree().process_frame
	_init_height_map()


func _build_tile_lookup() -> void:
	_tile_lookup.clear()
	for tile_def in TILES:
		var scene_name: String = tile_def["name_map"][0]
		for entry in tile_def["index_map"]:
			var index: int = _binary_to_int(entry["index"])
			_tile_lookup[index] = {
				"scene_name": scene_name,
				"rotation": entry["rotation"],
			}


## Converts a "binary-style" integer like 1010 to its actual bit value (10).
func _binary_to_int(binary_digits: int) -> int:
	var result: int = 0
	var place: int = 0
	var val: int = binary_digits
	while val > 0:
		var digit: int = val % 10
		result |= (digit << place)
		val /= 10
		place += 1
	return result


func _load_tile_scenes() -> void:
	var scene_dir := "res://scenes/tiles/"
	var loaded: Dictionary = {}
	for tile_def in TILES:
		for scene_name in tile_def["name_map"]:
			if loaded.has(scene_name):
				continue
			var path: String = scene_dir + scene_name + ".tscn"
			var scene: PackedScene = load(path)
			if not scene:
				push_warning("Failed to load tile scene: " + path)
				continue
			_tile_scenes[scene_name] = scene
			loaded[scene_name] = true


func _init_height_map() -> void:
	if not grid or grid.subdivided_points.is_empty():
		return
	height_map.resize(grid.subdivided_points.size())
	height_map.fill(0)
	_compute_quad_rotation_offsets()


## Computes per-quad rotation offsets by comparing each quad's orientation to the
## regular grid reference (where quad[0] is at the top-left, angle -135° from center).
func _compute_quad_rotation_offsets() -> void:
	var ref_angle := -PI * 3.0 / 4.0  # -135°: direction from center to TL
	_quad_rotation_offsets.resize(grid.subdivided_quads.size())

	for qi in range(grid.subdivided_quads.size()):
		var quad: PackedInt32Array = grid.subdivided_quads[qi]
		var center := (grid.subdivided_points[quad[0]] + grid.subdivided_points[quad[1]]
			+ grid.subdivided_points[quad[2]] + grid.subdivided_points[quad[3]]) * 0.25

		var dir := grid.subdivided_points[quad[0]] - center
		var angle := atan2(dir.z, dir.x)
		var diff := fmod(angle - ref_angle, TAU)
		if diff < 0:
			diff += TAU

		_quad_rotation_offsets[qi] = roundi(diff / (PI * 0.5)) % 4


## Sets a point's height and refreshes affected tiles.
func set_point_height(point_idx: int, height: int) -> void:
	if point_idx < 0 or point_idx >= height_map.size():
		return
	if grid.subdivided_is_outer_edge[point_idx]:
		return
	height_map[point_idx] = clampi(height, 0, max_height)
	compute_tile_layers()
	place_tiles()


## Increments a point's height by 1, wrapping back to 0.
func toggle_point_height(point_idx: int) -> void:
	if point_idx < 0 or point_idx >= height_map.size():
		return
	if grid.subdivided_is_outer_edge[point_idx]:
		return
	var new_h: int = (height_map[point_idx] + 1) % (max_height + 1)
	set_point_height(point_idx, new_h)


## For each subdivided quad, computes which mesh to place at each height layer.
func compute_tile_layers() -> void:
	quad_tile_layers.clear()

	if height_map.is_empty() or grid.subdivided_quads.is_empty():
		return

	for qi in range(grid.subdivided_quads.size()):
		var quad: PackedInt32Array = grid.subdivided_quads[qi]
		var h0: int = height_map[quad[0]]
		var h1: int = height_map[quad[1]]
		var h2: int = height_map[quad[2]]
		var h3: int = height_map[quad[3]]

		var max_h: int = maxi(maxi(h0, h1), maxi(h2, h3))

		var layers: Array = []

		for layer in range(max_h):
			var b0: int = 1 if h0 > layer else 0
			var b1: int = 1 if h1 > layer else 0
			var b2: int = 1 if h2 > layer else 0
			var b3: int = 1 if h3 > layer else 0
			var mesh_index: int = b0 | (b1 << 1) | (b2 << 2) | (b3 << 3)
			layers.append({"layer": layer, "mesh_index": mesh_index})

		if not layers.is_empty():
			for l in layers:
				var idx: int = l["mesh_index"]
				var b: String = "%d%d%d%d" % [(idx >> 3) & 1, (idx >> 2) & 1, (idx >> 1) & 1, idx & 1]
				var lookup_name: String = _tile_lookup[idx]["scene_name"] if _tile_lookup.has(idx) else "???"
				print("  Quad %d layer %d: %s (index %d) -> %s rot %d" % [
					qi, l["layer"], b, idx, lookup_name,
					_tile_lookup[idx]["rotation"] if _tile_lookup.has(idx) else -1
				])

		quad_tile_layers.append(layers)


## Places tile scenes at quad centers.
func place_tiles() -> void:
	if _tiles_container:
		_tiles_container.free()

	_tiles_container = Node3D.new()
	_tiles_container.name = "Tiles"
	add_child(_tiles_container)

	if quad_tile_layers.is_empty():
		return

	for qi in range(grid.subdivided_quads.size()):
		if qi >= quad_tile_layers.size():
			break

		var layers: Array = quad_tile_layers[qi]
		var quad: PackedInt32Array = grid.subdivided_quads[qi]

		var center := (grid.subdivided_points[quad[0]] + grid.subdivided_points[quad[1]]
			+ grid.subdivided_points[quad[2]] + grid.subdivided_points[quad[3]]) * 0.25

		for layer_data in layers:
			var mesh_index: int = layer_data["mesh_index"]
			var layer: int = layer_data["layer"]

			if mesh_index == 0:
				continue

			if not _tile_lookup.has(mesh_index):
				continue

			var lookup: Dictionary = _tile_lookup[mesh_index]
			var scene_name: String = lookup["scene_name"]
			var rotation_steps: int = lookup["rotation"]

			if not _tile_scenes.has(scene_name):
				continue

			var quad_offset: int = _quad_rotation_offsets[qi] if qi < _quad_rotation_offsets.size() else 0
			var final_rotation: int = (rotation_steps - quad_offset + 4) % 4

			var tile: Node3D = _tile_scenes[scene_name].instantiate()
			tile.position = center + Vector3.UP * layer * layer_height
			if final_rotation > 0:
				tile.rotation.y = deg_to_rad(final_rotation * 90.0)
			_tiles_container.add_child(tile)
