shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// LÂMPADAS DO LETREIRO (MultiMesh). Cada lâmpada tem a cor da instância e
// um número em INSTANCE_CUSTOM.r; o padrão do pisca vem de `fase`
// (calculada na CPU — nada de TIME, que perde precisão em placas fracas).

uniform float fase = 0.0;
uniform int modo = 0;          // 0 corrida, 1 todas piscando, 2 alternado
uniform float intensidade = 1.6;

varying float n;

void vertex() {
	n = INSTANCE_CUSTOM.r;
}

void fragment() {
	float on;
	if (modo == 0) {
		on = 0.25 + 0.75 * step(0.6, fract(n * 0.25 - fase));
	} else if (modo == 1) {
		on = 0.3 + 0.7 * step(0.5, fract(fase * 2.0));
	} else {
		on = 0.25 + 0.75 * step(0.5, fract(n * 0.5 + fase * 2.0));
	}
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = COLOR.rgb * (0.35 + rim * 0.65);
	ALBEDO = c * on * intensidade + vec3(0.12) * rim;
}
