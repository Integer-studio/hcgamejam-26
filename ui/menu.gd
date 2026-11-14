extends Control
## Title screen: logo + blinking "press any key". Any key, mouse button or gamepad
## button emits start_requested (screen_root.gd switches to the game).

signal start_requested

## Ignore input for a moment after showing up, so the key that brought us here
## (or a held key) doesn't start the game right away.
const INPUT_DELAY := 0.3

@onready var _prompt: Label = %Prompt

var _age := 0.0
var _started := false


func _ready() -> void:
	var blink := create_tween().set_loops()
	blink.tween_property(_prompt, "modulate:a", 0.15, 0.6).set_trans(Tween.TRANS_SINE)
	blink.tween_property(_prompt, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_age += delta


func _input(event: InputEvent) -> void:
	if _started or _age < INPUT_DELAY or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_started = true
		get_viewport().set_input_as_handled()
		start_requested.emit()
