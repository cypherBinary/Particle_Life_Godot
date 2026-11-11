extends Node2D

# seeding
@export var seeded := true
@export var simulation_seed := 168

# creation
@export var particleCount := 5000
@export var particleTypes := 3
@export var particlesSize := 2

@export var randomize_rules_on_reset := true

var particles := PackedVector2Array() # posx, posy, type
var particle_types := PackedInt32Array()
var velocities := PackedVector2Array()

# typing
var attractionDetail := 10.0
var rnd = Utils.Rnd
var rnd_generator = Utils.Rnd.rnd
var rules := PackedFloat32Array()

var types := {
	0: Color.from_string("#FF0050", Color.WHITE), # folly
	1: Color.from_string("#00FA9A", Color.WHITE), # spring green
	2: Color.from_string("#00BFFF", Color.WHITE), # deep sky blue
	3: Color.from_string("#FFFFFF", Color.WHITE), # ghost white
	4: Color.from_string("#FFFF33", Color.WHITE),  # electric yellow
}

func GetRule(inputType: int, targetType: int) -> float:
	return rules[inputType * particleTypes + targetType]

func SetRule(inputType: int, targetType: int, value: float) -> void:
	rules[inputType * particleTypes + targetType] = value

# temporary
@export var creation_area_ratio := Vector2(16, 10)
@export var creation_area_size := 100

# rules
@export var max_speed: float = 500
@export var max_force: float = 0.8
@export var damping_force: float = 0.98

@export var particle_repulsion_distance: float = 5
@export var particle_attraction_distance: float = 200

# ui
var ui := CanvasLayer.new()
var debug_panel := PanelContainer.new()
var debug_label := Label.new()

var setting_panel := PanelContainer.new()
var setting_content = VBoxContainer.new()

var checked_particles := 0
var found_particles := 0

var rule_matrix := RuleMatrix.new()

func _on_rule_changed(
	input_type: int,
	target_type: int,
	value: float
) -> void:
	SetRule(input_type, target_type, value)

	var data := rules.to_byte_array()
	rd.buffer_update(
		rules_buffer,
		0,
		data.size(),
		data
	)

# visuals
var particle_mesh := QuadMesh.new()
var particle_multimesh := MultiMesh.new()
var particle_renderer := MultiMeshInstance2D.new()
var particle_material := ShaderMaterial.new()

# settings
var force_mulriplier_label: Label
var force_multiplier_slider: HSlider
var max_speed_label: Label
var max_speed_slider: HSlider
var repulsion_distance_label: Label
var repulsion_distance_slider: HSlider
var attraction_distance_label: Label
var attraction_distance_slider: HSlider

var save_name_input: LineEdit
var save_list: VBoxContainer

var load_overlay: Control
var load_list: VBoxContainer

# gpu compute shader
var rd := RenderingServer.create_local_rendering_device()

var position_buffer
var next_positions_buffer
var velocity_buffer
var type_buffer
var rules_buffer
var params_buffer

var shader
var pipeline
var uniform_set
var params_uniform_set

# grid added to compute shader
var heads_buffer
var next_buffer
var cell_coords_buffer

@export var grid_cell_size := 200
var grid_table_size := 0
var grid_heads := PackedInt32Array()
var grid_next := PackedInt32Array()
var grid_cell_coords := PackedInt32Array()
var grid_params_buffer
var grid_params_uniform_set

# shader clearing the grid
var grid_clear_shader
var grid_clear_pipeline
var grid_clear_uniform_set
var grid_clear_params_buffer
var grid_clear_params_uniform_set

# shader building the grid
var grid_build_shader
var grid_build_pipeline
var grid_build_uniform_set
var grid_build_params_uniform_set

# saving
var rule_save_path := "user://rules.json"
var rule_saves_data := {}
var _loaded_rules := false

@onready var creature_manager = $Creature_Manager

func save_rule_saves():
	var file := FileAccess.open(rule_save_path, FileAccess.WRITE)

	file.store_string(JSON.stringify(rule_saves_data))

func load_rule_saves():
	var file := FileAccess.open(rule_save_path, FileAccess.READ)
		
	if file == null:
		return
	
	var data = JSON.parse_string(file.get_as_text())
	
	if data == null or not data is Dictionary:
		return
	
	rule_saves_data = data

