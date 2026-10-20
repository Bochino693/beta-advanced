shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;

// TOON LEVE (decoração do cenário LEVE, o padrão na TV Box): a mesma cara
// do toon.gdshader — cor do vértice x tinta, luz do sol em duas faixas,
// ambiente, brilho de borda, partes que brilham — mas TUDO calculado por
// VÉRTICE: por pixel sobra só pintar a cor pronta. A luz da cena vem do
// Mundo (aplicar_tema). Sem brilho especular (por vértice ficaria
// manchado) e sem contorno.

uniform vec4 tinta : source_color = vec4(1.0);
uniform float faixa : hint_range(0.0, 0.5) = 0.06;
uniform float luz_minima : hint_range(0.0, 1.0) = 0.0;
uniform float borda : hint_range(0.0, 2.0) = 0.35;
uniform vec3 cor_borda : source_color = vec3(1.0, 0.95, 0.9);
uniform vec3 emissao : source_color = vec3(0.0);
uniform float brilho_luz : hint_range(0.0, 4.0) = 1.4;
// luz da cena: para onde está o sol (normalizado) e cor x força (lineares)
uniform vec3 sol_dir = vec3(0.35, 0.79, 0.5);
uniform vec3 sol_cor = vec3(1.0);
uniform vec3 ambiente = vec3(0.4);
// NEBLINA de profundidade por vértice (a do motor, por pixel, fica
// desligada no cenário leve): mesma conta exponencial e mesma cor
uniform vec3 neblina_cor = vec3(0.7, 0.8, 0.95);
uniform float neblina_densidade = 0.0;

varying vec3 cor;
varying float neblina;

vec3 srgb_para_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 base = srgb_para_linear(COLOR.rgb) * srgb_para_linear(tinta.rgb);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 ate_camera = CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = normalize(ate_camera);
	neblina = 1.0 - exp(-neblina_densidade * length(ate_camera));
	float t = smoothstep(-faixa, faixa, dot(n, sol_dir) - 0.02);
	vec3 c = base * (ambiente + sol_cor * max(t, luz_minima));
	float rim = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float acesa = 1.0 - clamp(abs(COLOR.a - 0.5) * 5.0, 0.0, 1.0);
	c += srgb_para_linear(cor_borda) * borda * rim * rim * rim * base + srgb_para_linear(emissao)
		+ base * acesa * brilho_luz;
	cor = c;
}

void fragment() {
	ALBEDO = mix(cor, neblina_cor, neblina);
}
