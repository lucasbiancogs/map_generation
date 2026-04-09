class_name TileHover
extends Node3D

@export var _grid: BaseGrid
@export var _map_gen: MapGeneration
@export var hover_color: Color = Color(0.3, 0.6, 1.0, 0.4)

var _camera: Camera3D
var _hover_mesh: MeshInstance3D
var _hover_material: StandardMaterial3D
var _current_hover_idx: int = -1


func _ready() -> void:
	_camera = get_viewport().get_camera_3d()

	_hover_material = StandardMaterial3D.new()
	_hover_material.albedo_color = hover_color
	_hover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_hover_mesh = MeshInstance3D.new()
	_hover_mesh.visible = false
	add_child(_hover_mesh)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _current_hover_idx >= 0:
			_map_gen.toggle_point_height(_current_hover_idx)


func _physics_process(_delta: float) -> void:
	if not _grid or _grid.subdivided_points.is_empty():
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	if result.is_empty():
		_hover_mesh.visible = false
		_current_hover_idx = -1
		return

	var hit_pos: Vector3 = result["position"]
	var nearest_idx := _find_nearest_interior_point(hit_pos)

	if nearest_idx == -1:
		_hover_mesh.visible = false
		_current_hover_idx = -1
		return

	if nearest_idx != _current_hover_idx:
		_current_hover_idx = nearest_idx
		_build_tile_mesh(nearest_idx)

	_hover_mesh.visible = true


func _find_nearest_interior_point(pos: Vector3) -> int:
	var best_idx: int = -1
	var best_dist: float = INF

	for i in range(_grid.subdivided_points.size()):
		if _grid.subdivided_is_outer_edge[i]:
			continue
		var dist: float = pos.distance_squared_to(_grid.subdivided_points[i])
		if dist < best_dist:
			best_dist = dist
			best_idx = i

	return best_idx


func _build_tile_mesh(center_idx: int) -> void:
	var center := _grid.subdivided_points[center_idx]
	var corners := _grid.get_tile_corners(center_idx)

	if corners.size() < 3:
		_hover_mesh.visible = false
		return

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var lift := Vector3.UP * 0.01

	for i in range(corners.size()):
		var next_i: int = (i + 1) % corners.size()
		verts.append(center + lift)
		verts.append(corners[i] + lift)
		verts.append(corners[next_i] + lift)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arr_mesh.surface_set_material(0, _hover_material)

	_hover_mesh.mesh = arr_mesh
