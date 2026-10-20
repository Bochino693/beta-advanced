shader_type canvas_item;

// PAINEL COM VOLUME — placas e botões das telas, no mesmo estilo dos
// objetos 3D do jogo: frente em degradê com brilho de verniz, lateral mais
// escura embaixo (espessura), contorno escuro e sombra macia no chão.
// Tudo é calculado por pixel (distância até a borda arredondada): fica
// nítido em qualquer resolução, de 720p a 4K, sem imagem esticada.
//
// O retângulo que desenha é maior que o painel (margem para a sombra):
// UV 0..1 cobre (tamanho + 2 * margem); o painel fica no meio.

uniform vec2 tamanho = vec2(400.0, 200.0);
uniform float margem = 32.0;
uniform float raio = 32.0;
uniform float borda = 6.0;             // contorno escuro em volta
uniform float espessura = 12.0;        // lateral visível embaixo
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

float caixa(vec2 p, vec2 meio, float r) {
	vec2 q = abs(p) - meio + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// cobertura com borda de 1 pixel (antisserrilhado na resolução real)
float cobre(float d) {
	float w = max(fwidth(d), 1e-4);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

void fragment() {
	vec2 total = tamanho + vec2(2.0 * margem);
	vec2 p = UV * total - vec2(margem);           // pixel em relação ao canto do painel
	float r = min(raio, min(tamanho.x, tamanho.y) * 0.5);
	vec2 meio = tamanho * 0.5;
	// silhueta inteira (frente + lateral)
	float d_tudo = caixa(p - meio, meio, r);
	// frente: dentro do contorno, terminando acima da lateral
	float base_f = max(tamanho.y - borda - espessura, borda + 2.0 * r);
	vec2 centro_f = vec2(meio.x, (borda + base_f) * 0.5);
	vec2 meio_f = vec2(meio.x - borda, (base_f - borda) * 0.5);
	float d_frente = caixa(p - centro_f, meio_f, max(r - borda, 1.0));

	// sombra macia embaixo
	float d_sombra = caixa(p - meio - vec2(0.0, margem * 0.35), meio - vec2(margem * 0.1), r);
	float a_sombra = sombra * (1.0 - smoothstep(-margem * 0.2, margem * 0.85, d_sombra));
	vec4 cor = vec4(0.0, 0.03, 0.10, a_sombra);

	// halo do item escolhido (por fora do contorno)
	if (realce > 0.0) {
		float h = (1.0 - smoothstep(0.0, margem * 0.9, d_tudo)) * realce;
		cor = mix(cor, vec4(cor_realce.rgb, 1.0), h * 0.85);
		cor.a = max(cor.a, h * 0.85);
	}

	// contorno + lateral (espessura, mais escura embaixo)
	float yl = clamp((p.y - base_f) / max(espessura + borda, 1.0), 0.0, 1.0);
	vec3 lado = cor_lado.rgb * mix(1.2, 0.75, yl);
	float c_tudo = cobre(d_tudo);
	vec3 casca = mix(cor_borda.rgb, lado, cobre(d_tudo + borda));
	cor.rgb = mix(cor.rgb, casca, c_tudo);
	cor.a = max(cor.a, c_tudo);

	// frente: degradê + verniz + filete claro
	float t = clamp((p.y - borda) / max(base_f - borda, 1.0), 0.0, 1.0);
	vec3 frente = mix(cor_topo.rgb, cor_base.rgb, smoothstep(0.0, 1.0, t));
	float alt_f = base_f - borda;
	float d_verniz = caixa(p - vec2(meio.x, borda + alt_f * 0.26), vec2(meio_f.x - r * 0.3 - borda, alt_f * 0.19), max(r * 0.75, 2.0));
	float suave = clamp(alt_f * 0.04, 1.5, 8.0);
	float verniz = 1.0 - smoothstep(-suave, 0.0, d_verniz);
	frente = mix(frente, vec3(1.0), verniz * brilho * (1.0 - t * 0.5));
	float folga = borda * 0.35 + 1.0;
	float largura = max(borda * 0.5, 1.5);
	float filete = cobre(d_frente + folga) * cobre(-(d_frente + folga + largura));
	frente = mix(frente, cor_aro.rgb, filete * aro * (1.0 - t * 0.8));
	frente *= 1.0 - 0.16 * smoothstep(0.6, 1.0, t);   // curvinha escurecendo embaixo
	if (realce > 0.0) {
		frente = mix(frente, cor_realce.rgb, filete * realce);
	}
	float c_frente = cobre(d_frente);
	cor.rgb = mix(cor.rgb, frente, c_frente);
	cor.a *= opacidade;
	COLOR = cor;
}
