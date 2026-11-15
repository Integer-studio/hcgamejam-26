extends Control
## Title screen: logo + blinking "press any key". Any key, mouse button or gamepad
## button emits start_requested (screen_root.gd switches to the game).

signal start_requested

## Ignore input for a moment after showing up, so the key that brought us here
## (or a held key) doesn't start the game right away.
const INPUT_DELAY := 0.3

@onready var _prompt: Label = %Prompt

const CAMERA_CHECK_JS := """
window.__cameraState = 'asking';
window.__checkCamera = function () {
	if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
		window.__cameraState = 'insecure';
		return;
	}
	window.__cameraState = 'asking';
	navigator.mediaDevices.getUserMedia({ video: true })
		.then(function (stream) {
			stream.getTracks().forEach(function (track) { track.stop(); });
			window.__cameraState = 'ready';
		})
		.catch(function (error) { window.__cameraState = (error && error.name) || 'error'; });
};
window.__checkCamera();
"""
const CAMERA_MESSAGES := {
	"asking": "ALLOW CAMERA ACCESS TO PLAY",
	"NotAllowedError": "CAMERA BLOCKED - ALLOW IT IN THE BROWSER, THEN CLICK",
	"NotFoundError": "NO CAMERA FOUND - CONNECT ONE, THEN CLICK",
	"NotReadableError": "CAMERA IS USED BY ANOTHER APP - CLOSE IT, THEN CLICK",
	"insecure": "THE CAMERA NEEDS HTTPS OR LOCALHOST",
}
const READY_TEXT := "PRESS ANY KEY"

var _age := 0.0
var _started := false
var _needs_camera := OS.has_feature("web")
var _camera_ready := not OS.has_feature("web")
var _check_timer := 0.0


func _ready() -> void:
	if _needs_camera:
		JavaScriptBridge.eval(CAMERA_CHECK_JS, true)
		_update_camera_state()
	var blink := create_tween().set_loops()
	blink.tween_property(_prompt, "modulate:a", 0.15, 0.6).set_trans(Tween.TRANS_SINE)
	blink.tween_property(_prompt, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_age += delta
	if _needs_camera and not _camera_ready:
		_check_timer -= delta
		if _check_timer <= 0.0:
			_check_timer = 0.3
			_update_camera_state()


func _update_camera_state() -> void:
	var state := str(JavaScriptBridge.eval("window.__cameraState", true))
	_camera_ready = state == "ready"
	if _camera_ready:
		_prompt.text = READY_TEXT
	else:
		_prompt.text = CAMERA_MESSAGES.get(state, "CAMERA NOT AVAILABLE - CLICK TO TRY AGAIN")


func _input(event: InputEvent) -> void:
	if _started or _age < INPUT_DELAY or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if not _camera_ready:
			var state := str(JavaScriptBridge.eval("window.__cameraState", true))
			if state != "asking":
				JavaScriptBridge.eval("window.__checkCamera()", true)
				_update_camera_state()
			return
		_started = true
		get_viewport().set_input_as_handled()
		start_requested.emit()
