class_name ComputeShader extends RefCounted

# Threading
var _thread := Thread.new()
var _semaphore := Semaphore.new()
var _mutex := Mutex.new()
var _exit_thread := false
var _is_processing := false

# Data Containers
var _constants: Variant
var _input_bytes: PackedByteArray
var _input: Variant
var _output: Variant

# Rendering Device RID
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var buffer_rid: RID
var uniform_set_rid: RID
var current_buffer_size: int = -1

signal data_received(output: Variant)

func _init(shader_path: String) -> void:
	_thread.start(_thread_loop.bind(shader_path))

func set_input(data: Variant, constants: Variant = PackedFloat32Array()) -> void:
	_input = data
	_constants = constants
	_input_bytes = data.to_byte_array()

func get_output() -> Variant:
	var data = _output
	return data

func dispatch() -> void:
	if _is_processing:
		return
	_is_processing = true
	_semaphore.post()

func _thread_loop(path: String) -> void:
	rd = RenderingServer.create_local_rendering_device()
	shader_rid = rd.shader_create_from_spirv(load(path).get_spirv())
	pipeline_rid = rd.compute_pipeline_create(shader_rid)

	while !_exit_thread:
		_semaphore.wait()
		if _exit_thread: break

		_mutex.lock()
		var data_to_process := _input_bytes
		_mutex.unlock()

		if data_to_process.is_empty():
			_is_processing = false
			continue

		if current_buffer_size != data_to_process.size():
			_cleanup_gpu_resources()
			buffer_rid = rd.storage_buffer_create(data_to_process.size(), data_to_process)
			
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = 0
			uniform.add_id(buffer_rid)
			uniform_set_rid = rd.uniform_set_create([uniform], shader_rid, 0)
			current_buffer_size = data_to_process.size()
		else:
			rd.buffer_update(buffer_rid, 0, data_to_process.size(), data_to_process)

		var list := rd.compute_list_begin()
		var push_constants: PackedByteArray = _constants.to_byte_array()
		
		rd.compute_list_bind_compute_pipeline(list, pipeline_rid)
		rd.compute_list_bind_uniform_set(list, uniform_set_rid, 0)
		rd.compute_list_set_push_constant(list, push_constants, push_constants.size())
		rd.compute_list_dispatch(list, ceil(_input_bytes.size() / 64.0), 1, 1)
		rd.compute_list_end()
		
		rd.submit()
		rd.sync()

		var result_bytes := rd.buffer_get_data(buffer_rid)
		
		_mutex.lock()
		if _input is PackedVector2Array:
			_output = result_bytes.to_vector2_array()
		elif _input is PackedVector3Array:
			_output = result_bytes.to_vector3_array()
		elif _input is PackedFloat32Array:
			_output = result_bytes.to_float32_array()
		elif _input is PackedInt32Array:
			_output = result_bytes.to_int32_array()
		_mutex.unlock()

		_is_processing = false
		data_received.emit.call_deferred(_output)

	_cleanup_gpu_resources()
	rd.free_rid(pipeline_rid)
	rd.free_rid(shader_rid)
	rd.free()

func _cleanup_gpu_resources() -> void:
	if uniform_set_rid.is_valid():
		rd.free_rid(uniform_set_rid)
	if buffer_rid.is_valid():
		rd.free_rid(buffer_rid)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_exit_thread = true
		_semaphore.post()
		if _thread.is_started():
			_thread.wait_to_finish()
