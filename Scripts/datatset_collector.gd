extends Node

@onready var world_env = $WorldEnvironment


class Noises:
	var perlin:	NoiseTexture3D
	var large:	NoiseTexture3D
	var medium:	NoiseTexture3D
	var small:	NoiseTexture3D
	var curl:	GPUNoiseTexture3D
	
	func _init(
		_perlin: NoiseTexture3D,
		_large: NoiseTexture3D,
		_medium: NoiseTexture3D,
		_small: NoiseTexture3D,
		_curl: GPUNoiseTexture3D
	) -> void:
		perlin = _perlin
		large = _large
		medium = _medium
		small = _small
		curl = _curl


class NoisesCoeffs:
	var large:					float
	var medium:					float
	var small:					float
	var weather_map_constans:	float
	
	func _init(_large: float, _medium: float, _small: float, _weather_map_constans: float) -> void:
		large = _large
		medium = _medium
		small = _small
		weather_map_constans = _weather_map_constans


class ShaderParams:
	var noises: 		Noises
	var noises_params:	NoisesCoeffs
	
	func _init(_noises: Noises, _noises_params: NoisesCoeffs) -> void:
		noises = _noises
		noises_params = _noises_params


func get_shader_params() -> ShaderParams:
	var env = world_env.environment
	
	if not env:
		print("Нет Environment")
		return
	
	var sky = env.sky
	
	if not sky:
		print("Нет Sky")
		return
	
	var sky_material = sky.sky_material
	
	if not sky_material:
		print("Нет Sky Material")
		return
	
	var noises: Noises = Noises.new(
		sky_material.get_shader_parameter("perlin_noise"),
		sky_material.get_shader_parameter("large_cloud_noise"),
		sky_material.get_shader_parameter("medium_cloud_noise"),
		sky_material.get_shader_parameter("small_cloud_noise"),
		sky_material.get_shader_parameter("curl_noise")
	)
	
	var noises_params: NoisesCoeffs = NoisesCoeffs.new(
		sky_material.get_shader_parameter("large_cloud_form_const"),
		sky_material.get_shader_parameter("medium_cloud_form_const"),
		sky_material.get_shader_parameter("small_cloud_form_const"),
		sky_material.get_shader_parameter("weather_map_constans")
	)
	
	return ShaderParams.new(noises, noises_params)
	

func write_data(file: FileAccess, x: int, y: int, z: int, value: float):
	var string = "%d,%d,%d,%f;" % [x, y, z, value]
	
	file.store_line(string)


func noise_to_csv(noise: Noise, path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	
	var size: int = 256
	
	for z in range(size):
		for x in range(size):
			for y in range(size):
				var value: float = noise.get_noise_3d(
					float(x) / size,
					float(y) / size,
					float(z) / size,
				)
				
				write_data(file, x, y, z, value)
	
	file.close()


func _ready() -> void:
	var params = get_shader_params()
	
	noise_to_csv(params.noises.small.noise, "res://Dataset/small.csv")
