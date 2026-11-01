extends RefCounted
## Biblioteca de props de cenário montados com primitivas e juntados em lote.
## Cada prop (mochila, lixeira, planta, extintor...) vira várias caixas/cilindros/esferas, mas tudo
## vai para TRÊS MultiMesh por cena (caixas, cilindros, esferas), com cor por instância. Ou seja,
## encher a cena de objetos custa 3 draw calls, não 1 por peça. case_scene.gd chama dress(scene_id)
## e depois monta as MultiMesh com boxes / cyls / balls.

var boxes: Array = []   # [pos, size, cor, Basis]
var cyls: Array = []    # [pos, Vector3(diâmetro, altura, diâmetro), cor, Basis]
var balls: Array = []   # [pos, Vector3(diâmetros), cor, Basis]
var labels: Array = []  # [pos, texto, altura da linha, cor, fonte, rot_y] (cartazes; Label3D)

# paleta curta, a mesma da cena (azul-noite, madeira e papel aquecendo, vermelho raro)
const INK := Color("#111a33")
const NAVY := Color("#1b2650")
const PAPER := Color("#efe8d6")
const CREAM := Color("#e8e2cc")
const RED := Color("#b34a5e")
const RED_D := Color("#8a2a3e")
const YEL := Color("#ffc83d")
const WOOD := Color("#7a5a3e")
const WOOD_D := Color("#5a3d2a")
const METAL := Color("#8a96b8")
const METAL_D := Color("#4a5580")
const LEAF := Color("#2f5a52")
const LEAF_D := Color("#24425a")
const TEAL := Color("#3d6a8a")
const GREEN := Color("#4f7a5a")
const PURPLE := Color("#6b4a8a")
const CARD := Color("#a07a4a")
const BAGS := [Color("#4f7a5a"), Color("#c84a5e"), Color("#3d6a8a"), Color("#6b4a8a"), Color("#a8873d"), Color("#26407a")]
const BOOKS := [Color("#6b4a8a"), Color("#3d6a8a"), Color("#8a3d4f"), Color("#4f7a5a"), Color("#a8873d"), Color("#2e3b6b"), Color("#c9bfa6")]

var _t := Transform3D.IDENTITY   # referencial do prop sendo montado


# ------------------------------------------------------------------ primitivas no referencial atual
func _at(p: Vector3, rot_y: float) -> void:
	_t = Transform3D(Basis(Vector3.UP, rot_y), p)


func b(lp: Vector3, s: Vector3, c: Color, lb := Basis.IDENTITY) -> void:
	boxes.append([_t * lp, s, c, _t.basis * lb])


func c(lp: Vector3, r: float, h: float, col: Color, lb := Basis.IDENTITY) -> void:
	cyls.append([_t * lp, Vector3(r * 2.0, h, r * 2.0), col, _t.basis * lb])


func s(lp: Vector3, r: float, col: Color, scl := Vector3.ONE) -> void:
	balls.append([_t * lp, scl * r * 2.0, col, _t.basis])


# ------------------------------------------------------------------ props
## mochila no chão: corpo, bolso da frente, alças e um chaveiro
func backpack(p: Vector3, rot := 0.0, col := Color("#4f7a5a"), lying := false) -> void:
	_at(p, rot)
	var lb := Basis(Vector3.RIGHT, -PI / 2.0 + 0.15) if lying else Basis(Vector3.RIGHT, -0.12)
	var up := Vector3(0, 0.12, 0) if lying else Vector3(0, 0.21, 0)
	b(up, Vector3(0.32, 0.42, 0.18), col, lb)
	b(up + lb * Vector3(0, -0.07, 0.11), Vector3(0.24, 0.18, 0.07), col.darkened(0.25), lb)
	b(up + lb * Vector3(0, 0.22, -0.02), Vector3(0.16, 0.04, 0.05), col.darkened(0.4), lb)
	for x in [-0.1, 0.1]:
		b(up + lb * Vector3(x, 0.02, -0.1), Vector3(0.04, 0.36, 0.02), INK, lb)
	s(up + lb * Vector3(0.12, -0.1, 0.16), 0.03, YEL)


## cartaz na parede: papel, moldura de fita e texto pintado. normal = para onde o cartaz olha
func poster(p: Vector3, normal_rot: float, w: float, h: float, col: Color, txt := "", txt_col := INK, font := "marker") -> void:
	_at(p, normal_rot)
	b(Vector3.ZERO, Vector3(w, h, 0.012), col)
	b(Vector3(0, h * 0.5 - 0.02, 0.008), Vector3(w * 0.3, 0.05, 0.004), Color(0.9, 0.88, 0.8))   # fita no alto
	if txt != "":
		labels.append([_t * Vector3(0, h * 0.12, 0.012), txt, minf(h * 0.2, w * 0.22), txt_col, font, normal_rot])


