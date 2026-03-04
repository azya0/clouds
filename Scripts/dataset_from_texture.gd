extends Node3D

@export var noise_texture: NoiseTexture3D  # Подключаем в инспекторе

func _ready():
	# Ждем генерации текстуры
	await noise_texture.changed
	
	# Получаем данные
	await get_3d_noise_data()

func get_3d_noise_data():
	if not noise_texture:
		print("Нет текстуры!")
		return
	
	# Получаем RID через Texture2D (NoiseTexture3D наследуется от Texture2D)
	var texture_rid = noise_texture.get_rid()
	
	# Получаем RD RID
	var rd_rid = RenderingServer.texture_get_rd_texture(texture_rid)
	if not rd_rid.is_valid():
		print("Не удалось получить RD RID")
		return
	
	var rd = RenderingServer.get_rendering_device()
	
	# Синхронизация
	rd.sync()
	
	# Получаем данные
	var data = rd.texture_get_data(rd_rid, 0)
	
	if data.is_empty():
		print("Нет данных!")
		return
	
	print("Получено байт: ", data.size())
	print("Ожидаемый размер: 256x256x256 байта = ", 256 * 256 * 256)
	
	# Создаем 3D массив
	var size = 256
	var voxel_data = []
	voxel_data.resize(size)
	
	var peer = StreamPeerBuffer.new()
	peer.data_array = data
	peer.big_endian = false
	
	# Читаем данные срезами
	for z in range(size):
		var slice = []
		slice.resize(size)
		for y in range(size):
			var row = []
			row.resize(size)
			for x in range(size):
				row[x] = peer.get_float()
			slice[y] = row
		voxel_data[z] = slice
	
	print("Данные загружены!")
	
	# Сохраняем для проверки (MID срез)
	save_slice_as_image(voxel_data, size/2)

func analyze_noise_data(data: Array):
	var min_val = 1.0
	var max_val = 0.0
	var sum = 0.0
	var count = 0
	
	for z in range(data.size()):
		for y in range(data[z].size()):
			for x in range(data[z][y].size()):
				var val = data[z][y][x]
				min_val = min(min_val, val)
				max_val = max(max_val, val)
				sum += val
				count += 1
	
	print("Min: ", min_val)
	print("Max: ", max_val)
	print("Avg: ", sum / count)

func save_slice_as_image(data: Array, slice_z: int):
	var size = data.size()
	var image = Image.create(size, size, false, Image.FORMAT_RF)
	
	for y in range(size):
		for x in range(size):
			var val = data[slice_z][y][x]
			image.set_pixel(x, y, Color(val, 0, 0))
	
	image.save_png("res://Dataset/" + str(slice_z) + ".png")
	print("Срез сохранен!")
