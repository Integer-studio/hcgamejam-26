extends Camera2D

@export var target: Node2D
@export var follow_speed := 5.0
@export var look_ahead := 0.25
@export var max_look_ahead := 250.0
@export_range(0.0, 1.0) var player_screen_height := 0.66

var cutscene_target: Node2D = null


func _ready() -> void:
	if target == null:
		target = get_parent().get_node_or_null("Player")
	make_current()
	if target:
		global_position = target.global_position


func _physics_process(delta: float) -> void:
	var follow: Node2D = cutscene_target if cutscene_target else target
	if follow == null:
		return
	var visible_height := get_viewport_rect().size.y / zoom.y
	var wanted := follow.global_position - Vector2(0.0, (player_screen_height - 0.5) * visible_height)
	if follow is RigidBody2D and cutscene_target == null:
		wanted += ((follow as RigidBody2D).linear_velocity * look_ahead).limit_length(max_look_ahead)
	global_position = global_position.lerp(wanted, 1.0 - exp(-follow_speed * delta))
