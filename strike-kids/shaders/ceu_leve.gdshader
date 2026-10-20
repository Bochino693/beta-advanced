shader_type sky;

// CÉU LEVE (cenário LEVE, o padrão na TV Box): o mesmo degradê e as mesmas
// cores do ceu.gdshader, com os extras mais simples: uma camada de
// estrelas (não duas), nebulosa com dois senos, um leque de raios de luz
// (fundo do mar) e só o brilho do sol (o disco é o rostinho do astro.gdshader).

uniform vec3 cor_topo : source_color = vec3(0.20, 0.52, 1.0);
uniform vec3 cor_meio : source_color = vec3(0.45, 0.75, 1.0);
uniform vec3 cor_horizonte : source_color = vec3(1.0, 0.86, 0.95);
uniform vec3 cor_chao : source_color = vec3(0.55, 0.82, 0.55);
uniform vec3 dir_sol = vec3(0.35, 0.55, -0.75);
uniform vec3 cor_sol : source_color = vec3(1.0, 0.95, 0.75);
uniform float forca_sol = 1.0;
uniform float estrelas = 0.0;
uniform vec3 cor_nebulosa : source_color = vec3(0.9, 0.4, 1.0);
uniform float raios = 0.0;

// sorteio sem seno ("hash without sine", Dave Hoskins)
float h3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 c;
	if (y > 0.0) {
		c = mix(cor_horizonte, cor_meio, smoothstep(0.0, 0.18, y));
		c = mix(c, cor_topo, smoothstep(0.18, 0.75, y));
	} else {
		c = mix(cor_horizonte, cor_chao, smoothstep(0.0, -0.08, y));
	}
	if (estrelas > 0.0 && y > -0.02) {
		float n = sin(d.x * 3.1 + d.z * 1.7) * sin(d.y * 4.2 + d.z * 1.3);
		c += cor_nebulosa * smoothstep(0.35, 1.2, n) * 0.22 * estrelas;
		vec3 p = d * 90.0;
		vec3 cel = floor(p);
		float r = h3(cel);
		if (r > 0.955) {
			vec3 f = fract(p) - 0.5;
			float e = smoothstep(0.2, 0.0, length(f));
			vec3 tom = mix(vec3(1.0, 0.95, 0.8), vec3(0.75, 0.85, 1.0), fract(r * 31.0));
			c += tom * e * 2.2 * estrelas;
		}
	}
	if (raios > 0.0 && y > 0.0) {
		float s = max(0.0, sin(d.x * 21.0 + d.z * 9.0) * 0.5 + 0.5);
		float s2 = s * s;
		float s4 = s2 * s2;
		c += vec3(0.75, 1.0, 0.95) * (s4 * s4 * s2) * smoothstep(0.05, 0.7, y) * 0.45 * raios;
	}
	float sol = max(dot(d, normalize(dir_sol)), 0.0);
	float s2 = sol * sol;
	float s4 = s2 * s2;
	float s8 = s4 * s4;
	// só o BRILHO em volta: o disco do sol (e da lua) é o rostinho do
	// astro.gdshader, desenhado sempre exatamente nesta direção
	c += cor_sol * (s8 * s4 * 0.25) * forca_sol;
	COLOR = c;
}
