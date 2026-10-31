shader_type spatial;
// Sombreamento "pintado" para celular: luz em faixas (sem degradê), borda das faixas quebrada por
// ruído (pincelada), sombra puxando para azul-noite e retícula de quadrinho nas partes escuras.
render_mode cull_back;
uniform vec4 albedo : source_color = vec4(0.4, 0.5, 0.75, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.05, 0.09, 0.22, 1.0);
uniform float brush = 0.18;
uniform float emission_energy = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0, 0.78, 0.24, 1.0);
uniform float halftone = 1.0;
varying vec3 wpos;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x), mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x), mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	// mancha de pincel na cor base: duas escalas de ruído esticadas
	float n = vnoise(wpos * vec3(3.0, 9.0, 3.0)) * 0.6 + vnoise(wpos * 11.0) * 0.4;
	ALBEDO = albedo.rgb * (0.88 + n * 0.22);
	EMISSION = emission_color.rgb * emission_energy;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float n = vnoise(wpos * vec3(4.0, 12.0, 4.0)) - 0.5;
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float v = clamp(ndl * ATTENUATION + n * brush, 0.0, 1.0);
	float band = v < 0.42 ? 0.0 : (v < 0.62 ? 0.45 : (v < 0.86 ? 0.8 : 1.05));
	// retícula: pontos aparecem onde a luz é fraca
	vec2 p = mat2(vec2(0.707, -0.707), vec2(0.707, 0.707)) * (FRAGCOORD.xy / 6.0);
	float dotd = length(fract(p) - 0.5);
	float ht = step(dotd, (1.0 - v) * 0.42) * halftone;
	vec3 lit = ALBEDO * LIGHT_COLOR / PI * band;
	DIFFUSE_LIGHT += lit * (1.0 - ht * 0.45);
}
