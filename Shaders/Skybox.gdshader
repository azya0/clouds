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

uniform float phase_impact_1: hint_range(0.0, 50.0)	= 1.0;
uniform float phase_impact_2: hint_range(0.0, 50.0)	= 1.0;
uniform float phase_const_1: hint_range(0.0, 1.0)	= 0.0;
uniform float phase_const_2: hint_range(0.0, 1.0)	= 0.0;

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
	
	float current_time = TIME;

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

uniform vec4 ground_bottom_color : source_color = vec4(0.2, 0.169, 0.133, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float inv_ground_curve : hint_range(1, 100) = 30.0;
uniform float exposure : hint_range(0, 0.085) = 0.07;

const int ATMOSPHERE_VIEW_STEPS = 32;
const int ATMOSPHERE_LIGHT_STEPS = 32;
const float PLANET_RADIUS = 6371000.0;
const float ATMOSPHERE_RADIUS = 6471000.0;
const float RAYLEIGH_SCALE_HEIGHT = 8000.0;
const float MIE_SCALE_HEIGHT = 1200.0;
const vec3 BASE_RAYLEIGH_BETA = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const vec3 BASE_MIE_BETA = vec3(2.0e-5);

uniform float atmosphere_exposure : hint_range(0.0, 1.0) = 0.39;
uniform float atmosphere_intensity : hint_range(0.0, 64.0) = 20.3;
uniform float rayleigh_strength : hint_range(0.0, 8.0) = 0.835;
uniform float mie_strength : hint_range(0.0, 8.0) = 0.8;
uniform float mie_extinction_multiplier : hint_range(0.0, 8.0) = 0.7;
uniform float mie_g : hint_range(0.0, 0.99) = 0.7;
uniform float mie_halo_strength : hint_range(0.0, 2.0) = 0.35;
uniform float sun_disc_size_degrees : hint_range(0.05, 5.0) = 0.53;
uniform float sun_disc_softness_degrees : hint_range(0.0, 2.0) = 0.08;
uniform float sun_disc_intensity : hint_range(0.0, 16.0) = 1.2;

vec2 sphere_intersections(vec3 ray_origin, vec3 ray_direction, float radius) {
	float b = dot(ray_origin, ray_direction);
	float c = dot(ray_origin, ray_origin) - radius * radius;
	float discriminant = b * b - c;

	if (discriminant < 0.0) {
		return vec2(-1.0);
	}

	float sqrt_discriminant = sqrt(discriminant);
	return vec2(-b - sqrt_discriminant, -b + sqrt_discriminant);
}

float rayleigh_phase(float cos_theta) {
	return (3.0 / (16.0 * PI)) * (1.0 + cos_theta * cos_theta);
}

float mie_phase(float cos_theta, float g) {
	float g2 = g * g;
	float denominator = pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5);
	return (3.0 / (8.0 * PI)) * ((1.0 - g2) * (1.0 + cos_theta * cos_theta)) / ((2.0 + g2) * denominator);
}

vec3 get_sun_disc(vec3 view_direction, vec3 sun_direction) {
	float cos_angle = dot(view_direction, sun_direction);
	float disc_inner = cos(radians(sun_disc_size_degrees));
	float disc_outer = cos(radians(sun_disc_size_degrees + sun_disc_softness_degrees));
	float disc = smoothstep(disc_outer, disc_inner, cos_angle);

	return sunlight_color * sun_disc_intensity * disc;
}

vec2 atmosphere_density(vec3 position) {
	float height = max(0.0, length(position) - PLANET_RADIUS);
	return vec2(
		exp(-height / RAYLEIGH_SCALE_HEIGHT),
		exp(-height / MIE_SCALE_HEIGHT)
	);
}

bool ray_hits_planet(vec3 ray_origin, vec3 ray_direction) {
	vec2 hit = sphere_intersections(ray_origin, ray_direction, PLANET_RADIUS);
	return hit.y > 0.0;
}

