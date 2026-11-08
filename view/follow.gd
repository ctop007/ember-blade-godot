extends Node2D
## Keeps this node at target's position (target = an ActorView in the same world space).
var target: Node2D

func _process(_dt: float) -> void:
	if is_instance_valid(target):
		position = target.position
