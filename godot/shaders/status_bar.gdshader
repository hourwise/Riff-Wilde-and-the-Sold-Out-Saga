shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

uniform vec4 background_color : source_color = vec4(0.1, 0.1, 0.1, 0.8);
uniform vec4 fill_color : source_color = vec4(0.9, 0.1, 0.1, 1.0);
uniform vec4 border_color : source_color = vec4(0.02, 0.02, 0.02, 0.95);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float border_thickness : hint_range(0.0, 0.2) = 0.08;

void fragment() {
	bool border = UV.x < border_thickness || UV.x > 1.0 - border_thickness || UV.y < border_thickness || UV.y > 1.0 - border_thickness;
	float inner_progress = clamp((progress - border_thickness) / max(1.0 - border_thickness * 2.0, 0.001), 0.0, 1.0);
	float inner_x = clamp((UV.x - border_thickness) / max(1.0 - border_thickness * 2.0, 0.001), 0.0, 1.0);
	float mask = step(inner_x, inner_progress);
	vec4 final_color = mix(background_color, fill_color, mask);
	if (border) {
		final_color = border_color;
	}
	ALBEDO = final_color.rgb;
	ALPHA = final_color.a;
}