func save_rules(save_name: String):
	rule_saves_data[save_name] = {
		"particle_types": particleTypes,
		"rules": rules
	}

func load_rules(save_name: String) -> bool:
	if not rule_saves_data.has(save_name):
		return false

	var data: Dictionary = rule_saves_data[save_name]

	get_tree().set_meta("pending_rule_data", data)
	get_tree().reload_current_scene()

	return true

func _compute_shader_setup():
	# file
	var shader_file := load("res://Scripts/test.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)

	# buffers
	var position_data := particles.to_byte_array()
	var velocity_data := velocities.to_byte_array()
	var type_data := particle_types.to_byte_array()
	var rules_data := rules.to_byte_array()
	
	grid_table_size = 1
	while grid_table_size < particleCount * 2:
		grid_table_size *= 2

	grid_heads.resize(grid_table_size)
	grid_heads.fill(-1)
	grid_next.resize(particleCount)
	grid_next.fill(-1)
	grid_cell_coords.resize(particleCount * 2)
	grid_cell_coords.fill(-1)

	var head_data = grid_heads.to_byte_array()
	var next_data = grid_next.to_byte_array()
	var cell_coords_data = grid_cell_coords.to_byte_array()
	
	var next_positions_data = particles.duplicate().to_byte_array()
	

	var params_data := PackedFloat32Array([
		max_speed,
		damping_force,
		particle_attraction_distance,
		particle_repulsion_distance,

		0.016,
		particleCount,
		max_force,
		particleTypes
	]).to_byte_array()
	
	var grid_params_data := PackedFloat32Array([
		float(particleCount),
		float(grid_table_size),
		grid_cell_size,
		0.0
	]).to_byte_array()

	position_buffer = rd.storage_buffer_create(
		position_data.size(),
		position_data
	)

	velocity_buffer = rd.storage_buffer_create(
		velocity_data.size(),
		velocity_data
	)

	type_buffer = rd.storage_buffer_create(
		type_data.size(),
		type_data
	)

	rules_buffer = rd.storage_buffer_create(
		rules_data.size(),
		rules_data
	)
	
	heads_buffer = rd.storage_buffer_create(
		head_data.size(),
		head_data
	)
	
	next_buffer = rd.storage_buffer_create(
		next_data.size(),
		next_data
	)
	
	cell_coords_buffer = rd.storage_buffer_create(
		cell_coords_data.size(),
		cell_coords_data
	)
	
	next_positions_buffer = rd.storage_buffer_create(
		next_positions_data.size(),
		next_positions_data
	)
	
	params_buffer = rd.uniform_buffer_create(
		params_data.size(),
		params_data
	)
	
	grid_params_buffer = rd.uniform_buffer_create(
		grid_params_data.size(),
		grid_params_data
	)

	# uniforms
	var position_uniform := RDUniform.new()
	position_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	position_uniform.binding = 0
	position_uniform.add_id(position_buffer)

	var velocity_uniform := RDUniform.new()
	velocity_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	velocity_uniform.binding = 1
	velocity_uniform.add_id(velocity_buffer)

	var type_uniform := RDUniform.new()
	type_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	type_uniform.binding = 2
	type_uniform.add_id(type_buffer)

	var rules_uniform := RDUniform.new()
	rules_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	rules_uniform.binding = 3
	rules_uniform.add_id(rules_buffer)
	
	var heads_uniform := RDUniform.new()
	heads_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	heads_uniform.binding = 4
	heads_uniform.add_id(heads_buffer)
	
	var next_uniform := RDUniform.new()
	next_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	next_uniform.binding = 5
	next_uniform.add_id(next_buffer)
	
	var cell_coords_uniform := RDUniform.new()
	cell_coords_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cell_coords_uniform.binding = 6
	cell_coords_uniform.add_id(cell_coords_buffer)
	
	var next_positions_uniform := RDUniform.new()
	next_positions_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	next_positions_uniform.binding = 7
	next_positions_uniform.add_id(next_positions_buffer)
	
	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(params_buffer)
	
	var grid_params_uniform := RDUniform.new()
	grid_params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	grid_params_uniform.binding = 1
	grid_params_uniform.add_id(grid_params_buffer)

	# set 0
	uniform_set = rd.uniform_set_create(
		[
			position_uniform,
			velocity_uniform,
			type_uniform,
			rules_uniform,
			heads_uniform,
			next_uniform,
			cell_coords_uniform,
			next_positions_uniform
		],
		shader,
		0
	)

	# set 1
	params_uniform_set = rd.uniform_set_create(
		[params_uniform, grid_params_uniform],
		shader,
		1
	)

	pipeline = rd.compute_pipeline_create(shader)
	
	# Load and compile the grid-clearing shader.
	var clear_file := load("res://Scripts/grid_clear.glsl")
	var clear_spirv = clear_file.get_spirv()
	grid_clear_shader = rd.shader_create_from_spirv(clear_spirv)

	# Create the parameters for the clearing shader.
	var clear_params_data := PackedInt32Array([
		grid_table_size,
		0,
		0,
		0
	]).to_byte_array()

	grid_clear_params_buffer = rd.uniform_buffer_create(
		clear_params_data.size(),
		clear_params_data
	)

	# Connect heads_buffer to set 0, binding 0.
	var clear_heads_uniform := RDUniform.new()
	clear_heads_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	clear_heads_uniform.binding = 0
	clear_heads_uniform.add_id(heads_buffer)

	# Connect the parameter buffer to set 1, binding 0.
	var clear_params_uniform := RDUniform.new()
	clear_params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	clear_params_uniform.binding = 0
	clear_params_uniform.add_id(grid_clear_params_buffer)

	# Create the uniform sets for the clearing shader.
	grid_clear_uniform_set = rd.uniform_set_create(
		[clear_heads_uniform],
		grid_clear_shader,
		0
	)

	grid_clear_params_uniform_set = rd.uniform_set_create(
		[clear_params_uniform],
		grid_clear_shader,
		1
	)

	# Create the clearing pipeline.
	grid_clear_pipeline = rd.compute_pipeline_create(grid_clear_shader)

func _grid_build_setup() -> void:
	# Load and compile the shader.
	var shader_file := load("res://Scripts/grid_build.glsl")
	var shader_spirv = shader_file.get_spirv()
	grid_build_shader = rd.shader_create_from_spirv(shader_spirv)

	# Set 0: particle positions and grid buffers.
	var position_uniform := RDUniform.new()
	position_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	position_uniform.binding = 0
	position_uniform.add_id(position_buffer)

	var heads_uniform := RDUniform.new()
	heads_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	heads_uniform.binding = 1
	heads_uniform.add_id(heads_buffer)

	var next_uniform := RDUniform.new()
	next_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	next_uniform.binding = 2
	next_uniform.add_id(next_buffer)

	var cell_coords_uniform := RDUniform.new()
	cell_coords_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cell_coords_uniform.binding = 3
	cell_coords_uniform.add_id(cell_coords_buffer)

	grid_build_uniform_set = rd.uniform_set_create(
		[
			position_uniform,
			heads_uniform,
			next_uniform,
			cell_coords_uniform
		],
		grid_build_shader,
		0
	)

	# Set 1: grid settings.
	var grid_params_uniform := RDUniform.new()
	grid_params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	grid_params_uniform.binding = 0
	grid_params_uniform.add_id(grid_params_buffer)

	grid_build_params_uniform_set = rd.uniform_set_create(
		[grid_params_uniform],
		grid_build_shader,
		1
	)

	# Create the compute pipeline.
	grid_build_pipeline = rd.compute_pipeline_create(grid_build_shader)

func _update_grid_build_uniform_set() -> void:
	rd.free_rid(grid_build_uniform_set)
	
	var position_uniform := RDUniform.new()
	position_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	position_uniform.binding = 0
	position_uniform.add_id(position_buffer)

	var heads_uniform := RDUniform.new()
	heads_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	heads_uniform.binding = 1
	heads_uniform.add_id(heads_buffer)

	var next_uniform := RDUniform.new()
	next_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	next_uniform.binding = 2
	next_uniform.add_id(next_buffer)

	var cell_coords_uniform := RDUniform.new()
	cell_coords_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cell_coords_uniform.binding = 3
	cell_coords_uniform.add_id(cell_coords_buffer)

	grid_build_uniform_set = rd.uniform_set_create(
		[
			position_uniform,
			heads_uniform,
			next_uniform,
			cell_coords_uniform
		],
		grid_build_shader,
		0
	)

func _update_simulation_uniform_set() -> void:
	rd.free_rid(uniform_set)

	var position_uniform := RDUniform.new()
	position_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	position_uniform.binding = 0
	position_uniform.add_id(position_buffer)

	var velocity_uniform := RDUniform.new()
	velocity_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	velocity_uniform.binding = 1
	velocity_uniform.add_id(velocity_buffer)

	var type_uniform := RDUniform.new()
	type_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	type_uniform.binding = 2
	type_uniform.add_id(type_buffer)

	var rules_uniform := RDUniform.new()
	rules_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	rules_uniform.binding = 3
	rules_uniform.add_id(rules_buffer)

	var heads_uniform := RDUniform.new()
	heads_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	heads_uniform.binding = 4
	heads_uniform.add_id(heads_buffer)

	var next_uniform := RDUniform.new()
	next_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	next_uniform.binding = 5
	next_uniform.add_id(next_buffer)

	var cell_coords_uniform := RDUniform.new()
	cell_coords_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cell_coords_uniform.binding = 6
	cell_coords_uniform.add_id(cell_coords_buffer)

	var next_positions_uniform := RDUniform.new()
	next_positions_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	next_positions_uniform.binding = 7
	next_positions_uniform.add_id(next_positions_buffer)

	uniform_set = rd.uniform_set_create(
		[
			position_uniform,
			velocity_uniform,
			type_uniform,
			rules_uniform,
			heads_uniform,
			next_uniform,
			cell_coords_uniform,
			next_positions_uniform
		],
		shader,
		0
	)

func _update_grid() -> void:
	var compute_list := rd.compute_list_begin()

	# Pass 1: clear the hash table.
	rd.compute_list_bind_compute_pipeline(
		compute_list,
		grid_clear_pipeline
	)
	rd.compute_list_bind_uniform_set(
		compute_list,
		grid_clear_uniform_set,
		0
	)
	rd.compute_list_bind_uniform_set(
		compute_list,
		grid_clear_params_uniform_set,
		1
	)

	var clear_groups := int(ceil(float(grid_table_size) / 64.0))
	rd.compute_list_dispatch(compute_list, clear_groups, 1, 1)

	# Make the clear pass's writes visible to the next pass.
	rd.compute_list_add_barrier(compute_list)

	# Pass 2: insert all particles into the grid.
	rd.compute_list_bind_compute_pipeline(
		compute_list,
		grid_build_pipeline
	)
	rd.compute_list_bind_uniform_set(
		compute_list,
		grid_build_uniform_set,
		0
	)
	rd.compute_list_bind_uniform_set(
		compute_list,
		grid_build_params_uniform_set,
		1
	)

	var build_groups := int(ceil(float(particleCount) / 64.0))
	rd.compute_list_dispatch(compute_list, build_groups, 1, 1)

	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
func _compute_step(dt: float) -> void:
	var params_data := PackedFloat32Array([
		max_speed,
		damping_force,
		particle_attraction_distance,
		particle_repulsion_distance,

		dt,
		particleCount,
		max_force,
		particleTypes
	]).to_byte_array()

	rd.buffer_update(
		params_buffer,
		0,
		params_data.size(),
		params_data
	)

	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(
		compute_list,
		pipeline
	)

	rd.compute_list_bind_uniform_set(
		compute_list,
		uniform_set,
		0
	)

	rd.compute_list_bind_uniform_set(
		compute_list,
		params_uniform_set,
		1
	)

	rd.compute_list_dispatch(
		compute_list,
		particleCount,
		1,
		1
	)

	rd.compute_list_end()

	rd.submit()
	rd.sync()
	
	var temp = position_buffer
	position_buffer = next_positions_buffer
	next_positions_buffer = temp

	_update_simulation_uniform_set()
	_update_grid_build_uniform_set()

	# getting output
	var position_data := rd.buffer_get_data(position_buffer)
	var velocity_data := rd.buffer_get_data(velocity_buffer)

	particles = position_data.to_vector2_array()
	velocities = velocity_data.to_vector2_array()

func _draw_debug_info() -> void:
	debug_label.text = (
		"FPS: " + str(Engine.get_frames_per_second()) +
		"\nParticles: " + str(particles.size())
	)

func _draw_multimesh_particles() -> void:
	for i in range(particleCount):
		particle_multimesh.set_instance_transform_2d(
			i,
			Transform2D(0.0, particles[i])
		)
		particle_multimesh.set_instance_color(
			i,
			types[particle_types[i]]
		)

func _logic_setup():
	if seeded:
		rnd_generator.seed = simulation_seed

	# Rules: randomize only when requested or when the matrix size changes.
	if (randomize_rules_on_reset and not _loaded_rules) or rules.size() != particleTypes * particleTypes:
		rules.resize(particleTypes * particleTypes)

		for i in range(rules.size()):
			rules[i] = (
				roundf(Utils.Rnd.randf() * attractionDetail)
				/ attractionDetail
			) * 2.0 - 1.0

	# Particles: regenerate positions and velocities every reset.
	particles.resize(particleCount)
	velocities.resize(particleCount)
	particle_types.resize(particleCount)

	@warning_ignore("integer_division")
	for i in range((particleCount/particleTypes)):
		var val := particleTypes * i

		for j in range(particleTypes):
			var index := val + j
			
			var world_size = creation_area_ratio * creation_area_size

			particles[index] = Vector2(
				Utils.Rnd.range_f(-world_size.x, world_size.x),
				Utils.Rnd.range_f(-world_size.y, world_size.y)
			)

			particle_types[index] = j

			velocities[index] = Vector2.ZERO

func _particle_rendering_setup():
	particle_mesh.size = Vector2(particlesSize * 2, particlesSize * 2)

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

	particle_material.shader = multi_shader
	particle_renderer.material = particle_material

	particle_multimesh.mesh = particle_mesh
	particle_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	particle_multimesh.use_colors = true
	particle_multimesh.instance_count = particleCount

	particle_renderer.multimesh = particle_multimesh

	add_child(particle_renderer)

func _ui_setup():
	var content := VBoxContainer.new() # holds the panels
	content.add_theme_constant_override("separation", 8)
	
	add_child(ui)
	ui.add_child(content)
	
	#* bg
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.02, 0.02, 0.9)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 8
	bg.content_margin_bottom = 8
	
	#* debug
	debug_panel.position = Vector2(10, 10)
	debug_panel.add_theme_stylebox_override("panel", bg)


	content.add_child(debug_panel)
	debug_panel.add_child(debug_label)

	#* setting
	setting_panel.add_theme_stylebox_override("panel", bg)
	content.add_child(setting_panel)
	setting_panel.add_child(setting_content)
	
	# sliders
	force_mulriplier_label = Label.new()
	force_mulriplier_label.text = "Force Multiplier:"
	force_multiplier_slider = HSlider.new()
	force_multiplier_slider.min_value = 0.0
	force_multiplier_slider.max_value = 1.0
	force_multiplier_slider.step = 0.01
	force_multiplier_slider.value = 0.6
	
	setting_content.add_child(force_mulriplier_label)
	setting_content.add_child(force_multiplier_slider)
	
	max_speed_label = Label.new()
	max_speed_label.text = "Max Speed:"
	max_speed_slider = HSlider.new()
	max_speed_slider.min_value = 0.0
	max_speed_slider.max_value = 500.0
	max_speed_slider.step = 1.0
	max_speed_slider.value = 300.0
	
	setting_content.add_child(max_speed_label)
	setting_content.add_child(max_speed_slider)
	
	repulsion_distance_label = Label.new()
	repulsion_distance_label.text = "Repulsion Distance:"
	repulsion_distance_slider = HSlider.new()
	repulsion_distance_slider.min_value = 0.0
	repulsion_distance_slider.max_value = 300.0
	repulsion_distance_slider.step = 1.0
	repulsion_distance_slider.value = 50.0
	
	setting_content.add_child(repulsion_distance_label)
	setting_content.add_child(repulsion_distance_slider)
	
	attraction_distance_label = Label.new()
	attraction_distance_label.text = "Attraction Distance:"
	attraction_distance_slider = HSlider.new()
	attraction_distance_slider.min_value = 0.0
	attraction_distance_slider.max_value = 300.0
	attraction_distance_slider.step = 1.0
	attraction_distance_slider.value = 100.0
	
	setting_content.add_child(attraction_distance_label)
	setting_content.add_child(attraction_distance_slider)
	
	var matrix_label = Label.new()
	matrix_label.text = "Rule Matrix: "
	
	setting_content.add_child(matrix_label)
	
	# Matrix
	rule_matrix.setup(particleTypes, rules, types)
	rule_matrix.rule_changed.connect(_on_rule_changed)
	
	setting_content.add_child(rule_matrix)
	
	# Randomize button
	var randomize_button := Button.new()
	randomize_button.text = "Randomize"
	randomize_button.pressed.connect(_randomize_simulation)
	
	setting_content.add_child(randomize_button)
	
	# Reset button
	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.pressed.connect(_refresh_simulation)
	
	setting_content.add_child(reset_button)
	
	var exit_button := Button.new()
	exit_button.text = "Quit"
	exit_button.pressed.connect(
		func(): get_tree().quit()
	)
	
	exit_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ui.add_child(exit_button)

