shader_type canvas_item;
// Darkens the edges of whatever is under it. Put it on a full-screen ColorRect
// (mouse_filter = Ignore) above the picture.

uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
/** How dark the very edge gets. */
uniform float strength : hint_range(0.0, 1.0) = 0.9;
/** Where the darkening starts (0 = centre, 1 = edge midpoint). */
uniform float inner_radius : hint_range(0.0, 1.5) = 0.35;
/** Where it reaches full strength (corners are ~1.41). */
uniform float outer_radius : hint_range(0.0, 2.0) = 1.3;

void fragment() {
	float d = length((UV - 0.5) * 2.0);
	float v = smoothstep(inner_radius, outer_radius, d);
	COLOR = vec4(edge_color.rgb, edge_color.a * v * strength);
}
