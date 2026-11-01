"""Validador dos casos do RUMOR. Uso: python tools/validar_casos.py [arquivo.json ...]
Sem argumentos, valida todos os server/cases/*.json."""
import json, re, sys, glob, os

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
ICONS = set("celular mensagem onibus trofeu livro carta chocolate carregador baqueta fita computador pizza chave mochila coroa camera papel microfone bola prancheta caixa cartaz wifi relogio sacola".split())
HAIR = {"f": set("longo rabo coque trancas ondulado cacheado_longo".split()), "m": set("curto raspado franja cacheado".split())}
ACC = set("nenhum oculos bone fones brinco cachecol".split())
# limites por modo
RULES = {
 "solo":  {"locs": (2, 4), "people": (3, 5), "clues": (5, 14), "edges": (2, 4), "trades": 1, "dur": (600, 1200)},
 "multi": {"locs": (4, 5), "people": (6, 8), "clues": (14, 20), "edges": (5, 7), "trades": 2, "dur": (1500, 2100)},
}
W = lambda s: len(s.split())


def reach(trees, clues, items, start_flags):
    """Ponto fixo: a equipe conversa repetidas vezes, flags e pistas só crescem.
    Em cada rodada, cada pessoa abre na primeira entrada que casa com as flags atuais."""
    have = {c for c, v in clues.items() if v["release"] != "interrogatorio"} | set(items)
    flags = set(start_flags)
    def ok(cond, fl):
        return all(r in have for r in cond.get("requires", [])) and all(f in fl for f in cond.get("if", [])) \
            and not any(f in fl for f in cond.get("ifnot", []))
    changed = True
    while changed:
        changed = False
        for pid, t in trees.items():
            entry = next(e["node"] for e in t["entries"] if ok(e, flags))
            stack, seen = [(entry, frozenset(flags))], set()
            while stack:
                nid, fl = stack.pop()
                if (nid, fl) in seen: continue
                seen.add((nid, fl))
                nd = t["nodes"][nid]
                if nd.get("take_item") and nd["take_item"] not in have: continue
                fl = fl | set(nd.get("sets", []))
                for f in nd.get("sets", []):
                    if f not in flags: flags.add(f); changed = True
                for k in ("unlock", "give_item"):
                    if nd.get(k) and nd[k] not in have: have.add(nd[k]); changed = True
                for c in nd["choices"]:
                    if "next" in c and ok(c, fl): stack.append((c["next"], frozenset(fl)))
    return have


