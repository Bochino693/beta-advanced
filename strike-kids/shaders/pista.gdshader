shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// PISTA DO STRIKE KIDS: madeira envernizada e brilhante com a decoração de
// um boliche infantil — bordas de NEON na cor do cenário (sempre acesas,
// com luzes correndo para os pinos), SETAS ARCO-ÍRIS com contorno branco,
// uma TRILHA DE ESTRELAS no meio que pisca em sequência até os pinos
// ("mire no STRIKE!"), pontos coloridos, linha de falta neon, holofote nos
// pinos e o verniz refletindo o portal colorido lá no fundo.
// As coordenadas são do MUNDO: linha de falta em z = 0, pinos em z_pino1.
//
// NÍTIDO E LEVE: cada desenho é uma distância (SDF) com borda suave do
// tamanho de um pixel (fwidth) — liso em qualquer resolução, sem
// serrilhado — e só é calculado na faixa da pista onde ele existe. O
// mesmo vale para os brilhos (exp/sin): só onde eles aparecem.

uniform sampler2D madeira : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meia_largura = 0.675;
uniform float repete = 3.6;
uniform float z_pino1 = -14.0;
uniform float bola_z = 100.0;
uniform float luz = 0.0;            // 0..1 (acende forte durante a jogada)
uniform float fase = 0.0;           // fase das luzes que correm (vem da CPU)
uniform float fase_lenta = 0.0;     // fase da onda das estrelas (0..1, vem da CPU)
uniform float pulso = 0.0;          // 0..1 (pulsa devagar, vem da CPU)
uniform vec3 cor_luz : source_color = vec3(0.35, 0.85, 1.0);     // neon das bordas (cor do cenário)
uniform vec3 cor_reflexo_a : source_color = vec3(1.0, 0.76, 0.1); // o portal refletido no verniz
uniform vec3 cor_reflexo_b : source_color = vec3(0.91, 0.22, 0.31);
uniform vec3 tom_madeira : source_color = vec3(1.0, 0.84, 0.6);   // mel: madeira quente e viva
// luz da cena (o Mundo calcula: ambiente + sol no chão) e o que o verniz reflete
uniform vec3 luz_cena = vec3(1.2, 1.2, 1.22);
uniform vec3 cor_ceu : source_color = vec3(0.85, 0.93, 1.0);
uniform vec3 dir_sol = vec3(0.35, 0.79, 0.5);     // para onde está o sol (mundo, já normalizado)
uniform float verniz = 0.32;

varying vec3 pm;

const vec3 ARCO[7] = vec3[7](vec3(1.0, 0.23, 0.33), vec3(1.0, 0.56, 0.13), vec3(1.0, 0.85, 0.15),
	vec3(0.35, 0.86, 0.33), vec3(0.2, 0.8, 1.0), vec3(0.27, 0.47, 1.0), vec3(0.72, 0.38, 1.0));

