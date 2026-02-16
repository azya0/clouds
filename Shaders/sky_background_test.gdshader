shader_type sky;

uniform vec3 light_direction = vec3(0.0, -1.0, 0.0);

uniform int steps = 32;


vec3 sphere_intersection(vec3 position, vec3 direction, float radius) {
	float _dot = dot(position, direction);
	float length_2 = pow(length(position), 2.0);
	float _sqrt = sqrt(_dot * _dot + radius - length_2);
	
	return position + direction * (-_dot + _sqrt);
}

float get_height_percent(vec3 position) {
	return position.y / 6471000.0;
}

float R_func(float angle) {
	return 3.0 * PI / 16.0 * (1.0 + angle * angle);
}

float D(vec3 from, vec3 to, float H_0) {
	vec3 direction = normalize(to - from);
	float step_size = distance(to, from) / float(steps);
	vec3 addition = direction * step_size;
	
	float result = 0.0;
	
	for (int index = 0; index < steps; index++) {
		result += exp(-from.y / H_0) * step_size;
		
		from += addition;
	}
	
	return result;
}

float to_sun(vec3 position, float H_0) {
	vec3 to_sun = -normalize(light_direction);
	vec3 end = sphere_intersection(position, to_sun, 6471000.0);
	
	return D(position, end, H_0);
}

vec3 raymarch(vec3 direction, vec3 base, float H_0) {
	vec3 position = vec3(0.0, 6371000.0, 0.0);
	vec3 end = sphere_intersection(position, direction, 6471000.0);
	float step_size = distance(position, end) / float(steps);
	
	float D_XO = 0.0;
	
	vec3 result = vec3(0.0);
	
	for (int index = 0; index < steps; index++) {
		vec3 addition = exp(-base * (D_XO + to_sun(position, H_0)));
		addition *= base * exp(-position.y / H_0) * step_size;
		
		result += addition;
		
		position += step_size;
		D_XO += exp(-position.y / H_0) * step_size;
	}
	
	return result;
}

void sky() {
	float teta = dot(normalize(light_direction), EYEDIR);
	
	vec3 base = vec3(
		5.8e-6,
		13.5e-6,
		33.1e-6
	);
	
	vec3 rel = vec3(1.0) * R_func(teta) * raymarch(EYEDIR, base, 8000.0);
	
	COLOR = rel;
}