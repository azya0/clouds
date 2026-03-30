@tool
extends EditorScript

@export var bake_this_texture:	bool = false : set = _start
@export var input_file:			String = "res://weights.txt"
@export var shader_material:	ShaderMaterial = null


class Layer:
	var weights:	Array[Array] = []
	var biases:		Array[Array] = []
	
	func add_weight(weight: Array) -> void:
		weight.append(weight)
	
	func add_bias(bias: Array) -> void:
		biases.append(bias)


func get_context():
	var file = FileAccess.open(input_file, FileAccess.READ);
	var context = file.get_as_text();
	file.close();
	
	return context


func _start(new_value) -> void:
	var test = 4