void vertex() {
	pm = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// cobertura de uma forma pela distância (negativo = dentro), borda de 1 pixel
float cobre(float dist, float w) {
	return clamp(0.5 - dist / w, 0.0, 1.0);
}

// triângulo isósceles com a ponta na origem e a base em y = q.y (Inigo Quilez)
float sd_tri(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// estrela de 5 pontas (ponta para os pinos), raio r, vale = raio do vale / r
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

// pinta uma figura com contorno branco e um brilhinho em volta
vec3 adesivo(vec3 c, float dist, float w, vec3 cor, float contorno, float acesa) {
	float halo = exp(-max(dist, 0.0) * 22.0) * 0.35 * acesa;
	c += cor * halo;
	c = mix(c, vec3(1.0), cobre(dist - contorno, w));
	return mix(c, cor * (0.75 + 0.6 * acesa), cobre(dist, w));
}

void fragment() {
	vec2 uv = vec2(pm.x / (meia_largura * 2.0) + 0.5, -pm.z / repete);
	vec3 c = texture(madeira, uv).rgb * tom_madeira;
	// madeira um pouco mais viva (saturação e contraste)
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = clamp(mix(vec3(l), c, 1.25) * 1.04 - 0.02, 0.0, 1.0);
	float d = -pm.z;       // distância da linha de falta
	float ax = abs(pm.x);
	float dp = -z_pino1;   // distância dos pinos
	// largura de um pixel na pista (para as bordas suaves)
	float w = max(fwidth(d), fwidth(pm.x)) * 1.2 + 1e-4;
	float chamado = 1.0 - luz;   // esperando a bola: a pista "chama" a jogada

	// linha de falta neon (vermelho-rosa); o brilho dela some antes de 40 cm
	if (d < 0.4) {
		float falta = abs(d - 0.02) - 0.022;
		c = mix(c, vec3(1.0, 0.18, 0.35), cobre(falta, w));
		c += vec3(1.0, 0.2, 0.4) * exp(-max(falta, 0.0) * 40.0) * (0.25 + 0.2 * pulso);
	}

	// pontos coloridos de mira (a 1,6 m): o mais perto
	if (abs(d - 1.6) < 0.14) {
		float ip = clamp(round(pm.x / 0.17), -3.0, 3.0);
		float dd = length(vec2(pm.x - ip * 0.17, d - 1.6)) - 0.042;
		c = adesivo(c, dd, w, ARCO[int(ip) + 3], 0.013, 0.6);
	}

	// TRILHA DE ESTRELAS no meio da pista: piscam em sequência até os pinos
	if (ax < 0.36 && d > 1.9 && d < dp - 1.05) {
		float passo = 1.35;
		float k = clamp(round((d - 2.3) / passo), 0.0, 5.0);
		vec2 q = vec2(pm.x, d - (2.3 + k * passo));
		float r = 0.17 + k * 0.022;
		float de = sd_estrela(q, r, 0.48) - 0.014;
		// a "onda" de luz corre das estrelas perto para as longe
		float onda = step(0.72, fract(fase_lenta - k * 0.14));
		float acesa = mix(0.35, 1.0, max(onda * chamado, luz * 0.7));
		c = adesivo(c, de, w, ARCO[int(mod(k * 2.0, 7.0))], 0.02, acesa);
	}

	// SETAS ARCO-ÍRIS em V (a ponta do V é a seta do meio, a mais longe)
	if (d > 3.2 && d < 4.85) {
		float is = clamp(round(pm.x / 0.17), -3.0, 3.0);
		float ponta = 3.78 + (3.0 - abs(is)) * 0.3;
		float ds = sd_tri(vec2(pm.x - is * 0.17, ponta - d), vec2(0.066, 0.44));
		c = adesivo(c, ds, w, ARCO[int(is) + 3], 0.016, 0.75 + 0.25 * pulso);
	}

	// área dos pinos: marcas, um tom mais claro e o HOLOFOTE (chama o olhar)
	if (d > dp - 1.4) {
		vec2 r2 = vec2(pm.x, d - dp);
		float lin = clamp(round(r2.y / 0.329), 0.0, 3.0);
		float kk = clamp(round(r2.x / 0.38 + lin * 0.5), 0.0, lin);
		vec2 mp = vec2((kk - lin * 0.5) * 0.38, lin * 0.329);
		float marca = cobre(length(r2 - mp) - 0.08, w);
		c = mix(c, c * 1.2 + vec3(0.05), marca);
		c *= mix(1.0, 1.1, smoothstep(dp - 0.7, dp - 0.4, d));
		float spot = exp(-dot(r2 - vec2(0.0, 0.45), r2 - vec2(0.0, 0.45)) * 1.6);
		c += vec3(1.0, 0.92, 0.75) * spot * 0.28;
	}

	// luz da cena + verniz: reflete o céu quando se olha "deitado", o
	// portal colorido lá no fundo e um brilho do sol
	c *= luz_cena;
	vec3 v = normalize(CAMERA_POSITION_WORLD - pm);
	float f1 = 1.0 - clamp(v.y, 0.0, 1.0);
	float f2 = f1 * f1;
	float fres = f2 * f2;
	c = mix(c, cor_ceu, fres * verniz * 0.8);
	// o portal colorido refletido: só nos últimos 6 m antes dos pinos
	if (d > dp - 6.0) {
		float fundo = smoothstep(dp - 6.0, dp + 0.5, d);
		vec3 portal = mix(cor_reflexo_b, cor_reflexo_a, 0.5 + 0.5 * sin(pm.x * 9.0));
		c += portal * fres * fundo * 0.28;
	}
	vec3 refl = vec3(-v.x, v.y, -v.z);
	float brilho = pow(max(dot(refl, dir_sol), 0.0), 48.0);
	c += vec3(1.0, 0.95, 0.85) * brilho * verniz * 0.6;

	// BORDAS DE NEON: sempre acesas na cor do cenário; esperando a bola,
	// luzes correm para os pinos (convite); na jogada, correm forte e um
	// brilho acompanha a bola
	float borda = smoothstep(meia_largura - 0.085, meia_largura - 0.015, ax);
	// o neon "acende" a madeira perto (a mais de 60 cm da borda já é zero)
	float espalha = 0.0;
	if (ax > meia_largura - 0.6) {
		espalha = exp(-(meia_largura - ax) * 9.0) * 0.3;
	}
	float corre = smoothstep(0.42, 0.58, fract(d * 1.1 - fase)) * smoothstep(0.98, 0.84, fract(d * 1.1 - fase));
	// o brilho que acompanha a bola só existe com a pista acesa (na jogada)
	float onda_bola = 0.0;
	if (luz > 0.001) {
		onda_bola = exp(-abs(d - bola_z) * 1.6);
	}
	float forca = 0.75 + 0.45 * corre * chamado + luz * (corre * 0.6 + onda_bola * 1.4);
	vec3 e = cor_luz * (borda + espalha) * forca;
	e += cor_luz * onda_bola * luz * 0.18 * (1.0 - borda);
	ALBEDO = c + e;
}
