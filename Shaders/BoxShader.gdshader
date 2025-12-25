shader_type spatial;
render_mode unshaded;

uniform sampler3D perlin_noise;
uniform sampler3D large_cloud_noise;
uniform sampler3D medium_cloud_noise;
uniform sampler3D small_cloud_noise;

uniform int steps = 128;
uniform int sun_steps = 8;

uniform vec3 box_center;
uniform vec3 box_size;
uniform vec3 box_angle;

uniform float form_multiplier = 0.065;
uniform float density_multiplier = 0.25;

uniform vec3 light_direction  = vec3(1.0, -1.0, 1.0);
uniform float density_constant = 1.0;
uniform float sun_constant     = 1.0;

varying vec3 box_min;
varying vec3 box_max;

mat3 get_rotation_matrix(vec3 angles) {
    float cx = cos(angles.x);
    float sx = sin(angles.x);
    float cy = cos(angles.y);
    float sy = sin(angles.y);
    float cz = cos(angles.z);
    float sz = sin(angles.z);

    return mat3(
        vec3(cy * cz, cx * sz + sx * sy * cz, sx * sz - cx * sy * cz),
        vec3(-cy * sz, cx * cz - sx * sy * sz, sx * cz + cx * sy * sz),
        vec3(sy, -sx * cy, cx * cy)
    );
}

struct GetIntersectionsProps {
    vec3 ray_origin;
    vec3 ray_direction;
};

struct IntersectionResult {
    vec3[2] array;
	bool is_valid;
};

IntersectionResult get_intersections(GetIntersectionsProps props) {
	const float EPSILON = 1e-6;
	vec3 dodge_inf = EPSILON * sign(props.ray_direction);
	
	vec3 inv_dir = 1.0 / (props.ray_direction + dodge_inf);

	vec3 tbot = inv_dir * (box_min - props.ray_origin);
    vec3 ttop = inv_dir * (box_max - props.ray_origin);

    vec3 tminXYZ = min(ttop, tbot);
    vec3 tmaxXYZ = max(ttop, tbot);

	IntersectionResult result;

	float t_min = max(tminXYZ.x, max(tminXYZ.y, tminXYZ.z));
	float t_max = min(tmaxXYZ.x, min(tmaxXYZ.y, tmaxXYZ.z));

    result.array[0] = props.ray_origin + props.ray_direction * t_min;
    result.array[1] = props.ray_origin + props.ray_direction * t_max;

	result.is_valid = t_max > max(t_min, 0.0);

	return result;
}

IntersectionResult process_intersections(IntersectionResult intersection, mat3 rot, vec3 world_ray_origin) {
	for (int index = 0; index < 2; index++) {
        intersection.array[index] = rot * intersection.array[index] + box_center;
    }

	return intersection;
}

float process_noise(sampler3D noise, vec3 position) {
    return clamp((1.0 - texture(noise, position).r) * 1.5 - 0.25, 0.0, 1.0);
}

float remap(float value, float _min, float _max, float r_min, float r_max) {
    return r_min + (value - _min) / (_max - _min) * (r_max - r_min);
}

float low_frequency_noise(float high_frequency_value, vec3 position) {
	float perlin_value = texture(perlin_noise, position).r;

	return remap(
		perlin_value,
		high_frequency_value - 1.0, 1.0, 0.0, 1.0
	);
}

float high_frequency_noise(vec3 position) {
	float worley_larger = process_noise(large_cloud_noise, position);
	float worley_medium = process_noise(medium_cloud_noise, position);
	float worley_small = process_noise(small_cloud_noise, position);

	return worley_larger * 0.625 + worley_medium * 0.25 + worley_small * 0.125;
}

float get_density(vec3 position) {
	float high_octave = high_frequency_noise(position);
	float low_octave = low_frequency_noise(high_octave, position);

	float result = (high_octave * 0.15 + low_octave * 0.85) * form_multiplier;

	if (result < 0.05) {
		return 0.0;
	}

	return result;
}

// start_position in local coords
float cast_ray_to_sun(vec3 start_position) {
	if (sun_steps == 0) {
		return 1.0;
	}

	GetIntersectionsProps prop;
	prop.ray_origin = start_position;

	// #TODO add rotation logic
	vec3 direction = -normalize(light_direction);
	prop.ray_direction = direction;

	IntersectionResult intersection = get_intersections(prop);
	vec3 end_position;

	vec3 way = normalize(intersection.array[1] - start_position);

	if (dot(direction, way) > 0.0) {
		end_position = intersection.array[0];
	} else {
		end_position = intersection.array[1];
	}

	float total_distance = distance(start_position, end_position);
	float step_size = length(box_size) / float(sun_steps);
	int total_steps = int(total_distance / length(box_size) * float(sun_steps));

	vec3 current_pos = start_position;

	float full_density = 0.0;

	for (int index = 0; index < total_steps; index++) {
		full_density += get_density(current_pos / box_size + 0.5) * step_size;

		current_pos += direction;
	}

	return full_density;
}

vec4 raymarching(vec3 start_point, vec3 end_point, int iterations) {
	float total_distance = distance(start_point, end_point);
	float step_size = length(box_size) / float(iterations);
	int total_steps = int(total_distance / length(box_size) * float(iterations));

	vec3 direction = normalize(end_point - start_point);
	vec3 local_position = start_point - box_center;

	vec3 color = vec3(0.0);
	float transmittance = 1.0;

	for (int index = 0; index < total_steps; index++) {
		float density = get_density(local_position / box_size + 0.5) * step_size;
		// Почекать локалькую позицию
		float sun_density = cast_ray_to_sun(local_position);

		local_position += direction * step_size;

		float sun_impact = exp(-sun_constant * sun_density);
		float density_impact = density_constant * density;
		float light = sun_impact * density_impact;

		color += light * transmittance;
		transmittance *= exp(-sun_constant * density);
	}

	vec4 result = vec4(color, 1.0 - transmittance);

	return result;
}

float phase_function(float cos_teta, float g) {
	return (1.0 - pow(g, 2.0)) / (4.0 * PI * pow((1.0 + pow(g, 2.0) - 2.0 * g * cos_teta), 1.5));
}

void vertex() {
	box_min = box_center - box_size / 2.0;
	box_max = box_center + box_size / 2.0;
}

void fragment() {
    mat3 rotation_matrix = get_rotation_matrix(radians(box_angle));
    mat3 inv_rotation_matrix = get_rotation_matrix(radians(-box_angle));

    vec3 world_ray_origin = CAMERA_POSITION_WORLD - box_center;
	vec3 world_vertex_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 world_ray_direction = normalize(world_vertex_pos - CAMERA_POSITION_WORLD);

    vec3 local_ray_origin = inv_rotation_matrix * world_ray_origin;
    vec3 local_ray_direction = normalize(inv_rotation_matrix * world_ray_direction);

    GetIntersectionsProps intersection_props;
    intersection_props.ray_origin = local_ray_origin;
    intersection_props.ray_direction = local_ray_direction;

	// #TODO: remove translation from local coords to global
    IntersectionResult intersection = process_intersections(
		get_intersections(intersection_props),
		rotation_matrix,
		world_ray_origin
	);

	if (!intersection.is_valid) {
		discard;
	}

    float total_distance = distance(intersection.array[0], intersection.array[1]);

	if ((total_distance < 0.01) || (total_distance > length(box_size))) {
		discard;
	}

	vec4 result = raymarching(
		intersection.array[0],
		intersection.array[1],
		steps
	);

	ALBEDO = result.rgb;
	ALPHA = result.a;
}
