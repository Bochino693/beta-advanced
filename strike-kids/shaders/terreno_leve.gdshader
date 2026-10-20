shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;

// TERRENO LEVE (versão LEVE): o desenho do chão (terreno_desenho.gdshaderinc)
// com a luz (sol em duas faixas + ambiente) e a neblina feitas por VÉRTICE e
// as cores já lineares (Mundo.aplicar_tema). A versão ALTA usa o
// terreno.gdshader (mesmo desenho, luz e neblina na conta do motor).

#include "res://shaders/terreno_desenho.gdshaderinc"

uniform float faixa : hint_range(0.0, 0.5) = 0.25;
uniform float luz_minima : hint_range(0.0, 1.0) = 0.0;
// luz da cena: para onde está o sol (normalizado) e cor x força (lineares)
uniform vec3 sol_dir = vec3(0.35, 0.79, 0.5);
uniform vec3 sol_cor = vec3(1.0);
uniform vec3 ambiente = vec3(0.4);
// NEBLINA de profundidade por vértice (a do motor, por pixel, fica
// desligada no cenário leve): mesma conta exponencial e mesma cor
uniform vec3 neblina_cor = vec3(0.7, 0.8, 0.95);
uniform float neblina_densidade = 0.0;

varying vec3 pos_mundo;
varying vec3 luz;
varying float neblina;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float t = smoothstep(-faixa, faixa, dot(n, sol_dir) - 0.02);
	// o chão clareia um pouco no alto dos morros (como no terreno completo)
	float alt = clamp(pos_mundo.y / 4.0, 0.0, 1.0);
	luz = (ambiente + sol_cor * max(t, luz_minima)) * (1.0 + 0.23 * alt);
	neblina = 1.0 - exp(-neblina_densidade * length(CAMERA_POSITION_WORLD - pos_mundo));
}

void fragment() {
	vec2 p = pos_mundo.xz;
	// largura de um pixel no chão (bordas suaves, sem serrilhado)
	float w = (fwidth(p.x) + fwidth(p.y)) * 0.5 + 1e-5;
	ALBEDO = mix(desenho_do_chao(p, w) * luz, neblina_cor, neblina);
}
