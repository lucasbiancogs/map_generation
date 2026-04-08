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

## Height per subdivided grid point. -1 for outer edge (no tile).
var height_map: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	# Grid runs in its own _ready. Wait one frame to ensure it's done.
	await get_tree().process_frame
	generate_height_map()


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
