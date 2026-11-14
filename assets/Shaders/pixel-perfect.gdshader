shader_type canvas_item;

group_uniforms color;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 1.5) = 1.05;
/** Dvoubarevná paleta (stíny -> světla), použije se, když není gradient_map. */
uniform vec4 shadow_color : source_color = vec4(0.16, 0.10, 0.24, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.93, 0.80, 1.0);
/** Volitelně: GradientTexture1D s víc barvami palety. */
uniform sampler2D gradient_map : filter_linear, repeat_disable;
uniform bool use_gradient_map = true;
/** Kolik palety se přimíchá. 0 = originál, 1 = čistý duotón. */
uniform float palette_strength : hint_range(0.0, 1.0) = 0.3;
/** 0 = vypnuto. 6–12 dá jemně "malovaný" vzhled. */
uniform float posterize_steps : hint_range(0.0, 32.0, 1.0) = 0.0;

group_uniforms grain;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.06;
uniform float grain_size : hint_range(1.0, 8.0) = 1.0;
/** Jak často se zrno mění. 0 = statické. */
uniform float grain_fps : hint_range(0.0, 30.0) = 12.0;
group_uniforms;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash(vec2 p) {
	vec2 q = fract(p * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 c = src.rgb;

	// 1) saturace + kontrast
	c = mix(vec3(luma(c)), c, saturation);
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);

	// 2) paleta podle jasu (gradient map / duotón)
	float l = luma(c);
	vec3 pal = use_gradient_map
		? texture(gradient_map, vec2(l, 0.5)).rgb
		: mix(shadow_color.rgb, highlight_color.rgb, l);
	c = mix(c, pal, palette_strength);

	// 3) posterizace
	if (posterize_steps > 0.0) {
		c = floor(c * posterize_steps + 0.5) / posterize_steps;
	}

	// 4) grain – nejvíc ve středních tónech
	float t = grain_fps > 0.0 ? floor(TIME * grain_fps) : 0.0;
	float n = hash(floor(FRAGCOORD.xy / grain_size) + t * 17.13) - 0.5;
	float mid = 1.0 - abs(l * 2.0 - 1.0);
	c += n * grain_amount * (0.4 + 0.6 * mid);

	COLOR = vec4(clamp(c, 0.0, 1.0), src.a);
}