func _save_ui_setup() -> void:
	var title := Label.new()
	title.text = "Rule Presets"
	setting_content.add_child(title)

	# Textbox for the save name.
	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Preset name..."
	save_name_input.custom_minimum_size.x = 200
	setting_content.add_child(save_name_input)

	# Save button.
	var save_button := Button.new()
	save_button.text = "SAVE PRESET"
	save_button.pressed.connect(_on_save_pressed)
	setting_content.add_child(save_button)

	# List of existing saves.
	save_list = VBoxContainer.new()
	setting_content.add_child(save_list)
	
	var load_button := Button.new()
	load_button.text = "LOAD PRESET"
	load_button.pressed.connect(_show_load_menu)
	setting_content.add_child(load_button)

	_setup_load_overlay()

func _on_save_pressed() -> void:
	var save_name := save_name_input.text.strip_edges()

	if save_name.is_empty():
		return

	save_rules(save_name)
	save_rule_saves()
	refresh_save_list()

	save_name_input.clear()

func _show_load_menu() -> void:
	refresh_save_list()
	load_overlay.visible = true

func refresh_save_list() -> void:
	for child in load_list.get_children():
		child.free()

	for save_name in rule_saves_data.keys():
		var row := HBoxContainer.new()
		load_list.add_child(row)

		var load_button := Button.new()
		load_button.text = str(save_name)
		load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_button.pressed.connect(
			_on_load_pressed.bind(str(save_name))
		)
		row.add_child(load_button)

		var delete_button := Button.new()
		delete_button.text = "X"
		delete_button.tooltip_text = "Delete preset"
		delete_button.pressed.connect(
			_on_delete_pressed.bind(str(save_name))
		)
		row.add_child(delete_button)

	if rule_saves_data.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved presets yet."
		load_list.add_child(empty_label)

