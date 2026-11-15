extends Node
## Player sound effects (scene effects/player_sfx.tscn, placed in main.tscn).
## Every sound is a child AudioStreamPlayer with an AudioStreamRandomizer, which picks
## one of the variants and randomizes the pitch. Add/remove variants in its Streams.
##   Shoot      the hand is shot
##   Grab       the hand grabs something (and sometimes Huh as the pull starts)
##   Ungrab     the hand lets go
##   Collision  the body hits something, louder for harder hits
##   Rev        the player starts falling fast (once per fall)

@export var rope: Node2D
@export var player: RigidBody2D

@export_group("Huh")
## Chance that a grab is followed by "huh".
@export_range(0.0, 1.0) var huh_chance := 0.35
## Minimum time between two "huh"s (s).
@export var huh_cooldown := 4.0
## Delay after the grab (s).
@export var huh_delay := 0.25

@export_group("Rev (falling)")
## Falling speed (px/s) that counts as falling.
@export var fall_speed := 700.0
## How long he must fall that fast before the sound plays (s).
@export var fall_time := 0.25

@export_group("Collision")
## Speed change of a hit (px/s): below this it's silent.
@export var hit_speed_min := 250.0
## Speed change of a hit (px/s) that plays at full volume.
@export var hit_speed_max := 1400.0
## Volume of the softest hit (dB).
@export var hit_quiet_db := -16.0
## Minimum time between two hit sounds (s).
@export var hit_cooldown := 0.12

@onready var _shoot: AudioStreamPlayer = $Shoot
@onready var _grab: AudioStreamPlayer = $Grab
@onready var _ungrab: AudioStreamPlayer = $Ungrab
@onready var _huh: AudioStreamPlayer = $Huh
@onready var _collision: AudioStreamPlayer = $Collision
@onready var _rev: AudioStreamPlayer = $Rev

var _huh_timer := 0.0
var _hit_timer := 0.0
var _fall_timer := 0.0
var _rev_played := false
var _hit_this_frame := false
var _previous_velocity := Vector2.ZERO


func _ready() -> void:
	rope.shot.connect(_shoot.play)
	rope.released.connect(_ungrab.play)
	rope.hand_grabbed.connect(_on_grabbed)
	player.body_entered.connect(func(_body): _hit_this_frame = true)


func _on_grabbed(_body: Node) -> void:
	_grab.play()
	_rev_played = false
	if _huh_timer <= 0.0 and randf() < huh_chance:
		_huh_timer = huh_cooldown
		get_tree().create_timer(huh_delay).timeout.connect(func(): if rope.is_holding: _huh.play())


func _physics_process(delta: float) -> void:
	_huh_timer -= delta
	_hit_timer -= delta
	var velocity := player.linear_velocity

	if _hit_this_frame:
		_hit_this_frame = false
		var hit_speed := (_previous_velocity - velocity).length()
		if _hit_timer <= 0.0 and hit_speed > hit_speed_min and not player.freeze:
			_hit_timer = hit_cooldown
			var t := clampf((hit_speed - hit_speed_min) / (hit_speed_max - hit_speed_min), 0.0, 1.0)
			_collision.volume_db = lerpf(hit_quiet_db, 0.0, t)
			_collision.play()

	if velocity.y > fall_speed and not rope.is_holding and not player.freeze:
		_fall_timer += delta
		if _fall_timer >= fall_time and not _rev_played:
			_rev_played = true
			_rev.play()
	else:
		_fall_timer = 0.0
		if velocity.y < fall_speed * 0.3:
			_rev_played = false  # landed or going up: the next fall can rev again

	_previous_velocity = velocity
