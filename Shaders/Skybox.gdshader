shader_type sky;

uniform sampler3D perlin_noise;
uniform sampler3D large_cloud_noise;
uniform sampler3D medium_cloud_noise;
uniform sampler3D small_cloud_noise;

uniform int steps		= 128;

uniform vec3 light_direction	= vec3(1.0, -1.0, 1.0);
uniform float density_constant	= 1.0;
uniform float sun_constant		= 1.0;
uniform vec3 sunlight_color		= vec3(1.0);

uniform float phase_impact_1	= 1.0;
uniform float phase_impact_2	= 1.0;
uniform float phase_const_1		= 0.0;
uniform float phase_const_2		= 0.0;

uniform vec3 wind_way = vec3(1.0, 0.0, 0.0);

uniform float fluffiness_coefficient = 1.0;

float get_vorley_noise(sampler3D noise, vec3 position) {
    return texture(noise, position * fluffiness_coefficient).r;
}

float get_perlin_noise(vec3 position) {
	return texture(perlin_noise, position).r;
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

uniform float weather_map_constans = 1.355;

float get_cloud_map(vec3 position) {
	float value = get_perlin_noise(position);
	
	return value * weather_map_constans;
}


float get_density(vec3 position) {
	float value = get_cloud_form(position) * get_cloud_map(position);
	
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
	
	float _sqrt = sqrt(pow(_dot, 2.0) + 1.0 - pow(length(position), 2.0));
	
	return position + direction * (-_dot + _sqrt);
}


vec3 to_density_func_coords(vec3 position) {
	return position / 2.0 + 0.5; // [-1; 1] -> [0; 1]
}

uniform int sun_steps	= 8;

float cast_ray_to_sun(vec3 position) {
	if (sun_steps <= 0) {
		return 1.0;
	}
	
	vec3 direction = -normalize(light_direction);
	vec3 end_point = get_sphere_intersection(position, direction);
	float step_size = distance(end_point, position) / float(sun_steps);
	vec3 addition  = direction * step_size;

	float full_density = 0.0;

	for (int index = 0; index < sun_steps; index++) {
		vec3 local_position = to_density_func_coords(position);
		
		full_density += get_density(local_position);

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

	for (int index = 0; index < steps; index++) {
		vec3 local_position = to_density_func_coords(position);
		
		float density = get_density(local_position) * step_size;
		float sun_density = cast_ray_to_sun(position);

		position += addition;
		
		float sun_impact = exp(-sun_constant * sun_density);

		float phase1 = phase_impact_1 * phase_function(cos_teta, phase_const_1);
		float phase2 = phase_impact_2 * phase_function(cos_teta, phase_const_2);
		
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
		vec3 wind_impact = TIME / 10.0 * wind_way;
		//vec3 wind_impact = vec3(0.0);
		vec3 direction = EYEDIR;
		
		vec4 result = raymarching(direction);
		COLOR = result.rgb;
	}
	
}
