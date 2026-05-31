extends Node3D

@export var play_on_ready: bool = true
@export var loop: bool = true
@export var duration_seconds: float = 120.0
@export var time_scale: float = 1.0
@export var recording_fps: int = 60
@export var quit_when_finished: bool = false
@export var print_debug: bool = false

@export var world_environment: WorldEnvironment
@export var camera: Camera3D

@export_group("Sun")
@export_range(0.0, 89.0, 0.1, "degrees") var sun_start_elevation_degrees: float = 55.0
@export_range(0.0, 89.0, 0.1, "degrees") var sun_end_elevation_degrees: float = 8.0
@export_range(-360.0, 360.0, 0.1, "degrees") var sun_start_azimuth_degrees: float = 75.0
@export_range(-360.0, 360.0, 0.1, "degrees") var sun_end_azimuth_degrees: float = 115.0

@export_group("Camera")
@export var camera_position: Vector3 = Vector3.ZERO
@export_range(0.0, 89.0, 0.1, "degrees") var view_pitch_degrees: float = 55.0
@export_range(-360.0, 360.0, 0.1, "degrees") var start_yaw_degrees: float = 0.0
@export_range(-90.0, 90.0, 0.1, "degrees") var pan_degrees_per_second: float = 3.0

var _elapsed: float = 0.0
var _is_playing: bool = false
var _sky_material: ShaderMaterial
var _debug_elapsed: float = 0.0
var _finish_requested: bool = false
var _recorded_frames: int = 0


func _ready() -> void:
	set_process(true)
	_resolve_references()
	_is_playing = play_on_ready
	_apply_timelapse(0.0, 0.0)


func _process(delta: float) -> void:
	if not _is_playing:
		return

	var safe_duration = max(duration_seconds, 0.001)
	if not loop and quit_when_finished:
		_process_recording_frame(safe_duration)
		return

	_elapsed += delta * time_scale

	if loop:
		_elapsed = fmod(_elapsed, safe_duration)
	else:
		_elapsed = min(_elapsed, safe_duration)

	var progress = _elapsed / safe_duration
	_apply_timelapse(progress, _elapsed)
	_print_debug(delta, progress)


func play() -> void:
	_is_playing = true


func pause() -> void:
	_is_playing = false


func restart() -> void:
	_elapsed = 0.0
	_finish_requested = false
	_recorded_frames = 0
	_is_playing = true
	_apply_timelapse(0.0, 0.0)


func _process_recording_frame(safe_duration: float) -> void:
	var total_frames = max(1, int(round(safe_duration * max(recording_fps, 1))))
	var denominator = max(total_frames - 1, 1)
	var progress = float(_recorded_frames) / float(denominator)

	_elapsed = progress * safe_duration
	_apply_timelapse(progress, _elapsed)
	_print_debug(1.0 / float(max(recording_fps, 1)), progress)

	_recorded_frames += 1
	if _recorded_frames >= total_frames and not _finish_requested:
		_finish_requested = true
		_is_playing = false
		get_tree().call_deferred("quit")


func _resolve_references() -> void:
	if world_environment == null:
		world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment

	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D

	if world_environment == null:
		push_warning("TimelapseController: WorldEnvironment is not assigned.")
		return

	if world_environment.environment == null or world_environment.environment.sky == null:
		push_warning("TimelapseController: WorldEnvironment has no Sky.")
		return

	var material = world_environment.environment.sky.sky_material
	if material is ShaderMaterial:
		_sky_material = material
	else:
		push_warning("TimelapseController: Sky material is not a ShaderMaterial.")


func _apply_timelapse(progress: float, elapsed: float) -> void:
	var t = clamp(progress, 0.0, 1.0)
	var smooth_t = t * t * (3.0 - 2.0 * t)

	_apply_sun(smooth_t)
	_apply_camera(elapsed)


func _apply_sun(t: float) -> void:
	if _sky_material == null:
		return

	var elevation = lerp(deg_to_rad(sun_start_elevation_degrees), deg_to_rad(sun_end_elevation_degrees), t)
	var azimuth = lerp(deg_to_rad(sun_start_azimuth_degrees), deg_to_rad(sun_end_azimuth_degrees), t)
	var horizontal = cos(elevation)
	var visible_sun_direction = Vector3(
		sin(azimuth) * horizontal,
		sin(elevation),
		-cos(azimuth) * horizontal
	).normalized()
	_sky_material.set_shader_parameter("light_direction", -visible_sun_direction)


func _apply_camera(elapsed: float) -> void:
	if camera == null:
		return

	var yaw = deg_to_rad(start_yaw_degrees + pan_degrees_per_second * elapsed)
	var pitch = deg_to_rad(view_pitch_degrees)
	var horizontal = cos(pitch)
	var view_direction = Vector3(
		sin(yaw) * horizontal,
		sin(pitch),
		-cos(yaw) * horizontal
	).normalized()

	camera.global_position = to_global(camera_position)
	camera.look_at(camera.global_position + view_direction, Vector3.UP)
	camera.current = true


func _print_debug(delta: float, progress: float) -> void:
	if not print_debug:
		return

	_debug_elapsed += delta
	if _debug_elapsed < 1.0:
		return

	_debug_elapsed = 0.0
	var light_direction = Vector3.ZERO
	var visible_sun_direction = Vector3.ZERO
	if _sky_material != null:
		light_direction = _sky_material.get_shader_parameter("light_direction")
		visible_sun_direction = -light_direction

	var camera_position = Vector3.ZERO
	if camera != null:
		camera_position = camera.global_position

	print(
		"Timelapse progress=", snapped(progress, 0.001),
		" light_direction=", light_direction,
		" visible_sun_direction=", visible_sun_direction,
		" camera_position=", camera_position
	)