## lixeira de chão com saco e papel embolado
func trash(p: Vector3, col := METAL_D, full := true) -> void:
	_at(p, 0.0)
	c(Vector3(0, 0.3, 0), 0.19, 0.6, col)
	c(Vector3(0, 0.6, 0), 0.21, 0.04, col.darkened(0.3))
	if full:
		s(Vector3(0.04, 0.63, 0.02), 0.08, PAPER)
		s(Vector3(-0.07, 0.62, -0.05), 0.06, CREAM)


## planta de vaso: vaso, terra e folhas caindo para os lados (as folhas são esferas achatadas)
func plant(p: Vector3, big := false) -> void:
	var k := 1.5 if big else 1.0
	_at(p, 0.0)
	c(Vector3(0, 0.17 * k, 0), 0.17 * k, 0.34 * k, Color("#a05a4a"))
	c(Vector3(0, 0.34 * k, 0), 0.19 * k, 0.04 * k, Color("#8a4a3e"))
	for i in 6:
		var a := i * TAU / 6.0 + 0.3
		var r := 0.14 * k
		s(Vector3(cos(a) * r, (0.55 + 0.1 * (i % 2)) * k, sin(a) * r), 0.13 * k, LEAF if i % 2 == 0 else LEAF_D, Vector3(1.0, 0.45, 0.6))
	s(Vector3(0, 0.75 * k, 0), 0.12 * k, LEAF, Vector3(0.7, 1.0, 0.7))


## extintor vermelho com mangueira, preso na parede (rot = para onde olha)
func extinguisher(p: Vector3, rot := 0.0) -> void:
	_at(p, rot)
	c(Vector3(0, 0.3, 0.1), 0.08, 0.48, RED)
	c(Vector3(0, 0.57, 0.1), 0.03, 0.06, INK)
	b(Vector3(0.05, 0.6, 0.1), Vector3(0.1, 0.02, 0.03), INK)
	b(Vector3(0.07, 0.4, 0.17), Vector3(0.02, 0.32, 0.02), INK)
	b(Vector3(0, 0.75, 0.01), Vector3(0.3, 0.3, 0.01), Color("#c84a5e"))   # placa
	b(Vector3(0, 0.75, 0.02), Vector3(0.12, 0.18, 0.006), PAPER)


## relógio de parede (rot = para onde olha)
func clock(p: Vector3, rot := 0.0, r := 0.2) -> void:
	_at(p, rot)
	c(Vector3.ZERO, r, 0.05, PAPER, Basis(Vector3.RIGHT, PI / 2.0))
	c(Vector3(0, 0, -0.005), r * 1.12, 0.04, INK, Basis(Vector3.RIGHT, PI / 2.0))
	b(Vector3(0, r * 0.3, 0.03), Vector3(0.022, r * 0.6, 0.01), INK)
	b(Vector3(r * 0.22, 0, 0.03), Vector3(r * 0.5, 0.022, 0.01), INK, Basis(Vector3.BACK, 0.4))
	s(Vector3(0, 0, 0.035), 0.018, RED)


## troféu dourado (copa, haste e base de madeira)
func trophy(p: Vector3, k := 1.0) -> void:
	_at(p, 0.0)
	var gold := Color("#c9a24a")
	b(Vector3(0, 0.03 * k, 0), Vector3(0.12, 0.06, 0.12) * k, WOOD_D)
	c(Vector3(0, 0.1 * k, 0), 0.015 * k, 0.1 * k, gold)
	c(Vector3(0, 0.2 * k, 0), 0.06 * k, 0.1 * k, gold, Basis.IDENTITY)
	s(Vector3(0, 0.15 * k, 0), 0.05 * k, gold, Vector3(1, 0.5, 1))
	for x in [-1, 1]:
		c(Vector3(x * 0.075 * k, 0.21 * k, 0), 0.012 * k, 0.07 * k, gold, Basis(Vector3.BACK, x * 0.6))


## pilha de livros torta (n livros)
func books(p: Vector3, n: int, rot := 0.0, seed := 1) -> void:
	_at(p, rot)
	var y := 0.0
	for i in n:
		var h := 0.035 + float((seed + i * 3) % 4) * 0.012
		var w := 0.26 - float((seed + i) % 3) * 0.03
		b(Vector3(0.0, y + h * 0.5, 0.0), Vector3(w, h, w * 0.75), BOOKS[(seed + i * 2) % BOOKS.size()], Basis(Vector3.UP, (float((i * 7 + seed) % 5) - 2.0) * 0.12))
		y += h


