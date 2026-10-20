shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

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

varying vec3 pos_local;
varying vec3 normal_local;

vec3 srgb_para_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
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
