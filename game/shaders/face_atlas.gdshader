shader_type spatial;
// Rosto trocável: o decalque do rosto mostra UMA célula do atlas (olhos ou boca).
// Trocar a expressão = mudar `cell`, sem blendshape (o Mixamo descarta blendshapes).
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(4.0, 2.0);
uniform vec2 cell = vec2(0.0, 0.0);
// o UV do decalque cobre a célula (0,0); se o modelo mapear o atlas inteiro, use full_uv = true
uniform bool full_uv = false;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 uv = full_uv ? UV / grid : UV;
	vec4 c = texture(atlas, uv + cell / grid);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * tint.rgb;
}