## garrafas e copos (n) em fila
func bottles(p: Vector3, n: int, rot := 0.0, seed := 2) -> void:
	_at(p, rot)
	var cols := [Color("#6fbfa0"), Color("#9fd8ff"), Color("#e0a040"), Color("#c84a5e"), CREAM]
	for i in n:
		var h := 0.16 + float((i + seed) % 3) * 0.05
		var col: Color = cols[(i * 2 + seed) % cols.size()]
		c(Vector3(i * 0.09, h * 0.5, float((i * 5) % 3) * 0.03), 0.032, h, col)
		c(Vector3(i * 0.09, h + 0.025, float((i * 5) % 3) * 0.03), 0.013, 0.05, col.darkened(0.3))


## banqueta redonda de metal
func stool(p: Vector3, col := NAVY) -> void:
	_at(p, 0.0)
	c(Vector3(0, 0.62, 0), 0.17, 0.05, col)
	c(Vector3(0, 0.31, 0), 0.025, 0.6, METAL_D)
	c(Vector3(0, 0.02, 0), 0.15, 0.03, METAL_D)


## cadeira de plástico (assento e encosto inteiriços, pernas finas)
func plastic_chair(p: Vector3, rot := 0.0, col := Color("#c84a5e")) -> void:
	_at(p, rot)
	b(Vector3(0, 0.44, 0), Vector3(0.42, 0.04, 0.4), col)
	b(Vector3(0, 0.7, -0.19), Vector3(0.42, 0.42, 0.04), col, Basis(Vector3.RIGHT, -0.12))
	for x in [-0.18, 0.18]:
		for z in [-0.16, 0.16]:
			b(Vector3(x, 0.21, z), Vector3(0.03, 0.42, 0.03), col.darkened(0.3))


## pilha de cadeiras de plástico encaixadas
func chair_stack(p: Vector3, n: int, rot := 0.0, col := Color("#c84a5e")) -> void:
	for i in n:
		plastic_chair(p + Vector3(0, i * 0.07, 0), rot, col)


## caixas de papelão empilhadas
func cardboard(p: Vector3, rot := 0.0, n := 2) -> void:
	_at(p, rot)
	var y := 0.0
	for i in n:
		var sz := Vector3(0.5 - i * 0.08, 0.34 - i * 0.04, 0.4 - i * 0.05)
		var lb := Basis(Vector3.UP, (i % 2) * 0.25 - 0.1)
		b(Vector3(0, y + sz.y * 0.5, 0), sz, CARD if i % 2 == 0 else CARD.darkened(0.15), lb)
		b(Vector3(0, y + sz.y, 0), Vector3(sz.x * 0.98, 0.006, 0.05), Color("#c9bfa6"), lb)   # fita
		y += sz.y


## cone de trânsito
func cone(p: Vector3) -> void:
	_at(p, 0.0)
	b(Vector3(0, 0.015, 0), Vector3(0.3, 0.03, 0.3), Color("#d06030"))
	# corpo afinando em três gomos (o lote só tem cilindro reto)
	c(Vector3(0, 0.09, 0), 0.1, 0.12, Color("#e07040"))
	c(Vector3(0, 0.2, 0), 0.07, 0.1, PAPER)
	c(Vector3(0, 0.31, 0), 0.045, 0.12, Color("#e07040"))


## bola (basquete ou vôlei)
func ball(p: Vector3, col := Color("#a0603e"), r := 0.12) -> void:
	_at(p, 0.0)
	s(Vector3(0, r, 0), r, col)


## violão/guitarra encostado (rot = para onde olha a frente)
func guitar(p: Vector3, rot := 0.0, col := Color("#a8873d")) -> void:
	_at(p, rot)
	var lean := Basis(Vector3.RIGHT, -0.2)
	s(Vector3(0, 0.25, 0.05), 0.19, col, Vector3(1.0, 1.2, 0.35))
	s(Vector3(0, 0.5, 0.0), 0.14, col, Vector3(1.0, 1.0, 0.35))
	b(Vector3(0, 0.88, -0.07), Vector3(0.05, 0.62, 0.03), WOOD_D, lean)
	b(Vector3(0, 1.2, -0.13), Vector3(0.08, 0.14, 0.03), INK, lean)
	c(Vector3(0, 0.38, 0.12), 0.05, 0.01, INK, Basis(Vector3.RIGHT, PI / 2.0))


## estante de partituras (haste, base em tripé, bandeja inclinada com folhas)
func music_stand(p: Vector3, rot := 0.0) -> void:
	_at(p, rot)
	c(Vector3(0, 0.5, 0), 0.012, 1.0, METAL_D)
	for i in 3:
		var a := i * TAU / 3.0
		b(Vector3(cos(a) * 0.12, 0.02, sin(a) * 0.12), Vector3(0.26, 0.015, 0.02), METAL_D, Basis(Vector3.UP, -a))
	b(Vector3(0, 1.05, 0.02), Vector3(0.46, 0.32, 0.02), INK, Basis(Vector3.RIGHT, -0.35))
	b(Vector3(0.04, 1.06, 0.04), Vector3(0.34, 0.26, 0.01), PAPER, Basis(Vector3.RIGHT, -0.35))


