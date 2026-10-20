shader_type canvas_item;

// PAINEL COM VOLUME — placas e botões das telas, no mesmo estilo dos
// objetos 3D do jogo: frente em degradê com brilho de verniz, lateral mais
// escura embaixo (espessura), contorno escuro e sombra macia no chão.
// Tudo é calculado por pixel (distância até a borda arredondada): fica
// nítido em qualquer resolução, de 720p a 4K, sem imagem esticada.
//
// O retângulo que desenha é maior que o painel (margem para a sombra):
// UV 0..1 cobre (tamanho + 2 * margem); o painel fica no meio.
//
// LEVE NA TV BOX: as medidas que não mudam de pixel para pixel (centros,
// metades, raios, alturas) vêm prontas do Painel3D (scripts/painel3d.gd);
// a largura do pixel (antisserrilhado) é uma derivada só, e a sombra e o
// verniz só são calculados quando aparecem.

uniform vec2 tamanho = vec2(400.0, 200.0);
uniform float margem = 32.0;
uniform float borda = 6.0;             // contorno escuro em volta
uniform vec4 cor_topo : source_color = vec4(0.16, 0.42, 0.85, 1.0);
uniform vec4 cor_base : source_color = vec4(0.06, 0.20, 0.50, 1.0);
uniform vec4 cor_lado : source_color = vec4(0.03, 0.10, 0.28, 1.0);
uniform vec4 cor_borda : source_color = vec4(0.03, 0.08, 0.20, 1.0);
uniform vec4 cor_aro : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // filete claro por dentro da borda
uniform float aro = 0.55;
uniform float brilho = 0.22;           // verniz na metade de cima
uniform float sombra = 0.4;
uniform float opacidade = 1.0;
uniform float realce = 0.0;            // 0..1: brilho pulsante (item escolhido)
uniform vec4 cor_realce : source_color = vec4(1.0, 0.84, 0.25, 1.0);
// medidas prontas (Painel3D._medidas)
uniform vec2 meio = vec2(200.0, 100.0);          // metade do painel
uniform float r = 32.0;                          // raio da silhueta
uniform vec2 centro_f = vec2(200.0, 90.0);       // frente: centro, metade e raio
uniform vec2 meio_f = vec2(194.0, 84.0);
uniform float r_f = 26.0;
uniform float base_f = 180.0;                    // onde a frente acaba (começa a lateral)
uniform float div_lado = 18.0;
uniform float div_frente = 174.0;
uniform vec2 centro_v = vec2(200.0, 50.0);       // verniz: centro, metade, raio, suavidade
uniform vec4 verniz_m = vec4(150.0, 33.0, 24.0, 7.0);
uniform vec4 sombra_g = vec4(200.0, 111.0, -6.0, 27.0);   // centro (y), início e fim do esfumado
uniform vec2 sombra_m = vec2(197.0, 97.0);
uniform vec2 filete_g = vec2(3.1, 3.0);          // folga e largura do filete

float caixa(vec2 p, vec2 m, float rr) {
	vec2 q = abs(p) - m + vec2(rr);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rr;
}

void fragment() {
	vec2 p = UV * (tamanho + vec2(2.0 * margem)) - vec2(margem);
	// largura de um pixel (uma derivada só: a placa nunca gira)
	float w = max(fwidth(p.x), 1e-4);
	float d_tudo = caixa(p - meio, meio, r);
	vec4 cor = vec4(0.0, 0.03, 0.10, 0.0);
	// sombra macia embaixo
	if (sombra > 0.0) {
		float d_sombra = caixa(p - sombra_g.xy, sombra_m, r);
		cor.a = sombra * (1.0 - smoothstep(sombra_g.z, sombra_g.w, d_sombra));
	}
	// halo do item escolhido (por fora do contorno)
	if (realce > 0.0) {
		float h = (1.0 - smoothstep(0.0, margem * 0.9, d_tudo)) * realce;
		cor = mix(cor, vec4(cor_realce.rgb, 1.0), h * 0.85);
		cor.a = max(cor.a, h * 0.85);
	}
	// contorno + lateral (espessura, mais escura embaixo)
	float c_tudo = clamp(0.5 - d_tudo / w, 0.0, 1.0);
	if (c_tudo > 0.0) {
		float d_frente = caixa(p - centro_f, meio_f, r_f);
		float yl = clamp((p.y - base_f) / div_lado, 0.0, 1.0);
		vec3 lado = cor_lado.rgb * mix(1.2, 0.75, yl);
		vec3 casca = mix(cor_borda.rgb, lado, clamp(0.5 - (d_tudo + borda) / w, 0.0, 1.0));
		cor.rgb = mix(cor.rgb, casca, c_tudo);
		cor.a = max(cor.a, c_tudo);
		// frente: degradê + verniz + filete claro
		float c_frente = clamp(0.5 - d_frente / w, 0.0, 1.0);
		if (c_frente > 0.0) {
			float t = clamp((p.y - borda) / div_frente, 0.0, 1.0);
			vec3 frente = mix(cor_topo.rgb, cor_base.rgb, smoothstep(0.0, 1.0, t));
			if (brilho > 0.0) {
				float d_verniz = caixa(p - centro_v, verniz_m.xy, verniz_m.z);
				float verniz = 1.0 - smoothstep(-verniz_m.w, 0.0, d_verniz);
				frente = mix(frente, vec3(1.0), verniz * brilho * (1.0 - t * 0.5));
			}
			float df = d_frente + filete_g.x;
			float filete = clamp(0.5 - df / w, 0.0, 1.0) * clamp(0.5 + (df + filete_g.y) / w, 0.0, 1.0);
			frente = mix(frente, cor_aro.rgb, filete * aro * (1.0 - t * 0.8));
			frente *= 1.0 - 0.16 * smoothstep(0.6, 1.0, t);   // curvinha escurecendo embaixo
			if (realce > 0.0) {
				frente = mix(frente, cor_realce.rgb, filete * realce);
			}
			cor.rgb = mix(cor.rgb, frente, c_frente);
		}
	}
	cor.a *= opacidade;
	COLOR = cor;
}
