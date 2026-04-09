class_name BaseGrid
extends Node3D

## Shared grid data — all grid implementations must populate these.
var subdivided_points: Array[Vector3] = []
var subdivided_is_outer_edge: Array[bool] = []
var subdivided_quads: Array[PackedInt32Array] = []
var connectivity: Dictionary = {}
var connected_quads: Dictionary = {}

## Tracks which step we're currently displaying.
var current_step: int = 0


## Override in subclass.
func run_all() -> void:
	pass


## Override in subclass.
func reset() -> void:
	current_step = 0
	subdivided_points.clear()
	subdivided_is_outer_edge.clear()
	subdivided_quads.clear()
	connectivity.clear()
	connected_quads.clear()


## Override in subclass.
func run_step(_step: int) -> void:
	pass


## Returns sorted corner points for a tile centered on the given point index.
func get_tile_corners(center_idx: int) -> Array[Vector3]:
	var center: Vector3 = subdivided_points[center_idx]
	var corners: Array[Vector3] = []

	if connectivity.has(center_idx):
		var neighbors: Array[int] = connectivity[center_idx]
		for n in neighbors:
			corners.append((center + subdivided_points[n]) * 0.5)

	if connected_quads.has(center_idx):
		var quad_indices: Array[int] = connected_quads[center_idx]
		for qi in quad_indices:
			var quad: PackedInt32Array = subdivided_quads[qi]
			var qc: Vector3 = (subdivided_points[quad[0]] + subdivided_points[quad[1]]
				+ subdivided_points[quad[2]] + subdivided_points[quad[3]]) * 0.25
			corners.append(qc)

	corners.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(a.z - center.z, a.x - center.x) < atan2(b.z - center.z, b.x - center.x)
	)
	return corners


## Builds a StaticBody3D collider from the grid quads for raycasting.
func build_collider() -> void:
	var existing := get_node_or_null("GridCollider")
	if existing:
		existing.queue_free()

	var faces := PackedVector3Array()
	for quad in subdivided_quads:
		var p0: Vector3 = subdivided_points[quad[0]]
		var p1: Vector3 = subdivided_points[quad[1]]
		var p2: Vector3 = subdivided_points[quad[2]]
		var p3: Vector3 = subdivided_points[quad[3]]
		faces.append(p0); faces.append(p1); faces.append(p2)
		faces.append(p0); faces.append(p2); faces.append(p3)

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape

	var body := StaticBody3D.new()
	body.name = "GridCollider"
	body.add_child(col_shape)
	add_child(body)


## Builds connectivity from subdivided_quads (point-to-point and point-to-quad).
func build_connectivity() -> void:
	connectivity.clear()
	connected_quads.clear()

	for quad_idx in range(subdivided_quads.size()):
		var quad: PackedInt32Array = subdivided_quads[quad_idx]
		for vi in range(4):
			var pt: int = quad[vi]
			var right: int = quad[(vi + 1) % 4]
			var left: int = quad[(vi + 3) % 4]

			if not connectivity.has(pt):
				connectivity[pt] = [] as Array[int]
			var neighbors: Array[int] = connectivity[pt]
			if not neighbors.has(right):
				neighbors.append(right)
			if not neighbors.has(left):
				neighbors.append(left)

			if not connected_quads.has(pt):
				connected_quads[pt] = [] as Array[int]
			var pt_quads: Array[int] = connected_quads[pt]
			if not pt_quads.has(quad_idx):
				pt_quads.append(quad_idx)
