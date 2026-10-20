shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// SOL E LUA COM ROSTINHO (Mundo._astro): um quadradinho sempre de frente
// para a câmera, colocado NA DIREÇÃO do sol do céu (a mesma dir_sol do
// céu) e sempre à mesma distância da câmera — como o céu, fica "no
// infinito": por mais que a câmera ande, o rostinho continua exatamente
// sobre o brilho do sol do céu (nada de "dois sóis") e atrás de todo o
// cenário. Os raios giram devagar e o rosto pisca de vez em quando — tudo
// aqui, pelo relógio (TIME): o jogo não faz nada por quadro.

uniform sampler2D rosto : source_color, filter_linear_mipmap, repeat_disable;  // 2 quadros: olhos abertos | piscando
uniform sampler2D raios : source_color, filter_linear_mipmap, repeat_disable;
uniform float usa_raios = 1.0;
uniform float giro = 0.02;          // voltas por segundo
uniform float piscar_cada = 4.5;    // segundos entre uma piscada e outra
uniform vec4 tinta : source_color = vec4(1.0);
uniform vec3 direcao = vec3(0.146, 0.358, -0.922);
uniform float distancia = 140.0;    // da câmera até ele (m)
uniform float tamanho = 17.8;       // lado do quadrado a essa distância (m)

void vertex() {
	vec3 centro = CAMERA_POSITION_WORLD + normalize(direcao) * distancia;
	vec3 p = centro + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * tamanho;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
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
