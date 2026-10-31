import json, re, sys
ANCH = {
 "corredor": "quadro_avisos mural celular armario_aberto lixeira",
 "biblioteca": "caderno_entrada pasta_gremio computador estante mesa_estudo",
 "teatro": "caixa_props quadro_teatro trono arara_figurino cortina",
 "sala_aula": "lousa mesa_professor carteira_fundo mochila janela",
 "cantina": "balcao cardapio bandeja geladeira mural_cantina",
 "patio": "banco_patio arvore bicicletario lixeira_patio poste",
 "sala_professores": "escaninho cafeteira mural_recados computador_prof armario_prof",
 "quadra": "arquibancada placar bolsa_esportiva vestiario_porta rede",
 "sala_diretor": "mesa_diretor gaveta quadro_fotos telefone cofre",
 "deposito": "caixa_achados prateleira vassoura caixa_fusiveis porta_fundos",
 "laboratorio": "bancada microscopio armario_vidros quadro_tabela pia",
 "sala_musica": "piano bateria estante_partituras armario_instrumentos quadro_horarios"}
ANCH = {k: set(v.split()) for k, v in ANCH.items()}
EX = set("neutro feliz surpreso bravo desconfiado triste nervoso".split())
AN = set("falando pensando nervoso negando apontando dando_de_ombros rindo".split())
W = lambda s: len(s.split())

