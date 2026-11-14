extends Control
## Height meter beside the UI mountain picture.
##   left:  your head, at the best height of this run (it never goes down)
##   right: the best height of every earlier run (with that run's face)
## Top of the mountain picture = top of the highest object in the level,
## bottom = where the player started. Runs are saved in user://runs.json,
## faces of the runs in user://run_faces/.
##
## Attach to the full-screen Control under the HUD CanvasLayer in main.tscn.
## `mountain` and `player` are found automatically when left empty.

const RUNS_PATH := "user://runs.json"
const FACES_DIR := "user://run_faces"
const DEFAULT_FACE := preload("res://assets/player/oblicej.png")

## The mountain picture (TextureRect). Empty = first TextureRect child.
@export var mountain: Control
## The player body. Empty = node "Player" in the level.
@export var player: Node2D
@export var head_height := 34.0
@export var old_head_height := 24.0
## Space between the mountain and the heads.
@export var gap := 4.0
## Only this many most recent runs are shown on the right.
@export var max_runs_shown := 40

var _start_y := 0.0
var _top_y := 0.0
var _best_height := 0.0
var _runs: Array = []
var _head: TextureRect
var _old_heads: Array[TextureRect] = []
var _player_sprite: Sprite2D
var _saved := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if mountain == null:
		for child in get_children():
			if child is TextureRect:
				mountain = child
				break
	if player == null and owner:
		player = owner.get_node_or_null("Player")
	if mountain == null or player == null:
		push_warning("HeightMeter: mountain or player not found")
		set_process(false)
		return
	for child in player.get_children():
		if child is Sprite2D:
			_player_sprite = child
			break

	_start_y = player.global_position.y
	_top_y = _find_top_y()
	_runs = _load_runs()

	for run in _runs.slice(-max_runs_shown):
		var head := _make_head(_load_face(str(run.get("face", ""))), old_head_height)
		head.modulate = Color(1, 1, 1, 0.85)
		head.set_meta("height", float(run.get("height", 0.0)))
		_old_heads.append(head)
	_head = _make_head(DEFAULT_FACE, head_height)


func _process(_delta: float) -> void:
	var height := maxf(0.0, _start_y - player.global_position.y)
	_best_height = maxf(_best_height, height)
	if _player_sprite and _head.texture != _player_sprite.texture:
		_head.texture = _player_sprite.texture  # follows the webcam face swap

	var bounds := _mountain_bounds()
	_head.position = Vector2(bounds.position.x - gap - _head.size.x, _y_for(_best_height, bounds) - _head.size.y * 0.5)

	# Old runs on the right; heads that would overlap are pushed further right.
	var taken: Array[Vector2] = []
	for head in _old_heads:
		var y := _y_for(head.get_meta("height"), bounds) - head.size.y * 0.5
		var x := bounds.end.x + gap
		for spot in taken:
			if absf(spot.y - y) < head.size.y * 0.6 and spot.x >= x:
				x = spot.x + head.size.x * 0.7
		taken.append(Vector2(x, y))
		head.position = Vector2(x, y)


func _exit_tree() -> void:
	_save_run()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_run()


# --- layout ------------------------------------------------------------------

## Screen rect of the mountain picture in this Control's space (handles its rotation/scale).
func _mountain_bounds() -> Rect2:
	var to_local := get_global_transform().affine_inverse() * mountain.get_global_transform()
	var r := Rect2(Vector2.ZERO, mountain.size)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var bounds := Rect2(to_local * (corners[0] as Vector2), Vector2.ZERO)
	for c in corners:
		bounds = bounds.expand(to_local * (c as Vector2))
	return bounds


func _y_for(height: float, bounds: Rect2) -> float:
	var full := maxf(_start_y - _top_y, 1.0)
	return lerpf(bounds.end.y, bounds.position.y, clampf(height / full, 0.0, 1.0))


func _make_head(texture: Texture2D, height: float) -> TextureRect:
	var head := TextureRect.new()
	head.texture = texture
	head.mouse_filter = MOUSE_FILTER_IGNORE
	head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var aspect := float(DEFAULT_FACE.get_width()) / DEFAULT_FACE.get_height()
	head.size = Vector2(height * aspect, height)
	add_child(head)
	return head


# --- level -------------------------------------------------------------------

## Top (smallest y) of every collision shape in the level, except the player
## and the background parallax.
func _find_top_y() -> float:
	var top := _start_y
	var level: Node = owner if owner else get_tree().current_scene
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == player or node is Parallax2D or node is CanvasLayer:
			continue
		if node is CollisionPolygon2D:
			var xf: Transform2D = node.global_transform
			for p in (node as CollisionPolygon2D).polygon:
				top = minf(top, (xf * p).y)
		elif node is CollisionShape2D and (node as CollisionShape2D).shape:
			var rect: Rect2 = (node as CollisionShape2D).shape.get_rect()
			var xf: Transform2D = node.global_transform
			for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
				top = minf(top, (xf * (p as Vector2)).y)
		stack.append_array(node.get_children())
	return top


# --- saving ------------------------------------------------------------------

func _load_runs() -> Array:
	if not FileAccess.file_exists(RUNS_PATH):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(RUNS_PATH))
	return data if data is Array else []


func _load_face(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return DEFAULT_FACE
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image else DEFAULT_FACE


func _save_run() -> void:
	if _saved or player == null:
		return
	_saved = true
	if _best_height < 1.0:
		return  # never left the start
	var time := Time.get_unix_time_from_system()
	var entry := {"height": _best_height, "time": time, "face": ""}
	var face: Texture2D = FaceSwap.face_texture
	if face:
		DirAccess.make_dir_recursive_absolute(FACES_DIR)
		var path := "%s/run_%d.png" % [FACES_DIR, int(time * 1000.0)]
		if face.get_image().save_png(path) == OK:
			entry.face = path
	_runs.append(entry)
	var file := FileAccess.open(RUNS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_runs, "\t"))
