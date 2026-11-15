extends Node
## Player sound effects. Created by rope.gd in _ready(), listens to the rope and the
## player body. Each sound type has a few variants, one is picked at random.
##   shoot      the hand is shot
##   grab       the hand grabs something (and sometimes "huh" as the pull starts)
##   ungrab     the hand lets go
##   collision  the body hits something, louder for harder hits
##   rev        the player starts falling fast (once per fall)

const SOUNDS := {
	"shoot": [preload("res://assets/sfx/shoot1.ogg"), preload("res://assets/sfx/shoot2.ogg"), preload("res://assets/sfx/shoot3.ogg")],
	"grab": [preload("res://assets/sfx/grab1.ogg"), preload("res://assets/sfx/grab3.ogg")],
	"ungrab": [preload("res://assets/sfx/ungrab1.ogg"), preload("res://assets/sfx/ungrab2.ogg"), preload("res://assets/sfx/ungrab3.ogg")],
	"huh": [preload("res://assets/sfx/huh1.ogg"), preload("res://assets/sfx/huh2.ogg"), preload("res://assets/sfx/heh3.ogg")],
	"collision": [preload("res://assets/sfx/collision1.ogg"), preload("res://assets/sfx/collision2.ogg")],
	"rev": [preload("res://assets/sfx/rev1.ogg"), preload("res://assets/sfx/rev2.ogg"), preload("res://assets/sfx/rev3.ogg")],
}

## Chance that a grab is followed by "huh".
var huh_chance := 0.35
## Minimum time between two "huh"s.
var huh_cooldown := 4.0
## Falling speed (px/s) that counts as falling; it must last fall_time.
var fall_speed := 700.0
var fall_time := 0.25
## Speed change (px/s) of a hit: below min it's silent, at max it's full volume.
var hit_speed_min := 250.0
var hit_speed_max := 1400.0
var hit_cooldown := 0.12

var rope: Node
var player: RigidBody2D

var _players := {}
var _last := {}  # sound name -> index of the variant played last (not repeated)
var _huh_timer := 0.0
var _hit_timer := 0.0
var _fall_timer := 0.0
var _rev_played := false
var _hit_this_frame := false
var _previous_velocity := Vector2.ZERO


func _ready() -> void:
	for sound_name in SOUNDS:
		var audio := AudioStreamPlayer.new()
		audio.max_polyphony = 3
		add_child(audio)
		_players[sound_name] = audio
	rope.shot.connect(func(): play("shoot"))
	rope.released.connect(func(): play("ungrab"))
	rope.hand_grabbed.connect(_on_grabbed)
	player.body_entered.connect(func(_body): _hit_this_frame = true)


func play(sound_name: String, volume_db := 0.0) -> void:
	var variants: Array = SOUNDS[sound_name]
	var index := randi() % variants.size()
	if variants.size() > 1 and index == _last.get(sound_name, -1):
		index = (index + 1) % variants.size()
	_last[sound_name] = index
	var audio: AudioStreamPlayer = _players[sound_name]
	audio.stream = variants[index]
	audio.volume_db = volume_db
	audio.pitch_scale = randf_range(0.93, 1.07)
	audio.play()


func _on_grabbed(_body: Node) -> void:
	play("grab")
	_rev_played = false
	if _huh_timer <= 0.0 and randf() < huh_chance:
		_huh_timer = huh_cooldown
		get_tree().create_timer(0.25).timeout.connect(func(): if rope.is_holding: play("huh"))


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
			play("collision", lerpf(-16.0, 0.0, t))

	if velocity.y > fall_speed and not rope.is_holding and not player.freeze:
		_fall_timer += delta
		if _fall_timer >= fall_time and not _rev_played:
			_rev_played = true
			play("rev")
	else:
		_fall_timer = 0.0
		if velocity.y < fall_speed * 0.3:
			_rev_played = false  # landed or going up: the next fall can rev again

	_previous_velocity = velocity
