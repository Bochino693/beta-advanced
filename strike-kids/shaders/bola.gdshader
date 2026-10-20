shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// BOLA: textura (estrelas / corações) + luz em faixas + brilho de verniz
// bem marcado (bolinha branca de reflexo) + borda iluminada.

uniform sampler2D textura : source_color, filter_linear_mipmap, repeat_enable;
uniform float faixa = 0.08;
uniform float borda = 0.45;
uniform vec3 cor_borda : source_color = vec3(0.8, 0.9, 1.0);
uniform float brilho = 1.6;
uniform float aceso : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	ALBEDO = texture(textura, UV).rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = cor_borda * rim * borda + ALBEDO * aceso * 0.6;
}

void light() {
	float t = smoothstep(-faixa, faixa, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR * t * ATTENUATION / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float s = smoothstep(0.965, 0.975, dot(NORMAL, h));
	SPECULAR_LIGHT += LIGHT_COLOR * s * brilho * ATTENUATION;
}
