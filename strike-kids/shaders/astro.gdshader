shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// SOL E LUA COM ROSTINHO (Mundo._astro): um quadradinho bem longe no céu,
// sempre de frente para a câmera. Os raios do sol giram devagar e o rosto
// pisca de vez em quando — tudo aqui, pelo relógio (TIME): o jogo não faz
// nada por quadro. Um desenho só (rosto e raios juntos).

uniform sampler2D rosto : source_color, filter_linear_mipmap, repeat_disable;  // 2 quadros: olhos abertos | piscando
uniform sampler2D raios : source_color, filter_linear_mipmap, repeat_disable;
uniform float usa_raios = 1.0;
uniform float giro = 0.02;          // voltas por segundo
uniform float piscar_cada = 4.5;    // segundos entre uma piscada e outra
uniform vec4 tinta : source_color = vec4(1.0);

void vertex() {
	// sempre de frente para a câmera (com o tamanho do nó)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 fundo = vec4(0.0);
	if (usa_raios > 0.5) {
		float a = TIME * giro * TAU;
		vec2 q = UV - 0.5;
		q = vec2(q.x * cos(a) - q.y * sin(a), q.x * sin(a) + q.y * cos(a));
		fundo = texture(raios, q + 0.5);
	}
	float pisca = step(piscar_cada - 0.16, mod(TIME, piscar_cada));
	vec4 r = texture(rosto, vec2((clamp(UV.x, 0.002, 0.998) + pisca) * 0.5, UV.y));
	// o rosto por cima dos raios
	float a_saida = r.a + fundo.a * (1.0 - r.a);
	vec3 cor = r.rgb * r.a + fundo.rgb * fundo.a * (1.0 - r.a);
	ALBEDO = (cor / max(a_saida, 1e-4)) * tinta.rgb;
	ALPHA = a_saida * tinta.a;
}
