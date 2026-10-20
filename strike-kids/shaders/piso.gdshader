shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// PISO DE MADEIRA da área de quem joga: o mesmo verniz "desenhado" da
// pista (cor da cena + reflexo do céu), leve — cobre a tela quando a
// câmera olha para o mascote. Com os pontos coloridos da área de
// arremesso e a estrela da saída, nas cores da pista (bordas suaves).

uniform sampler2D madeira : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 escala_uv = vec2(4.2, 1.6);
uniform vec3 tom : source_color = vec3(0.93, 0.84, 0.76);
uniform vec3 luz_cena = vec3(1.2, 1.2, 1.22);
uniform vec3 cor_ceu : source_color = vec3(0.85, 0.93, 1.0);
uniform float verniz = 0.22;
uniform float pulso = 0.0;

varying vec3 pm;

const vec3 ARCO[7] = vec3[7](vec3(1.0, 0.23, 0.33), vec3(1.0, 0.56, 0.13), vec3(1.0, 0.85, 0.15),
	vec3(0.35, 0.86, 0.33), vec3(0.2, 0.8, 1.0), vec3(0.27, 0.47, 1.0), vec3(0.72, 0.38, 1.0));

void vertex() {
	pm = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cobre(float dist, float w) {
	return clamp(0.5 - dist / w, 0.0, 1.0);
}

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

vec3 adesivo(vec3 c, float dist, float w, vec3 cor, float contorno) {
	c = mix(c, vec3(1.0), cobre(dist - contorno, w));
	return mix(c, cor, cobre(dist, w));
}

void fragment() {
	vec3 c = texture(madeira, UV * escala_uv).rgb * tom;
	float w = max(fwidth(pm.z), fwidth(pm.x)) * 1.2 + 1e-4;
	// pontos coloridos logo atrás da linha de falta
	if (abs(pm.z - 0.55) < 0.1 && abs(pm.x) < 0.62) {
		float ip = clamp(round(pm.x / 0.17), -3.0, 3.0);
		float dd = length(vec2(pm.x - ip * 0.17, pm.z - 0.55)) - 0.032;
		c = adesivo(c, dd, w, ARCO[int(ip) + 3], 0.011);
	}
	// a estrela da saída (de onde a bola sai), brilhando de leve
	if (abs(pm.z - 1.45) < 0.32 && abs(pm.x) < 0.32) {
		float de = sd_estrela(vec2(pm.x, 1.45 - pm.z), 0.2, 0.48) - 0.015;
		c += vec3(1.0, 0.85, 0.2) * exp(-max(de, 0.0) * 20.0) * (0.15 + 0.15 * pulso);
		c = adesivo(c, de, w, vec3(1.0, 0.82, 0.15), 0.02);
	}
	c *= luz_cena;
	vec3 v = normalize(CAMERA_POSITION_WORLD - pm);
	float f1 = 1.0 - clamp(v.y, 0.0, 1.0);
	float f2 = f1 * f1;
	ALBEDO = mix(c, cor_ceu, f2 * f2 * verniz);
}
