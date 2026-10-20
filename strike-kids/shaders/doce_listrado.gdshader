shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// LISTRAS DE BALA (para-choques): calculadas no shader pela posição no
// próprio objeto — listras em espiral perfeitas e nítidas em qualquer
// resolução, numa malha simples (cápsula). Luz toon como no resto do jogo.

uniform vec4 cor_a : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cor_b : source_color = vec4(1.0, 0.23, 0.31, 1.0);
uniform float listras_por_metro = 4.0;
uniform float giro = 1.0;            // voltas da espiral por listra
uniform float faixa : hint_range(0.0, 0.5) = 0.08;
uniform float borda : hint_range(0.0, 2.0) = 0.35;
uniform float especular : hint_range(0.0, 2.0) = 0.5;

varying vec3 pos_local;

vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	pos_local = VERTEX;
}

void fragment() {
	// o ângulo em volta da cápsula vem do UV dela (na CapsuleMesh o UV.x dá a
	// volta: x = -sen, z = -cos): é o mesmo atan(z, x) de antes, sem o
	// atan, que é caro por pixel
	float ang = -0.25 - UV.x;
	float s = fract(pos_local.y * listras_por_metro + ang * giro) - 0.5;
	float w = fwidth(s) * 0.75 + 1e-5;
	float m = clamp(0.5 - (abs(s) - 0.25) / w, 0.0, 1.0);
	vec3 base = lin(mix(cor_a.rgb, cor_b.rgb, m));
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * rim * borda;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(-faixa, faixa, ndl - 0.02);
	DIFFUSE_LIGHT += LIGHT_COLOR * t * ATTENUATION / PI;
	if (especular > 0.0) {
		vec3 h = normalize(VIEW + LIGHT);
		float sp = smoothstep(0.93, 0.95, dot(NORMAL, h));
		SPECULAR_LIGHT += LIGHT_COLOR * sp * especular * ATTENUATION;
	}
}
