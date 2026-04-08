## This class is designed only for debug pourposes.
class_name OrganicGridVisualizer
extends Node3D

@export var grid: OrganicGrid
@export var map_gen: MapGeneration

## Visualization toggles.
var show_grid_wireframe: bool = true
var show_points: bool = true
var show_tile_edges: bool = true
var show_connectivity: bool = false
var show_height_map: bool = false
var show_tile_layers: bool = false

## Rebuilds visualization for the grid's current step, respecting toggle flags.
func refresh() -> void:
	_clear()
	if not grid or grid.current_step == 0:
		return

	match grid.current_step:
		1:
			if show_points:
				_draw_points(grid.points, grid.is_outer_edge)
		2:
			if show_grid_wireframe:
				_draw_triangles()
			if show_points:
				_draw_points(grid.points, grid.is_outer_edge)
		3:
			if show_grid_wireframe:
				_draw_quads_and_tris()
			if show_points:
				_draw_points(grid.points, grid.is_outer_edge)
		_:
			# Steps 4+ use subdivided data.
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
			if show_tile_layers and map_gen and not map_gen.quad_tile_layers.is_empty():
				_draw_tile_layers()


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
	_create_point_cloud(inner_pos, Color(1.0, 1.0, 0.2), 0.03)
	_create_point_cloud(outer_pos, Color(1.0, 0.3, 0.2), 0.04)


func _draw_triangles() -> void:
	var lines := PackedVector3Array()
	var tri_count: int = grid.triangles.size() / 3
	for t in range(tri_count):
		var i0: int = grid.triangles[t * 3]
		var i1: int = grid.triangles[t * 3 + 1]
		var i2: int = grid.triangles[t * 3 + 2]
		lines.append(grid.points[i0]); lines.append(grid.points[i1])
		lines.append(grid.points[i1]); lines.append(grid.points[i2])
		lines.append(grid.points[i2]); lines.append(grid.points[i0])
	_add_line_mesh(lines, Color(0.3, 0.7, 1.0))


func _draw_quads_and_tris() -> void:
	var quad_lines := PackedVector3Array()
	for quad in grid.quads:
		var p0 := grid.points[quad[0]]; var p1 := grid.points[quad[1]]
		var p2 := grid.points[quad[2]]; var p3 := grid.points[quad[3]]
		quad_lines.append(p0); quad_lines.append(p1)
		quad_lines.append(p1); quad_lines.append(p2)
		quad_lines.append(p2); quad_lines.append(p3)
		quad_lines.append(p3); quad_lines.append(p0)
	_add_line_mesh(quad_lines, Color(0.2, 0.9, 0.3))

	var tri_lines := PackedVector3Array()
	for tri_idx in grid.unmergeable_triangle_indices:
		var v := grid._get_tri_vertices(tri_idx)
		tri_lines.append(grid.points[v[0]]); tri_lines.append(grid.points[v[1]])
		tri_lines.append(grid.points[v[1]]); tri_lines.append(grid.points[v[2]])
		tri_lines.append(grid.points[v[2]]); tri_lines.append(grid.points[v[0]])
	_add_line_mesh(tri_lines, Color(1.0, 0.5, 0.1))


func _draw_grid_wireframe() -> void:
	var lines := PackedVector3Array()
	for quad in grid.subdivided_quads:
		var p0 := grid.subdivided_points[quad[0]]; var p1 := grid.subdivided_points[quad[1]]
		var p2 := grid.subdivided_points[quad[2]]; var p3 := grid.subdivided_points[quad[3]]
		lines.append(p0); lines.append(p1)
		lines.append(p1); lines.append(p2)
		lines.append(p2); lines.append(p3)
		lines.append(p3); lines.append(p0)
	_add_line_mesh(lines, Color(0.2, 0.9, 0.3))


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

	_add_line_mesh(lines, Color(0.9, 0.4, 0.4))


func _draw_height_map() -> void:
	# Group points by height and draw each group with a distinct color.
	var max_h: int = 0
	for h in map_gen.height_map:
		if h > max_h:
			max_h = h

	var groups: Dictionary = {}  # height -> PackedVector3Array
	for i in range(map_gen.height_map.size()):
		var h: int = map_gen.height_map[i]
		if not groups.has(h):
			groups[h] = PackedVector3Array()
		groups[h].append(grid.subdivided_points[i])

	for h in groups.keys():
		var color: Color
		if h == 0:
			color = Color(0.2, 0.4, 0.9)  # water = blue
		elif max_h <= 1:
			color = Color(0.3, 0.8, 0.3)  # land = green
		else:
			var t: float = float(h - 1) / float(maxi(max_h - 1, 1))
			color = Color(0.3, 0.8, 0.3).lerp(Color(0.6, 0.4, 0.2), t)  # green -> brown
		_create_point_cloud(groups[h], color, 0.04)


func _draw_tile_layers() -> void:
	# Color each quad face by its bottom-layer marching-squares index.
	# Index 0 = all water (blue), index 15 = all land (green), transitions = orange/yellow.
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var lift := Vector3.UP * 0.003

	for qi in range(grid.subdivided_quads.size()):
		if qi >= map_gen.quad_tile_layers.size():
			break
		var layers: Array = map_gen.quad_tile_layers[qi]
		if layers.is_empty():
			continue

		# Use the bottom layer's mesh_index for coloring.
		var mesh_index: int = layers[0]["mesh_index"]
		var color: Color
		if mesh_index == 0:
			color = Color(0.15, 0.3, 0.7, 0.7)   # all water
		elif mesh_index == 15:
			color = Color(0.3, 0.7, 0.2, 0.7)     # all land
		else:
			color = Color(0.9, 0.7, 0.2, 0.7)     # transition

		var quad: PackedInt32Array = grid.subdivided_quads[qi]
		var p0 := grid.subdivided_points[quad[0]] + lift
		var p1 := grid.subdivided_points[quad[1]] + lift
		var p2 := grid.subdivided_points[quad[2]] + lift
		var p3 := grid.subdivided_points[quad[3]] + lift

		# Two triangles per quad.
		verts.append(p0); verts.append(p1); verts.append(p2)
		verts.append(p0); verts.append(p2); verts.append(p3)
		for _i in range(6):
			colors.append(color)
			normals.append(Vector3.UP)

	if verts.is_empty():
		return

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arr_mesh.surface_set_material(0, mat)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arr_mesh
	add_child(mesh_inst)


func _draw_connectivity() -> void:
	var lines := PackedVector3Array()
	for pt_idx in grid.connectivity.keys():
		var pos: Vector3 = grid.subdivided_points[pt_idx]
		var neighbors: Array[int] = grid.connectivity[pt_idx]
		for n in neighbors:
			var n_pos: Vector3 = grid.subdivided_points[n]
			lines.append(pos + Vector3.UP * 0.01)
			lines.append(n_pos + Vector3.UP * 0.01)
	_add_line_mesh(lines, Color(1.0, 0.2, 0.6, 0.6))


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
