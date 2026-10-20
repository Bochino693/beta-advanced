shader_type canvas_item;

// IMAGEM DA CÂMERA -> foto quadrada. Converte o que a webcam manda (RGB,
// YCbCr num só quadro ou Y + CbCr separados), recorta o quadrado do meio
// e espelha (a criança se vê como num espelho).

uniform sampler2D cam_a : filter_linear;   // RGB, YCbCr ou só o Y
uniform sampler2D cam_b : filter_linear;   // CbCr (quando vem separado)
uniform int tipo = 1;                      // 1 RGB, 2 YCbCr, 3 YCbCr separado
uniform vec2 escala_uv = vec2(1.0, 1.0);   // recorte do quadrado do meio
uniform bool espelhar = true;
uniform int giro = 0;                      // 0, 1, 2, 3 = 0°, 90°, 180°, 270° (câmera montada de lado)

vec3 ycbcr(float y, vec2 cbcr) {
	cbcr -= vec2(0.5);
	return vec3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
}

void fragment() {
	vec2 uv = UV;
	if (espelhar) {
		uv.x = 1.0 - uv.x;
	}
	vec2 q = uv - 0.5;
	if (giro == 1) {
		q = vec2(q.y, -q.x);
	} else if (giro == 2) {
		q = -q;
	} else if (giro == 3) {
		q = vec2(-q.y, q.x);
	}
	uv = q * escala_uv + 0.5;
	vec3 c;
	if (tipo == 3) {
		c = ycbcr(texture(cam_a, uv).r, texture(cam_b, uv).rg);
	} else if (tipo == 2) {
		vec3 t = texture(cam_a, uv).rgb;
		c = ycbcr(t.r, t.gb);
	} else {
		c = texture(cam_a, uv).rgb;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
