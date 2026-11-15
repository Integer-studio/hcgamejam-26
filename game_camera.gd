extends Camera2D

@export var target: Node2D
@export var follow_speed := 5.0
@export var look_ahead := 0.25
@export var max_look_ahead := 250.0
@export_range(0.0, 1.0) var player_screen_height := 0.66

@export_group("Landing Shake")
@export var min_fall_height := 600.0
@export var max_fall_height := 3000.0
@export var max_shake := 40.0
@export var shake_fade_speed := 1.8
@export var min_impact_speed := 700.0

var cutscene_target: Node2D = null
var rope: Node = null
var fall_start_y := 0.0
var previous_velocity := Vector2.ZERO
var shake_strength := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	if target == null:
		target = get_parent().get_node_or_null("Player")
	rope = get_parent().get_node_or_null("Rope")
	make_current()
	if target:
		global_position = target.global_position
		fall_start_y = target.global_position.y


func _physics_process(delta: float) -> void:
	var follow: Node2D = cutscene_target if cutscene_target else target
	if follow == null:
		return
	var visible_height := get_viewport_rect().size.y / zoom.y
	var wanted := follow.global_position - Vector2(0.0, (player_screen_height - 0.5) * visible_height)
	if follow is RigidBody2D and cutscene_target == null:
		wanted += ((follow as RigidBody2D).linear_velocity * look_ahead).limit_length(max_look_ahead)
	global_position = global_position.lerp(wanted, 1.0 - exp(-follow_speed * delta))
	_check_landing()
	_update_shake(delta)


func _check_landing() -> void:
	if not (target is RigidBody2D):
		return
	var body := target as RigidBody2D
	var velocity := body.linear_velocity
	var held_by_rope: bool = rope != null and rope.get("is_holding") == true
	var stopped_hard := previous_velocity.y > min_impact_speed and velocity.y < previous_velocity.y * 0.4
	if stopped_hard and not held_by_rope:
		var fall_height := body.global_position.y - fall_start_y
		if fall_height > min_fall_height:
			var amount := clampf((fall_height - min_fall_height) / (max_fall_height - min_fall_height), 0.0, 1.0)
			shake(0.35 + 0.65 * amount)
	if velocity.y <= 0.0 or held_by_rope:
		fall_start_y = body.global_position.y
	previous_velocity = velocity


func shake(amount: float) -> void:
	shake_strength = maxf(shake_strength, clampf(amount, 0.0, 1.0))


func _update_shake(delta: float) -> void:
	if shake_strength <= 0.0:
		offset = Vector2.ZERO
		return
	shake_strength = maxf(0.0, shake_strength - shake_fade_speed * delta)
	var power := shake_strength * shake_strength * max_shake
	offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * power
