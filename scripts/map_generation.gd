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
	{"name_map": "Water", "index_map": [{"index": 0000, "rotation": 0}]},
	{"name_map": "Dual_Grid_L_L_L_L", "index_map": [{"index": 1111, "rotation": 0}]},
	{"name_map": "Dual_Grid_L_W_W_W", "index_map": [{"index": 1000, "rotation": 0}, {"index": 0100, "rotation": 1}, {"index": 0010, "rotation": 2}, {"index": 0001, "rotation": 3}]},
	{"name_map": "Dual_Grid_L_L_L_W", "index_map": [{"index": 1110, "rotation": 0}, {"index": 0111, "rotation": 1}, {"index": 1011, "rotation": 2}, {"index": 1101, "rotation": 3}]},
	{"name_map": "Dual_Grid_L_L_W_W", "index_map": [{"index": 1100, "rotation": 0}, {"index": 0110, "rotation": 1}, {"index": 0011, "rotation": 2}, {"index": 1001, "rotation": 3}]},
	{"name_map": "Dual_Grid_L_W_L_W", "index_map": [{"index": 1010, "rotation": 0}, {"index": 0101, "rotation": 1}]},
]

## Loaded tile scenes: scene_name -> PackedScene.
var _tile_scenes: Dictionary = {}
## Runtime lookup: marching-squares index (0-15) -> {scene_name: String, rotation: int}.
var _tile_lookup: Dictionary = {}
## Container node for placed tile instances.
var _tiles_container: Node3D
## Per-quad canonical vertex order [TL, TR, BR, BL] based on spatial position.
var _quad_canonical_corners: Array[PackedInt32Array] = []
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
		var scene_name: String = tile_def["name_map"]
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
		var scene_name: String = tile_def["name_map"]
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
	_compute_quad_canonical_order()


## Computes per-quad canonical vertex ordering and rotation offsets.
## Sorts each quad's vertices into spatial [TL, TR, BR, BL] order by angle from center,
## starting from the vertex closest to the -135° reference (top-left direction).
## This ensures the marching-squares index bits correspond to consistent corner positions
## regardless of how the quad was originally constructed.
func _compute_quad_canonical_order() -> void:
	var ref_angle := -PI * 3.0 / 4.0  # -135°: direction from center to TL
	_quad_canonical_corners.clear()
	_quad_rotation_offsets.resize(grid.subdivided_quads.size())

	for qi in range(grid.subdivided_quads.size()):
		var quad: PackedInt32Array = grid.subdivided_quads[qi]
		var center := (grid.subdivided_points[quad[0]] + grid.subdivided_points[quad[1]]
			+ grid.subdivided_points[quad[2]] + grid.subdivided_points[quad[3]]) * 0.25

		# Compute angle from center for each vertex.
		var angles: Array[float] = []
		for i in range(4):
			var dir := grid.subdivided_points[quad[i]] - center
			angles.append(atan2(dir.z, dir.x))

		# Sort vertex indices by angle ascending (CCW order).
		var sorted_indices: Array[int] = [0, 1, 2, 3]
		sorted_indices.sort_custom(func(a: int, b: int) -> bool:
			return angles[a] < angles[b]
		)

		# Find which sorted position is closest to the reference angle.
		var best_start: int = 0
		var best_diff: float = INF
		for i in range(4):
			var d: float = absf(_wrap_angle(angles[sorted_indices[i]] - ref_angle))
			if d < best_diff:
				best_diff = d
				best_start = i

		# Build canonical order starting from TL, going CCW: TL, TR, BR, BL.
		var canonical := PackedInt32Array()
		canonical.resize(4)
		for i in range(4):
			canonical[i] = quad[sorted_indices[(best_start + i) % 4]]
		_quad_canonical_corners.append(canonical)

		# Rotation offset: how many 90° steps the TL vertex is from the reference.
		var tl_angle: float = angles[sorted_indices[best_start]]
		var diff := fmod(tl_angle - ref_angle, TAU)
		if diff < 0.0:
			diff += TAU
		_quad_rotation_offsets[qi] = roundi(diff / (PI * 0.5)) % 4


## Wraps an angle difference to the range [-PI, PI].
func _wrap_angle(angle: float) -> float:
	return fmod(angle + PI, TAU) - PI


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
		var corners: PackedInt32Array = _quad_canonical_corners[qi]
		var h0: int = height_map[corners[0]]
		var h1: int = height_map[corners[1]]
		var h2: int = height_map[corners[2]]
		var h3: int = height_map[corners[3]]

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


## Places tile scenes at quad centers, deforming meshes to fit each quad's shape.
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

			var tile: Node3D = _tile_scenes[scene_name].instantiate()
			tile.position = center + Vector3.UP * layer * layer_height
			_set_variation_seeds(tile, qi * 97 + layer * 31)
			_tiles_container.add_child(tile)
			_deform_tile_to_quad(tile, qi, rotation_steps)


# ===========================================================================
# Lattice deformation — warp tile meshes to fit irregular quad shapes
# ===========================================================================

