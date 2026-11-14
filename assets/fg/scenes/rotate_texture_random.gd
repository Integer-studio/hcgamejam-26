extends Sprite2D
#@export var speed_deg := 90.0
var speed_deg

func _ready() -> void:
	speed_deg = randi_range(-40,40)
	pass 


func _physics_process(delta: float) -> void:
	rotation += deg_to_rad(speed_deg) * delta
	
