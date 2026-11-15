extends CanvasLayer
## Anime impact frame when the player lands after falling from a big height
## (scene effects/impact_frames.tscn, placed in main.tscn).
## The fall is measured from the highest point since the player last stood on ground
## or held the rope, to where he lands. Effect: white flash -> black/white impact frame
## with speed lines around the player, the game in slow motion while it is on screen.
## The look (colors, lines, distortion) is in the Effect node's material.

@export var rope: Node2D
@export var player: RigidBody2D

## Fall height (px) that triggers the effect.
@export var min_fall_height := 900.0

@export_group("Timing")
## White flash -> impact frame (s, real time).
@export var flash_time := 0.12
## How long the impact frame stays on screen (s, real time).
@export var hold_time := 0.8
## Game speed while the impact frame is shown (1 = no slow motion).
@export_range(0.01, 1.0) var slow_motion_scale := 0.1
## Time to get back to normal speed afterwards (s, real time).
@export var speed_up_time := 0.25

@onready var _effect: ColorRect = $Effect
@onready var _material: ShaderMaterial = _effect.material

var _top_y := 0.0
var _tween: Tween


func _ready() -> void:
	_effect.visible = false
	_top_y = player.global_position.y


func _physics_process(_delta: float) -> void:
	var y := player.global_position.y
	if player.freeze or rope.is_holding:
		_top_y = y  # noclip / hanging on the rope: the fall starts from here
		return
	_top_y = minf(_top_y, y)
	if rope.time_since_on_ground == 0.0:  # standing on ground this frame
		if y - _top_y >= min_fall_height:
			play()
		_top_y = y


func play() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var center := player.get_global_transform_with_canvas().origin / screen_size
	_material.set_shader_parameter("radial_center", center)
	_material.set_shader_parameter("t", 0.0)
	_effect.visible = true

	if _tween:
		_tween.kill()
	Engine.time_scale = slow_motion_scale
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_property(_material, "shader_parameter/t", 1.0, flash_time)
	_tween.tween_interval(hold_time)
	_tween.tween_callback(_effect.hide)
	_tween.tween_property(Engine, "time_scale", 1.0, speed_up_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # leaving to the menu in the middle of the slow motion
