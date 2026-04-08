class_name OrganicGrid
extends Node3D

## Distance from center to hex vertex.
@export_range(0.5, 20.0) var hex_size: float = 1.0
## Number of concentric rings per patch.
@export_range(1, 10) var iterations_count: int = 6
## Seed for random triangle merging.
@export var randomization_seed: int = 0
## Relaxation iterations (Laplacian smoothing passes).
@export_range(0, 200) var relaxation_iterations: int = 10

## Generated grid points (position + outer edge flag).
var points: Array[Vector3] = []
var is_outer_edge: Array[bool] = []
## Triangle indices (each group of 3 ints = one triangle).
var triangles: PackedInt32Array = PackedInt32Array()
## Quad vertex indices (each group of 4 ints = one quad).
var quads: Array[PackedInt32Array] = []
## Triangles that couldn't be merged (indices into the triangles list).
var unmergeable_triangle_indices: Array[int] = []
## Subdivided grid (final output of the subdivision step).
var subdivided_points: Array[Vector3] = []
var subdivided_is_outer_edge: Array[bool] = []
var subdivided_quads: Array[PackedInt32Array] = []
## Connectivity: point index -> array of connected point indices.
var connectivity: Dictionary = {}
## Point-to-quad connectivity: point index -> array of quad indices.
var connected_quads: Dictionary = {}

const STEP_NAMES: PackedStringArray = [
	"1: Generate Points",
	"2: Construct Triangles",
	"3: Merge into Quads",
	"4: Subdivide",
	"5: Build Connectivity",
	"6: Laplacian Relaxation",
]
const TOTAL_STEPS: int = 6


func _ready() -> void:
	run_all()


func run_all() -> void:
	for step in range(1, TOTAL_STEPS + 1):
		_execute_step(step)
	_clear_visualization()
	_visualize_subdivided()
	build_collider()


## Builds a StaticBody3D collider from the grid quads for raycasting.
func build_collider() -> void:
	# Remove existing collider if any.
	var existing := get_node_or_null("GridCollider")
	if existing:
		existing.queue_free()

	var faces := PackedVector3Array()
	for quad in subdivided_quads:
		var p0 := subdivided_points[quad[0]]
		var p1 := subdivided_points[quad[1]]
		var p2 := subdivided_points[quad[2]]
		var p3 := subdivided_points[quad[3]]
		# Two triangles per quad.
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


func reset() -> void:
	points.clear()
	is_outer_edge.clear()
	triangles.clear()
	quads.clear()
	unmergeable_triangle_indices.clear()
	subdivided_points.clear()
	subdivided_is_outer_edge.clear()
	subdivided_quads.clear()
	connectivity.clear()
	connected_quads.clear()
	_clear_visualization()


func run_step(step: int) -> void:
	_execute_step(step)
	_clear_visualization()
	_visualize_step(step)


func _execute_step(step: int) -> void:
	match step:
		1: generate_hex_grid_points()
		2: construct_triangles()
		3: merge_triangles_into_quads()
		4: subdivide_grid()
		5: build_connectivity()
		6: apply_relaxation()


func _visualize_step(step: int) -> void:
	match step:
		1:
			_visualize_points(points, is_outer_edge)
		2:
			_visualize_triangles()
			_visualize_points(points, is_outer_edge)
		3:
			_visualize_quads_and_tris()
			_visualize_points(points, is_outer_edge)
		4:
			_visualize_subdivided()
		5:
			_visualize_subdivided()
			_visualize_connectivity()
		6:
			_visualize_subdivided()


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
# Step 3 — Merge adjacent triangles into quads
# ===========================================================================