def check(p):
    raw = open(p, encoding="utf8").read(); d = json.loads(raw); err = []
    n = os.path.basename(p)[:-5]
    if d["id"] != n: err.append("id diferente do arquivo")
    if "—" in raw or "–" in raw: err.append("travessão")
    mode = d.get("mode")
    if mode not in RULES: err.append("mode"); mode = "multi"
    R = RULES[mode]
    if n.startswith("solo_") != (mode == "solo"): err.append("solo_* só para mode solo")
    if d["difficulty"] not in (1, 2, 3): err.append("difficulty")
    if not R["dur"][0] <= d["duration_sec"] <= R["dur"][1]: err.append("duration_sec")
    cards = {c["id"]: c for c in d["cards"]}; clues = {c["id"]: c for c in d["clues"]}
    items = {i["id"]: i for i in d.get("items", [])}
    if len(cards) + len(clues) + len(items) != len(set(cards) | set(clues) | set(items)): err.append("ids repetidos")
    people = [c for c in d["cards"] if c["kind"] == "pessoa"]
    if not R["people"][0] <= len(people) <= R["people"][1]: err.append("pessoas %d" % len(people))
    for c in d["cards"]:
        if c["kind"] == "pessoa":
            g = c.get("gender")
            if g not in HAIR: err.append("gender " + c["id"])
            elif c["look"]["hair"] not in HAIR[g]: err.append("cabelo x gênero " + c["id"])
            if c["look"]["accessory"] not in ACC: err.append("acessório " + c["id"])
            gr = c.get("talk", {}).get("greet", [])
            if not 1 <= len(gr) <= 2 or c["talk"].get("mood") not in EX: err.append("talk " + c["id"])
        if c["kind"] == "fato" and c.get("icon") not in ICONS: err.append("icon fato " + c["id"])
        if c["kind"] == "lugar" and c["id"] not in ANCH and c.get("scene") not in ANCH: err.append("lugar sem scene " + c["id"])
    for i in items.values():
        if i.get("icon") not in ICONS: err.append("icon item " + i["id"])
    locs = d["locations"]
    if not R["locs"][0] <= len(locs) <= R["locs"][1] or d["scene"] != locs[0] or any(l not in ANCH for l in locs): err.append("locations")
    if W(d["briefing"]) > 45: err.append("briefing longo %d" % W(d["briefing"]))
    h = d.get("hints", [])
    if not 4 <= len(h) <= 6 or any(W(x) > 25 for x in h): err.append("hints")
    if not R["clues"][0] <= len(clues) <= R["clues"][1]: err.append("pistas %d" % len(clues))
    splits = 0
    for c in d["clues"]:
        if W(c["text"]) > 35: err.append("pista longa " + c["id"])
        if len(c["title"].split()) > 4: err.append("título longo " + c["id"])
        if "who" in c and c["who"] not in cards: err.append("who " + c["id"])
        for l in c.get("chat", {}).get("lines", []):
            if W(l["text"]) > 35: err.append("chat longo")
            if l["who"].islower() and l["who"] not in cards: err.append("chat who " + l["who"])
        if "post" in c and c["post"].get("who") and c["post"]["who"] not in cards: err.append("post who " + c["id"])
        r = c["release"]
        if not (r in ("start", "hotspot", "interrogatorio") or re.fullmatch(r"t\+\d+", r)): err.append("release " + c["id"])
        if c["deal"] == "split":
            splits += 1
            if mode == "solo": err.append("split em solo " + c["id"])
            if r not in ("start",) and not r.startswith("t+"): err.append("split só em start/t+ " + c["id"])
        elif c["deal"] != "team": err.append("deal " + c["id"])
    if mode == "multi" and splits < 2: err.append("multi precisa de split")
    if not any(c["release"].startswith("t+") and 150 <= int(c["release"][2:]) <= 300 for c in d["clues"]): err.append("sem t+ 150..300")
    per = {}; hs_clues, hs_items = set(), set()
    for hsp in d["hotspots"]:
        if hsp["scene"] not in locs or hsp["object"] not in ANCH[hsp["scene"]]: err.append("âncora " + hsp["id"])
        if ("clue" in hsp) == ("item" in hsp): err.append("hotspot clue xor item " + hsp["id"])
        if "clue" in hsp:
            if hsp["clue"] not in clues or clues[hsp["clue"]]["release"] != "hotspot": err.append("hs clue " + hsp["id"])
            hs_clues.add(hsp["clue"])
        if "item" in hsp:
            if hsp["item"] not in items: err.append("hs item " + hsp["id"])
            hs_items.add(hsp["item"])
        per[hsp["scene"]] = per.get(hsp["scene"], 0) + 1
    if any(not 1 <= per.get(l, 0) <= 2 for l in locs): err.append("hotspots por cena %s" % per)
    for cid, c in clues.items():
        if c["release"] == "hotspot" and cid not in hs_clues: err.append("pista hotspot órfã " + cid)
    for i in items:
        if i not in hs_items: err.append("item sem hotspot " + i)
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
    bad_flags, unlockers, takers = set(), {}, {}
    for pid, t in trees.items():
        nodes, ent = t["nodes"], t["entries"]
        if not 3 <= len(nodes) <= 6: err.append("nós %s %d" % (pid, len(nodes)))
        if set(ent[-1]) != {"node"}: err.append("última entry com condição " + pid)
        for e in ent:
            if e["node"] not in nodes: err.append("entry node " + e["node"])
            for f in e.get("if", []) + e.get("ifnot", []):
                if f not in all_sets: err.append("flag nunca setada " + f)
        rch = {e["node"] for e in ent}; stack = list(rch)
        while stack:
            x = stack.pop()
            for c in nodes[x]["choices"]:
                if "next" in c and c["next"] not in rch: rch.add(c["next"]); stack.append(c["next"])
        if set(nodes) - rch: err.append("nó inalcançável %s %s" % (pid, set(nodes) - rch))
        for nid, nd in nodes.items():
            if not 1 <= len(nd["lines"]) <= 3: err.append("falas %s.%s" % (pid, nid))
            for l in nd["lines"]:
                if l["expr"] not in EX or l["anim"] not in AN: err.append("expr/anim %s.%s" % (pid, nid))
                if W(l["text"]) > 22: err.append("fala longa %s.%s (%d)" % (pid, nid, W(l["text"])))
                for f in re.findall(r"\{por:(\w+)\}", l["text"]):
                    if f not in nd.get("sets", []) and not any(f in e.get("if", []) and e["node"] == nid for e in ent):
                        err.append("{por:%s} sem garantia em %s.%s" % (f, pid, nid))
            if nd.get("unlock"):
                if nd["unlock"] not in clues: err.append("unlock " + nd["unlock"])
                unlockers.setdefault(nd["unlock"], []).append(pid)
            for k in ("give_item", "take_item"):
                if k in nd and nd[k] not in items: err.append(k + " " + nd[k])
            if nd.get("take_item"): takers.setdefault(nd["take_item"], set()).add(pid)
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
    if len(takers) < R["trades"]: err.append("trocas %d" % len(takers))
    for it, who in takers.items():
        if len(who) > 1: err.append("item %s usado por mais de uma pessoa" % it)
    for cid, c in clues.items():
        if c["release"] == "interrogatorio" and cid not in unlockers: err.append("interrogatório sem unlock " + cid)
        if c["release"] in ("start", "hotspot") and cid in unlockers: err.append("unlock de pista já disponível " + cid)
    normal = reach(trees, clues, items, set())
    worst = reach(trees, clues, items, bad_flags)
    if set(clues) - normal: err.append("pistas inalcançáveis %s" % (set(clues) - normal))
    sol = d["solution"]
    if sol.get("culprit") not in cards or cards[sol["culprit"]]["kind"] != "pessoa": err.append("culprit")
    if not sol.get("culprit_question"): err.append("culprit_question")
    if not R["edges"][0] <= len(sol["edges"]) <= R["edges"][1]: err.append("edges %d" % len(sol["edges"]))
    if not 1 <= len(sol["traps"]) <= 3: err.append("traps")
    if len(sol["categories"]) > 3: err.append("categorias")
    cats = {c["id"] for c in sol["categories"]}; lts = {l["id"] for l in d["link_types"]}
    if not 2 <= len(lts) <= 3: err.append("link_types")
    keys = set()
    for e in sol["edges"] + sol["traps"]:
        if e["from"] not in cards or e["to"] not in cards or e["type"] not in lts or e["category"] not in cats: err.append("edge ids " + str(e))
        k = (e["from"], e["to"], e["type"])
        if k in keys: err.append("edge/trap repetida " + str(k))
        keys.add(k)
        for x in e.get("evidence", []):
            if x not in clues: err.append("evidence " + x)
    for e in sol["edges"]:
        ev = e["evidence"]
        if not any(x in worst for x in ev): err.append("edge sem prova no pior caminho %s>%s" % (e["from"], e["to"]))
        if not any(clues[x]["release"] != "interrogatorio" for x in ev): err.append("edge só por interrogatório %s>%s" % (e["from"], e["to"]))
    ce = sol.get("culprit_evidence", [])
    if not ce or any(x not in clues for x in ce): err.append("culprit_evidence")
    elif not any(clues[x]["release"] != "interrogatorio" and x in worst for x in ce): err.append("culpado sem prova no pior caminho")
    print("%-18s %-5s dif %d %4ds | locs %d pessoas %d pistas %2d split %d itens %d edges %d | %s" % (
        n, mode, d["difficulty"], d["duration_sec"], len(locs), len(people), len(clues), splits, len(items), len(sol["edges"]), err or "OK"))
    return not err

if __name__ == "__main__":
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(os.path.dirname(__file__), "..", "server", "cases", "*.json")))
    res = [check(f) for f in files]
    sys.exit(0 if all(res) else 1)
