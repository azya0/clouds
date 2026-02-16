shader_type sky;

uniform sampler3D perlin_noise;
uniform sampler3D large_cloud_noise;
uniform sampler3D medium_cloud_noise;
uniform sampler3D small_cloud_noise;

uniform int steps		= 128;
uniform int sun_steps	= 8;

uniform float form_multiplier		= 0.065;

uniform vec3 light_direction	= vec3(1.0, -1.0, 1.0);
uniform float density_constant	= 0.48;
uniform float sun_constant		= 0.47;
uniform vec3 sunlight_color		= vec3(1.0);

uniform float phase_impact_1	= 20.0;
uniform float phase_impact_2	= 10.0;
uniform float phase_const_1		= 0.9;
uniform float phase_const_2		= 0.4;

uniform vec3 wind_way = vec3(1.0, 0.0, 0.0);

render_mode use_debanding;

uniform vec4 sky_top_color : source_color = vec4(0.385, 0.454, 0.55, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float inv_sky_curve : hint_range(1, 100) = 4.0;
uniform vec4 ground_bottom_color : source_color = vec4(0.2, 0.169, 0.133, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float inv_ground_curve : hint_range(1, 100) = 30.0;
uniform float sun_angle_max = 0.877;
uniform float inv_sun_curve : hint_range(1, 100) = 22.78;
uniform float exposure : hint_range(0, 128) = 1.0;

uniform sampler2D sky_cover : filter_linear, source_color, hint_default_black;
uniform vec4 sky_cover_modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);


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


// [-1; 1] -> [0; 1]
vec3 to_noise_coords(vec3 coords) {
	return coords / 2.0 + 0.5;
}

vec3 sphere_intersection(vec3 position, vec3 direction) {
	float _dot = dot(position, direction);
	float length_2 = pow(length(position), 2.0);
	float _sqrt = sqrt(_dot * _dot + 1.0 - length_2);
	
	return position + direction * (-_dot + _sqrt);
}


float cast_ray_to_sun(vec3 position) {
	vec3 direction = -normalize(light_direction);
	vec3 end_position = sphere_intersection(position, direction);
	vec3 step_size = (end_position - position) / float(sun_steps);
	float step_length = length(step_size);

	float full_density = 0.0;

	for (int index = 0; index < sun_steps; index++) {
		full_density += get_density(to_noise_coords(position)) * step_length;

		position += step_size;
	}

	return full_density;
}


vec4 raymarching(vec3 wind_impact, vec3 direction) {
	float step_size = 0.25 / float(steps);
	vec3 position = 0.75 * direction + wind_impact;
	vec3 addition = direction * step_size;

	vec3 color = vec3(0.0);
	float transmittance = 1.0;

	float cos_teta = max(0, dot(direction, light_direction));

	for (int index = 0; index < steps; index++) {
		float density = get_density(to_noise_coords(position)) * step_size;
		// float sun_density = cast_ray_to_sun(position);
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


vec3 get_base(vec3 direction) {
	float v_angle = clamp(direction.y, -1.0, 1.0);
	vec3 sky = mix(sky_top_color.rgb, sky_horizon_color.rgb, clamp(pow(1.0 - v_angle, inv_sky_curve), 0.0, 1.0));

	if (LIGHT0_ENABLED) {
		float sun_angle = dot(LIGHT0_DIRECTION, direction);
		float sun_size = cos(LIGHT0_SIZE);
		if (sun_angle > sun_size) {
			sky = LIGHT0_COLOR * LIGHT0_ENERGY;
		} else if (sun_angle > sun_angle_max) {
			float c2 = (sun_size - sun_angle) / (sun_size - sun_angle_max);
			sky = mix(sky, LIGHT0_COLOR * LIGHT0_ENERGY, clamp(pow(1.0 - c2, inv_sun_curve), 0.0, 1.0));
		}
	}

	if (LIGHT1_ENABLED) {
		float sun_angle = dot(LIGHT1_DIRECTION, direction);
		float sun_size = cos(LIGHT1_SIZE);
		if (sun_angle > sun_size) {
			sky = LIGHT1_COLOR * LIGHT1_ENERGY;
		} else if (sun_angle > sun_angle_max) {
			float c2 = (sun_size - sun_angle) / (sun_size - sun_angle_max);
			sky = mix(sky, LIGHT1_COLOR * LIGHT1_ENERGY, clamp(pow(1.0 - c2, inv_sun_curve), 0.0, 1.0));
		}
	}

	if (LIGHT2_ENABLED) {
		float sun_angle = dot(LIGHT2_DIRECTION, direction);
		float sun_size = cos(LIGHT2_SIZE);
		if (sun_angle > sun_size) {
			sky = LIGHT2_COLOR * LIGHT2_ENERGY;
		} else if (sun_angle > sun_angle_max) {
			float c2 = (sun_size - sun_angle) / (sun_size - sun_angle_max);
			sky = mix(sky, LIGHT2_COLOR * LIGHT2_ENERGY, clamp(pow(1.0 - c2, inv_sun_curve), 0.0, 1.0));
		}
	}

	if (LIGHT3_ENABLED) {
		float sun_angle = dot(LIGHT3_DIRECTION, direction);
		float sun_size = cos(LIGHT3_SIZE);
		if (sun_angle > sun_size) {
			sky = LIGHT3_COLOR * LIGHT3_ENERGY;
		} else if (sun_angle > sun_angle_max) {
			float c2 = (sun_size - sun_angle) / (sun_size - sun_angle_max);
			sky = mix(sky, LIGHT3_COLOR * LIGHT3_ENERGY, clamp(pow(1.0 - c2, inv_sun_curve), 0.0, 1.0));
		}
	}
	
	vec3 ground = mix(ground_bottom_color.rgb, ground_horizon_color.rgb, clamp(pow(1.0 + v_angle, inv_ground_curve), 0.0, 1.0));

	return mix(ground, sky, step(0.0, direction.y)) * exposure;
}


void sky() {
	vec3 base = get_base(EYEDIR);
	
	if (EYEDIR.y >= 0.0) {
		//vec3 wind_impact = TIME / 10.0 * wind_way;
		vec3 wind_impact = vec3(0.0);
		vec3 direction = EYEDIR;
		
		vec4 result = raymarching(wind_impact, direction);
		COLOR = result.rgb;
	}
}
