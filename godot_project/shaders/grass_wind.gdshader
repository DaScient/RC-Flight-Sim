// grass_wind.gdshader
// GPU grass blades that bend in the wind. Spatial vertex shader; uses only the
// per-vertex green-channel COLOR as a "stiffness/height" weight so the blade
// root stays planted while the tip sways. GLES3-safe (no derivatives, no
// instancing-specific extensions beyond MultiMesh which Godot handles).
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.3);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.4;
uniform float wind_speed : hint_range(0.0, 8.0) = 2.0;
uniform float gust : hint_range(0.0, 2.0) = 0.0; // pushed by WeatherController
uniform float stiffness : hint_range(0.1, 4.0) = 1.5;

void vertex() {
	// COLOR.g authored 0 at root -> 1 at tip controls sway amount.
	float bend = pow(COLOR.g, stiffness);
	vec3 wd = normalize(wind_direction);
	// Phase varies per-blade by world position so the field ripples.
	float phase = VERTEX.x * 0.25 + VERTEX.z * 0.25;
	float sway = sin(TIME * wind_speed + phase) * 0.5 + 0.5;
	float amount = (wind_strength + gust) * bend * sway;
	VERTEX += wd * amount;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
