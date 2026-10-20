shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// ARCO DO PORTAL (em cima do letreiro, no fim da pista): raios de sol
// alternando duas cores do cenário. Os raios são a própria malha (um leque
// de triângulos: COLOR.r diz a cor do raio, COLOR.g a distância do
// centro) — por pixel é só uma mistura de cores: levíssimo.

uniform vec3 cor_a : source_color = vec3(1.0, 0.76, 0.1);
uniform vec3 cor_b : source_color = vec3(0.91, 0.22, 0.31);
uniform float pulso = 0.0;      // brilho do centro pulsando (vem da CPU)

void fragment() {
	float r = COLOR.g;
	vec3 c = mix(cor_b, cor_a, COLOR.r);
	c *= 1.12 - 0.35 * r;
	c += vec3(1.0, 0.95, 0.8) * (0.3 + 0.12 * pulso) * clamp(1.0 - r * 2.2, 0.0, 1.0);
	ALBEDO = c;
}
