shader_type canvas_item;

// A IMAGEM 3D NA TELA: esticada até a tela inteira (quando a imagem 3D é
// desenhada menor que a tela) e, de quebra, o ajuste de cor (mais vivo e
// com um pouco mais de contraste) — de graça, na mesma passada que já
// existe. Sem o pós-processamento do motor (que custaria uma imagem a mais).
//
// NITIDEZ (só no PC, só quando a imagem 3D está menor que a tela): realce
// de bordas adaptativo (como o "CAS" da AMD): devolve a definição que o
// esticar tira, sem criar halos. Na TV Box fica desligado (custaria 5
// leituras por pixel numa tela 1080p) — lá o 3D já sai no tamanho da tela.

uniform float saturacao = 1.12;
uniform float contraste = 1.04;
uniform float nitidez = 0.0;      // 0 = desligado; 0,3..0,6 = realce

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	if (nitidez > 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec3 n = texture(TEXTURE, UV + vec2(0.0, -px.y)).rgb;
		vec3 s = texture(TEXTURE, UV + vec2(0.0, px.y)).rgb;
		vec3 l = texture(TEXTURE, UV + vec2(-px.x, 0.0)).rgb;
		vec3 r = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb;
		vec3 mn = min(c, min(min(n, s), min(l, r)));
		vec3 mx = max(c, max(max(n, s), max(l, r)));
		// quanto realçar: menos onde já há muito contraste (sem halos)
		vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
		vec3 w = -amp * nitidez * 0.2;
		c = clamp((c + (n + s + l + r) * w) / (1.0 + 4.0 * w), 0.0, 1.0);
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, saturacao);
	c = (c - 0.5) * contraste + 0.5;
	COLOR = vec4(c, 1.0);
}