## caixa de som / amplificador pequeno
func speaker(p: Vector3, rot := 0.0, k := 1.0) -> void:
	_at(p, rot)
	b(Vector3(0, 0.3 * k, 0), Vector3(0.4, 0.6, 0.32) * k, INK)
	c(Vector3(0, 0.38 * k, 0.165 * k), 0.12 * k, 0.01, Color("#2a2a3e"), Basis(Vector3.RIGHT, PI / 2.0))
	c(Vector3(0, 0.14 * k, 0.165 * k), 0.06 * k, 0.01, Color("#2a2a3e"), Basis(Vector3.RIGHT, PI / 2.0))


## caneca
func mug(p: Vector3, col := CREAM) -> void:
	_at(p, 0.0)
	c(Vector3(0, 0.05, 0), 0.04, 0.1, col)
	b(Vector3(0.05, 0.05, 0), Vector3(0.02, 0.05, 0.015), col)


## folhas de papel soltas no chão ou na mesa
func papers(p: Vector3, n: int, spread := 0.3, seed := 3) -> void:
	_at(p, 0.0)
	for i in n:
		var a := float((seed + i * 37) % 100) / 100.0 * TAU
		var r := spread * float((seed * 7 + i * 13) % 100) / 100.0
		b(Vector3(cos(a) * r, 0.004 + i * 0.002, sin(a) * r), Vector3(0.21, 0.004, 0.29), Color("#b8b2a2") if i % 3 else Color("#a8a292"), Basis(Vector3.UP, a * 1.7))


## arquivo de aço com gavetas
func file_cabinet(p: Vector3, rot := 0.0) -> void:
	_at(p, rot)
	b(Vector3(0, 0.66, 0), Vector3(0.46, 1.32, 0.55), METAL)
	for i in 4:
		b(Vector3(0, 0.18 + i * 0.32, 0.28), Vector3(0.4, 0.28, 0.01), METAL.darkened(0.12))
		b(Vector3(0, 0.26 + i * 0.32, 0.29), Vector3(0.12, 0.025, 0.02), INK)
	b(Vector3(0, 1.36, 0), Vector3(0.24, 0.08, 0.18), CARD)   # caixa em cima


## estante baixa com fichários coloridos
func binder_shelf(p: Vector3, rot := 0.0, length := 1.0) -> void:
	_at(p, rot)
	b(Vector3(0, 0.45, 0), Vector3(length, 0.9, 0.36), WOOD_D)
	for row in 2:
		var y := 0.12 + row * 0.42
		var x := -length * 0.5 + 0.06
		var i := 0
		while x < length * 0.5 - 0.08:
			var w := 0.07
			b(Vector3(x + w * 0.5, y + 0.15, 0.06), Vector3(w, 0.3, 0.28), BAGS[(i + row * 3) % BAGS.size()])
			x += w + 0.008
			i += 1


## porta-guarda-chuva com dois guarda-chuvas
func umbrella_stand(p: Vector3) -> void:
	_at(p, 0.0)
	c(Vector3(0, 0.25, 0), 0.12, 0.5, METAL_D)
	b(Vector3(0.03, 0.55, 0), Vector3(0.04, 0.6, 0.04), RED_D, Basis(Vector3.BACK, 0.15))
	b(Vector3(-0.03, 0.52, 0.03), Vector3(0.04, 0.55, 0.04), NAVY, Basis(Vector3.BACK, -0.12))
	b(Vector3(0.09, 0.85, 0), Vector3(0.1, 0.02, 0.02), RED_D)


## colchonete azul da educação física empilhado
func gym_mats(p: Vector3, n: int, rot := 0.0) -> void:
	_at(p, rot)
	for i in n:
		b(Vector3(0.02 * (i % 2), 0.05 + i * 0.1, 0), Vector3(1.0, 0.09, 0.6), Color("#2e4f9a") if i % 2 == 0 else Color("#26407a"))


## balde de tinta com respingo
func paint_can(p: Vector3, col := TEAL) -> void:
	_at(p, 0.0)
	c(Vector3(0, 0.12, 0), 0.12, 0.24, PAPER)
	c(Vector3(0, 0.245, 0), 0.115, 0.01, col)
	b(Vector3(0.12, 0.2, 0), Vector3(0.01, 0.08, 0.03), col)


