# Implementation Progress

## Grid Generation Pipeline

- [x] **Step 1 — Generate Hex Grid Points**
  Concentric hexagonal rings of points around a center. Each ring `i` has `6*(i+1)` points. Outermost ring flagged as outer edge.

- [x] **Step 2 — Construct Triangles**
  Connect adjacent rings with triangles. Subdivision points create double-triangle fans between rings.

- [x] **Step 3 — Merge Triangles into Quads**
  Randomly merge adjacent triangle pairs into quadrilaterals using a seed for reproducibility. Some triangles remain unmerged.

- [x] **Step 4 — Subdivide into Final Quads**
  Quads subdivide into 4 smaller quads; remaining triangles into 3 smaller quads. Shared edge midpoints via dictionary.

- [x] **Step 5 — Build Connectivity Info**
  For each point, record connected points (neighbors sharing a quad edge) and connected quads.

- [x] **Step 6 — Relaxation**
  Laplacian smoothing: interior points move to centroid of neighbors. Outer-edge points are pinned. Fixed iteration count.

## Tile System

- [x] **Dual-grid tile mesh construction**
  Fan-triangulated tile shapes from midpoints + quad centers, sorted by angle. `get_tile_corners()` on OrganicGrid.

- [x] **Height map**
  Integer height per grid point (0 = water, 1+ = land/cliff). Outer edge forced to 0. Assigned via Perlin noise (`MapGeneration` class).

- [ ] **Marching-squares mesh lookup**
  For each quad, read 4 corner heights. For each height transition layer, reduce to binary (above/below), compute 4-bit index (0–15), select from the 16 FBX mesh variants.

- [ ] **Layer stacking**
  Multi-height cliffs: iterate from min to max height per quad, place one mesh per layer at the corresponding vertical offset.

- [ ] **Import FBX tile assets**
  Import the 16 `Dual_Grid_*.fbx` meshes + `Water.fbx` into the Godot project.

- [ ] **Lattice deformation**
  Deform tile meshes to match the organic grid shape using 8 control points (4 bottom at grid vertices, 4 top elevated by tile height).

## Visualization

- [x] **Wireframe rendering** — Triangle edges as lines.
- [x] **Point markers** — Color-coded spheres (yellow = interior, red = outer edge).
- [x] **Tile edge wireframe** — Dual-grid tile outlines (light red).
- [x] **Visibility toggles** — UI checkboxes for wireframe, points, tile edges, connectivity.
- [x] **Tile hover preview** — Highlighted tile shape on mouse hover via raycasting.
- [ ] **Height map visualization** — Color-coded points or tiles by height value.
- [ ] **3D tile rendering** — Render stacked FBX meshes per quad based on height map.
