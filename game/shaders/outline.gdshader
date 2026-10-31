shader_type spatial;
// Contorno de tinta: casco invertido. Segundo passe barato (sem luz).
render_mode cull_front, unshaded;
uniform float width = 0.025;
uniform vec4 ink : source_color = vec4(0.02, 0.035, 0.08, 1.0);
void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = ink.rgb; }
