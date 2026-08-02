class_name TorchFlicker
extends OmniLight3D
## Makes a light behave like fire.
##
## The brief calls for warm torchlight in a dark gothic cemetery, and a torch that
## burns at a constant energy reads as a lamp rather than a flame. Two noise
## streams at different rates give a slow breathing wander with a fast crackle on
## top, which is what sells fire cheaply.
##
## Position wobbles slightly too, so cast shadows shift and the world feels alive
## rather than static.

@export var base_energy: float = 2.4
## How far energy swings, as a fraction of base.
@export_range(0.0, 1.0, 0.05) var flicker_depth: float = 0.35
@export var slow_rate: float = 1.7
@export var fast_rate: float = 11.0
## Sideways drift in metres. Small on purpose; large values look like a fault.
@export var sway: float = 0.05

var _noise: FastNoiseLite = null
var _time: float = 0.0
var _rest_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_rest_position = position

	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0

	# Each torch starts at a different point in the noise field, or a street of
	# them pulses in unison and reads as a single flashing light.
	_time = randf() * 1000.0


func _process(delta: float) -> void:
	_time += delta

	var slow: float = _noise.get_noise_2d(_time * slow_rate, 0.0)
	var fast: float = _noise.get_noise_2d(0.0, _time * fast_rate)
	# Slow wander dominates; the crackle is a smaller overlay.
	var combined: float = slow * 0.7 + fast * 0.3

	light_energy = base_energy * (1.0 + combined * flicker_depth)

	if sway > 0.0:
		position = _rest_position + Vector3(
			_noise.get_noise_2d(_time * 2.3, 11.0) * sway,
			0.0,
			_noise.get_noise_2d(17.0, _time * 2.1) * sway
		)
