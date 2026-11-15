extends Node

@export var win_image: Texture2D
@export var target_name := "Kyf"
@export var target: Node2D
@export var play_again_text := "PLAY AGAIN"
@export var fade_time := 1.2
@export var wait_before_continue := 1.0

@export_group("Nodes")
@export var player: RigidBody2D
@export var rope: Node2D

var has_won := false
var can_continue := false
var screen: ColorRect
var prompt: Label


func _ready() -> void:
	if player == null:
		player = _find_in_level("Player") as RigidBody2D
	if rope == null:
		rope = _find_in_level("Rope") as Node2D
	if target == null:
		target = get_parent().find_child(target_name, true, false) as Node2D
	if win_image == null:
		win_image = load("res://assets/ui/you_won.png")
	rope.hand_touched.connect(_on_hand_touched)
	rope.hand_grabbed.connect(_on_hand_touched)


func _find_in_level(node_name: String) -> Node:
	var level := get_parent()
	while level != null:
		var found := level.get_node_or_null(node_name)
		if found:
			return found
		level = level.get_parent()
	return null


func _player_face() -> Texture2D:
	for child in player.get_children():
		if child is Sprite2D and child.texture:
			return child.texture
	return null


func _build_screen() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	screen = ColorRect.new()
	screen.color = Color.BLACK
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.modulate.a = 0.0
	layer.add_child(screen)

	var title := _picture(win_image, 1.0)
	var title_width := screen_size.x * 0.66
	title.size = Vector2(title_width, title_width * win_image.get_height() / win_image.get_width())
	title.position = Vector2((screen_size.x - title_width) * 0.5, screen_size.y * 0.03)
	screen.add_child(title)

	var face_texture := _player_face()
	if face_texture:
		var face := Sprite2D.new()
		face.texture = face_texture
		var face_height := screen_size.y * 0.34
		face.scale = Vector2.ONE * face_height / face_texture.get_height()
		face.position = screen_size * 0.5
		screen.add_child(face)

	prompt = Label.new()
	prompt.text = play_again_text
	var settings := LabelSettings.new()
	settings.font_size = 32
	settings.outline_size = 6
	settings.outline_color = Color.BLACK
	prompt.label_settings = settings
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.size = Vector2(screen_size.x, 50.0)
	prompt.position = Vector2(0.0, screen_size.y * 0.8)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(prompt)
	var blink := create_tween().set_loops()
	blink.tween_property(prompt, "modulate:a", 0.15, 0.6).set_trans(Tween.TRANS_SINE)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


func _picture(texture: Texture2D, share: float) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.size_flags_stretch_ratio = share
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _show_height_meter_on_top() -> void:
	var level := get_parent()
	for control in level.find_children("*", "Control", true, false):
		var script: Script = control.get_script()
		if script and script.resource_path.ends_with("height_meter.gd"):
			var layer := control.get_parent()
			while layer != null and not (layer is CanvasLayer):
				layer = layer.get_parent()
			if layer:
				(layer as CanvasLayer).layer = 21
			return


func _on_hand_touched(body: Node) -> void:
	if has_won or body == null or target == null:
		return
	if body != target and not target.is_ancestor_of(body):
		return
	_win()


func _win() -> void:
	has_won = true
	player.set_deferred("freeze", true)
	rope.set_process_unhandled_input(false)
	_build_screen()
	_show_height_meter_on_top()
	var tween := create_tween()
	tween.tween_property(screen, "modulate:a", 1.0, fade_time)
	await tween.finished
	await get_tree().create_timer(wait_before_continue).timeout
	can_continue = true


func _unhandled_input(event: InputEvent) -> void:
	if not can_continue:
		return
	var pressed := (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	can_continue = false
	var node: Node = self
	while node != null:
		if node.has_method("start_game"):
			node.start_game.call_deferred()
			return
		node = node.get_parent()
	get_tree().reload_current_scene()
