shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// SOMBRA REDONDA (blob) embaixo de bola, pinos e personagens: dá a noção de
// altura (o 3D "salta") e custa quase nada.

uniform sampler2D textura : source_color, filter_linear, repeat_disable;
uniform float forca = 0.55;

void fragment() {
	vec4 t = texture(textura, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a * forca * COLOR.a;
}
