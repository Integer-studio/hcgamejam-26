extends Node

enum Trigger { HAND_TOUCHES_GROUP, PLAYER_ENTERS_AREA }

@export var trigger := Trigger.HAND_TOUCHES_GROUP
@export var touch_group := "rocks"
@export var trigger_area: Area2D
@export var play_only_once := true

@export_group("Dialog")
@export var lines: Array[String] = ["Player: Hmm... a rock.", "Player: Maybe I can climb it."]
@export var letters_per_second := 40.0
@export var text_size := 26
@export var name_size := 22

@export_group("Camera")
@export var zoom_in := 2.0
@export var zoom_time := 0.6
@export var camera_focus: Node2D
@export var focus_on_speaker := true

@export_group("Nodes")
@export var player: RigidBody2D
@export var rope: Node2D
@export var dialog_box: Control
@export var text_label: Label
@export var name_label: Label

var has_played := false
var is_playing := false
var line_index := 0
var text_tween: Tween
var in_dialog := false
var saved_velocity := Vector2.ZERO
var camera: Camera2D
var normal_zoom := Vector2.ONE


func _ready() -> void:
	if player == null:
		player = get_parent().get_node_or_null("Player")
	if rope == null:
		rope = get_parent().get_node_or_null("Rope")
	if dialog_box == null:
		dialog_box = find_child("DialogBox", true, false) as Control
	if text_label == null:
		text_label = find_child("text", true, false) as Label
	if name_label == null:
		name_label = find_child("name", true, false) as Label
	if trigger_area == null:
		for child in find_children("*", "Area2D", true, false):
			trigger_area = child
			break
	if dialog_box:
		dialog_box.visible = false
	if text_label:
		text_label.add_theme_font_size_override("font_size", text_size)
	if name_label:
		name_label.add_theme_font_size_override("font_size", name_size)
	match trigger:
		Trigger.HAND_TOUCHES_GROUP:
			rope.hand_touched.connect(_on_hand_touched)
		Trigger.PLAYER_ENTERS_AREA:
			trigger_area.body_entered.connect(_on_body_entered)


func _on_hand_touched(body: Node) -> void:
	if body != null and body.is_in_group(touch_group):
		_try_to_start()


func _on_body_entered(body: Node) -> void:
	if body == player:
		_try_to_start()


func _try_to_start() -> void:
	if is_playing or (has_played and play_only_once):
		return
	has_played = true
	_start()


func _start() -> void:
	is_playing = true
	camera = get_viewport().get_camera_2d()
	normal_zoom = camera.zoom
	saved_velocity = player.linear_velocity
	player.set_deferred("freeze", true)
	rope.start_retract()
	rope.set_process_unhandled_input(false)
	if camera_focus and "cutscene_target" in camera:
		camera.cutscene_target = camera_focus
	var tween := create_tween()
	tween.tween_property(camera, "zoom", normal_zoom * zoom_in, zoom_time).set_trans(Tween.TRANS_SINE)
	await tween.finished
	dialog_box.visible = true
	in_dialog = true
	line_index = 0
	_show_line()


func _show_line() -> void:
	var speaker_name := ""
	var text := lines[line_index]
	var colon := text.find(":")
	if colon > 0 and _find_speaker(text.substr(0, colon).strip_edges()) != null:
		speaker_name = text.substr(0, colon).strip_edges()
		text = text.substr(colon + 1).strip_edges()
	var speaker := _find_speaker(speaker_name)
	if name_label:
		name_label.text = speaker_name
		name_label.visible = speaker_name != ""
	elif speaker_name != "":
		text = speaker_name + ": " + text
	if "cutscene_target" in camera:
		if focus_on_speaker and speaker != null and speaker != player:
			camera.cutscene_target = speaker
		else:
			camera.cutscene_target = camera_focus
	text_label.text = text
	text_label.visible_ratio = 0.0
	var duration := text.length() / letters_per_second
	if text_tween:
		text_tween.kill()
	text_tween = create_tween()
	text_tween.tween_property(text_label, "visible_ratio", 1.0, duration)


func _find_speaker(speaker_name: String) -> Node2D:
	if speaker_name == "":
		return null
	if speaker_name.to_lower() == "player":
		return player
	return get_parent().find_child(speaker_name, true, false) as Node2D


func _unhandled_input(event: InputEvent) -> void:
	if not in_dialog:
		return
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		if text_label.visible_ratio < 1.0:
			if text_tween:
				text_tween.kill()
			text_label.visible_ratio = 1.0
		elif line_index < lines.size() - 1:
			line_index += 1
			_show_line()
		else:
			_end()


func _end() -> void:
	in_dialog = false
	dialog_box.visible = false
	if "cutscene_target" in camera:
		camera.cutscene_target = null
	var tween := create_tween()
	tween.tween_property(camera, "zoom", normal_zoom, zoom_time).set_trans(Tween.TRANS_SINE)
	await tween.finished
	player.freeze = false
	player.linear_velocity = saved_velocity
	rope.set_process_unhandled_input(true)
	is_playing = false
