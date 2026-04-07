# Procedural Map Generation - Research Document

Research based on the Unity project at `../Procedural-Generation/`.

---

## 1. Project Overview

- **Engine:** Unity 6000.0.58f1 with URP (Universal Render Pipeline)
- **Language:** C#
- **Core Concept:** Hexagonal grid composed of merged patches, where each cell is a quad. Tiles (land/water) are placed on grid points using a dual-grid approach. 3D tile meshes are deformed via lattice modifiers to conform to the grid geometry.

---

## 2. Grid Creation Algorithm

The grid is built in layers. Multiple hexagonal **patches** are created independently, then **merged** into a single seamless grid.

### 2.1 Single Patch Construction

Each patch goes through these steps (implemented in `HexagridUtils.cs`):

#### Step 1 — Generate Hexagon Grid Points

Concentric hexagonal rings of points are generated around a center:

- **Ring 0:** Single center point at origin.
- **Ring N (1..iterations):** 6 × N points arranged along the edges of a hexagon.
  - Hex vertices at angles: 0°, 60°, 120°, 180°, 240°, 300° (offset by +30°).
  - Subdivision points interpolated between vertices.
- Points on the outermost ring are flagged `IsOnOuterEdge = true`.

**Parameters:**
- `hexagonSize` (0.5–20, default 1): distance from center to hex vertex.
- `iterationsCount` (1–10, default 1): number of concentric rings.

#### Step 2 — Construct Triangles

Adjacent rings are connected by triangles:
- Triangles fan from inner ring points to outer ring points.
- Each hexagon edge subdivision creates pairs of triangles.

#### Step 3 — Merge Triangles into Quads

Adjacent triangle pairs are randomly merged into quadrilaterals:
- Uses `randomizationSeed` for reproducibility.
- Some triangles remain unmerged if they lack an adjacent pair.

#### Step 4 — Subdivide into Final Quads

Each shape is subdivided:
- **Quads → 4 smaller quads** (center point + 4 edge midpoints).
- **Remaining triangles → 3 smaller quads** (center point + 3 edge midpoints).
- Edge midpoints are shared via a dictionary to prevent duplicates.
- A midpoint is flagged `IsOnOuterEdge` only if **both** endpoints are outer-edge points.

#### Step 5 — Build Connectivity Info

For each point, record:
- **Connected points:** neighbors sharing a quad edge (max 8).
- **Connected quads:** quads that share this point as a vertex (max 8).

#### Step 6 — Relaxation (see Section 4)

#### Step 7 — Apply World Offset

Translate all points by the patch's world-space center position.

### 2.2 Patch Merging

Multiple patches form a grid (e.g., 3×3):

1. Each patch is generated independently.
2. Shared outer-edge points between adjacent patches are identified (by proximity).
3. Duplicate points are merged; quad indices are remapped to the global point list.
4. Points that are no longer on the global boundary lose their `IsOnOuterEdge` flag.
5. Relaxation is applied again to the merged grid for global smoothing.

### 2.3 Data Structures

```
Point {
    Position: Vector3       // World position (x, y=0, z)
    IsOnOuterEdge: bool     // Boundary flag — fixed during relaxation
}

Quad {
    FirstVertexIndex: int
    SecondVertexIndex: int
    ThirdVertexIndex: int
    FourthVertexIndex: int
}

Triangle {
    FirstVertexIndex: int
    SecondVertexIndex: int
    ThirdVertexIndex: int
}

GridData {
    GridPoints: Point[]
    GridQuads: Quad[]
    GridPointsConnectivityInfos: GridPointConnectivityInfo[]
}

GridPointConnectivityInfo {
    PointID: int
    ConnectedPointsIDs: int[]   // max 8
    ConnectedQuadsIDs: int[]    // max 8
}
```

### 2.4 Grid Configuration

| Parameter | Range | Default | Effect |
|-----------|-------|---------|--------|
| `horizontalHexagonCount` | — | 3 | Patches across X |
| `verticalHexagonCount` | — | 3 | Patches across Z |
| `hexagonSize` | 0.5–20 | 1 | Patch scale |
| `iterationsCount` | 1–10 | 1 | Rings per patch |
| `relaxationIterationsCount` | 0–200 | 3 | Smoothing passes |
| `randomizationSeed` | — | 0 | Seed for triangle merging |

---

## 3. Assets

### 3.1 Tile Meshes (FBX)

Located in `Assets/Visuals/Meshes/Tiles_For_Placement/`. This is a **dual-grid** system — tile meshes are placed on grid **points** (not quads). Each tile mesh represents a specific corner configuration:

**Naming convention:** `Dual_Grid_[C1]_[C2]_[C3]_[C4].fbx` where each corner is `L` (land) or `W` (water).

All 16 combinations exist as FBX files:
- `Dual_Grid_L_L_L_L.fbx` — fully land
- `Dual_Grid_L_L_L_W.fbx` — 3 land, 1 water corner
- `Dual_Grid_L_L_W_W.fbx` — 2 adjacent land, 2 adjacent water
- `Dual_Grid_L_W_L_W.fbx` — alternating (diagonal)
- `Dual_Grid_L_W_W_W.fbx` — 1 land, 3 water
- ... (and rotational variants)
- `Water.fbx` — flat water plane

Each mesh has a default lattice height of `2.6` units and is deformed at runtime by a **lattice modifier** (8 control points forming a cube) to conform to the irregular grid shape.

### 3.2 Textures

| File | Size | Usage |
|------|------|-------|
| `Grass.png` | 3.6 MB | Land tile surface |
| `Water_Normal_Map.jpeg` | 327 KB | Water wave normals |
| `Skybox.png` | 4.0 MB | Sky background |

### 3.3 Materials

