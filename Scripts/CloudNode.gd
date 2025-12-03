@tool
extends CSGBox3D

var steps: int = 128
var wind: Vector2 = Vector2(1.0, 0.0)

var form_multiplier: float = 0.065;
var density_multiplier: float = 0.25;


func _ready():
	var shader_material = ShaderMaterial.new()
	shader_material.shader = preload("res://Shaders/BoxShader.gdshader")
	self.material = shader_material
	
	shader_material.set_shader_parameter("perlin_noise", load("res://NoiseTextures/PerlinNoise.tres"))
	shader_material.set_shader_parameter("large_cloud_noise", load("res://NoiseTextures/LargeScaleNoise.tres"))
	shader_material.set_shader_parameter("medium_cloud_noise", load("res://NoiseTextures/MediumScaleNoise.tres"))
	shader_material.set_shader_parameter("small_cloud_noise", load("res://NoiseTextures/SmallScaleNoise.tres"))
	
	shader_material.set_shader_parameter("steps", steps)
	
	shader_material.set_shader_parameter("box_center", position)
	shader_material.set_shader_parameter("box_size", size)
	shader_material.set_shader_parameter("box_angle", rotation_degrees)
	
	shader_material.set_shader_parameter("wind", wind)
	
	shader_material.set_shader_parameter("form_multiplier", form_multiplier)
	shader_material.set_shader_parameter("density_multiplier", density_multiplier)
