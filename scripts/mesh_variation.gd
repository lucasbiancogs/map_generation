class_name MeshVariation
extends Node3D

## Picks one child node deterministically based on a seed and frees the others.
## Add mesh variations as children — one will be kept at runtime.
## Set variation_seed before adding to the scene tree.

var variation_seed: int = 0

func _ready() -> void:
	var children := get_children()
	if children.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	var keep_idx: int = rng.randi() % children.size()
	for i in range(children.size()):
		if i != keep_idx:
			children[i].queue_free()
