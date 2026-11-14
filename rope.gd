extends Node2D
@export var player: RigidBody2D
@export var hand_sprite: Node2D
@onready var line: Line2D = $Line

@export var shoot_speed := 760.0
@export var hand_gravity := 1100.0
@export var max_rope := 450.0
@export var reel_start := 60.0
@export var reel_accel := 1300.0
@export var reel_max := 950.0
@export var min_rope := 20.0
@export var rope_spring := 70.0
@export var rope_damp := 9.0
@export var max_stretch := 45.0

enum State { NONE, FLYING, DANGLING, HOOKED } 


var state := State.NONE
var hand_pos := Vector2.ZERO
var hand_vel := Vector2.ZERO
var anchor := Vector2.ZERO

var rope_len := 0.0
var reel_t := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			
			var dir := (get_global_mouse_position() - player.global_position).normalized()
			hand_pos = player.global_position
			hand_vel = dir * shoot_speed + player.linear_velocity
			state = State.FLYING
			
		else:
			state = State.NONE


func _physics_process(dt: float) -> void:
	
	match state:
		State.FLYING, State.DANGLING:
			_move_hand(dt)
			
		State.HOOKED:
			_reel(dt)
			
	_draw_rope()


func _move_hand(dt: float) -> void:
	
	var old := hand_pos
	hand_vel.y += hand_gravity * dt
	hand_pos += hand_vel * dt
	
	var q := PhysicsRayQueryParameters2D.create(old, hand_pos)
	q.exclude = [player.get_rid()]
	
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		
		anchor = hit.position + hit.normal * 2.0
		hand_pos = anchor
		rope_len = min(max_rope, player.global_position.distance_to(anchor))
		reel_t = 0.0
		state = State.HOOKED
		return


	var to_hand := hand_pos - player.global_position
	if to_hand.length() > max_rope:
		
		state = State.DANGLING
		var n := to_hand.normalized()
		
		hand_pos = player.global_position + n * max_rope
		var rel := (hand_vel - player.linear_velocity).dot(n)
		
		if rel > 0.0:
			hand_vel -= n * rel



func _reel(dt: float) -> void:
	reel_t += dt
	var speed: float = min(reel_max, reel_start + reel_accel * reel_t)
	
	var to_anchor := anchor - player.global_position
	var dist := to_anchor.length()
	
	if dist - (rope_len - speed * dt) <= max_stretch:  
		rope_len = max(min_rope, rope_len - speed * dt)
		
	var stretch := dist - rope_len
	if stretch <= 0.0 or dist < 0.001:
		return
	var dir := to_anchor / dist
	var vr := player.linear_velocity.dot(dir)
	var target := speed if rope_len > min_rope else 0.0
	var acc := rope_spring * stretch - rope_damp * (vr - target)
	if acc > 0.0:
		player.apply_central_force(dir * acc * player.mass)


func _draw_rope() -> void:
	if state == State.NONE:
		line.clear_points()
		if hand_sprite:
			hand_sprite.visible = false
			
		return
	if hand_sprite:
		hand_sprite.visible = true
		hand_sprite.global_position = hand_pos
		
	line.points = PackedVector2Array([line.to_local(player.global_position), line.to_local(hand_pos)])
