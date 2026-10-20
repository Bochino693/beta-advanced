shader_type canvas_item;

// Brilho que passa pela logo Lazer & Sport na abertura (faixa diagonal
// clara, só onde a imagem existe).

uniform float pos = -1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = UV.x * 0.8 + UV.y * 0.3 - pos;
	float b = (1.0 - smoothstep(0.0, 0.06, abs(d))) * 0.6;
	COLOR = vec4(min(c.rgb + vec3(b), vec3(1.0)), c.a);
}
