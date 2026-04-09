class_name RegularGrid
extends BaseGrid

@export_range(2, 50) var width: int = 10
@export_range(2, 50) var height: int = 10
@export_range(0.1, 5.0) var cell_size: float = 1.0

const STEP_NAMES: PackedStringArray = ["1: Generate Grid"]
const TOTAL_STEPS: int = 1


func _ready() -> void:
	run_all()


func run_all() -> void:
	_generate()
	current_step = TOTAL_STEPS
	build_collider()


func reset() -> void:
	super.reset()


func run_step(step: int) -> void:
	if step == 1:
		_generate()
	current_step = step
	build_collider()


func _generate() -> void:
	reset()

	for y in range(height):
		for x in range(width):
			var offset_x: float = (width - 1) * cell_size * 0.5
			var offset_z: float = (height - 1) * cell_size * 0.5
			var pos := Vector3(x * cell_size - offset_x, 0.0, y * cell_size - offset_z)
			subdivided_points.append(pos)
			var is_edge: bool = (x == 0 or x == width - 1 or y == 0 or y == height - 1)
			subdivided_is_outer_edge.append(is_edge)

	for y in range(height - 1):
		for x in range(width - 1):
			var i0: int = y * width + x
			var i1: int = i0 + 1
			var i2: int = i0 + width + 1
			var i3: int = i0 + width
			subdivided_quads.append(PackedInt32Array([i0, i1, i2, i3]))

	build_connectivity()