## Deforms all meshes within a tile to match the quad's actual corner positions.
## Uses bilinear interpolation in XZ to map the mesh's AABB corners to the quad
## corners, with rotation_steps shifting which AABB corner maps to which quad corner.
func _deform_tile_to_quad(tile: Node3D, qi: int, rotation_steps: int) -> void:
	var canonical: PackedInt32Array = _quad_canonical_corners[qi]
	var quad: PackedInt32Array = grid.subdivided_quads[qi]
	var center := (grid.subdivided_points[quad[0]] + grid.subdivided_points[quad[1]]
		+ grid.subdivided_points[quad[2]] + grid.subdivided_points[quad[3]]) * 0.25

	# Build target XZ corners in tile local space (tile is at center, no rotation).
	# AABB corner order: [TL(min_x,min_z), TR(max_x,min_z), BR(max_x,max_z), BL(min_x,max_z)]
	# rotation_steps shifts which canonical corner each AABB corner maps to.
	var target_xz: Array[Vector3] = []
	for i in range(4):
		var canon_idx: int = (i - rotation_steps + 4) % 4
		target_xz.append(grid.subdivided_points[canonical[canon_idx]] - center)

	# Collect all MeshInstance3D nodes in the tile.
	var mesh_instances: Array[MeshInstance3D] = []
	_find_mesh_instances(tile, mesh_instances)
	if mesh_instances.is_empty():
		return

	# Compute a combined AABB in the tile root's local space.
	var ref_aabb := _compute_combined_aabb(tile, mesh_instances)

	# Deform each mesh.
	for mi in mesh_instances:
		_deform_mesh_instance(mi, tile, ref_aabb, target_xz)


## Sets variation_seed on all MeshVariation nodes in the tile before it enters the tree.
func _set_variation_seeds(node: Node, base_seed: int) -> void:
	if node is MeshVariation:
		node.variation_seed = base_seed
	for child in node.get_children():
		_set_variation_seeds(child, base_seed)


## Recursively finds all MeshInstance3D nodes under the given node.
func _find_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_mesh_instances(child, result)


## Computes the combined AABB of all mesh instances in the tile root's local space.
func _compute_combined_aabb(tile_root: Node3D, instances: Array[MeshInstance3D]) -> AABB:
	var combined := AABB()
	var first := true

	for mi in instances:
		var mesh: Mesh = mi.mesh
		if not mesh:
			continue
		var mi_to_tile: Transform3D = tile_root.global_transform.affine_inverse() * mi.global_transform
		var mesh_aabb: AABB = mesh.get_aabb()
		for corner_idx in range(8):
			var corner: Vector3 = mesh_aabb.get_endpoint(corner_idx)
			var tile_pos: Vector3 = mi_to_tile * corner
			if first:
				combined = AABB(tile_pos, Vector3.ZERO)
				first = false
			else:
				combined = combined.expand(tile_pos)

	return combined


## Deforms a single MeshInstance3D using bilinear interpolation in XZ.
func _deform_mesh_instance(mi: MeshInstance3D, tile_root: Node3D,
		ref_aabb: AABB, target_xz: Array[Vector3]) -> void:
	var src_mesh: Mesh = mi.mesh
	if not src_mesh:
		return

	var mi_to_tile: Transform3D = tile_root.global_transform.affine_inverse() * mi.global_transform
	var tile_to_mi: Transform3D = mi_to_tile.affine_inverse()

	var new_mesh := ArrayMesh.new()

	for surf_idx in range(src_mesh.get_surface_count()):
		var arrays: Array = src_mesh.surface_get_arrays(surf_idx)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var new_vertices := PackedVector3Array()
		new_vertices.resize(vertices.size())

		for vi in range(vertices.size()):
			var tile_pos: Vector3 = mi_to_tile * vertices[vi]

			# Normalize XZ within the reference AABB.
			var u: float = 0.5
			var w: float = 0.5
			if ref_aabb.size.x > 0.001:
				u = clampf((tile_pos.x - ref_aabb.position.x) / ref_aabb.size.x, 0.0, 1.0)
			if ref_aabb.size.z > 0.001:
				w = clampf((tile_pos.z - ref_aabb.position.z) / ref_aabb.size.z, 0.0, 1.0)

			# Bilinear interpolation: target_xz = [TL, TR, BR, BL]
			var new_xz: Vector3 = (
				target_xz[0] * (1.0 - u) * (1.0 - w) +
				target_xz[1] * u * (1.0 - w) +
				target_xz[3] * (1.0 - u) * w +
				target_xz[2] * u * w
			)

			var deformed: Vector3 = Vector3(new_xz.x, tile_pos.y, new_xz.z)
			new_vertices[vi] = tile_to_mi * deformed

		arrays[Mesh.ARRAY_VERTEX] = new_vertices
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mat: Material = src_mesh.surface_get_material(surf_idx)
		if mat:
			new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, mat)

	mi.mesh = new_mesh
