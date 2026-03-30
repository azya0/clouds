shader_type sky;

uniform sampler3D perlin_noise;
uniform sampler3D large_cloud_noise;
uniform sampler3D medium_cloud_noise;
uniform sampler3D small_cloud_noise;
uniform sampler3D curl_noise;

uniform int steps		= 128;

uniform vec3 light_direction	= vec3(1.0, -1.0, 1.0);
uniform float density_constant	= 1.0;
uniform float sun_constant		= 1.0;
uniform vec3 sunlight_color		= vec3(1.0);

uniform float phase_impact_1	= 1.0;
uniform float phase_impact_2	= 1.0;
uniform float phase_const_1		= 0.0;
uniform float phase_const_2		= 0.0;

uniform float fluffiness_coefficient = 1.0;

float get_vorley_noise(sampler3D noise, vec3 position) {
    return texture(noise, position * fluffiness_coefficient).r;
}

float get_perlin_noise(vec3 position) {
	return texture(perlin_noise, position).r;
}

vec3 to_01(vec3 position) {
	return position / 2.0 + 0.5; // [-1; 1] -> [0; 1]
}

float to_01(float value) {
	return value / 2.0 + 0.5; // [-1; 1] -> [0; 1]
}

uniform float large_cloud_form_const = 1.0;
uniform float medium_cloud_form_const = 1.0;
uniform float small_cloud_form_const = 1.0;

float get_cloud_form(vec3 position) {
	float worley_larger = get_vorley_noise(large_cloud_noise, position);
	float worley_medium = get_vorley_noise(medium_cloud_noise, position);
	float worley_small = get_vorley_noise(small_cloud_noise, position);

	return (
		worley_larger * large_cloud_form_const +
	    worley_medium * medium_cloud_form_const +
		worley_small * small_cloud_form_const
	);
}

uniform float weather_map_constans = 0.035;

float get_cloud_map(vec3 position) {
	float value = get_perlin_noise(position);
	
	return to_01(value) * weather_map_constans;
}

uniform int curl_steps         = 3;
uniform float curl_intensivity = 0.02;
uniform float edges_wind_power = 0.002;


vec3 move_by_curl(vec3 position, float time) {
	vec3 result_position = position;
	
	for (int index = 0; index < curl_steps; index++) {
		vec3 curl_coords = result_position + time * edges_wind_power;
		
		vec3 curl_position = texture(curl_noise, curl_coords).xyz;
		result_position += curl_position * curl_intensivity;
	}
	
	return result_position;
}

uniform vec3 wind_direction = vec3(1., 0., 0.);

float get_density(vec3 position, float time) {
	vec3 wind_impact = time / 100.0 * -wind_direction;
    
    float cloud_map = get_cloud_map(position);
	
	vec3 moved_position = move_by_curl(position, time) + wind_impact;
	
	float value = get_cloud_form(moved_position) * cloud_map;
	
	if (value < 0.05) {
		return 0.0;
	}
	
	return value;
}


float phase_function(float cos_teta, float g) {
	const float base = (1.0 / 4.0 / PI);

	return base * pow((1.0 - pow(g, 2.0)) / (1.0 + pow(g, 2.0) - 2.0 * g * cos_teta), 1.5);
}


vec3 get_sphere_intersection(vec3 position, vec3 direction) {
	float _dot = dot(position, direction);
	
	float _sqrt = sqrt(_dot * _dot + 1.0 - length(position) * length(position));
	
	return position + direction * (-_dot + _sqrt);
}

uniform int sun_steps	= 8;

float cast_ray_to_sun(vec3 position, float current_time) {
	if (sun_steps <= 0) {
		return 0.0;
	}
	
	vec3 direction = -normalize(light_direction);
	vec3 end_point = get_sphere_intersection(position, direction);
	float step_size = distance(end_point, position) / float(sun_steps);
	vec3 addition  = direction * step_size;

	float full_density = 0.0;

	for (int index = 0; index < sun_steps; index++) {
		// Важно переводить в локальные координаты!
		vec3 local_position = to_01(position);
		
		full_density += get_density(local_position, current_time);

		position += addition;
	}

	return full_density * step_size;
}

uniform float percentage_troposphere = 0.25;

vec4 raymarching(vec3 direction) {
	float step_size = percentage_troposphere / float(steps);
	vec3 position = (1. - percentage_troposphere) * direction;
	vec3 addition = direction * step_size;

	vec3 color = vec3(0.);
	float transmittance = 1.;

	float cos_teta = max(0, dot(direction, normalize(light_direction)));
	
	float phase1 = phase_impact_1 * phase_function(cos_teta, phase_const_1);
	float phase2 = phase_impact_2 * phase_function(cos_teta, phase_const_2);
	
	float current_time = 0.0;

	for (int index = 0; index < steps; index++) {
		vec3 local_position = to_01(position);
		
		float density = get_density(local_position, current_time) * step_size;
		float sun_density = cast_ray_to_sun(position, current_time);

		position += addition;
		
		float sun_impact = exp(-sun_constant * sun_density);
		
		float density_impact = density_constant * density;

		float light = (phase1 + phase2) * sun_impact * density_impact;

		color += sunlight_color * light * transmittance;
		transmittance *= exp(-sun_constant * density);
	}

	vec4 result = vec4(color, 1.0 - transmittance);

	// Add phase function impact
	//result *= phase_function();

	return result;
}


void sky() {
	if (EYEDIR.y >= 0.0) {
		vec3 direction = EYEDIR;
		
		vec4 result = raymarching(direction);
		COLOR = result.rgb;
	}
	
}