## carro estacionado (silhueta simples de caixas)
func car(p: Vector3, rot := 0.0, col := Color("#3a4a7a")) -> void:
	_at(p, rot)
	b(Vector3(0, 0.45, 0), Vector3(1.7, 0.55, 3.9), col)
	b(Vector3(0, 0.95, -0.2), Vector3(1.5, 0.5, 2.0), col.darkened(0.1))
	b(Vector3(0, 0.95, -0.2), Vector3(1.52, 0.38, 1.7), Color("#1a2650"))   # vidros
	for x in [-0.78, 0.78]:
		for z in [-1.25, 1.25]:
			c(Vector3(x, 0.32, z), 0.32, 0.2, INK, Basis(Vector3.BACK, PI / 2.0))
	b(Vector3(0.6, 0.55, 1.96), Vector3(0.3, 0.12, 0.02), Color("#fff2b8"))
	b(Vector3(-0.6, 0.55, 1.96), Vector3(0.3, 0.12, 0.02), Color("#fff2b8"))
	b(Vector3(0.6, 0.55, -1.96), Vector3(0.3, 0.1, 0.02), RED)
	b(Vector3(-0.6, 0.55, -1.96), Vector3(0.3, 0.1, 0.02), RED)


## saco de lixo preto amarrado
func trash_bag(p: Vector3) -> void:
	_at(p, 0.0)
	s(Vector3(0, 0.22, 0), 0.24, Color("#1c2034"), Vector3(1.0, 0.9, 0.9))
	s(Vector3(0, 0.45, 0), 0.06, Color("#1c2034"))


## escada de abrir encostada na parede
func step_ladder(p: Vector3, rot := 0.0) -> void:
	_at(p, rot)
	var lean := Basis(Vector3.RIGHT, -0.12)
	for x in [-0.2, 0.2]:
		b(Vector3(x, 0.8, 0.05), Vector3(0.04, 1.6, 0.04), METAL, lean)
	for i in 5:
		b(Vector3(0, 0.25 + i * 0.3, 0.05 - i * 0.035), Vector3(0.4, 0.03, 0.08), METAL_D)


## globo terrestre de mesa
func globe(p: Vector3) -> void:
	_at(p, 0.0)
	c(Vector3(0, 0.02, 0), 0.08, 0.04, WOOD_D)
	c(Vector3(0, 0.1, 0), 0.01, 0.14, Color("#c9a24a"))
	s(Vector3(0, 0.25, 0), 0.13, TEAL)
	s(Vector3(0.04, 0.29, 0.06), 0.06, GREEN, Vector3(1.2, 0.8, 0.6))


## pufe / almofada grande no chão
func beanbag(p: Vector3, col := PURPLE) -> void:
	_at(p, 0.0)
	s(Vector3(0, 0.2, 0), 0.34, col, Vector3(1.1, 0.6, 1.0))
	s(Vector3(0, 0.32, -0.15), 0.22, col.darkened(0.15), Vector3(1.0, 0.8, 0.6))


# ------------------------------------------------------------------ vestir cada cena
## Lugares escolhidos longe das âncoras, das pessoas do caso, dos figurantes e da frente da câmera.
func dress(id: String) -> void:
	match id:
		"corredor": _corredor()
		"biblioteca": _biblioteca()
		"teatro": _teatro()
		"sala_aula": _sala_aula()
		"cantina": _cantina()
		"patio": _patio()
		"sala_professores": _sala_professores()
		"quadra": _quadra()
		"sala_diretor": _sala_diretor()
		"deposito": _deposito()
		"laboratorio": _laboratorio()
		"sala_musica": _sala_musica()
		"fachada": _fachada()


func _corredor() -> void:
	# primeiro plano (chão vazio perto da câmera)
	backpack(Vector3(-0.95, 0, -0.5), 2.2, BAGS[5], true)
	papers(Vector3(-0.6, 0, -0.1), 3, 0.3, 11)
	backpack(Vector3(-1.72, 0, -2.4), 0.6, BAGS[1])
	backpack(Vector3(-1.75, 0, -7.9), -0.3, BAGS[2], true)
	backpack(Vector3(-1.7, 0, -12.2), 1.2, BAGS[4])
	poster(Vector3(-2.38, 2.55, -2.2), PI / 2.0, 0.6, 0.45, Color("#e0c040"), "FEIRA DE\nCIÊNCIAS", INK)
	poster(Vector3(-2.38, 2.5, -8.4), PI / 2.0, 0.5, 0.6, Color("#c84a5e"), "VOTE\nCHAPA 2", CREAM)
	poster(Vector3(-2.38, 2.55, -11.6), PI / 2.0, 0.55, 0.4, PAPER, "NÃO CORRA", RED_D, "bebas")
	trash(Vector3(1.95, 0, -10.0), GREEN)
	plant(Vector3(-1.95, 0, -14.45), true)
	plant(Vector3(1.95, 0, -14.45), true)
	books(Vector3(2.05, 0.46, -1.75), 3, 0.3, 4)
	papers(Vector3(0.3, 0, -8.2), 3, 0.35, 5)
	cone(Vector3(1.9, 0, -12.6))


