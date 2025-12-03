shader_type spatial;
render_mode world_vertex_coords, unshaded;

uniform sampler3D cloud;


struct Segment {
	bool was_init;
	vec3 start_point;
	vec3 end_point;
};


Segment get_intersection(vec3 ray_origin, vec3 ray_direction, vec3 sphere_center, float radius) {
	Segment result;
	result.was_init = false;

	float b = 2.0 * dot(ray_origin, ray_direction);
	float c = dot(ray_origin, ray_origin) - pow(radius, 2.0);

	float discrim = pow(b, 2.0) - 4.0 * c;

	if (discrim >= 0.0) {
		float t_0 = (-b - sqrt(discrim)) / 2.0;
		float t_1 = (-b + sqrt(discrim)) / 2.0;

		// Retrun to global coords
		result.start_point = ray_direction * t_0 + ray_origin + sphere_center;
		result.end_point   = ray_direction * t_1 + ray_origin + sphere_center;

		result.was_init = true;
	}

	return result;
}


void fragment() {
	vec3 ray_origin    = CAMERA_POSITION_WORLD;
	vec3 sphere_center = vec3(0.0, 0.0, 0);
	vec3 ray_direction = normalize(VERTEX - ray_origin);

	Segment data = get_intersection(
		ray_origin - sphere_center,
		ray_direction,
		sphere_center,
		length(VERTEX - sphere_center)
	);

	if (data.was_init) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
	} else {
		ALBEDO = vec3(0.0, 0.0, 1.0);
	}

	ALPHA  = 1.0;
}
