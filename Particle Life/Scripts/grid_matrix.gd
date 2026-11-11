class_name RuleMatrix
extends Control

signal rule_changed(input_type: int, target_type: int, value: float)

var rules: PackedFloat32Array
var particle_types: int = 3
var type_colors: Dictionary = {}

var cell_size := 35.0
var label_size := 15.0
var font_size := 14
var cell_gap := 2.0


func setup(
	type_count: int,
	initial_rules: PackedFloat32Array,
	colors: Dictionary
) -> void:
	particle_types = type_count
	rules = initial_rules
	type_colors = colors

	custom_minimum_size = Vector2(
		label_size + particle_types * (cell_size + cell_gap),
		label_size + particle_types * (cell_size + cell_gap)
	)

	queue_redraw()

func _draw() -> void:
	if rules.size() != particle_types * particle_types:
		return

	var font := ThemeDB.fallback_font

	# Column headers: target particle types.
	for target in range(particle_types):
		var x := label_size + target * (cell_size + cell_gap)
		draw_circle(
			Vector2(x + cell_size / 2.0, label_size / 2.0),
			6.0,
			type_colors[target % type_colors.size()],
			true,
			-1,
			true
		)

	# Row headers: input particle types.
	for input_type in range(particle_types):
		var y := label_size + input_type * (cell_size + cell_gap)
		draw_circle(
			Vector2(label_size / 2.0, y + cell_size / 2.0),
			6.0,
			type_colors[input_type % type_colors.size()],
			true,
			-1,
			true
		)

	# Rule cells.
	for input_type in range(particle_types):
		for target in range(particle_types):
			var index := input_type * particle_types + target
			var value := rules[index]

			var x := label_size + target * (cell_size + cell_gap)
			var y := label_size + input_type * (cell_size + cell_gap)
			var rect := Rect2(x, y, cell_size, cell_size)

			draw_rect(rect, _value_color(value), true)
			draw_rect(rect, Color(0.35, 0.35, 0.35), false, 1.0)

			var text := "%.1f" % value
			var text_width := font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
			).x

			draw_string(
				font,
				Vector2(
					x + (cell_size - text_width) / 2.0,
					y + cell_size / 2.0 + font_size * 0.35
				),
				text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				Color.WHITE
			)

func _value_color(value: float) -> Color:
	if value < 0.0:
		return Color(0.95, 0.12, 0.16).lerp(
			Color(0.10, 0.10, 0.10), clampf(value + 1.0, 0.0, 1.0)
		)

	return Color(0.10, 0.10, 0.10).lerp(
		Color(0.10, 0.85, 0.35), clampf(value, 0.0, 1.0)
	)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed:
		return

	var mouse: Vector2 = event.position
	var column := int((mouse.x - label_size) / (cell_size + cell_gap))
	var row := int((mouse.y - label_size) / (cell_size + cell_gap))

	if row < 0 or row >= particle_types:
		return
	if column < 0 or column >= particle_types:
		return

	var local_x := fposmod(mouse.x - label_size, cell_size + cell_gap)
	var local_y := fposmod(mouse.y - label_size, cell_size + cell_gap)

	# Ignore clicks in the gaps between cells.
	if local_x >= cell_size or local_y >= cell_size:
		return

	var index := row * particle_types + column

	if event.button_index == MOUSE_BUTTON_LEFT:
		rules[index] = minf(2.0, snappedf(rules[index] + 0.1, 0.1))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		rules[index] = maxf(-1.0, snappedf(rules[index] - 0.1, 0.1))
	else:
		return

	rule_changed.emit(row, column, rules[index])
	queue_redraw()

func refresh(new_rules: PackedFloat32Array) -> void:
	rules = new_rules
	queue_redraw()
