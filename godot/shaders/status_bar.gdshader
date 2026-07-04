shader_type spatial;
render_mode unshaded, transparency_alpha, depth_test_disabled;

uniform vec4 background_color : source_color = vec4(0.1, 0.1, 0.1, 0.8);
uniform vec4 fill_color : source_color = vec4(0.9, 0.1, 0.1, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billboard behavior: Face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	float mask = step(UV.x, progress);
	vec4 final_color = mix(background_color, fill_color, mask);
	ALBEDO = final_color.rgb;
	ALPHA = final_color.a;
}
