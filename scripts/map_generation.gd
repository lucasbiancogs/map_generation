class_name MapGeneration
extends Node3D

@export var grid: OrganicGrid

@export_group("Noise Settings")
## Seed for the noise generator.
@export var noise_seed: int = 0
## Frequency of the noise — lower values produce larger features.
@export_range(0.01, 2.0) var noise_frequency: float = 0.3
## Number of noise octaves for detail layering.
@export_range(1, 6) var noise_octaves: int = 3
## Noise values below this become water (height 0).
@export_range(0.0, 1.0) var water_threshold: float = 0.4
## Maximum terrain height (noise maps to 0..max_height).
@export_range(1, 5) var max_height: int = 3

## Height per subdivided grid point. 0 = water, 1+ = land/cliff.
var height_map: PackedInt32Array = PackedInt32Array()

## Per-quad tile layers. Each entry is an array of {layer: int, mesh_index: int}.
## mesh_index is a 4-bit marching-squares index (0–15).
var quad_tile_layers: Array[Array] = []


func _ready() -> void:
	# Grid runs in its own _ready. Wait one frame to ensure it's done.
	await get_tree().process_frame
	generate_height_map()
	compute_tile_layers()


func generate_height_map() -> void:
	if not grid or grid.subdivided_points.is_empty():
		return

	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = noise_frequency
	noise.fractal_octaves = noise_octaves
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

	var point_count: int = grid.subdivided_points.size()
	height_map.resize(point_count)

	for i in range(point_count):
		if grid.subdivided_is_outer_edge[i]:
			height_map[i] = 0
			continue

		var pos: Vector3 = grid.subdivided_points[i]
		# FastNoiseLite returns values in [-1, 1], remap to [0, 1].
		var noise_val: float = (noise.get_noise_2d(pos.x, pos.z) + 1.0) * 0.5

		if noise_val < water_threshold:
			height_map[i] = 0
		else:
			# Map the remaining range [water_threshold, 1] to [1, max_height].
			var t: float = (noise_val - water_threshold) / (1.0 - water_threshold)
			height_map[i] = clampi(int(t * max_height) + 1, 1, max_height)


## For each subdivided quad, computes which mesh to place at each height layer.
## Uses marching-squares: 4 corner heights reduced to binary per layer -> 4-bit index.
func compute_tile_layers() -> void:
	quad_tile_layers.clear()

	if height_map.is_empty() or grid.subdivided_quads.is_empty():
		return

	for quad in grid.subdivided_quads:
		var h0: int = height_map[quad[0]]
		var h1: int = height_map[quad[1]]
		var h2: int = height_map[quad[2]]
		var h3: int = height_map[quad[3]]

		var min_h: int = mini(mini(h0, h1), mini(h2, h3))
		var max_h: int = maxi(maxi(h0, h1), maxi(h2, h3))

		var layers: Array = []

		if min_h == max_h:
			# Flat quad — all corners same height.
			# Index 15 (all above) for land, index 0 (all below) for water.
			var mesh_index: int = 15 if min_h > 0 else 0
			layers.append({"layer": min_h, "mesh_index": mesh_index})
		else:
			# Transition quad — compute one mesh per height step.
			for layer in range(min_h, max_h):
				var b0: int = 1 if h0 > layer else 0
				var b1: int = 1 if h1 > layer else 0
				var b2: int = 1 if h2 > layer else 0
				var b3: int = 1 if h3 > layer else 0
				var mesh_index: int = b0 | (b1 << 1) | (b2 << 2) | (b3 << 3)
				layers.append({"layer": layer, "mesh_index": mesh_index})

		quad_tile_layers.append(layers)
