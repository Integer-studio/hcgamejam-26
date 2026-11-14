@tool
extends Node2D

@export var fg_material: ShaderMaterial:
		set(v):
				fg_material = v
				if is_inside_tree():
						_apply(self)

func _ready() -> void:
		_apply(self)
		child_entered_tree.connect(func(n): _apply(n))

func _apply(node: Node) -> void:
		if node is CanvasItem and (node is Sprite2D or node is AnimatedSprite2D):
				node.material = fg_material
		for c in node.get_children():
				_apply(c)
