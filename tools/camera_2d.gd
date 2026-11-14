extends Camera2D

@export var speed := 1500.0
var _prev_camera: Camera2D
@onready var debug_light: PointLight2D = %DebugCamera/PointLight2D

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		if is_current():
			_prev_camera.make_current()
			debug_light.enabled = false
		else:
			_prev_camera = get_viewport().get_camera_2d()
			global_position = _prev_camera.global_position
			make_current()
			debug_light.enabled = true

func _process(delta):
	if not is_current():
		return
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# WASD by physical key position (works the same on QWERTZ/AZERTY layouts)
	var wasd := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	dir = (dir + wasd).limit_length(1.0)
	var mult := 5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	global_position += dir * speed * mult * delta
