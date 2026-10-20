shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;

// TERRENO (versão ALTA): o mesmo desenho do chão do terreno_leve
// (terreno_desenho.gdshaderinc: 1 sorteio por pixel, sem seno — o terreno
// antigo, com 9 sorteios por pixel, custava de 4 a 6 vezes mais e era o que
// mais pesava na versão ALTA), com a luz e a neblina feitas na MESMA conta
// do motor: cor em linear, luz e neblina, e a volta para sRGB no fim. Fica
// igual ao terreno antigo (que usava o cálculo de luz do motor), por bem
// menos. As cores chegam do Mundo já no espaço da conta do motor.

#include "res://shaders/terreno_desenho.gdshaderinc"

uniform float faixa : hint_range(0.0, 0.5) = 0.25;
uniform float luz_minima : hint_range(0.0, 1.0) = 0.0;
// luz da cena: para onde está o sol (normalizado) e cor x força (lineares)
uniform vec3 sol_dir = vec3(0.35, 0.79, 0.5);
uniform vec3 sol_cor = vec3(1.0);
uniform vec3 ambiente = vec3(0.4);
// neblina de profundidade (mesma conta exponencial e mesma cor do motor)
uniform vec3 neblina_cor = vec3(0.7, 0.8, 0.95);
uniform float neblina_densidade = 0.0;

varying vec3 pos_mundo;
varying vec3 luz;
varying float neblina;

vec3 para_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float t = smoothstep(-faixa, faixa, dot(n, sol_dir) - 0.02);
	// o chão clareia um pouco no alto dos morros (+10% na cor, como antes)
	float alt = clamp(pos_mundo.y / 4.0, 0.0, 1.0);
	luz = (ambiente + sol_cor * max(t, luz_minima)) * pow(1.0 + 0.1 * alt, 4.8);
	neblina = 1.0 - exp(-neblina_densidade * length(CAMERA_POSITION_WORLD - pos_mundo));
}

void fragment() {
	vec2 p = pos_mundo.xz;
	// largura de um pixel no chão (bordas suaves, sem serrilhado)
	float w = (fwidth(p.x) + fwidth(p.y)) * 0.5 + 1e-5;
	ALBEDO = para_srgb(mix(desenho_do_chao(p, w) * luz, neblina_cor, neblina));
}
