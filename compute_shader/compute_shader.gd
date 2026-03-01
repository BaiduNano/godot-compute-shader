class_name ComputeShader extends RefCounted

# Threading
var _thread := Thread.new()
var _semaphore := Semaphore.new()
var _mutex := Mutex.new()
var _exit_thread := false
var _is_processing := false

# Logic Data
var _constants: PackedByteArray
var _buffer_registry: Dictionary[int, PackedByteArray] # binding_index -> PackedByteArray

# Rendering Device RIDs
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var uniform_set_rid: RID

var _dispatch_size := Vector3i.ONE
var _buffer_rids: Dictionary[int, RID] # binding_index -> RID

signal task_completed(results: Dictionary)

func _init(shader_path: String) -> void:
	_thread.start(_thread_loop.bind(shader_path))

func set_buffer(binding: int, data: Variant) -> void:
	_mutex.lock()
	_buffer_registry[binding] = data.to_byte_array()
	_mutex.unlock()

func set_constants(data: Variant) -> void:
	_mutex.lock()
	_constants = data.to_byte_array()
	_mutex.unlock()

func dispatch(x_groups: int, y_groups: int = 1, z_groups: int = 1) -> void:
	if _is_processing: return
	_is_processing = true
	_dispatch_size = Vector3i(x_groups, y_groups, z_groups)
	_semaphore.post()

func _thread_loop(path: String) -> void:
	rd = RenderingServer.create_local_rendering_device()
	var shader_file = load(path)
	shader_rid = rd.shader_create_from_spirv(shader_file.get_spirv())
	pipeline_rid = rd.compute_pipeline_create(shader_rid)

	while !_exit_thread:
		_semaphore.wait()
		if _exit_thread: break

		_mutex.lock()
		_update_gpu_resources()
		var pc := _constants
		var size = _dispatch_size
		_mutex.unlock()

		# Run Compute
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline_rid)
		rd.compute_list_bind_uniform_set(list, uniform_set_rid, 0)
		if !pc.is_empty():
			rd.compute_list_set_push_constant(list, pc, pc.size())
		rd.compute_list_dispatch(list, size.x, size.y, size.z)
		rd.compute_list_end()
		
		rd.submit()
		rd.sync()

		var final_results := {}
		for binding in _buffer_rids:
			final_results[binding] = rd.buffer_get_data(_buffer_rids[binding])
		
		_is_processing = false
		task_completed.emit.call_deferred(final_results)

	_cleanup_all_gpu_resources()
	rd.free()

func _update_gpu_resources() -> void:
	var uniforms: Array[RDUniform] = []
	var needs_new_uniform_set = false

	for binding in _buffer_registry:
		var data: PackedByteArray = _buffer_registry[binding]
		if _buffer_rids.has(binding):
			rd.free_rid(_buffer_rids[binding])
		_buffer_rids[binding] = rd.storage_buffer_create(data.size(), data)
		needs_new_uniform_set = true

	if needs_new_uniform_set or !uniform_set_rid.is_valid():
		for binding in _buffer_rids:
			var uni := RDUniform.new()
			uni.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uni.binding = binding
			uni.add_id(_buffer_rids[binding])
			uniforms.append(uni)
		
		uniform_set_rid = rd.uniform_set_create(uniforms, shader_rid, 0)

func _cleanup_all_gpu_resources() -> void:
	if uniform_set_rid.is_valid(): rd.free_rid(uniform_set_rid)
	for rid in _buffer_rids.values():
		rd.free_rid(rid)
	rd.free_rid(pipeline_rid)
	rd.free_rid(shader_rid)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_exit_thread = true
		_semaphore.post()
		if _thread.is_started():
			_thread.wait_to_finish()
