shader_type canvas_item;
// Fundo de todas as telas: noite azul com chuva diagonal, retícula de quadrinho e vinheta.
// Barato o bastante para celular fraco: só matemática por pixel, nenhuma textura.
uniform vec4 top_color : source_color = vec4(0.22, 0.34, 0.62, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.06, 0.1, 0.22, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.784, 0.239, 1.0);
uniform vec2 glow_pos = vec2(0.82, 0.12);
uniform float rain_amount = 1.0;
uniform vec2 px_size = vec2(720.0, 1280.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
	// luz amarela distante (poste/janela) com bandas de pintura, não degradê liso
	float d = distance(uv * vec2(px_size.x / px_size.y, 1.0), glow_pos * vec2(px_size.x / px_size.y, 1.0));
	float g = clamp(1.0 - d * 2.2, 0.0, 1.0);
	g = floor(g * 5.0) / 5.0;
	col = mix(col, glow_color.rgb, g * 0.28);
	// retícula: pontos maiores onde é mais escuro
	vec2 p = FRAGCOORD.xy / 7.0;
	p = mat2(vec2(0.707, -0.707), vec2(0.707, 0.707)) * p;
	float dotd = length(fract(p) - 0.5);
	float dark = 1.0 - dot(col, vec3(0.3, 0.59, 0.11)) * 2.4;
	col *= 1.0 - step(dotd, clamp(dark, 0.0, 1.0) * 0.32) * 0.35;
	// chuva: colunas com gotas alongadas que descem inclinadas
	vec2 r = uv * vec2(px_size.x / 9.0, 1.0);
	r.x += uv.y * 18.0;
	float colid = floor(r.x);
	float speed = 0.7 + hash(vec2(colid, 1.0)) * 0.8;
	float y = fract(uv.y * 1.6 - TIME * speed + hash(vec2(colid, 7.0)));
	float streak = smoothstep(0.0, 0.03, y) * smoothstep(0.16, 0.03, y) * step(0.82, hash(vec2(colid, 3.0)));
	float thin = 1.0 - smoothstep(0.0, 0.12, abs(fract(r.x) - 0.5));
	col += vec3(0.55, 0.65, 0.95) * streak * thin * 0.35 * rain_amount;
	// vinheta
	float v = distance(uv, vec2(0.5));
	col *= 1.0 - smoothstep(0.5, 0.9, v) * 0.4;
	COLOR = vec4(col, 1.0);
}