def check(n):
    p = f"C:/Project/detetive/server/cases/{n}.json"
    raw = open(p, encoding="utf8").read(); d = json.loads(raw); err = []
    if "\u2014" in raw or "\u2013" in raw: err.append("travessão")
    cards = {c["id"]: c for c in d["cards"]}; clues = {c["id"]: c for c in d["clues"]}
    items = {i["id"]: i for i in d.get("items", [])}
    if set(cards) & set(clues) or set(items) & (set(cards) | set(clues)): err.append("ids duplicados entre cartas/pistas/itens")
    locs = d["locations"]
    need = {1: (3, 3), 2: (3, 4), 3: (4, 4)}[d["difficulty"]]
    if not need[0] <= len(locs) <= need[1] or d["scene"] != locs[0] or any(l not in ANCH for l in locs): err.append("locations")
    if W(d["briefing"]) > 45: err.append("briefing longo")
    for c in d["clues"]:
        if W(c["text"]) > 35: err.append("pista longa " + c["id"])
        if "who" in c and c["who"] not in cards: err.append("who " + c["id"])
        for l in c.get("chat", {}).get("lines", []):
            if W(l["text"]) > 35: err.append("chat longo")
            if l["who"].islower() and l["who"] not in cards: err.append("chat who " + l["who"])
        r = c["release"]
        if not (r in ("start", "hotspot", "interrogatorio") or re.fullmatch(r"t\+\d+", r)): err.append("release " + c["id"])
    if not any(c["release"].startswith("t+") and 150 <= int(c["release"][2:]) <= 300 for c in d["clues"]): err.append("sem t+ 150..300")
    # hotspots
    per = {}
    hs_clues, hs_items = set(), set()
    for h in d["hotspots"]:
        if h["scene"] not in locs or h["object"] not in ANCH[h["scene"]]: err.append("âncora " + h["id"])
        if ("clue" in h) == ("item" in h): err.append("hotspot clue xor item " + h["id"])
        if "clue" in h:
            if h["clue"] not in clues or clues[h["clue"]]["release"] != "hotspot": err.append("hs clue " + h["id"])
            hs_clues.add(h["clue"])
        if "item" in h:
            if h["item"] not in items: err.append("hs item " + h["id"])
            hs_items.add(h["item"])
        per[h["scene"]] = per.get(h["scene"], 0) + 1
    if any(not 1 <= per.get(l, 0) <= 2 for l in locs): err.append("hotspots por cena %s" % per)
    for cid, c in clues.items():
        if c["release"] == "hotspot" and cid not in hs_clues: err.append("pista hotspot órfã " + cid)
    for i in items:
        if i not in hs_items: err.append("item sem hotspot " + i)
    # people
    sp = {}
    for s in d["scene_people"]:
        if s["id"] not in cards or s["scene"] not in locs: err.append("scene_people " + str(s))
        sp[s["scene"]] = sp.get(s["scene"], 0) + 1
        if "tree" not in cards[s["id"]].get("talk", {}): err.append("sem tree " + s["id"])
    if any(not 1 <= sp.get(l, 0) <= 3 for l in locs): err.append("pessoas por cena %s" % sp)
    trees = {s["id"]: cards[s["id"]]["talk"]["tree"] for s in d["scene_people"]}
    all_sets = set()
    for t in trees.values():
        for nd in t["nodes"].values(): all_sets |= set(nd.get("sets", []))
    bad_flags = set(); unlockers = {}; takers = 0
    for pid, t in trees.items():
        nodes = t["nodes"]
        if not 3 <= len(nodes) <= 6: err.append("nós %s %d" % (pid, len(nodes)))
        ent = t["entries"]
        if ent[-1].keys() != {"node"}: err.append("última entry com condição " + pid)
        for e in ent:
            if e["node"] not in nodes: err.append("entry node " + e["node"])
            for f in e.get("if", []) + e.get("ifnot", []):
                if f not in all_sets: err.append("flag nunca setada " + f)
        reach = {e["node"] for e in ent}
        stack = list(reach)
        while stack:
            x = stack.pop()
            for c in nodes[x]["choices"]:
                if "next" in c and c["next"] not in reach: reach.add(c["next"]); stack.append(c["next"])
        if set(nodes) - reach: err.append("nó inalcançável %s %s" % (pid, set(nodes) - reach))
        for nid, nd in nodes.items():
            if not 1 <= len(nd["lines"]) <= 3: err.append("falas %s.%s" % (pid, nid))
            for l in nd["lines"]:
                if l["expr"] not in EX or l["anim"] not in AN: err.append("expr/anim %s.%s" % (pid, nid))
                if W(l["text"]) > 22: err.append("fala longa %s.%s: %s" % (pid, nid, l["text"]))
                for f in re.findall(r"\{por:(\w+)\}", l["text"]):
                    if f not in nd.get("sets", []) and not any(f in e.get("if", []) and e["node"] == nid for e in ent):
                        err.append("{por:%s} sem garantia em %s.%s" % (f, pid, nid))
            if "unlock" in nd:
                if nd["unlock"] not in clues: err.append("unlock " + nd["unlock"])
                unlockers.setdefault(nd["unlock"], []).append(pid)
            for k in ("give_item", "take_item"):
                if k in nd and nd[k] not in items: err.append(k + " " + nd[k])
            if "take_item" in nd: takers += 1
            if nd.get("end"):
                if nd["choices"] or not nd.get("lock"): err.append("nó final %s.%s" % (pid, nid))
                continue
            ch = nd["choices"]
            if not 1 <= len(ch) <= 4: err.append("escolhas %s.%s" % (pid, nid))
            if not any(not c.get("requires") and not c.get("if") and c["kind"] != "ruim" for c in ch):
                err.append("sem saída livre %s.%s" % (pid, nid))
            for c in ch:
                if W(c["text"]) > 9: err.append("escolha longa: " + c["text"])
                if c["kind"] not in ("boa", "neutra", "ruim"): err.append("kind")
                if ("next" in c) == bool(c.get("end")): err.append("next/end %s.%s" % (pid, nid))
                if "next" in c and c["next"] not in nodes: err.append("next " + c["next"])
                for r in c.get("requires", []):
                    if r not in clues and r not in items: err.append("requires " + r)
                for f in c.get("if", []) + c.get("ifnot", []):
                    if f not in all_sets: err.append("flag " + f)
                if c["kind"] == "ruim":
                    tg = nodes[c["next"]]
                    if not (tg.get("end") and tg.get("lock") and tg.get("sets")): err.append("ruim sem lock/flag %s" % pid)
                    elif tg["lines"][0]["expr"] not in ("bravo", "nervoso"): err.append("lock expr")
                    else: bad_flags |= set(tg["sets"])
    if takers < 1: err.append("sem tarefa de troca")
    for cid, c in clues.items():
        if (c["release"] == "interrogatorio") != (cid in unlockers): err.append("interrogatorio x unlock " + cid)

    # ---------- busca de estados ----------
    base = frozenset(cid for cid, c in clues.items() if c["release"] != "interrogatorio")
    def ok(cond_c, flags, have):
        return all(r in have for r in cond_c.get("requires", [])) and all(f in flags for f in cond_c.get("if", [])) \
               and not any(f in flags for f in cond_c.get("ifnot", []))
    def search(start_flags):
        start = (frozenset(start_flags), base | frozenset(items))  # itens de hotspot pegos no começo
        seen = {start}; q = [start]; all_clues = set(base); nodes_seen = set()
        while q:
            flags, have = q.pop()
            for pid, t in trees.items():
                nid = next(e["node"] for e in t["entries"] if ok(e, flags, have))
                stack = [(nid, flags, have)]; local = set()
                while stack:
                    nid, fl, hv = stack.pop()
                    nd = t["nodes"][nid]
                    if "take_item" in nd and nd["take_item"] not in hv: continue
                    fl = fl | frozenset(nd.get("sets", []))
                    hv = set(hv)
                    if "unlock" in nd: hv.add(nd["unlock"])
                    if "give_item" in nd: hv.add(nd["give_item"])
                    if "take_item" in nd: hv.discard(nd["take_item"])
                    hv = frozenset(hv)
                    key = (pid, nid, fl, hv)
                    if key in local: continue
                    local.add(key); nodes_seen.add((pid, nid))
                    st = (fl, hv)
                    all_clues |= {x for x in hv if x in clues}
                    if st not in seen: seen.add(st); q.append(st)
                    for c in nd["choices"]:
                        if "next" in c and ok(c, fl, hv): stack.append((c["next"], fl, hv))
            if len(seen) > 200000: err.append("explosão de estados"); break
        return all_clues, nodes_seen
    normal, nseen = search(set())
    worst, _ = search(bad_flags)
    if set(clues) - normal: err.append("pistas inalcançáveis %s" % (set(clues) - normal))
    for pid, t in trees.items():
        for nid in t["nodes"]:
            if (pid, nid) not in nseen: err.append("nó nunca visitado na busca %s.%s" % (pid, nid))
    sol = d["solution"]
    if sol.get("culprit") not in cards or cards[sol["culprit"]]["kind"] != "pessoa": err.append("culprit")
    if not sol.get("culprit_question"): err.append("culprit_question")
    if not 3 <= len(sol["edges"]) <= 4: err.append("edges")
    if not 1 <= len(sol["traps"]) <= 2: err.append("traps")
    if len(sol["categories"]) > 3: err.append("categorias")
    cats = {c["id"] for c in sol["categories"]}; lts = {l["id"] for l in d["link_types"]}
    for e in sol["edges"] + sol["traps"]:
        if e["from"] not in cards or e["to"] not in cards or e["type"] not in lts or e["category"] not in cats: err.append("edge ids " + str(e))
        for x in e.get("evidence", []):
            if x not in clues: err.append("evidence " + x)
    for e in sol["edges"]:
        ev = e["evidence"]
        if not any(x in worst for x in ev): err.append("edge sem prova no pior caminho %s>%s" % (e["from"], e["to"]))
        if not any(clues[x]["release"] != "interrogatorio" for x in ev): err.append("edge só depende de interrogatório %s>%s" % (e["from"], e["to"]))
    ce = sol.get("culprit_evidence", [])
    if not ce or any(x not in clues for x in ce): err.append("culprit_evidence")
    if not any(clues[x]["release"] != "interrogatorio" for x in ce): err.append("culpado só por interrogatório")
    if not any(x in worst for x in ce): err.append("culpado sem prova no pior caminho")
    print(n, "| dif", d["difficulty"], "| locs", len(locs), "| pistas", len(clues), "| itens", len(items), "| hotspots", len(d["hotspots"]),
          "| pessoas", len(trees), "| flags ruins", sorted(bad_flags), "|", err or "OK")
    return not err

res = [check(n) for n in ["rumor_1017", "ninguem", "objeto_trocado"]]
sys.exit(0 if all(res) else 1)
