shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// TOON SEM RECEBER SOMBRA (personagens e pinos: sem manchas de sombra no rosto)
// TOON DO STRIKE KIDS
// Cor vem da cor do vértice (sRGB, pintada no modelador). Luz em duas
// faixas (sol / sombra colorida), brilho de borda e, nos rostos, o desenho
// do rosto projetado de frente (atlas de expressões).

uniform vec4 tinta : source_color = vec4(1.0);
uniform float faixa : hint_range(0.0, 0.5) = 0.06;
uniform float luz_minima : hint_range(0.0, 1.0) = 0.0;
uniform float borda : hint_range(0.0, 2.0) = 0.35;
uniform vec3 cor_borda : source_color = vec3(1.0, 0.95, 0.9);
uniform float especular : hint_range(0.0, 2.0) = 0.0;
uniform float tamanho_especular : hint_range(0.5, 0.999) = 0.92;
uniform vec3 emissao : source_color = vec3(0.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// partes que brilham (alfa do vértice = 0.5): núcleo do peito, antena, orelhas
uniform float brilho_luz : hint_range(0.0, 4.0) = 1.4;

uniform bool usa_rosto = false;
uniform sampler2D rosto : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 rosto_centro = vec2(0.0, 0.235);
uniform vec2 rosto_tamanho = vec2(0.46, 0.40);
uniform vec2 rosto_grade = vec2(4.0, 2.0);
uniform vec2 rosto_celula = vec2(0.0, 0.0);

// ESTAMPA DA ROUPA desenhada aqui (não na malha): bordas perfeitas em 4K.
//   1 = estrela de frente no peito; 2 = bolinhas em fileiras na saia;
//   3 = listras (camiseta de pirata): faixas de 2 x estampa_raio a cada
//       bolinhas_dy, a partir de bolinhas_y0, até bolinhas_y_max.
// Só aparece onde a cor do vértice é a da roupa (estampa_base).
uniform int estampa = 0;
uniform vec3 estampa_base : source_color = vec3(1.0);
uniform vec3 estampa_cor : source_color = vec3(1.0, 0.85, 0.2);
uniform vec2 estampa_centro = vec2(0.0, 0.1);
uniform float estampa_raio = 0.06;
uniform float estampa_dentro = 0.5;      // estrela: raio do vale / raio da ponta
uniform float bolinhas_y0 = -0.05;
uniform float bolinhas_dy = 0.05;
uniform int bolinhas_fileiras = 3;
uniform int bolinhas_n0 = 12;
uniform float bolinhas_y_max = 0.08;

varying vec3 pos_local;
varying vec3 normal_local;

vec3 srgb_para_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// distância até uma estrela de 5 pontas (ponta para cima): raio r da
// ponta, "vale" = raio do vale / raio da ponta (fórmula de Inigo Quilez)
float sd_estrela(vec2 p, float r, float vale) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = vale * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float cobre(float d) {
	float w = max(fwidth(d), 1e-6);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

// distância até a bolinha mais perto (fileiras desencontradas em volta do eixo Y)
float sd_bolinhas(vec3 p) {
	float melhor = 1e3;
	float raio_h = max(length(p.xz), 1e-4);
	float ang = atan(p.x, p.z);
	for (int k = 0; k < 8; k++) {
		if (k >= bolinhas_fileiras) {
			break;
		}
		float y = bolinhas_y0 + float(k) * bolinhas_dy;
		float n = float(bolinhas_n0 - k);
		float desloc = 0.5 * float(k % 2);
		float passo = 6.28318531 / n;
		float i = floor(ang / passo - desloc + 0.5);
		float d_ang = ang - (i + desloc) * passo;
		vec2 q = vec2(d_ang * raio_h, p.y - y);
		melhor = min(melhor, length(q) - estampa_raio);
	}
	return melhor;
}

// conversões de cor feitas por VÉRTICE (não por pixel): mesma cor, bem
// mais leve na placa de vídeo
varying vec3 cor_base;
varying vec3 cor_brilho;
varying vec3 cor_emissao;

void vertex() {
	pos_local = VERTEX;
	normal_local = NORMAL;
	cor_base = srgb_para_linear(COLOR.rgb) * srgb_para_linear(tinta.rgb);
	cor_brilho = srgb_para_linear(cor_borda) * borda;
	cor_emissao = srgb_para_linear(emissao);
}

void fragment() {
	vec3 base = cor_base;
	if (usa_rosto && normal_local.z > 0.05) {
		vec2 uv = (pos_local.xy - rosto_centro) / rosto_tamanho + 0.5;
		uv.y = 1.0 - uv.y;
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
			vec4 f = texture(rosto, (clamp(uv, 0.004, 0.996) + rosto_celula) / rosto_grade);
			float m = f.a * smoothstep(0.75, 0.95, COLOR.a) * smoothstep(0.05, 0.3, normal_local.z);
			base = mix(base, f.rgb, m);
		}
	}
	if (estampa > 0) {
		// só sobre o tecido (a cor do vértice é a da roupa)
		float tecido = 1.0 - smoothstep(0.05, 0.12, distance(COLOR.rgb, estampa_base));
		float d = 1e3;
		float lado = 1.0;
		if (estampa == 1) {
			d = sd_estrela(pos_local.xy - estampa_centro, estampa_raio, estampa_dentro) - estampa_raio * 0.06;
			lado = smoothstep(0.15, 0.4, normal_local.z) * step(0.0, pos_local.z);
		} else if (estampa == 2) {
			d = sd_bolinhas(pos_local);
			lado = 1.0 - smoothstep(bolinhas_y_max - 0.01, bolinhas_y_max, pos_local.y);
		} else {
			float y = pos_local.y - bolinhas_y0;
			d = abs(y - bolinhas_dy * floor(y / bolinhas_dy + 0.5)) - estampa_raio;
			lado = (1.0 - smoothstep(bolinhas_y_max - 0.01, bolinhas_y_max, pos_local.y)) * step(-estampa_raio, y);
		}
		float m = cobre(d) * tecido * lado;
		// filete um pouco mais escuro em volta (desenho de adesivo)
		float filete = cobre(abs(d + estampa_raio * 0.06) - estampa_raio * 0.06) * tecido * lado * float(estampa == 1);
		vec3 cor = srgb_para_linear(estampa_cor) * srgb_para_linear(tinta.rgb);
		base = mix(base, cor, m);
		base = mix(base, cor * 0.72, filete * 0.6);
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float luz = 1.0 - clamp(abs(COLOR.a - 0.5) * 5.0, 0.0, 1.0);
	EMISSION = cor_brilho * rim * base + cor_emissao + vec3(flash) * base
		+ base * luz * brilho_luz;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(-faixa, faixa, ndl - 0.02);
	float luz = max(t * ATTENUATION, luz_minima);
	DIFFUSE_LIGHT += LIGHT_COLOR * luz / PI;
	if (especular > 0.0) {
		vec3 h = normalize(VIEW + LIGHT);
		float s = smoothstep(tamanho_especular, tamanho_especular + 0.02, dot(NORMAL, h));
		SPECULAR_LIGHT += LIGHT_COLOR * s * especular * ATTENUATION;
	}
}
