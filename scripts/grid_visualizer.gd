## This class is designed only for debug purposes.
class_name GridVisualizer
extends Node3D

@export var grid: BaseGrid
@export var map_gen: MapGeneration

## Visualization toggles.
var show_grid_wireframe: bool = true
var show_points: bool = true
var show_tile_edges: bool = true
var show_connectivity: bool = false
var show_height_map: bool = false


func refresh() -> void:
	_clear()
	if not grid or grid.current_step == 0:
		return

	var organic := grid as OrganicGrid

	# Steps 1-3 are OrganicGrid-specific.
	if organic and grid.current_step <= 3:
		match grid.current_step:
			1:
				if show_points:
					_draw_points(organic.points, organic.is_outer_edge)
			2:
				if show_grid_wireframe:
					_draw_triangles(organic)
				if show_points:
					_draw_points(organic.points, organic.is_outer_edge)
			3:
				if show_grid_wireframe:
					_draw_quads_and_tris(organic)
				if show_points:
					_draw_points(organic.points, organic.is_outer_edge)
		return

	# Steps 4+ use shared BaseGrid data — works with any grid.
	if show_grid_wireframe:
		_draw_grid_wireframe()
	if show_points:
		_draw_points(grid.subdivided_points, grid.subdivided_is_outer_edge)
	if show_connectivity and grid.current_step >= 5:
		_draw_connectivity()
	if show_tile_edges and grid.current_step >= 7:
		_draw_tile_edges()
	if show_height_map and map_gen and not map_gen.height_map.is_empty():
		_draw_height_map()


func _clear() -> void:
	for child in get_children():
		child.queue_free()


# ===========================================================================
# Drawing functions
# ===========================================================================

func _draw_points(pts: Array[Vector3], outer: Array[bool]) -> void:
	var inner_pos := PackedVector3Array()
	var outer_pos := PackedVector3Array()
	for i in range(pts.size()):
		if outer[i]:
			outer_pos.append(pts[i])
		else:
			inner_pos.append(pts[i])
	_create_point_cloud(inner_pos, Color(1.0, 1.0, 0.0), 0.03)
	_create_point_cloud(outer_pos, Color(1.0, 1.0, 0.0), 0.04)


func _draw_triangles(organic: OrganicGrid) -> void:
	var lines := PackedVector3Array()
	var tri_count: int = organic.triangles.size() / 3
	for t in range(tri_count):
		var i0: int = organic.triangles[t * 3]
		var i1: int = organic.triangles[t * 3 + 1]
		var i2: int = organic.triangles[t * 3 + 2]
		lines.append(organic.points[i0]); lines.append(organic.points[i1])
		lines.append(organic.points[i1]); lines.append(organic.points[i2])
		lines.append(organic.points[i2]); lines.append(organic.points[i0])
	_add_line_mesh(lines, Color(1.0, 1.0, 0.0))


func _draw_quads_and_tris(organic: OrganicGrid) -> void:
	var quad_lines := PackedVector3Array()
	for quad in organic.quads:
		var p0: Vector3 = organic.points[quad[0]]; var p1: Vector3 = organic.points[quad[1]]
		var p2: Vector3 = organic.points[quad[2]]; var p3: Vector3 = organic.points[quad[3]]
		quad_lines.append(p0); quad_lines.append(p1)
		quad_lines.append(p1); quad_lines.append(p2)
		quad_lines.append(p2); quad_lines.append(p3)
		quad_lines.append(p3); quad_lines.append(p0)
	_add_line_mesh(quad_lines, Color(1.0, 1.0, 0.0))

	var tri_lines := PackedVector3Array()
	for tri_idx in organic.unmergeable_triangle_indices:
		var v := organic._get_tri_vertices(tri_idx)
		tri_lines.append(organic.points[v[0]]); tri_lines.append(organic.points[v[1]])
		tri_lines.append(organic.points[v[1]]); tri_lines.append(organic.points[v[2]])
		tri_lines.append(organic.points[v[2]]); tri_lines.append(organic.points[v[0]])
	_add_line_mesh(tri_lines, Color(1.0, 1.0, 0.0))


func _draw_grid_wireframe() -> void:
	var lines := PackedVector3Array()
	for quad in grid.subdivided_quads:
		var p0: Vector3 = grid.subdivided_points[quad[0]]
		var p1: Vector3 = grid.subdivided_points[quad[1]]
		var p2: Vector3 = grid.subdivided_points[quad[2]]
		var p3: Vector3 = grid.subdivided_points[quad[3]]
		lines.append(p0); lines.append(p1)
		lines.append(p1); lines.append(p2)
		lines.append(p2); lines.append(p3)
		lines.append(p3); lines.append(p0)
	_add_line_mesh(lines, Color(1.0, 1.0, 0.0))


func _draw_tile_edges() -> void:
	var lines := PackedVector3Array()
	var lift := Vector3.UP * 0.005

	for idx in range(grid.subdivided_points.size()):
		if grid.subdivided_is_outer_edge[idx]:
			continue
		var corners := grid.get_tile_corners(idx)
		if corners.size() < 3:
			continue
		for i in range(corners.size()):
			var next_i: int = (i + 1) % corners.size()
			lines.append(corners[i] + lift)
			lines.append(corners[next_i] + lift)

	_add_line_mesh(lines, Color(1.0, 1.0, 0.0))


func _draw_height_map() -> void:
	var max_h: int = 0
	for h in map_gen.height_map:
		if h > max_h:
			max_h = h

	var groups: Dictionary = {}
	for i in range(map_gen.height_map.size()):
		var h: int = map_gen.height_map[i]
		if not groups.has(h):
			groups[h] = PackedVector3Array()
		groups[h].append(grid.subdivided_points[i])

	for h in groups.keys():
		_create_point_cloud(groups[h], Color(1.0, 1.0, 0.0), 0.04)



func _draw_connectivity() -> void:
	var lines := PackedVector3Array()
	for pt_idx in grid.connectivity.keys():
		var pos: Vector3 = grid.subdivided_points[pt_idx]
		var neighbors: Array[int] = grid.connectivity[pt_idx]
		for n in neighbors:
			var n_pos: Vector3 = grid.subdivided_points[n]
			lines.append(pos + Vector3.UP * 0.01)
			lines.append(n_pos + Vector3.UP * 0.01)
	_add_line_mesh(lines, Color(1.0, 1.0, 0.0, 0.6))


# ===========================================================================
# Mesh helpers
# ===========================================================================

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
