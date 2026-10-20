shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// O POÇO DO ALÇAPÃO (embaixo do fosso): paredes que escurecem com a
// profundidade e faixas de luz em volta, cada vez mais fracas lá embaixo —
// dá a perspectiva da queda dos pinos. Sem luz nem textura: barato.

uniform vec3 cor_topo : source_color = vec3(0.10, 0.20, 0.45);
uniform vec3 cor_fundo : source_color = vec3(0.0, 0.004, 0.02);
uniform vec3 cor_faixa : source_color = vec3(0.35, 0.9, 1.0);
uniform float y_topo = -0.14;
uniform float y_fundo = -1.75;
uniform float passo_faixas = 0.3;

varying float fundura;

void vertex() {
	fundura = y_topo - (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float t = clamp(fundura / (y_topo - y_fundo), 0.0, 1.0);
	vec3 c = mix(cor_topo, cor_fundo, sqrt(t));
	// faixas finas de luz (bordas suaves pela largura do pixel)
	float d = abs(fract(fundura / passo_faixas + 0.5) - 0.5) * passo_faixas;
	float aa = fwidth(fundura) * 1.2 + 0.0005;
	float faixa = 1.0 - smoothstep(0.007, 0.007 + aa, d);
	faixa *= step(passo_faixas * 0.5, fundura);
	c += cor_faixa * faixa * (1.0 - t) * (1.0 - t) * 0.9;
	ALBEDO = c;
}
