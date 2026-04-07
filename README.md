# Map Generation

Procedural hexagonal map generation in Godot 4.4, based on the Unity project in `../Procedural-Generation/`.

## How it works

1. **Hex grid points** — Concentric hexagonal rings of points are generated around a center.
2. **Triangulation** — Adjacent rings are connected by triangles.
3. **Quad merging** — Triangle pairs are merged into quads (TODO).
4. **Subdivision** — Quads/triangles are subdivided into smaller quads (TODO).
5. **Relaxation** — Laplacian smoothing creates an organic look (TODO).
6. **Tile placement** — Dual-grid land/water tiles (TODO).

## Running

Open `project.godot` in Godot 4.4 and press Play.

## Project structure

```
scenes/         Main scene
scripts/        GDScript source files
assets/         Textures, materials, meshes, shaders
RESEARCH.md     Detailed analysis of the original Unity project
```
