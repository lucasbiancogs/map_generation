class_name HexGrid
extends Node3D

## Distance from center to hex vertex.
@export_range(0.5, 20.0) var hex_size: float = 1.0
## Number of concentric rings per patch.
@export_range(1, 10) var iterations_count: int = 4

## Generated grid points (position + outer edge flag).
var points: Array[Vector3] = []
var is_outer_edge: Array[bool] = []
## Triangle indices (each group of 3 ints = one triangle).
var triangles: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	generate_hex_grid_points()
	construct_triangles()
	_build_visualization()


# ===========================================================================
# Step 1 — Generate hexagon grid points (concentric rings)
# ===========================================================================

func generate_hex_grid_points() -> void:
	points.clear()
	is_outer_edge.clear()

	# Ring 0: center point.
	points.append(Vector3.ZERO)
	is_outer_edge.append(false)

	for i in range(iterations_count):
		# Previous outer-edge points are no longer on the edge.
		for idx in range(is_outer_edge.size()):
			is_outer_edge[idx] = false

		# Generate new ring at distance hex_size * (i + 1).
		var ring_size: float = hex_size * (i + 1)
		var subdivision_count: int = i  # ring 1 = 0 subdivisions, ring 2 = 1, etc.
		var ring_points: Array[Vector3] = _calculate_ring_positions(ring_size, subdivision_count)

		for p in ring_points:
			points.append(p)
			is_outer_edge.append(true)


## Generates points for one hexagonal ring.
## [param ring_size]: radius of this ring.
## [param subdivision_count]: extra points to insert between each pair of hex vertices.
func _calculate_ring_positions(ring_size: float, subdivision_count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var angle_step: float = deg_to_rad(60.0)

	for side in range(6):
		var angle: float = deg_to_rad(side * 60.0 + 30.0)
		var next_angle: float = angle + angle_step

		var current_pt := Vector3(cos(angle), 0.0, sin(angle)) * ring_size
		var next_pt := Vector3(cos(next_angle), 0.0, sin(next_angle)) * ring_size

		# Vertex point.
		result.append(current_pt)

		# Subdivision (in-between) points.
		for j in range(subdivision_count):
			var t: float = (j + 1.0) / (subdivision_count + 1.0)
			result.append(current_pt.lerp(next_pt, t))

	return result


# ===========================================================================
# Step 2 — Construct triangles connecting adjacent rings
# ===========================================================================

func construct_triangles() -> void:
	triangles.clear()

	var current_point_index: int = 1

	for i in range(iterations_count):
		var current_iter_count: int = 6 * (i + 1)
		var previous_iter_count: int = 1 if i == 0 else 6 * i
		var prev_first_index: int = current_point_index - previous_iter_count
		var prev_conn_index: int = prev_first_index
		var first_index: int = current_point_index
		var last_index: int = first_index + current_iter_count - 1

		for offset in range(current_iter_count):
			# Check if this is a subdivision point (adds extra triangle).
			var adds_another: bool = (offset % (i + 1)) != 0

			var pt_index: int = first_index + offset
			var next_pt_index: int = pt_index + 1
			if next_pt_index > last_index:
				next_pt_index = first_index + (pt_index % last_index)

			if adds_another:
				var prev_next: int = prev_conn_index + 1
				if prev_next >= first_index:
					prev_next = prev_first_index

				triangles.append(pt_index)
				triangles.append(prev_conn_index)
				triangles.append(prev_next)

				prev_conn_index = prev_next

			triangles.append(pt_index)
			triangles.append(next_pt_index)
			triangles.append(prev_conn_index)

		current_point_index = last_index + 1


# ===========================================================================
# Visualization — draw grid as wireframe + point markers
# ===========================================================================

func _build_visualization() -> void:
	_build_wireframe_mesh()
	_build_point_markers()


## Draws triangle edges as lines.
func _build_wireframe_mesh() -> void:
	var lines := PackedVector3Array()

	var tri_count: int = triangles.size() / 3
	for t in range(tri_count):
		var i0: int = triangles[t * 3]
		var i1: int = triangles[t * 3 + 1]
		var i2: int = triangles[t * 3 + 2]
		var p0: Vector3 = points[i0]
		var p1: Vector3 = points[i1]
		var p2: Vector3 = points[i2]
		lines.append(p0); lines.append(p1)
		lines.append(p1); lines.append(p2)
		lines.append(p2); lines.append(p0)

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines

	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arr_mesh.surface_set_material(0, mat)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arr_mesh
	add_child(mesh_inst)


## Draws small spheres at each grid point. Outer-edge points are colored differently.
func _build_point_markers() -> void:
	# We use two MultiMeshInstance3D: one for interior, one for outer-edge.
	var inner_positions: PackedVector3Array = PackedVector3Array()
	var outer_positions: PackedVector3Array = PackedVector3Array()

	for i in range(points.size()):
		if is_outer_edge[i]:
			outer_positions.append(points[i])
		else:
			inner_positions.append(points[i])

	_create_point_cloud(inner_positions, Color(1.0, 1.0, 0.2), 0.04)
	_create_point_cloud(outer_positions, Color(1.0, 0.3, 0.2), 0.06)


func _create_point_cloud(positions: PackedVector3Array, color: Color, radius: float) -> void:
	if positions.is_empty():
		return

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = positions.size()

	for i in range(positions.size()):
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))

	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.multimesh = mm
	add_child(mm_inst)
