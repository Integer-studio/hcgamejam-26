extends Node

@export var player: RigidBody2D
@export var rope: Node2D
@export var dialog_box: Control
@export var text_label: Label
@export var lines: Array[String] = ["Hmm... a rock.", "Maybe I can climb it."]
@export var zoom_in := 2.0
@export var zoom_time := 0.6
@export var letters_per_second := 40.0

var played := false
var line_index := 0
var in_dialog := false
var saved_velocity := Vector2.ZERO
var camera: Camera2D
var normal_zoom := Vector2.ONE


func _ready() -> void:
		dialog_box.visible = false
		camera = player.get_node("Camera2D")
		normal_zoom = camera.zoom
		player.body_entered.connect(_on_player_touched)


func _on_player_touched(body: Node) -> void:
		if played or not body.is_in_group("rocks"):
				return
		played = true
		_start()


func _start() -> void:
		saved_velocity = player.linear_velocity
		player.freeze = true
		rope.start_retract()
		rope.set_process_unhandled_input(false)
		var tween := create_tween()
		tween.tween_property(camera, "zoom", normal_zoom * zoom_in, zoom_time).set_trans(Tween.TRANS_SINE)
		await tween.finished
		dialog_box.visible = true
		in_dialog = true
		line_index = 0
		_show_line()


func _show_line() -> void:
		text_label.text = lines[line_index]
		text_label.visible_ratio = 0.0
		var duration := lines[line_index].length() / letters_per_second
		create_tween().tween_property(text_label, "visible_ratio", 1.0, duration)


func _unhandled_input(event: InputEvent) -> void:
		if not in_dialog:
				return
		if event is InputEventMouseButton and event.pressed:
				get_viewport().set_input_as_handled()
				if text_label.visible_ratio < 1.0:
						text_label.visible_ratio = 1.0
				elif line_index < lines.size() - 1:
						line_index += 1
						_show_line()
				else:
						_end()


func _end() -> void:
		in_dialog = false
		dialog_box.visible = false
		var tween := create_tween()
		tween.tween_property(camera, "zoom", normal_zoom, zoom_time).set_trans(Tween.TRANS_SINE)
		await tween.finished
		player.freeze = false
		player.linear_velocity = saved_velocity
		rope.set_process_unhandled_input(true)
