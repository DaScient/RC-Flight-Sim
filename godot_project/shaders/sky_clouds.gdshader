// sky_clouds.gdshader
// Physically-flavoured procedural sky with raymarch-lite fBm cloud layer.
// shader_type sky works in both Forward+ and Compatibility (GLES3) renderers.
// All features used here (value-noise fBm, gradients) are GLES3-safe — no
// compute, no screen-space buffers, no derivatives required.
shader_type sky;
render_mode use_quarter_res_pass;

// --- Time-of-day / atmosphere uniforms (driven by WeatherController) -------
uniform vec3 day_top_color : source_color = vec3(0.18, 0.38, 0.72);
uniform vec3 day_horizon_color : source_color = vec3(0.65, 0.78, 0.95);
uniform vec3 night_top_color : source_color = vec3(0.01, 0.02, 0.05);
uniform vec3 night_horizon_color : source_color = vec3(0.04, 0.05, 0.10);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy : hint_range(0.0, 20.0) = 8.0;

// 0 = midnight, 1 = noon. Drives the day/night blend.
uniform float daylight : hint_range(0.0, 1.0) = 1.0;

// --- Cloud controls (driven by the dynamic weather system) -----------------
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_sharpness : hint_range(0.1, 8.0) = 2.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec2 cloud_wind = vec2(0.01, 0.004); // UV drift per second
uniform float cloud_quality : hint_range(1.0, 5.0) = 3.0; // fBm octaves (LOD)

// Simple value-noise hash (deterministic, GLES3-friendly).
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) break;
		sum += amp * value_noise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return sum;
}

void sky() {
	// Sky gradient by elevation (EYEDIR.y in -1..1).
	float h = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 top = mix(night_top_color, day_top_color, daylight);
	vec3 horizon = mix(night_horizon_color, day_horizon_color, daylight);
	vec3 sky_col = mix(horizon, top, pow(h, 0.5));

	// Sun disc + glow using LIGHT0 direction.
	float sun_d = dot(EYEDIR, LIGHT0_DIRECTION);
	float disc = smoothstep(0.9995, 0.9998, sun_d);
	float glow = pow(max(sun_d, 0.0), 64.0);
	sky_col += sun_color * (disc * sun_energy + glow * 0.4 * daylight);

	// Stars at night (only above the horizon).
	if (daylight < 0.4 && EYEDIR.y > 0.0) {
		float star = step(0.997, hash(floor(EYEDIR.xz * 400.0)));
		sky_col += vec3(star) * (1.0 - daylight) * 0.8;
	}

	// Cloud layer: project the view ray onto a virtual cloud plane.
	if (EYEDIR.y > 0.02) {
		vec2 uv = EYEDIR.xz / EYEDIR.y;
		uv = uv * 0.15 + cloud_wind * TIME;
		int octaves = int(clamp(cloud_quality, 1.0, 5.0));
		float n = fbm(uv * 2.0, octaves);
		// Coverage threshold -> soft cloud mask.
		float mask = smoothstep(1.0 - cloud_coverage, 1.0, pow(n, cloud_sharpness) + cloud_coverage * 0.5);
		mask *= smoothstep(0.02, 0.25, EYEDIR.y); // fade at horizon
		vec3 lit_cloud = cloud_color * mix(0.4, 1.0, daylight);
		sky_col = mix(sky_col, lit_cloud, clamp(mask, 0.0, 1.0));
	}

	COLOR = sky_col;
}