| Material | Purpose |
|----------|---------|
| `Grass.mat` | Land tiles (uses Grass.png) |
| `Water.mat` | Water tiles (uses Water_Normal_Map.jpeg + shader graph) |
| `Dual_Grid.mat` | Grid line visualization overlay |
| `Rocks.mat` | Rock/detail elements |
| `Raycast_Preview.mat` | Hover highlight |
| `Skybox.mat` | Skybox |

### 3.4 Shaders

- **GridVisualization.shader** — Renders grid lines using UV-based edge detection. Properties: InsideColor, EdgeColor, EdgeWidth. Uses alpha blending.
- **Water.shadergraph** — Animated water with Gerstner waves, custom lighting, depth fade, refraction, and panning UVs.
- Supporting HLSL: `Gerstner_Waves.hlsl`, `Custom_Lighting.hlsl`, `HSV_Lerp.hlsl`.
- Supporting subgraphs: `Blended_Normals`, `Depth_Fade`, `Panning_UVs`, `Refracted_UVs`, `Scene_Position`.

---

## 4. Relaxation Algorithm

### 4.1 What It Is

**Laplacian smoothing** — each interior point moves to the centroid (average position) of its connected neighbors. This transforms the rigid hexagonal geometry into a more organic, natural-looking grid.

### 4.2 Algorithm (Pseudocode)

```
for iteration in 0..relaxationIterationsCount:
    for each point in grid:
        if point.IsOnOuterEdge:
            skip  // boundary points are FIXED

        neighbors = connectivityInfo[point]
        avgPosition = average(neighbors[i].Position for all i)
        point.Position = avgPosition
```

### 4.3 Key Properties

| Property | Value |
|----------|-------|
| **Type** | Laplacian smoothing |
| **Boundary handling** | Outer-edge points are pinned (never moved) |
| **Convergence** | No explicit check — runs a fixed number of iterations |
| **Neighborhood** | Direct edge-connected points (from quad edges) |
| **Iteration count** | 0–200 (configurable) |
| **Application** | Applied twice: once per-patch (usually 0 iterations), once on the merged global grid |
| **Effect** | Low iterations → subtle smoothing; high iterations → very uniform cell sizes but grid loses hexagonal character |

### 4.4 Why It Works

The connectivity from Step 5 means each interior point typically has 3–4 neighbors (from adjacent quads). Moving each point to the average of its neighbors:
- Eliminates sharp angles and irregular spacing.
- Tends toward equal edge lengths within the interior.
- Preserves the overall boundary shape (outer-edge points are fixed).
- Creates the organic, slightly irregular look typical of procedural maps.

---

## 5. Tile Placement System

### 5.1 Dual-Grid Concept

The grid has two layers:
1. **Primary grid:** The quad mesh (used for structure and visualization).
2. **Dual grid:** Tiles are centered on grid **points**, not quads. Each tile's corners extend to the midpoints of connected edges and centers of connected quads.

### 5.2 Tile Mesh Construction

For each grid point (tile center):
1. Compute midpoints between center and each connected point.
2. Compute centers of each connected quad.
3. Interleave these to form corner points.
4. Sort corner points by angle from center.
5. Triangulate as a fan from center to sorted corners.

### 5.3 Tile Types

Only two types: `WATER` (0) and `LAND` (1).

The mesh selected for rendering depends on the 4 neighboring tile types (the quad's corner point types), giving the `Dual_Grid_[L/W]_[L/W]_[L/W]_[L/W]` naming scheme.

### 5.4 Lattice Deformation

3D tile meshes are deformed to match the grid shape:
- 8 control points form a bounding cube around each tile position.
- 4 bottom points = grid vertex positions at ground level.
- 4 top points = same positions elevated by `TILE_LATTICE_DEFAULT_HEIGHT` (2.6).
- The lattice modifier warps the FBX mesh vertices to fit between these control points.

### 5.5 Placement Rules

- Only interior points (not on outer edge) can receive tiles.
- First tile can be placed anywhere.
- Subsequent tiles must be adjacent to already-placed tiles.
- Max 3 tiles can be selected/previewed simultaneously.

---

## 6. Grid Visualization

- Each quad is subdivided into 4 triangles (from quad center) for rendering.
- **UV mapping:** X channel = edge detection (0 at center, 1 at vertices); Y channel = outer-edge masking.
- The `GridVisualization.shader` uses UV.x to draw lines at quad edges and UV.y to fade out boundary edges.
- A separate mesh collider is built from the grid quads for mouse-based raycasting.

---

## 7. Key Source Files

| File | Purpose |
|------|---------|
| `Scripts/Grids/Hexagrid/HexagridUtils.cs` | Core grid generation algorithm |
| `Scripts/Grids/Hexagrid/HexagridConstruction.cs` | Grid constructor (merges patches) |
| `Scripts/Grids/Hexagrid/HexagridPatch.cs` | Single patch creator |
| `Scripts/Grids/GridData.cs` | Grid data container |
| `Scripts/Grids/Point.cs` | Point struct |
| `Scripts/Grids/Quad.cs` | Quad struct |
| `Scripts/Grids/GridPointConnectivityInfo.cs` | Connectivity data |
| `Scripts/Grids/Hexagrid/Triangle.cs` | Triangle struct |
| `Scripts/Grids/GridVisualizer.cs` | Grid mesh visualization |
| `Scripts/Tile_Placement/TilePlacementController.cs` | Tile placement logic |
| `Scripts/Tile_Placement/TileMeshData.cs` | Tile mesh construction |
| `Scripts/Tile_Rendering/TilesRenderingManager.cs` | Tile rendering + lattice deformation |
| `Scripts/Mesh_Modification/LatticeModifier.cs` | Lattice deformation math |
| `Visuals/Shaders/GridVisualization.shader` | Grid line shader |