func _on_load_pressed(save_name: String) -> void:
	load_overlay.visible = false
	load_rules(save_name)

func _setup_load_overlay() -> void:
	load_overlay = Control.new()
	load_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	load_overlay.visible = false
	load_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(load_overlay)

	# Darken the screen behind the popup.
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.65)
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	load_overlay.add_child(background)

	# Center the popup.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	load_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 300)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)

	var content := VBoxContainer.new()
	panel.add_child(content)

	var title := Label.new()
	title.text = "Load Preset"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	# Scrollable list, so it can handle many saves.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(380, 220)
	content.add_child(scroll)

	load_list = VBoxContainer.new()
	load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(load_list)

	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.pressed.connect(
		func(): load_overlay.visible = false
	)
	content.add_child(close_button)

func _on_delete_pressed(save_name: String) -> void:
	rule_saves_data.erase(save_name)
	save_rule_saves()
	refresh_save_list()

func _update_settings():
	force_mulriplier_label.text = "Force multiplier: " + str(max_force)
	max_force = force_multiplier_slider.value
	max_speed_label.text = "Max speed: " + str(max_speed)
	max_speed = max_speed_slider.value
	repulsion_distance_label.text = "Repulsion distance: " + str(particle_repulsion_distance)
	particle_repulsion_distance = repulsion_distance_slider.value
	attraction_distance_label.text = "Attraction distance: " + str(particle_attraction_distance)
	particle_attraction_distance = attraction_distance_slider.value

