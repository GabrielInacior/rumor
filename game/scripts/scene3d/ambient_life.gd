extends Node3D
## Figurantes que deixam a escola viva: rodinhas de alunos conversando (viram a cabeça para quem
## fala, gesticulam, riem) e gente passando ao fundo. Não são tocáveis e não carregam pista.
## Desempenho: no máximo ~6 por cena (metade no celular), visual sorteado mas estável por cena.

const Character := preload("res://scripts/scene3d/character.gd")

const SKINS := ["#f1c9a5", "#e0ac84", "#c98d6b", "#a8714f", "#8a5a3c", "#6b4430"]
const HAIRS := ["curto", "longo", "coque", "cacheado", "raspado", "franja", "rabo"]
const HAIR_COLORS := ["#1c1830", "#3a2a20", "#6b4a2a", "#2a2a3a", "#8a3a2a", "#c9a46b"]
const TOPS := ["#3d5a8a", "#5a3d6b", "#2f6b5a", "#7a3d4a", "#4a4a5a", "#6b5a3d", "#2a4a6b", "#8a6a3d"]
const ACCS := ["nenhum", "nenhum", "nenhum", "fones", "bone", "oculos"]
const MOODS := ["feliz", "neutro", "surpreso", "desconfiado", "feliz", "neutro"]
const GESTURES := ["falando", "rindo", "dando_de_ombros", "apontando", "pensando"]

var _groups: Array = []   # [{members:[Character], speaker:int, t:float}]
var _walkers: Array = []  # [{ch, a, b, dir, speed}]
var _rng := RandomNumberGenerator.new()


func populate(scene_id: String, spots: Dictionary) -> void:
	_rng.seed = hash(scene_id)
	var low := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	var budget := 3 if low else 6
	for g in spots.get("groups", []):
		var members := []
		for p in g:
			if budget <= 0:
				break
			members.append(_spawn(p))
			budget -= 1
		if members.size() >= 2:
			# cada um olha para o centro da rodinha
			var center := Vector3.ZERO
			for m in members:
				center += (m as Node3D).position
			center /= members.size()
			for m in members:
				var to := center - (m as Node3D).position
				(m as Node3D).rotation.y = atan2(to.x, to.z)
			_groups.append({"members": members, "speaker": 0, "t": _rng.randf_range(0.5, 2.0)})
		else:
			for m in members:
				(m as Node3D).queue_free()
	for w in spots.get("walks", []):
		if budget <= 0:
			break
		var ch := _spawn(w[0])
		ch.play("walking")
		_walkers.append({"ch": ch, "a": w[0], "b": w[1], "dir": 1.0, "speed": _rng.randf_range(0.7, 1.1), "wait": 0.0})
		budget -= 1


func _spawn(pos: Vector3) -> Node3D:
	var look := {
		"skin": SKINS[_rng.randi() % SKINS.size()],
		"hair": HAIRS[_rng.randi() % HAIRS.size()],
		"hair_color": HAIR_COLORS[_rng.randi() % HAIR_COLORS.size()],
		"top": TOPS[_rng.randi() % TOPS.size()],
		"accessory": ACCS[_rng.randi() % ACCS.size()],
	}
	var ch := Character.new()
	add_child(ch)
	ch.setup({"id": "", "look": look, "talk": {"mood": MOODS[_rng.randi() % MOODS.size()]}})
	ch.position = pos
	ch.scale = Vector3.ONE * _rng.randf_range(0.94, 1.04)
	return ch


func _process(dt: float) -> void:
	for g in _groups:
		g["t"] -= dt
		if g["t"] <= 0.0:
			var members: Array = g["members"]
			(members[g["speaker"]] as Node3D).call("set_talking", false)
			g["speaker"] = (int(g["speaker"]) + 1 + _rng.randi() % maxi(1, members.size() - 1)) % members.size()
			var sp: Node3D = members[g["speaker"]]
			sp.call("set_talking", true)
			sp.call("set_expression", MOODS[_rng.randi() % MOODS.size()])
			sp.call("play", GESTURES[_rng.randi() % GESTURES.size()])
			# quem escuta reage de vez em quando
			for m in members:
				if m != sp and _rng.randf() < 0.35:
					(m as Node3D).call("set_expression", ["feliz", "surpreso", "desconfiado"][_rng.randi() % 3])
					(m as Node3D).call("play", "idle")
			g["t"] = _rng.randf_range(1.4, 3.2)
	for w in _walkers:
		var ch: Node3D = w["ch"]
		if w["wait"] > 0.0:
			w["wait"] -= dt
			if w["wait"] <= 0.0:
				ch.call("play", "walking")
			continue
		var target: Vector3 = w["b"] if w["dir"] > 0 else w["a"]
		var to := target - ch.position
		to.y = 0
		var d := to.length()
		if d < 0.05:
			w["dir"] = -float(w["dir"])
			w["wait"] = _rng.randf_range(0.8, 2.5)
			ch.call("play", "idle")
			continue
		var step := minf(d, float(w["speed"]) * dt)
		ch.position += to / d * step
		ch.rotation.y = lerp_angle(ch.rotation.y, atan2(to.x, to.z), 0.2)
		# boneco provisório: sobe e desce no passo (o modelo riggado usa a animação de andar)
		if not ch.get("anim"):
			ch.position.y = (w["a"] as Vector3).y + absf(sin(Time.get_ticks_msec() / 160.0)) * 0.04
