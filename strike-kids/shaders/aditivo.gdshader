shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Brilhos, chamas dos jatos, faíscas: soma luz (fica bonito com o glow).

uniform sampler2D textura : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 cor : source_color = vec4(1.0);
uniform float forca = 1.0;

void fragment() {
	vec4 t = texture(textura, UV);
	vec4 c = t * cor * COLOR;
	ALBEDO = c.rgb * c.a * forca;
	ALPHA = 1.0;
}
