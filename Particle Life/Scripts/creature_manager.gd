extends Node

@export var world: Node2D

var mouse_held := false
var held_position := Vector2.ZERO

var placing = false

var ui := CanvasLayer.new()
var creature_save_overlay: Control
var creature_save_content: VBoxContainer
var creature_name_input: LineEdit

var creature_load_overlay: Control
var creature_load_list: VBoxContainer

var creature_save_path := "user://creatures.json"
var creature_saves_data := {}

var creature_mesh := QuadMesh.new()
var creature_multimesh := MultiMesh.new()
var creature_renderer := MultiMeshInstance2D.new()
var creature_material := ShaderMaterial.new()

class Creature:
	var world_position: Vector2
	var particles := PackedVector2Array()
	var particle_types := PackedInt32Array()
	var velocities := PackedVector2Array()
	var rules := PackedFloat32Array()

var creatures: Array[Creature] = []
var selected_creature: Creature

func _setup_creature_save_menu():
	add_child(ui)
	
	creature_save_overlay = Control.new()
	creature_save_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	creature_save_overlay.visible = false
	creature_save_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(creature_save_overlay)
	
	# Darken the screen behind the popup.
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.65)
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	creature_save_overlay.add_child(background)
	
	# Center the popup.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	creature_save_overlay.add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 80)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)

	creature_save_content = VBoxContainer.new()
	panel.add_child(creature_save_content)
	
	creature_name_input = LineEdit.new()
	creature_name_input.placeholder_text = "Creature name"
	creature_name_input.custom_minimum_size.x = 200
	creature_save_content.add_child(creature_name_input)
	
	var save_button := Button.new()
	save_button.text = "SAVE"
	save_button.pressed.connect(_on_save_creature)
	creature_save_content.add_child(save_button)
	
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.pressed.connect(
		func(): creature_save_overlay.visible = false
	)
	creature_save_content.add_child(close_button)

func _setup_creature_load_menu() -> void:
	creature_load_overlay = Control.new()
	creature_load_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	creature_load_overlay.visible = false
	creature_load_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	ui.add_child(creature_load_overlay)

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.65)
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	creature_load_overlay.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	creature_load_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 300)
	center.add_child(panel)

	var content := VBoxContainer.new()
	panel.add_child(content)

	var title := Label.new()
	title.text = "Load Creature"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	creature_load_list = VBoxContainer.new()
	creature_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(creature_load_list)

	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.pressed.connect(
		func():
			creature_load_overlay.visible = false
	)
	content.add_child(close_button)
	
	# load menu button
	var load_button := Button.new()
	load_button.text = "BEASTIARY"
	load_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	load_button.offset_top = 10
	load_button.offset_bottom = 40
	load_button.offset_right = -10
	load_button.offset_left = -160

	load_button.pressed.connect(
		func():
			refresh_creature_load_list()
			creature_load_overlay.visible = true
	)
	
	ui.add_child(load_button)

func _setup_creature_rendering() -> void:
	creature_mesh.size = Vector2(
		world.particlesSize * 2,
		world.particlesSize * 2
	)

	var multi_shader := Shader.new()
	multi_shader.code = """
	shader_type canvas_item;

	void fragment() {
		vec2 p = UV - vec2(0.5);

		float d = length(p) - 0.5;
		float aa = fwidth(d);

		COLOR.a *= 1.0 - smoothstep(-aa, aa, d);
	}
	"""

	creature_material.shader = multi_shader
	creature_renderer.material = creature_material

	creature_multimesh.mesh = creature_mesh
	creature_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	creature_multimesh.use_colors = true
	creature_multimesh.instance_count = 0

	creature_renderer.multimesh = creature_multimesh

	add_child(creature_renderer)

func refresh_creature_load_list() -> void:
	for child in creature_load_list.get_children():
		child.queue_free()

	for save_name in creature_saves_data.keys():
		var content = HBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		var button := Button.new()
		button.text = str(save_name)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		button.pressed.connect(
			_on_load_creature_pressed.bind(str(save_name))
		)
		
		content.add_child(button)
		
		var remove_button = Button.new()
		remove_button.text = "X"
		
		remove_button.pressed.connect(
			_on_delete_creature_pressed.bind(str(save_name))
		)
		
		content.add_child(remove_button)
		
		
		creature_load_list.add_child(content)


	if creature_saves_data.is_empty():
		var label := Label.new()
		label.text = "No saved creatures."
		creature_load_list.add_child(label)

func _on_delete_creature_pressed(save_name: String) -> void:
	creature_saves_data.erase(save_name)
	save_creature_saves()
	refresh_creature_load_list()

func _on_load_creature_pressed(save_name: String) -> void:
	var creature := load_creature(save_name)

	if creature == null:
		return

	selected_creature = creature

	creature_load_overlay.visible = false

	print("Loaded creature: ", save_name)
	
	placing = true

func _on_save_creature() -> void:
	if selected_creature == null:
		return

	var save_name := creature_name_input.text.strip_edges()

	if save_name.is_empty():
		return

	save_creature(save_name, selected_creature)

	creature_name_input.clear()
	creature_save_overlay.visible = false

func _create_creature(position: Vector2, radius: float) -> void:
	var creature := Creature.new()

	creature.world_position = position
	creature.rules = world.rules.duplicate()

	var radius_squared := radius * radius

	for i in range(world.particles.size()):
		var offset:Vector2 = world.particles[i] - position

		if offset.length_squared() <= radius_squared:
			creature.particles.append(offset)
			creature.particle_types.append(world.particle_types[i])

	selected_creature = creature
	creature_save_overlay.visible = true

	print(
		"Creature created at: ",
		position,
		" radius: ",
		radius,
		" particles: ",
		creature.particles.size()
	)