func _ready() -> void:
	if get_tree().has_meta("pending_rule_data"):
		var data: Dictionary = get_tree().get_meta("pending_rule_data")
		get_tree().remove_meta("pending_rule_data")

		particleTypes = int(data["particle_types"])
		rules = PackedFloat32Array(data["rules"])

	_loaded_rules = true

	_logic_setup()

	_loaded_rules = false

	_particle_rendering_setup()
	_ui_setup()

	_compute_shader_setup()
	_grid_build_setup()
	
	load_rule_saves()
	_save_ui_setup()

var pressed = false

func _process(dt: float) -> void:
	# visuals
	_draw_debug_info()
	_draw_multimesh_particles()

	# logic
	_update_settings()
	_update_grid()
	_compute_step(dt)
	
	queue_redraw()
	
	if Input.is_key_pressed(KEY_SPACE):
		if not pressed:
			pressed = true
			_randomize_simulation()
	else:
		if pressed:
			pressed = false

func _draw() -> void:
	if creature_manager.placing:
		draw_circle(
			get_global_mouse_position(),
			50,
			Color(0.2, 0.2, 0.2, 0.9),
			true,
			-1,
			true
		)
	if creature_manager.mouse_held:
		var r:float = (get_global_mouse_position() - creature_manager.held_position).length()

		draw_circle(
			creature_manager.held_position,
			r,
			Color(0.2, 0.2, 0.2, 0.9),
			true,
			-1,
			true
		)
		draw_dashed_line(creature_manager.held_position, get_global_mouse_position(), Color.WHITE, 8, 12, true, true)

