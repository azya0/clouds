shader_type sky;

uniform sampler3D perlin_noise;
uniform sampler3D large_cloud_noise;
uniform sampler3D medium_cloud_noise;
uniform sampler3D small_cloud_noise;

uniform int steps		= 128;
uniform int sun_steps	= 8;

uniform float form_multiplier		= 0.065;

uniform vec3 light_direction	= vec3(1.0, -1.0, 1.0);
uniform float density_constant	= 1.0;
uniform float sun_constant		= 1.0;
uniform vec3 sunlight_color		= vec3(1.0);

uniform float phase_impact_1	= 1.0;
uniform float phase_impact_2	= 1.0;
uniform float phase_const_1		= 0.0;
uniform float phase_const_2		= 0.0;

uniform vec3 wind_way = vec3(1.0, 0.0, 0.0);


struct RayLimit {
	vec3 start;
	vec3 end;	
};


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


float phase_function(float cos_teta, float g) {
	const float base = (1.0 / 4.0 / PI);

	return base * pow((1.0 - pow(g, 2.0)) / (1.0 + pow(g, 2.0) - 2.0 * g * cos_teta), 1.5);
}


vec4 raymarching(vec3 wind_impact, vec3 direction) {
	float step_size = 1.0 / float(steps);
	vec3 position = 0.75 * direction + wind_impact;
	vec3 addition = direction * step_size;

	vec3 color = vec3(0.0);
	float transmittance = 1.0;

	float cos_teta = max(0, dot(direction, light_direction));

	for (int index = 0; index < steps; index++) {
		vec3 local_position = position / 2.0 + 0.5; // [-1; 1] -> [0; 1]
		
		float density = get_density(local_position) * step_size;
		//float sun_density = cast_ray_to_sun(local_position);
		float sun_density = 0.0;

		position += addition;

		float phase1 = phase_impact_1 * phase_function(cos_teta, phase_const_1);
		float phase2 = phase_impact_2 * phase_function(cos_teta, phase_const_2);

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
	vec3 wind_impact = TIME / 10.0 * wind_way;
	//vec3 wind_impact = vec3(0.0);
	vec3 direction = EYEDIR;
	
	vec4 result = raymarching(wind_impact, direction);
	COLOR = result.rgb;
}
