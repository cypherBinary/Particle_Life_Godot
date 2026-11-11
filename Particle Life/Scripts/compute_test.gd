extends Node

var rd := RenderingServer.create_local_rendering_device()

func _ready():
	var data := PackedFloat32Array([0, 1, 2, 3, 4])

	var buffer := rd.storage_buffer_create(data.to_byte_array().size(), data.to_byte_array())

	var shader_file := load("res://Scripts/test.glsl")
	var shader_spirv = shader_file.get_spirv()
	var shader := rd.shader_create_from_spirv(shader_spirv)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer)

	var uniform_set := rd.uniform_set_create([uniform], shader, 0)
	var pipeline := rd.compute_pipeline_create(shader)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 5, 1, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	var result_bytes := rd.buffer_get_data(buffer)
	var result := result_bytes.to_float32_array()

	print(result)
