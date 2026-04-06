extends Camera3D


func _physics_process(delta: float) -> void:
	self.rotate(Vector3(0.0, 1.0, 0.0), delta / 10.0);