func merge_triangles_into_quads() -> void:
	quads.clear()
	unmergeable_triangle_indices.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = randomization_seed

	var tri_count: int = triangles.size() / 3

	# Build adjacency: two triangles are adjacent if they share exactly 2 vertices.
	var adjacency: Dictionary = {}  # tri_index -> Array[int] of adjacent tri indices
	for i in range(tri_count):
		adjacency[i] = [] as Array[int]

	for i in range(tri_count):
		var iv := _get_tri_vertices(i)
		for j in range(i + 1, tri_count):
			var jv := _get_tri_vertices(j)
			var shared: int = 0
			for vi in iv:
				for vj in jv:
					if vi == vj:
						shared += 1
			if shared == 2:
				adjacency[i].append(j)
				adjacency[j].append(i)

	# Track which triangles are still available for merging.
	var mergeable: Dictionary = {}  # tri_index -> true
	for i in range(tri_count):
		mergeable[i] = true

	# Random upper limit on merges for more varied results.
	var max_merges: int = rng.randi_range(tri_count / 3, tri_count)

	while not mergeable.is_empty():
		if quads.size() >= max_merges:
			for idx in mergeable.keys():
				unmergeable_triangle_indices.append(idx)
			break

		# Pick a random mergeable triangle.
		var keys: Array = mergeable.keys()
		var tri_a: int = keys[rng.randi_range(0, keys.size() - 1)]

		# Filter its adjacency list to only still-mergeable triangles.
		var available_neighbors: Array[int] = []
		for n in adjacency[tri_a]:
			if mergeable.has(n):
				available_neighbors.append(n)

		if available_neighbors.is_empty():
			mergeable.erase(tri_a)
			unmergeable_triangle_indices.append(tri_a)
			continue

		var tri_b: int = available_neighbors[rng.randi_range(0, available_neighbors.size() - 1)]

		# Merge into a quad.
		quads.append(_merge_two_triangles(tri_a, tri_b))

		# Remove both from mergeable set.
		mergeable.erase(tri_a)
		mergeable.erase(tri_b)

		# Update adjacency: remove references to merged triangles.
		# If a neighbor loses all its mergeable neighbors, it becomes unmergeable.
		_remove_from_adjacency(tri_a, tri_b, adjacency, mergeable, unmergeable_triangle_indices)
		_remove_from_adjacency(tri_b, tri_a, adjacency, mergeable, unmergeable_triangle_indices)


## Returns the 3 vertex indices of the triangle at the given index.
func _get_tri_vertices(tri_index: int) -> PackedInt32Array:
	var base: int = tri_index * 3
	return PackedInt32Array([triangles[base], triangles[base + 1], triangles[base + 2]])


## Merges two triangles into a quad. The shared edge vertices go to positions 0 and 2,
## and the unique vertices go to positions 1 and 3, forming a proper quad winding.
func _merge_two_triangles(tri_a: int, tri_b: int) -> PackedInt32Array:
	var va := _get_tri_vertices(tri_a)
	var vb := _get_tri_vertices(tri_b)

	var shared: Array[int] = []
	var unique: Array[int] = []

	# Collect all 6 vertex indices, identify shared vs unique.
	for v in va:
		var found := false
		for u in vb:
			if v == u:
				found = true
				break
		if found:
			shared.append(v)
		else:
			unique.append(v)

	for v in vb:
		var found := false
		for u in va:
			if v == u:
				found = true
				break
		if not found:
			unique.append(v)

	# Quad winding: shared[0], unique[0], shared[1], unique[1]
	return PackedInt32Array([shared[0], unique[0], shared[1], unique[1]])


## Removes a merged triangle from the adjacency of its neighbors.
## If a neighbor loses all mergeable neighbors, it becomes unmergeable.
func _remove_from_adjacency(tri_index: int, other_merged: int, adjacency: Dictionary,
		mergeable: Dictionary, unmergeable: Array[int]) -> void:
	for neighbor in adjacency[tri_index]:
		if neighbor == other_merged:
			continue
		var neighbor_adj: Array[int] = adjacency[neighbor]
		neighbor_adj.erase(tri_index)

		# Check if this neighbor still has any mergeable adjacent triangles.
		var has_mergeable_neighbor := false
		for n in neighbor_adj:
			if mergeable.has(n):
				has_mergeable_neighbor = true
				break
		if not has_mergeable_neighbor and mergeable.has(neighbor):
			mergeable.erase(neighbor)
			unmergeable.append(neighbor)


# ===========================================================================
# Step 4 — Subdivide quads and remaining triangles into smaller quads
# ===========================================================================

