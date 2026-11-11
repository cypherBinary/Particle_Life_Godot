extends Camera2D

@export var move_speed := 1000.0
@export var shift_multiplier := 3.0
@export var zoom_speed := 1.15
@export var min_zoom := 0.1
@export var max_zoom := 5.0

func _process(dt: float) -> void:
	var direction := Vector2(
		(Input.is_key_pressed(KEY_D) as float) - (Input.is_key_pressed(KEY_A) as float),
		(Input.is_key_pressed(KEY_S) as float) - (Input.is_key_pressed(KEY_W) as float)
	)

	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	var speed := move_speed

	if Input.is_key_pressed(KEY_SHIFT):
		speed *= shift_multiplier

	position += direction * speed * dt

	if Input.is_key_pressed(KEY_E):
		zoom *= pow(zoom_speed, dt * 10.0)

	if Input.is_key_pressed(KEY_Q):
		zoom /= pow(zoom_speed, dt * 10.0)

	zoom.x = clamp(zoom.x, min_zoom, max_zoom)
	zoom.y = clamp(zoom.y, min_zoom, max_zoom)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom *= zoom_speed

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom /= zoom_speed

		zoom.x = clamp(zoom.x, min_zoom, max_zoom)
		zoom.y = clamp(zoom.y, min_zoom, max_zoom)