vec3 get_atmosphere_color(vec3 view_direction, vec3 sun_direction) {
	vec3 ray_origin = vec3(0.0, PLANET_RADIUS + 1.0, 0.0);
	vec2 atmosphere_hit = sphere_intersections(ray_origin, view_direction, ATMOSPHERE_RADIUS);

	if (atmosphere_hit.y <= 0.0) {
		return vec3(0.0);
	}

	float ray_length = atmosphere_hit.y;
	float view_step_size = ray_length / float(ATMOSPHERE_VIEW_STEPS);
	vec3 view_step = view_direction * view_step_size;
	vec3 position = ray_origin + view_step * 0.5;

	float view_optical_depth_rayleigh = 0.0;
	float view_optical_depth_mie = 0.0;
	vec3 rayleigh_sum = vec3(0.0);
	vec3 mie_sum = vec3(0.0);

	vec3 rayleigh_beta = BASE_RAYLEIGH_BETA * rayleigh_strength;
	vec3 mie_beta = BASE_MIE_BETA * mie_strength;
	vec3 mie_extinction = mie_beta * mie_extinction_multiplier;

	for (int view_index = 0; view_index < ATMOSPHERE_VIEW_STEPS; view_index++) {
		vec2 density = atmosphere_density(position);
		float step_rayleigh_depth = density.x * view_step_size;
		float step_mie_depth = density.y * view_step_size;

		view_optical_depth_rayleigh += step_rayleigh_depth;
		view_optical_depth_mie += step_mie_depth;

		vec2 sun_hit = sphere_intersections(position, sun_direction, ATMOSPHERE_RADIUS);
		float sun_ray_length = sun_hit.y;
		float light_step_size = sun_ray_length / float(ATMOSPHERE_LIGHT_STEPS);
		vec3 light_step = sun_direction * light_step_size;
		vec3 light_position = position + light_step * 0.5;

		float sun_optical_depth_rayleigh = 0.0;
		float sun_optical_depth_mie = 0.0;
		bool blocked_by_planet = ray_hits_planet(position, sun_direction);

		if (!blocked_by_planet) {
			for (int light_index = 0; light_index < ATMOSPHERE_LIGHT_STEPS; light_index++) {
				vec2 light_density = atmosphere_density(light_position);
				sun_optical_depth_rayleigh += light_density.x * light_step_size;
				sun_optical_depth_mie += light_density.y * light_step_size;
				light_position += light_step;
			}

			vec3 optical_depth = (
				rayleigh_beta * (view_optical_depth_rayleigh + sun_optical_depth_rayleigh) +
				mie_extinction * (view_optical_depth_mie + sun_optical_depth_mie)
			);
			vec3 transmittance = exp(-optical_depth);

			rayleigh_sum += transmittance * step_rayleigh_depth;
			mie_sum += transmittance * step_mie_depth;
		}

		position += view_step;
	}

	float cos_theta = dot(view_direction, sun_direction);
	vec3 scattering = (
		rayleigh_sum * rayleigh_beta * rayleigh_phase(cos_theta) +
		mie_sum * mie_beta * mie_phase(cos_theta, mie_g) * mie_halo_strength
	);

	vec3 color = sunlight_color * scattering * atmosphere_intensity;
	return vec3(1.0) - exp(-color * atmosphere_exposure);
}


void sky() {
	float v_angle = clamp(EYEDIR.y, -1.0, 1.0);
	vec3 sun_direction = -normalize(light_direction);

	vec3 ground = mix(ground_bottom_color.rgb, ground_horizon_color.rgb, clamp(pow(1.0 + v_angle, inv_ground_curve), 0.0, 1.0));

	if (EYEDIR.y >= 0.0) {
		vec3 direction = EYEDIR;
		vec3 view_direction = normalize(direction);
		vec3 atmosphere = get_atmosphere_color(view_direction, sun_direction);
		atmosphere += get_sun_disc(view_direction, sun_direction);
		vec3 sky_behind = atmosphere * exposure;

		vec4 result = raymarching(direction);

		vec3 finalColor = sky_behind * (1.0 - result.a) + result.rgb;

		COLOR = finalColor;
	} else {
		COLOR = ground * exposure;
	}
}