func subdivide_grid() -> void:
	# Start with a copy of the original points.
	subdivided_points = points.duplicate()
	subdivided_is_outer_edge = is_outer_edge.duplicate()
	subdivided_quads.clear()

	# Dictionary to prevent duplicate edge midpoints.
	# Key: packed pair of point indices -> midpoint index.
	var edge_midpoints: Dictionary = {}

	# Subdivide each quad into 4 smaller quads.
	for quad in quads:
		var center := _quad_center(quad)
		var center_idx: int = subdivided_points.size()
		subdivided_points.append(center)
		subdivided_is_outer_edge.append(false)

		var vert_indices := PackedInt32Array([quad[0], quad[1], quad[2], quad[3]])
		_subdivide_shape(vert_indices, center_idx, edge_midpoints)

	# Subdivide each unmergeable triangle into 3 smaller quads.
	for tri_idx in unmergeable_triangle_indices:
		var v := _get_tri_vertices(tri_idx)
		var p0 := subdivided_points[v[0]]
		var p1 := subdivided_points[v[1]]
		var p2 := subdivided_points[v[2]]

		var center := (p0 + p1 + p2) / 3.0
		var center_idx: int = subdivided_points.size()
		subdivided_points.append(center)
		subdivided_is_outer_edge.append(false)

		_subdivide_shape(v, center_idx, edge_midpoints)


func _quad_center(quad: PackedInt32Array) -> Vector3:
	return (subdivided_points[quad[0]] + subdivided_points[quad[1]]
		+ subdivided_points[quad[2]] + subdivided_points[quad[3]]) * 0.25


## Subdivides a shape (3 or 4 vertices) around a center point into quads.
## For each edge, creates a midpoint (or reuses an existing one), then forms
## a quad: center, mid_i, vertex_(i+1), mid_(i+1).
func _subdivide_shape(vert_indices: PackedInt32Array, center_idx: int,
		edge_midpoints: Dictionary) -> void:
	var count: int = vert_indices.size()
	var mid_indices := PackedInt32Array()
	mid_indices.resize(count)

	# Create or reuse edge midpoints.
	for i in range(count):
		var idx_a: int = vert_indices[i]
		var idx_b: int = vert_indices[(i + 1) % count]

		# Canonical key: smaller index first.
		var key_lo: int = mini(idx_a, idx_b)
		var key_hi: int = maxi(idx_a, idx_b)
		var key: int = (key_hi << 16) | key_lo

		if edge_midpoints.has(key):
			mid_indices[i] = edge_midpoints[key]
		else:
			var mid_pos := (subdivided_points[idx_a] + subdivided_points[idx_b]) * 0.5
			var mid_outer: bool = subdivided_is_outer_edge[idx_a] and subdivided_is_outer_edge[idx_b]
			var mid_idx: int = subdivided_points.size()
			subdivided_points.append(mid_pos)
			subdivided_is_outer_edge.append(mid_outer)
			edge_midpoints[key] = mid_idx
			mid_indices[i] = mid_idx

	# Create one quad per edge: center, mid[i], vertex[i+1], mid[i+1].
	for i in range(count):
		var next_i: int = (i + 1) % count
		subdivided_quads.append(PackedInt32Array([
			center_idx,
			mid_indices[i],
			vert_indices[next_i],
			mid_indices[next_i]
		]))


# ===========================================================================
# Step 5 — Build connectivity info
# ===========================================================================

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

			# Track which quads touch this point.
			if not connected_quads.has(pt):
				connected_quads[pt] = [] as Array[int]
			var pt_quads: Array[int] = connected_quads[pt]
			if not pt_quads.has(quad_idx):
				pt_quads.append(quad_idx)


# ===========================================================================
# Step 6 — Relaxation (Laplacian smoothing)
# ===========================================================================

func apply_relaxation() -> void:
	for _iter in range(relaxation_iterations):
		for pt_idx in range(subdivided_points.size()):
			if subdivided_is_outer_edge[pt_idx]:
				continue

			if not connectivity.has(pt_idx):
				continue

			var neighbors: Array[int] = connectivity[pt_idx]
			var avg := Vector3.ZERO
			for n in neighbors:
				avg += subdivided_points[n]
			avg /= neighbors.size()
			subdivided_points[pt_idx] = avg