func _place_creature(position: Vector2) -> void:
	for i in range(len(selected_creature.particles)):
		selected_creature.particles[i] = selected_creature.particles[i] + position
		selected_creature.velocities.append(Vector2.ZERO)
	
	selected_creature.world_position = Vector2.ZERO
	creatures.append(selected_creature)

func save_creature_saves() -> void:
	var file := FileAccess.open(creature_save_path, FileAccess.WRITE)

	if file == null:
		return

	file.store_string(JSON.stringify(creature_saves_data))

func load_creature_saves() -> void:
	var file := FileAccess.open(creature_save_path, FileAccess.READ)

	if file == null:
		return

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		return

	creature_saves_data = data

func save_creature(save_name: String, creature: Creature) -> void:
	var particle_data := []
	var particle_type_data := []
	var rule_data := []

	for particle in creature.particles:
		particle_data.append([
			particle.x,
			particle.y
		])

	for particle_type in creature.particle_types:
		particle_type_data.append(particle_type)

	for rule in creature.rules:
		rule_data.append(rule)

	creature_saves_data[save_name] = {
		"position": [
			creature.world_position.x,
			creature.world_position.y
		],
		"particles": particle_data,
		"particle_types": particle_type_data,
		"rules": rule_data
	}

	save_creature_saves()

func load_creature(save_name: String) -> Creature:
	if not creature_saves_data.has(save_name):
		return null

	var data: Dictionary = creature_saves_data[save_name]

	var creature := Creature.new()

	var position_data: Array = data["position"]

	creature.world_position = Vector2(
		float(position_data[0]),
		float(position_data[1])
	)

	creature.particles.clear()

	for particle in data["particles"]:
		creature.particles.append(
			Vector2(
				float(particle[0]),
				float(particle[1])
			)
		)
	
	creature.particle_types = PackedInt32Array(data["particle_types"])
	creature.rules = PackedFloat32Array(data["rules"])

	return creature

func _draw_creatures() -> void:
	var total_particles := 0

	for creature in creatures:
		total_particles += creature.particles.size()

	creature_multimesh.instance_count = total_particles

	var instance := 0

	for creature in creatures:
		for i in range(creature.particles.size()):
			var position := (
				creature.world_position
				+ creature.particles[i]
			)

			creature_multimesh.set_instance_transform_2d(
				instance,
				Transform2D(0.0, position)
			)

			creature_multimesh.set_instance_color(
				instance,
				world.types[creature.particle_types[i]]
			)

			instance += 1

func _get_force(
	position: Vector2,
	input_type: int,
	repulsion_r: float,
	attraction_r: float,
	rules: PackedFloat32Array
) -> Vector2:
	var force := Vector2.ZERO

	var interaction_r := repulsion_r + attraction_r
	var interaction_squared := interaction_r * interaction_r

	var attraction_half := attraction_r / 2.0

	for creature in creatures:
		for i in range(creature.particles.size()):
			var particle := creature.particles[i]

			if particle == position:
				continue

			var diff := particle - position
			var distance_squared := diff.length_squared()

			if distance_squared > interaction_squared:
				continue

			if distance_squared == 0.0:
				continue

			var distance := sqrt(distance_squared)

			if distance <= repulsion_r:
				var force_value := -1.0 + distance / repulsion_r

				force += (
					diff / distance
					* (world.max_speed * force_value)
				)

			else:
				var d := distance - repulsion_r
				var t: float

				if d <= attraction_half:
					t = d / attraction_half
				else:
					t = 1.0 - (d - attraction_half) / attraction_half
					
				t *= world.max_force

				var rule_index:int = (
					input_type * world.particleTypes
					+ creature.particle_types[i]
				)

				force += (
					diff / distance
					* (world.max_speed * t)
					* rules[rule_index]
				)

	return force

func _creature_logic(dt: float) -> void:
	for creature in creatures:
		for p in range(len(creature.particles)):
			var force := _get_force(creature.particles[p], creature.particle_types[p], world.particle_repulsion_distance, world.particle_attraction_distance, creature.rules)
			
			var desired_velocity := force

			var force_length := desired_velocity.length()

			if force_length > world.max_speed:
				desired_velocity = (
					desired_velocity / force_length
					* world.max_speed
				)

			var velocity := creature.velocities[p]

			velocity = velocity.lerp(
				desired_velocity,
				world.damping_force
			)

			var velocity_length := velocity.length()

			if velocity_length > world.max_speed:
				velocity = (
					velocity / velocity_length
					* world.max_speed
				)

			creature.velocities[p] = velocity

			creature.particles[p] += (
				velocity * dt
			)

func _ready() -> void:
	load_creature_saves()
	_setup_creature_save_menu()
	_setup_creature_load_menu()
	_setup_creature_rendering()

func _process(_delta: float) -> void:
	_draw_creatures()
	_creature_logic(_delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				mouse_held = true
				held_position = world.get_global_mouse_position()
			else:
				mouse_held = false
				_create_creature(held_position, (held_position - world.get_global_mouse_position()).length())
		if event.button_index == MOUSE_BUTTON_LEFT:
			if placing:
				placing = false
				_place_creature(world.get_global_mouse_position())
				
