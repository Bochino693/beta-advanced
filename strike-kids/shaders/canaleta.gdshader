shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// CANALETA DE CADA CENÁRIO: a mesma calha (e a mesma colisão) de sempre,
// com o desenho do cenário feito aqui — nítido em qualquer resolução (borda
// de 1 pixel pelo fwidth) e leve (sem textura, sem conta de luz do motor):
//   0 PARQUE: listras de doce em diagonal, lábios amarelos;
//   1 ESPAÇO: metal azul-escuro com emendas de painel e luzes que correm
//     pelo fundo até os pinos, lábios de neon;
//   2 MAR: água com reflexos ondulando e bolhinhas, lábios de espuma;
//   3 DINOS: bambu verde com nós e fibras, lábios de madeira clara.
// As coordenadas são do MUNDO (a calha pode ser juntada com outras peças).

uniform int modo = 0;
uniform vec3 cor_a : source_color = vec3(1.0, 0.48, 0.72);
uniform vec3 cor_b : source_color = vec3(1.0, 0.95, 0.88);
uniform vec3 cor_c : source_color = vec3(1.0, 0.82, 0.25);
// luz da cena (o Mundo calcula: ambiente + sol), como na pista
uniform vec3 luz_cena = vec3(1.2, 1.2, 1.22);
uniform float centro = 0.8;      // |x| do meio de cada calha

varying vec3 pw;

void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// cobertura de uma forma pela distância (negativo = dentro), borda de 1 pixel
float cobre(float d, float w) {
	return clamp(0.5 - d / max(w, 1e-5), 0.0, 1.0);
}

float sorteio(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float ux = abs(pw.x) - centro;            // -0,16 (lado da pista) .. 0,16 (lado de fora)
	float z = pw.z;
	float sombra = COLOR.r;                   // a calha escurece no fundo (perfil)
	float labio = smoothstep(-0.032, -0.012, pw.y);
	vec3 c;
	if (modo == 0) {
		float t = z * 2.4 + ux * 6.0;
		float m = cobre(abs(fract(t) - 0.5) - 0.25, fwidth(t));
		c = mix(cor_b, cor_a, m);
		c = mix(c, cor_c, labio);
	} else if (modo == 1) {
		// emendas dos painéis a cada 0,5 m e rebites dos lados
		float ds = abs(fract(z * 2.0 + 0.5) - 0.5) * 0.5;
		float emenda = cobre(ds - 0.004, fwidth(z) * 1.5);
		vec2 r = vec2(abs(ux) - 0.1, ds - 0.06);
		float rebite = cobre(length(r) - 0.008, fwidth(z) * 1.5);
		c = cor_a * (1.0 - 0.35 * emenda) + cor_b * 0.35 * rebite;
		// luzes que correm pelo fundo até os pinos (e o filete do meio)
		float p = fract(z * 0.8 + TIME * 1.3);
		float pulso = exp(-pow((p - 0.5) * 9.0, 2.0)) * (1.0 - smoothstep(0.02, 0.07, abs(ux)));
		float filete = cobre(abs(ux) - 0.004, fwidth(ux) * 1.5);
		c += cor_c * (pulso * 1.1 + filete * 0.45);
		c = mix(c, cor_c * 1.15, labio);
	} else if (modo == 2) {
		// reflexos da água ondulando (somem de longe, sem serrilhar)
		float o = sin(z * 7.0 + sin(ux * 38.0 + TIME * 1.7) * 1.3 + TIME * 2.2);
		float fw = fwidth(z * 7.0) + 1e-4;
		float reflexo = smoothstep(0.82 - fw, 0.92 + fw, o) * clamp(1.4 - fw * 1.6, 0.0, 1.0);
		c = mix(cor_a, cor_b, 0.25 + 0.35 * smoothstep(-0.12, 0.02, pw.y)) + vec3(0.85, 1.0, 1.0) * reflexo * 0.35;
		// bolhinhas: uma por célula (0,08 x 0,22 m), indo devagar para os pinos
		vec2 q = vec2(ux / 0.08, (z + TIME * 0.12) / 0.22);
		vec2 cel = floor(q);
		float h = sorteio(cel);
		vec2 centro_b = cel + vec2(0.25 + 0.5 * h, 0.2 + 0.6 * fract(h * 7.3));
		vec2 d = (q - centro_b) * vec2(0.08, 0.22);
		float raio = 0.007 + 0.009 * fract(h * 13.1);
		float bolha = cobre(abs(length(d) - raio) - 0.0018, fwidth(z) * 1.2) * step(0.45, h);
		c = mix(c, vec3(0.92, 1.0, 1.0), bolha * 0.85);
		c = mix(c, cor_c, labio);
	} else {
		// bambu: gomos de 0,42 m, nó escuro com um anel claro do lado, fibras
		float dn = abs(fract(z / 0.42 + 0.5) - 0.5) * 0.42;
		float w = fwidth(z) * 1.5;
		float no = cobre(dn - 0.011, w);
		float anel = cobre(abs(dn - 0.03) - 0.007, w);
		float fibra = 0.9 + 0.1 * sin(ux * 95.0 + sin(z * 2.7) * 0.6);
		c = cor_a * fibra;
		c = mix(c, cor_b, anel * 0.7);
		c = mix(c, cor_a * 0.45, no);
		c = mix(c, cor_c, labio);
	}
	ALBEDO = c * sombra * min(luz_cena, vec3(1.3));
}
