shader_type canvas_item;

uniform float blur_radius : hint_range(0.0, 6.0) = 0.5;
uniform vec4 fog_color : source_color = vec4(0.55, 0.65, 0.85, 1.0);
uniform float fog_amount : hint_range(0.0, 1.0) = 0.4;
uniform float desaturate : hint_range(0.0, 1.0) = 1;
uniform float darken : hint_range(0.0, 1.0) = 0.10;

void fragment() {
	// 5x5 box blur
	vec4 col = vec4(0.0);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 off = vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * blur_radius;
			col += texture(TEXTURE, UV + off);
		}
	}
	col /= 25.0;

	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(gray), desaturate);   // less saturated
	col.rgb = mix(col.rgb, fog_color.rgb, fog_amount); // tint toward sky
	col.rgb *= 1.0 - darken;                           // darker

	COLOR = col * COLOR;
}