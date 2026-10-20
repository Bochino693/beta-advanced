shader_type canvas_item;

// FOTO REDONDA com aro colorido (placar, faixa "VEZ DE", strike, fim).

uniform vec4 cor_aro : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float aro = 0.08;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	vec4 c = texture(TEXTURE, UV);
	float dentro = 1.0 - smoothstep(1.0 - aro - 0.025, 1.0 - aro, r);
	float tudo = 1.0 - smoothstep(0.97, 1.0, r);
	COLOR = vec4(mix(cor_aro.rgb, c.rgb, dentro), tudo * COLOR.a);
}