func _biblioteca() -> void:
	backpack(Vector3(0.15, 0, -0.95), 2.8, BAGS[1])
	papers(Vector3(0.4, 0, -0.4), 2, 0.2, 12)
	plant(Vector3(-4.4, 0, -0.6), true)
	plant(Vector3(4.4, 0, -11.2), true)
	books(Vector3(-0.75, 0.79, -3.75), 4, 0.4, 1)
	books(Vector3(1.6, 0.79, -6.2), 3, -0.2, 6)
	books(Vector3(-3.6, 0, -5.0), 6, 0.2, 3)
	books(Vector3(-3.3, 0, -5.4), 4, -0.5, 9)
	backpack(Vector3(0.45, 0, -7.5), 2.4, BAGS[3])
	poster(Vector3(-4.93, 2.1, -4.0), PI / 2.0, 0.7, 0.9, Color("#26407a"), "LEIA\nMAIS", YEL)
	poster(Vector3(-4.93, 2.0, -8.6), PI / 2.0, 0.6, 0.8, PAPER, "CLUBE DO\nLIVRO", RED_D)
	clock(Vector3(4.93, 2.7, -5.0), -PI / 2.0)
	trash(Vector3(4.3, 0, -2.2))
	beanbag(Vector3(3.6, 0, -3.2), PURPLE)
	beanbag(Vector3(4.2, 0, -4.2), Color("#3d6a8a"))
	globe(Vector3(1.75, 1.145, -0.95))


func _teatro() -> void:
	cardboard(Vector3(3.4, 0.9, -8.8), 0.3, 3)
	cardboard(Vector3(-3.9, 0.9, -8.6), -0.2, 2)
	extinguisher(Vector3(5.44, 0.4, -3.0), -PI / 2.0)
	backpack(Vector3(0.52, 0.51, -1.4), PI, BAGS[0], true)
	backpack(Vector3(-1.5, 0.51, -0.2), PI + 0.4, BAGS[5], true)
	poster(Vector3(5.44, 2.4, -1.5), -PI / 2.0, 0.8, 1.1, Color("#8a2a3e"), "HAMLET\nSEXTA", YEL, "bebas")
	bottles(Vector3(-2.9, 0.9, -5.75), 2, 0.0, 1)
	speaker(Vector3(-4.6, 0.9, -6.2), 0.4, 1.4)
	speaker(Vector3(4.6, 0.9, -6.2), -0.4, 1.4)
	clock(Vector3(-5.44, 3.4, -3.0), PI / 2.0, 0.25)


func _sala_aula() -> void:
	backpack(Vector3(-0.1, 0, 0.5), 2.6, BAGS[2], true)
	books(Vector3(1.7, 0, 0.35), 4, 0.6, 8)
	papers(Vector3(0.6, 0, 0.9), 3, 0.3, 13)
	backpack(Vector3(-1.75, 0, -2.75), 0.4, BAGS[1])
	backpack(Vector3(0.9, 0, -4.1), -0.6, BAGS[3], true)
	backpack(Vector3(-2.6, 0, -1.2), 1.2, BAGS[4])
	binder_shelf(Vector3(3.1, 0, -6.7), -PI / 2.0, 1.2)
	books(Vector3(3.1, 0.9, -6.6), 3, 0.2, 2)
	globe(Vector3(3.15, 0.9, -7.15))
	poster(Vector3(3.44, 1.9, -2.6), -PI / 2.0, 0.9, 0.6, Color("#e0c040"), "A B C D\nE F G", INK, "bebas")
	poster(Vector3(3.44, 2.0, -6.0), -PI / 2.0, 0.5, 0.7, PAPER, "MAPA", INK, "bebas")
	plant(Vector3(-3.25, 0.98, -5.6))
	papers(Vector3(-0.9, 0, -2.2), 3, 0.3, 7)


func _cantina() -> void:
	cone(Vector3(-0.7, 0, -0.1))
	papers(Vector3(-0.2, 0, 0.4), 2, 0.25, 14)
	trash_bag(Vector3(1.6, 0, 0.1))
	trash(Vector3(3.5, 0, -0.8), GREEN)
	trash(Vector3(3.5, 0, -1.4), Color("#3d6a8a"))
	plant(Vector3(-3.55, 0, -7.4), true)
	chair_stack(Vector3(3.45, 0, -3.0), 4, -PI / 2.0, Color("#c84a5e"))
	bottles(Vector3(0.3, 0.77, -1.7), 3, 0.2, 3)
	bottles(Vector3(-0.2, 0.77, -4.3), 2, 0.0, 4)
	clock(Vector3(2.0, 2.65, -7.97))
	poster(Vector3(-3.94, 1.9, -1.6), PI / 2.0, 0.6, 0.8, Color("#4f7a5a"), "SUCO\nNATURAL", CREAM)
	mug(Vector3(0.95, 0.77, -1.35), TEAL)


