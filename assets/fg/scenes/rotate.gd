extends StaticBody2D

@export var speed_deg := 90.0

func _ready() -> void:
	pass 


func _process(delta: float) -> void:
	rotation += deg_to_rad(speed_deg) * delta
	
