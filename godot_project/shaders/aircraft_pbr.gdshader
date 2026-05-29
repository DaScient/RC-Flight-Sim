// aircraft_pbr.gdshader
// Master PBR material for all aircraft (Part 1A). Supports albedo / metallic /
// roughness / normal maps, pre-computed (baked) ambient occlusion, and an
// optional livery decal layer. A `detail_enabled` uniform lets graphics
// presets disable the normal + AO + decal work on the Low preset for free.
// GLES3-safe: standard texture sampling only, no screen-space passes.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// --- Base PBR maps ----------------------------------------------------------
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform sampler2D metallic_tex : hint_default_black;
uniform float metallic_factor : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D roughness_tex : hint_default_white;
uniform float roughness_factor : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D normal_tex : hint_normal;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D ao_tex : hint_default_white; // pre-computed ambient occlusion
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

// --- Livery decal layer (optional) -----------------------------------------
uniform sampler2D livery_tex : source_color, hint_default_transparent;
uniform bool livery_enabled = false;

// --- Quality switch: presets set this to 0.0 on Low to skip detail maps -----
uniform bool detail_enabled = true;

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_tint;
	vec3 col = base.rgb;

	// Livery decal blended over the base albedo by its own alpha.
	if (livery_enabled) {
		vec4 decal = texture(livery_tex, UV);
		col = mix(col, decal.rgb, decal.a);
	}
	ALBEDO = col;

	METALLIC = texture(metallic_tex, UV).r * metallic_factor;
	ROUGHNESS = texture(roughness_tex, UV).r * roughness_factor;

	if (detail_enabled) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
		float ao = texture(ao_tex, UV).r;
		AO = mix(1.0, ao, ao_strength);
		AO_LIGHT_AFFECT = 1.0;
	}
}
