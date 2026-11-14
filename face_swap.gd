extends Node
## Swaps the player's face for one taken from the webcam.
## start() is called every time a level starts (screen_root.gd): the player has the
## default face and a helper tries every 3 s until it finds a usable face, then the
## texture is swapped once. stop() (back in the menu) turns the camera off.
##   web:     web/face_capture.js in the browser (MediaPipe)
##   desktop: tools/face_capture/face_capture.py (Python + OpenCV via `uv run`)
## Every Sprite2D in the group "player_face" gets the new texture.

const DEFAULT_FACE := preload("res://assets/player/oblicej.png")
const GROUP := "player_face"

const JS_PATH := "res://web/face_capture.js"

const PY_DIR := "res://tools/face_capture"
const PY_OUT := "user://captured_face.png"

var face_texture: Texture2D

var _js_api: JavaScriptObject
var _callback: JavaScriptObject  # must stay referenced, or JS calls into nothing
var _pid := -1
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_poll_desktop)
	add_child(_timer)


## Forget the previous face and look for a new one.
func start() -> void:
	stop()
	face_texture = null
	if OS.has_feature("web"):
		_start_web()
	else:
		_start_desktop()


## Stop looking and turn the camera off.
func stop() -> void:
	if _js_api:
		_js_api.stop()
	_timer.stop()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1


# --- web ---------------------------------------------------------------------

func _start_web() -> void:
	if _js_api == null:
		var js := FileAccess.get_file_as_string(JS_PATH)
		if js.is_empty():
			push_warning("FaceSwap: %s missing from export (check include filter)" % JS_PATH)
			return
		JavaScriptBridge.eval(js, true)
		_js_api = JavaScriptBridge.get_interface("faceCapture")
		_callback = JavaScriptBridge.create_callback(_on_web_face_found)
	var png := DEFAULT_FACE.get_image().save_png_to_buffer()
	_js_api.start(Marshalls.raw_to_base64(png), _callback)


func _on_web_face_found(args: Array) -> void:
	var data_url := str(args[0])
	var b64 := data_url.substr(data_url.find(",") + 1)
	var image := Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		push_warning("FaceSwap: could not decode captured face")
		return
	_apply(image)


# --- desktop -----------------------------------------------------------------

func _start_desktop() -> void:
	var dir := ProjectSettings.globalize_path(PY_DIR)
	# `uv run` creates the venv and installs OpenCV on first use, so nobody has to set it up.
	var uv := _find_executable("uv")
	if uv.is_empty():
		push_warning("FaceSwap: `uv` not found, webcam face disabled (https://docs.astral.sh/uv/)")
		return
	var out := ProjectSettings.globalize_path(PY_OUT)
	DirAccess.remove_absolute(out)
	_pid = OS.create_process(uv, [
		"run", "--quiet", "--project", dir,
		"python", dir.path_join("face_capture.py"),
		"--out", out,
		"--mask", ProjectSettings.globalize_path(DEFAULT_FACE.resource_path),
		"--model", dir.path_join("face_detection_yunet_2023mar.onnx"),
		"--interval", "3",
		"--parent-pid", str(OS.get_process_id()),
	])
	if _pid <= 0:
		push_warning("FaceSwap: could not start face_capture.py")
		_pid = -1
		return
	_timer.start()


func _poll_desktop() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		return
	_timer.stop()
	_pid = -1
	var out := ProjectSettings.globalize_path(PY_OUT)
	if not FileAccess.file_exists(out):
		push_warning("FaceSwap: face_capture.py ended without a face (camera unavailable?)")
		return
	var image := Image.load_from_file(out)
	DirAccess.remove_absolute(out)
	if image == null:
		push_warning("FaceSwap: could not load captured face")
		return
	_apply(image)


func _find_executable(name: String) -> String:
	var output: Array = []
	var finder := "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(finder, [name], output) != 0 or output.is_empty():
		return ""
	return str(output[0]).strip_edges().get_slice("\n", 0).strip_edges()


func _exit_tree() -> void:
	stop()


# --- shared ------------------------------------------------------------------

func _apply(image: Image) -> void:
	face_texture = ImageTexture.create_from_image(image)
	for node in get_tree().get_nodes_in_group(GROUP):
		if node is Sprite2D:
			_swap(node)


func _swap(sprite: Sprite2D) -> void:
	sprite.texture = face_texture
	var tween := sprite.create_tween()
	sprite.modulate = Color(3, 3, 3)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.4)
