extends StaticBody2D

@export var speed_deg := 90.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	rotation += deg_to_rad(speed_deg) * delta
	
