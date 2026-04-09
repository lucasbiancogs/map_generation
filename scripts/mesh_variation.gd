class_name MeshVariation
extends Node3D

## Randomly picks one child node and frees the others.
## Add mesh variations as children — one will be kept at runtime.

func _ready() -> void:
	var children := get_children()
	if children.is_empty():
		return

	var keep_idx: int = randi() % children.size()
	for i in range(children.size()):
		if i != keep_idx:
			children[i].queue_free()
