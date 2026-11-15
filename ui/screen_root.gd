extends Control
## Root of crt-shader.tscn. Shows the menu or the game inside the CRT/unify viewports,
## so both get the same post-processing. Esc in the game goes back to the menu
## (the level is freed and starts fresh next time).

@export var menu_scene: PackedScene = preload("res://ui/menu.tscn")
@export var game_scene: PackedScene = preload("res://main.tscn")
## The innermost SubViewport, where the menu/game is placed.
@export var screen_path: NodePath = ^"SubViewportContainer/SubViewport/SubViewportContainer2/SubViewport"
## Background music, loops across menu and game.
@export var music: AudioStream = preload("res://assets/soundtrack.ogg")
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_volume_db := -2.0

var _current: Node
var _in_game := false


func _ready() -> void:
	_start_music()
	show_menu()


func _start_music() -> void:
	if music == null:
		return
	if "loop" in music:
		music.loop = true
	var player := AudioStreamPlayer.new()
	player.name = "Music"
	player.stream = music
	player.volume_db = music_volume_db
	add_child(player)
	player.play()


func _input(event: InputEvent) -> void:
	if _in_game and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		show_menu.call_deferred()


func show_menu() -> void:
	FaceSwap.stop()
	var menu := menu_scene.instantiate()
	menu.start_requested.connect(start_game, CONNECT_DEFERRED)
	_swap(menu)
	_in_game = false


func start_game() -> void:
	_swap(game_scene.instantiate())
	_in_game = true
	FaceSwap.start()  # every new game looks for a new face


func _swap(node: Node) -> void:
	var screen := get_node(screen_path)
	if is_instance_valid(_current):
		screen.remove_child(_current)
		_current.queue_free()
	screen.add_child(node)
	_current = node
