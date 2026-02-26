extends Node2D

var cs := ComputeShader.new("uid://d3t7rb0p5wh1i")

var input := PackedFloat32Array([1.0])
var _init_pos: Vector2
var _last_tick: float
var _gpu_fps: float

@onready var _timer := $Timer

func _ready() -> void:
	_init_pos = $Icon.global_position
	for i in range(1e2):
		input.append(i)
	cs.data_received.connect(func(o): input = o)
	_timer.timeout.connect(func():
		_gpu_fps = input[0] - _last_tick
		_last_tick = input[0]
	)

func _process(_delta: float) -> void:
	var total_elements := input.size()
	var res := sin(deg_to_rad(input[0]))
	cs.set_input(input, PackedInt32Array([total_elements, 0, 0, 0]))
	cs.dispatch()

	_fps()
	
	$Output.text = "GPU CPS: %d\n%.3f" % [_gpu_fps, res]
	$Icon.global_position.x = _init_pos.x + ( 300 * res)

func _do() -> void:
	for i in range(input.size()):
		input[i] = input[i] + 1.0

func _fps() -> void:
	$Label.text = "FPS: %d" % Engine.get_frames_per_second()