func _patio() -> void:
	backpack(Vector3(-0.95, 0, 0.6), 0.4, BAGS[3], true)
	for x in [-5.2, 5.2]:
		_at(Vector3(x, 0, -12.3), 0.0)
		b(Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 0.6), Color("#5a6a9e"))
		for i in 4:
			s(Vector3(-0.6 + i * 0.4, 0.62, 0), 0.22, LEAF if i % 2 == 0 else LEAF_D, Vector3(1, 0.8, 1))
	cone(Vector3(3.6, 0, -4.0))
	cone(Vector3(4.0, 0, -4.6))
	ball(Vector3(1.9, 0, -1.4), Color("#a0603e"))
	trash_bag(Vector3(2.95, 0, -2.4))
	backpack(Vector3(-2.2, 0, -7.6), 0.8, BAGS[0], true)
	umbrella_stand(Vector3(-5.9, 0, -11.4))


func _sala_professores() -> void:
	cardboard(Vector3(-1.1, 0, 0.5), 0.3, 2)
	papers(Vector3(-0.6, 0.6, 0.5), 3, 0.15, 15)
	binder_shelf(Vector3(-3.15, 0, -1.0), PI / 2.0, 1.4)
	plant(Vector3(3.1, 0, -0.6), true)
	books(Vector3(0.6, 0.78, -3.3), 3, 0.5, 5)
	papers(Vector3(-0.2, 0.78, -3.9), 4, 0.25, 9)
	mug(Vector3(-0.5, 0.78, -3.2), RED_D)
	mug(Vector3(0.1, 0.78, -4.0), TEAL)
	clock(Vector3(3.44, 2.4, -1.5), -PI / 2.0)
	poster(Vector3(3.44, 1.9, -5.6), -PI / 2.0, 0.6, 0.8, PAPER, "CALENDÁRIO", INK, "bebas")
	umbrella_stand(Vector3(-2.95, 0, 0.9))
	file_cabinet(Vector3(-3.1, 0, -6.6), PI / 2.0)


func _quadra() -> void:
	cone(Vector3(1.5, 0, -0.5))
	ball(Vector3(0.5, 0, -0.9), CREAM)
	for i in 4:
		cone(Vector3(-5.8, 0, -2.5 - i * 1.2))
	gym_mats(Vector3(-5.6, 0, -11.8), 5, 0.1)
	for i in 5:
		ball(Vector3(-4.8 + (i % 3) * 0.35, 0, -10.6 + (i / 3) * 0.3), Color("#a0603e") if i % 2 == 0 else CREAM)
	bottles(Vector3(-2.1, 0.45, -2.0), 3, 0.0, 6)
	backpack(Vector3(4.75, 0.5, -9.2), -PI / 2.0, BAGS[2], true)
	backpack(Vector3(5.1, 1.0, -4.2), -PI / 2.0, BAGS[4], true)
	for x in [-5.0, -3.6, 5.6]:
		_at(Vector3(x, 4.6, -14.42), 0.0)
		b(Vector3(0, 0, 0.02), Vector3(0.9, 1.3, 0.02), Color("#8a2a3e") if x < 0 else Color("#26407a"))
		b(Vector3(0, 0, 0.035), Vector3(0.4, 0.4, 0.01), YEL)
	trophy(Vector3(-0.2, 0.45, -2.0), 1.4)


func _sala_diretor() -> void:
	books(Vector3(-0.95, 0, -1.1), 5, 0.3, 5)
	file_cabinet(Vector3(-2.65, 0, -2.0), PI / 2.0)
	plant(Vector3(-2.65, 0, -3.2), true)
	books(Vector3(-0.35, 0.84, -4.6), 4, 0.2, 2)
	mug(Vector3(0.4, 0.84, -4.6), PAPER)
	for z in [-1.4, -2.6]:
		_at(Vector3(-2.95, 1.9, z), PI / 2.0)
		b(Vector3.ZERO, Vector3(0.45, 0.34, 0.03), Color("#c9a24a"))
		b(Vector3(0, 0, 0.02), Vector3(0.37, 0.26, 0.01), PAPER)
	clock(Vector3(-2.95, 2.55, -4.0), PI / 2.0)
	trash(Vector3(1.0, 0, -5.0), WOOD_D, false)
	trophy(Vector3(-1.6, 2.33, -6.15), 1.2)