func save():
	var file := FileAccess.open("user://rules.json", FileAccess.WRITE)

	var data := {
		"particle_types": particleTypes,
		"rules": rules
	}

	file.store_string(JSON.stringify(data))

func _randomize_simulation() -> void:
	_logic_setup()

	rd.buffer_update(
		position_buffer,
		0,
		particles.to_byte_array().size(),
		particles.to_byte_array()
	)

	rd.buffer_update(
		velocity_buffer,
		0,
		velocities.to_byte_array().size(),
		velocities.to_byte_array()
	)

	rd.buffer_update(
		type_buffer,
		0,
		particle_types.to_byte_array().size(),
		particle_types.to_byte_array()
	)

	rd.buffer_update(
		rules_buffer,
		0,
		rules.to_byte_array().size(),
		rules.to_byte_array()
	)
	
	rd.buffer_update(
		next_positions_buffer,
		0,
		particles.to_byte_array().size(),
		particles.to_byte_array()
	)
	
	rule_matrix.refresh(rules)

func _refresh_simulation() -> void:
	for i in range(len(particles)):
		var world_size = creation_area_ratio * creation_area_size

		particles[i] = Vector2(
			Utils.Rnd.range_f(-world_size.x, world_size.x),
			Utils.Rnd.range_f(-world_size.y, world_size.y)
		)


		velocities[i] = Vector2.ZERO
		
	rd.buffer_update(
		position_buffer,
		0,
		particles.to_byte_array().size(),
		particles.to_byte_array()
	)

	rd.buffer_update(
		velocity_buffer,
		0,
		velocities.to_byte_array().size(),
		velocities.to_byte_array()
	)

	rd.buffer_update(
		type_buffer,
		0,
		particle_types.to_byte_array().size(),
		particle_types.to_byte_array()
	)

	rd.buffer_update(
		rules_buffer,
		0,
		rules.to_byte_array().size(),
		rules.to_byte_array()
	)
	
	rd.buffer_update(
		next_positions_buffer,
		0,
		particles.to_byte_array().size(),
		particles.to_byte_array()
	)
	
	rule_matrix.refresh(rules)
