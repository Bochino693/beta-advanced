shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

// CONTORNO (casca invertida): a malha é inflada ao longo da normal e
// desenhada só por dentro. A espessura acompanha a distância, para o traço
// ficar com a mesma grossura na tela de perto e de longe.
// RECUO: a casca é empurrada um pouquinho para longe da câmera. Contra o
// fundo o traço continua igual, mas onde uma peça encosta em outra (manga
// no ombro, lenço na camiseta) o traço fica escondido atrás dela — sem
// "costuras" riscadas por cima da roupa.

uniform float espessura = 0.0035;
uniform float recuo = 0.015;
uniform vec4 cor_contorno : source_color = vec4(0.17, 0.10, 0.27, 1.0);
uniform float usa_cor_vertice : hint_range(0.0, 1.0) = 0.55;

vec3 srgb_para_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// a cor do traço é feita por vértice (por pixel sobra só pintar)
varying vec3 cor;

void vertex() {
	vec4 pv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = clamp(-pv.z, 0.8, 9.0);
	vec4 p = MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * espessura * d, 1.0);
	p.xyz += normalize(p.xyz) * recuo * d;
	POSITION = PROJECTION_MATRIX * p;
	cor = mix(srgb_para_linear(cor_contorno.rgb), srgb_para_linear(COLOR.rgb) * 0.28, usa_cor_vertice);
}

void fragment() {
	ALBEDO = cor;
}
