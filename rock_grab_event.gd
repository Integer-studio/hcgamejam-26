extends Node

@export var rock_group := "rocks"
@export var rock_name := "Mrs Rock"
@export var rocks_ungrabbable_after := true
@export var lines: Array[String] = [
	"Mrs Rock: heeeeyy!?!?!",
	"Mrs Rock: why did you touch me???",
	"Mrs Rock: this is sexual harassment!!!! [let go]",
	"Player: Sorry :(  won't happen again",
]
@export var letters_per_second := 35.0

@export_group("Dialog Box")
@export var text_size := 26
@export var name_size := 22
@export var box_height := 140.0

@export_group("Camera")
@export var zoom_in := 1.6
@export var zoom_time := 0.5

@export_group("Nodes")
@export var player: RigidBody2D
@export var rope: Node2D

const LET_GO_TAG := "[let go]"

var has_played := false
var in_dialog := false
var line_index := 0
var text_tween: Tween
var rock: Node2D
var camera: Camera2D
var normal_zoom := Vector2.ONE
var dialog_box: PanelContainer
var name_label: Label
var text_label: Label


func _ready() -> void:
	if player == null:
		player = _find_in_level("Player") as RigidBody2D
	if rope == null:
		rope = _find_in_level("Rope") as Node2D
	_build_dialog_box()
	rope.hand_grabbed.connect(_on_hand_grabbed)


func _find_in_level(node_name: String) -> Node:
	var level := get_parent()
	while level != null:
		var found := level.get_node_or_null(node_name)
		if found:
			return found
		level = level.get_parent()
	return null


func _build_dialog_box() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	dialog_box = PanelContainer.new()
	dialog_box.anchor_left = 0.0
	dialog_box.anchor_right = 1.0
	dialog_box.anchor_top = 1.0
	dialog_box.anchor_bottom = 1.0
	dialog_box.offset_left = 20.0
	dialog_box.offset_right = -20.0
	dialog_box.offset_top = -box_height - 20.0
	dialog_box.offset_bottom = -20.0
	dialog_box.visible = false
	layer.add_child(dialog_box)
	var column := VBoxContainer.new()
	dialog_box.add_child(column)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", name_size)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	column.add_child(name_label)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("font_size", text_size)
	column.add_child(text_label)


func _on_hand_grabbed(body: Node) -> void:
	if has_played or body == null or not body.is_in_group(rock_group):
		return
	has_played = true
	rock = body as Node2D
	if rocks_ungrabbable_after:
		for each_rock in get_tree().get_nodes_in_group(rock_group):
			each_rock.add_to_group("not_grabbable")
	rope.set_process_unhandled_input(false)
	camera = get_viewport().get_camera_2d()
	normal_zoom = camera.zoom
	create_tween().tween_property(camera, "zoom", normal_zoom * zoom_in, zoom_time).set_trans(Tween.TRANS_SINE)
	in_dialog = true
	line_index = 0
	dialog_box.visible = true
	_show_line()


func _show_line() -> void:
	var text := lines[line_index]
	var let_go := text.contains(LET_GO_TAG)
	text = text.replace(LET_GO_TAG, "").strip_edges()
	var speaker_name := ""
	var speaker: Node2D = null
	var colon := text.find(":")
	if colon > 0:
		var found := _speaker_from_name(text.substr(0, colon).strip_edges())
		if found != null:
			speaker = found
			speaker_name = text.substr(0, colon).strip_edges()
			text = text.substr(colon + 1).strip_edges()
	name_label.text = speaker_name
	name_label.visible = speaker_name != ""
	if "cutscene_target" in camera:
		camera.cutscene_target = speaker if speaker != player else null
	text_label.text = text
	text_label.visible_ratio = 0.0
	if text_tween:
		text_tween.kill()
	text_tween = create_tween()
	text_tween.tween_property(text_label, "visible_ratio", 1.0, text.length() / letters_per_second)
	if let_go:
		rope.start_retract()


func _speaker_from_name(speaker_name: String) -> Node2D:
	if speaker_name.to_lower() == "player":
		return player
	if speaker_name.to_lower() == rock_name.to_lower():
		return rock
	return _find_in_level(speaker_name) as Node2D


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
	create_tween().tween_property(camera, "zoom", normal_zoom, zoom_time).set_trans(Tween.TRANS_SINE)
	rope.set_process_unhandled_input(true)
