@tool
extends Node

@export var bake_this_texture: bool = false : set = _bake_noise
@export var source_noise_texture: GPUNoiseTexture3D
@export var output_path: String = "res://Dataset/test.tres"

func _bake_noise(_new_value):
	if not source_noise_texture:
		print("Не передал текстуру")
		bake_this_texture = false
		return
	
	call_deferred("_start_baking")

func _start_baking():
	var slices = source_noise_texture.get_data()
	
	if not slices.is_empty():
		_save_texture(slices)
		return
	
	if not source_noise_texture.changed.is_connected(_on_noise_texture_changed):
		source_noise_texture.changed.connect(_on_noise_texture_changed)
	
	_start_timeout_timer()

func _start_timeout_timer():
	print("Пошло запекание")
	await get_tree().create_timer(2.0).timeout
	
	if bake_this_texture:
		print("Таймаут! Пробуем сохранить имеющиеся данные...")
		var slices = source_noise_texture.get_data()
		if not slices.is_empty():
			_save_texture(slices)
		else:
			printerr("Данные так и не сгенерировались!")
			bake_this_texture = false

func _on_noise_texture_changed():
	print("Сигнал changed получен!")
	
	if source_noise_texture.changed.is_connected(_on_noise_texture_changed):
		source_noise_texture.changed.disconnect(_on_noise_texture_changed)
	
	await get_tree().process_frame
	
	var slices = source_noise_texture.get_data()
	if not slices.is_empty():
		_save_texture(slices)

func _save_texture(image_slices):
	print("Формат: ", source_noise_texture.get_format())
	print("Размер: ", source_noise_texture.width, "x", 
		  source_noise_texture.height, "x", source_noise_texture.depth)
	print("Срезов: ", image_slices.size())
	
	var baked = ImageTexture3D.new()
	var create_error = baked.create(
		source_noise_texture.get_format(),
		source_noise_texture.width,
		source_noise_texture.height,
		source_noise_texture.depth,
		false,
		image_slices
	)
	
	if create_error != OK:
		printerr("Ошибка создания: ", create_error)
		bake_this_texture = false
		return
	
	print("Сохраняю в: ", output_path)
	var save_error = ResourceSaver.save(baked, output_path)
	
	if save_error == OK:
		print("Текстура сохранена!")
	else:
		printerr("Ошибка сохранения: ", save_error)
	
	bake_this_texture = false