# ===========================================================================
# Visualization — draw grid as wireframe + point markers
# ===========================================================================

func _clear_visualization() -> void:
	for child in get_children():
		child.queue_free()


## Step 1 visualization: just points.
func _visualize_points(pts: Array[Vector3], outer: Array[bool]) -> void:
	var inner_pos := PackedVector3Array()
	var outer_pos := PackedVector3Array()
	for i in range(pts.size()):
		if outer[i]:
			outer_pos.append(pts[i])
		else:
			inner_pos.append(pts[i])
	_create_point_cloud(inner_pos, Color(1.0, 1.0, 0.2), 0.04)
	_create_point_cloud(outer_pos, Color(1.0, 0.3, 0.2), 0.06)


## Step 2 visualization: triangle wireframe.
func _visualize_triangles() -> void:
	var lines := PackedVector3Array()
	var tri_count: int = triangles.size() / 3
	for t in range(tri_count):
		var i0: int = triangles[t * 3]
		var i1: int = triangles[t * 3 + 1]
		var i2: int = triangles[t * 3 + 2]
		lines.append(points[i0]); lines.append(points[i1])
		lines.append(points[i1]); lines.append(points[i2])
		lines.append(points[i2]); lines.append(points[i0])
	_add_line_mesh(lines, Color(0.3, 0.7, 1.0))


## Step 3 visualization: quads (green) + unmergeable triangles (orange).
func _visualize_quads_and_tris() -> void:
	var quad_lines := PackedVector3Array()
	for quad in quads:
		var p0 := points[quad[0]]; var p1 := points[quad[1]]
		var p2 := points[quad[2]]; var p3 := points[quad[3]]
		quad_lines.append(p0); quad_lines.append(p1)
		quad_lines.append(p1); quad_lines.append(p2)
		quad_lines.append(p2); quad_lines.append(p3)
		quad_lines.append(p3); quad_lines.append(p0)
	_add_line_mesh(quad_lines, Color(0.2, 0.9, 0.3))

	var tri_lines := PackedVector3Array()
	for tri_idx in unmergeable_triangle_indices:
		var v := _get_tri_vertices(tri_idx)
		tri_lines.append(points[v[0]]); tri_lines.append(points[v[1]])
		tri_lines.append(points[v[1]]); tri_lines.append(points[v[2]])
		tri_lines.append(points[v[2]]); tri_lines.append(points[v[0]])
	_add_line_mesh(tri_lines, Color(1.0, 0.5, 0.1))


## Step 4+ visualization: subdivided quads.
func _visualize_subdivided() -> void:
	var lines := PackedVector3Array()
	for quad in subdivided_quads:
		var p0 := subdivided_points[quad[0]]; var p1 := subdivided_points[quad[1]]
		var p2 := subdivided_points[quad[2]]; var p3 := subdivided_points[quad[3]]
		lines.append(p0); lines.append(p1)
		lines.append(p1); lines.append(p2)
		lines.append(p2); lines.append(p3)
		lines.append(p3); lines.append(p0)
	_add_line_mesh(lines, Color(0.2, 0.9, 0.3))
	_visualize_points(subdivided_points, subdivided_is_outer_edge)


## Draws a line from each point to all its connected neighbors.
func _visualize_connectivity() -> void:
	var lines := PackedVector3Array()
	for pt_idx in connectivity.keys():
		var pos: Vector3 = subdivided_points[pt_idx]
		var neighbors: Array[int] = connectivity[pt_idx]
		for n in neighbors:
			# Draw each connection as a line slightly raised to avoid z-fighting with the quad wireframe.
			var n_pos: Vector3 = subdivided_points[n]
			lines.append(pos + Vector3.UP * 0.01)
			lines.append(n_pos + Vector3.UP * 0.01)
	_add_line_mesh(lines, Color(1.0, 0.2, 0.6, 0.6))


func _add_line_mesh(lines: PackedVector3Array, color: Color) -> void:
	if lines.is_empty():
		return

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arr_mesh.surface_set_material(0, mat)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arr_mesh
	add_child(mesh_inst)



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