func _deposito() -> void:
	paint_can(Vector3(0.85, 0, -0.4), Color("#4e6fc0"))
	papers(Vector3(0.2, 0, -0.6), 3, 0.3, 16)
	paint_can(Vector3(-2.1, 0, -5.6), TEAL)
	paint_can(Vector3(-1.85, 0, -5.75), RED_D)
	paint_can(Vector3(-2.05, 0.24, -5.65), YEL)
	step_ladder(Vector3(2.3, 0, -0.9), -PI / 2.0)
	cardboard(Vector3(-2.0, 0, -0.5), 0.2, 3)
	cone(Vector3(1.9, 0, -0.1))
	trash_bag(Vector3(-1.4, 0, -0.1))
	plastic_chair(Vector3(1.9, 0, -4.9), 2.5, Color("#55608f"))


func _laboratorio() -> void:
	bottles(Vector3(-0.6, 0.94, -5.15), 4, 0.0, 2)
	bottles(Vector3(0.9, 0.94, -2.45), 3, 0.0, 5)
	cardboard(Vector3(-3.0, 0, -0.5), 0.3, 2)
	_at(Vector3(3.1, 0, -6.4), 0.0)   # cilindro de gás preso na parede
	c(Vector3(0, 0.6, 0), 0.13, 1.2, Color("#3d6a4a"))
	c(Vector3(0, 1.25, 0), 0.05, 0.1, METAL)
	clock(Vector3(3.44, 2.5, -3.0), -PI / 2.0)
	poster(Vector3(3.44, 1.9, -5.4), -PI / 2.0, 0.6, 0.8, Color("#4f7a5a"), "DNA", CREAM, "bebas")
	plant(Vector3(-3.25, 1.03, -3.2))
	stool(Vector3(1.9, 0, -5.8))


func _sala_musica() -> void:
	ball(Vector3(-0.6, 0, -0.4), Color("#c9a24a"), 0.09)
	papers(Vector3(-0.1, 0, -0.1), 3, 0.3, 17)
	guitar(Vector3(1.7, 0, -5.2), -0.4, Color("#c84a5e"))
	music_stand(Vector3(-1.9, 0, -2.0), 0.5)
	music_stand(Vector3(1.9, 0, -2.6), -0.6)
	speaker(Vector3(-3.0, 0, -6.5), 0.3, 1.3)
	poster(Vector3(3.44, 2.0, -4.2), -PI / 2.0, 0.7, 0.9, Color("#26407a"), "ROCK\nNA ESCOLA", YEL)
	clock(Vector3(-3.44, 2.5, -5.6), PI / 2.0)
	_at(Vector3(-0.2, 0, -6.4), 0.1)   # teclado no suporte em X
	b(Vector3(0, 0.75, 0), Vector3(1.0, 0.07, 0.3), INK)
	b(Vector3(0, 0.79, 0.04), Vector3(0.9, 0.012, 0.16), PAPER)
	for x in [-0.35, 0.35]:
		b(Vector3(x, 0.37, 0), Vector3(0.04, 0.75, 0.04), METAL_D, Basis(Vector3.BACK, 0.5))
		b(Vector3(x, 0.37, 0), Vector3(0.04, 0.75, 0.04), METAL_D, Basis(Vector3.BACK, -0.5))
	ball(Vector3(-2.2, 0, -1.0), Color("#c9a24a"), 0.08)   # pandeiro esquecido (vira disco)


func _fachada() -> void:
	# carro parado na rua, cortando o canto de baixo do quadro (moldura de primeiro plano)
	car(Vector3(2.7, 0, 3.0), PI / 2.0, Color("#3a4a7a"))
	trash_bag(Vector3(1.9, 0.16, -0.7))
	trash_bag(Vector3(1.2, 0.16, -0.9))
	_at(Vector3(-4.6, 0.16, -1.2), 0.0)   # bicicleta presa no poste: duas rodas e quadro
	c(Vector3(-0.4, 0.33, 0), 0.3, 0.04, INK, Basis(Vector3.RIGHT, PI / 2.0))
	c(Vector3(0.4, 0.33, 0), 0.3, 0.04, INK, Basis(Vector3.RIGHT, PI / 2.0))
	b(Vector3(0, 0.55, 0), Vector3(0.8, 0.04, 0.04), RED, Basis(Vector3.BACK, 0.25))
	b(Vector3(0.35, 0.75, 0), Vector3(0.04, 0.4, 0.04), INK)
	poster(Vector3(-5.0, 0.7, -2.23), 0.0, 0.6, 0.5, Color("#e0c040"), "FESTA\nJUNINA", INK)
	poster(Vector3(6.0, 0.7, -2.23), 0.0, 0.5, 0.6, PAPER, "MATRÍCULAS", RED_D, "bebas")
