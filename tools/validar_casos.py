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
ACC = set("nenhum oculos bone fones brinco cachecol oculos_leitura cracha".split())
HAIR_ADULT = {"f": set("coque_baixo chanel coque longo".split()), "m": set("calvo grisalho_curto curto raspado".split())}
FACIAL = set("nenhum bigode barba cavanhaque".split())
# limites por modo
RULES = {
 "solo":  {"locs": (2, 5), "people": (3, 6), "clues": (5, 20), "edges": (2, 5), "trades": 1, "dur": (600, 1500)},
 "multi": {"locs": (5, 7), "people": (8, 10), "clues": (18, 28), "edges": (5, 7), "trades": 2, "dur": (1500, 2400)},
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
            elif c["look"]["hair"] not in (HAIR_ADULT if c.get("adult") else HAIR)[g]: err.append("cabelo x gênero/idade " + c["id"])
            if c.get("adult"):
                if c["look"].get("outfit") not in ("formal", "uniforme"): err.append("outfit adulto " + c["id"])
                if g == "m" and c["look"].get("facial_hair") not in FACIAL: err.append("facial_hair " + c["id"])
                if g == "f" and "facial_hair" in c["look"]: err.append("facial_hair em mulher " + c["id"])
            elif "outfit" in c["look"] or "facial_hair" in c["look"] or "adult" in c: err.append("campo adulto em adolescente " + c["id"])
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
            if l["who"].islower() and not l["who"].startswith("@") and l["who"] not in cards: err.append("chat who " + l["who"])
        if "post" in c and c["post"].get("who") and c["post"]["who"] not in cards: err.append("post who " + c["id"])
        r = c["release"]
        if not (r in ("start", "hotspot", "interrogatorio") or re.fullmatch(r"t\+\d+", r)): err.append("release " + c["id"])
        if c["deal"] == "split":
            splits += 1
            if mode == "solo": err.append("split em solo " + c["id"])
            if r not in ("start",) and not r.startswith("t+"): err.append("split só em start/t+ " + c["id"])
        elif c["deal"] != "team": err.append("deal " + c["id"])
    VMODELS = set("celular mensagem onibus trofeu livro carta chocolate carregador baqueta fita computador pizza chave mochila coroa camera papel microfone bola prancheta caixa cartaz wifi relogio sacola cofre urna microscopio spray cadeado revista recorte dinheiro tenis pegada pendrive envelope cracha camera_seg impressora prova luva bolsa ingresso muro vidro alarme molde lousa bloco balas caixinha_som balde disjuntor achados postit redacao comanda".split())
    VART = {"ransom": ("text",), "cctv": ("stamp", "caption"), "pix": ("valor", "de", "para", "hora")}
    for c in d["clues"]:
        vis = c.get("visual")
        if not isinstance(vis, dict): err.append("pista sem visual " + c["id"]); continue
        if "model" in vis:
            if vis["model"] not in VMODELS or "art" in vis: err.append("visual model inválido %s: %s" % (c["id"], vis.get("model")))
        elif vis.get("art") in VART:
            if any(not vis.get(k) for k in VART[vis["art"]]): err.append("visual art sem campos " + c["id"])
        else: err.append("visual inválido " + c["id"])
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
    sp, seen_default = {}, {}
    for e in d["scene_people"]:
        if e["id"] not in cards or e["scene"] not in locs: err.append("scene_people " + str(e))
        if e["id"] in seen_default: err.append("entrada depois da padrão " + e["id"])
        if not e.get("if") and not e.get("ifnot"):
            seen_default[e["id"]] = e["scene"]; sp[e["scene"]] = sp.get(e["scene"], 0) + 1
        if "tree" not in cards[e["id"]].get("talk", {}): err.append("sem tree " + e["id"])
    for pid in {e["id"] for e in d["scene_people"]}:
        if pid not in seen_default: err.append("sem entrada padrão " + pid)
    if any(not 1 <= sp.get(l, 0) <= 3 for l in locs): err.append("pessoas por cena %s" % sp)
    occ = {}
    for e in d["scene_people"]: occ.setdefault(e["scene"], set()).add(e["id"])
    for sc, ps in occ.items():
        if len(ps) > 3: err.append("até %d pessoas podem estar em %s" % (len(ps), sc))
    moves = sum(1 for e in d["scene_people"] if e.get("if") or e.get("ifnot"))
    def scene_of(pid, F):
        for e in d["scene_people"]:
            if e["id"] == pid and set(e.get("if", [])) <= F and not (set(e.get("ifnot", [])) & F): return e["scene"]
    trees = {e["id"]: cards[e["id"]]["talk"]["tree"] for e in d["scene_people"]}
    all_sets = set()
    for t in trees.values():
        for nd in t["nodes"].values(): all_sets |= set(nd.get("sets", []))
    bad_flags, unlockers, takers = set(), {}, {}
    duo_count = [0]
    for pid, t in trees.items():
        nodes, ent = t["nodes"], t["entries"]
        if not 3 <= len(nodes) <= 10: err.append("nós %s %d" % (pid, len(nodes)))
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
            if not 1 <= len(nd["lines"]) <= 4: err.append("falas %s.%s" % (pid, nid))
            cast = nd.get("cast", [])
            for x in cast:
                if x not in cards or cards[x]["kind"] != "pessoa" or x not in trees: err.append("cast inválido %s.%s" % (pid, nid))
            if cast: duo_count[0] += 1 if any(e["node"] == nid for e in ent) else 0
            for l in nd["lines"]:
                if l.get("who", pid) not in [pid] + cast: err.append("who fora do cast %s.%s" % (pid, nid))
                if "react" in l and l["react"] not in EX: err.append("react %s.%s" % (pid, nid))
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
    for e in d["scene_people"]:
        for f in e.get("if", []) + e.get("ifnot", []):
            if f not in all_sets: err.append("flag de movimento nunca setada " + f)
    for pid, t in trees.items():
        for e in t["entries"]:
            nd = t["nodes"][e["node"]]
            if nd.get("cast"):
                F = set(e.get("if", []))
                where_ = {x: scene_of(x, F) for x in [pid] + nd["cast"]}
                if len(set(where_.values())) != 1: err.append("conversa a dois sem as duas na mesma sala %s: %s" % (pid, where_))
        for nid, nd in t["nodes"].items():
            if nd.get("cast") and not any(e["node"] == nid for e in t["entries"]):
                preds = [o for o in t["nodes"].values() if any(c.get("next") == nid for c in o["choices"])]
                if not preds or any(not set(nd["cast"]) <= set(o.get("cast", [])) for o in preds): err.append("nó com cast sem antecessor com cast %s.%s" % (pid, nid))
    if mode == "multi" and not (2 <= moves <= 3 and 1 <= duo_count[0] <= 2): err.append("multi: movimentos %d, conversas a dois %d" % (moves, duo_count[0]))
    if mode == "solo" and not 1 <= moves <= 2: err.append("solo: movimentos %d" % moves)
    if mode == "solo" and d["difficulty"] >= 2 and duo_count[0] != 1: err.append("solo médio/difícil: conversas a dois %d" % duo_count[0])
    # confissões e mentiras
    culprit = d["solution"]["culprit"]
    liars = set()
    for pid, t in trees.items():
        nodes = t["nodes"]
        flag_src = {}
        for nid, nd in nodes.items():
            for f in nd.get("sets", []): flag_src.setdefault(f, []).append(nid)
        def incoming(nid): return [c for o in nodes.values() for c in o["choices"] if c.get("next") == nid]
        for nid, nd in nodes.items():
            cf = nd.get("confession")
            if cf is not None and cf not in ("full", "partial", "slip"): err.append("confession inválida %s.%s" % (pid, nid))
            if nd.get("contradiction"):
                if pid == culprit: err.append("contradiction no culpado %s.%s" % (pid, nid))
                elif all(c.get("requires") for c in incoming(nid)) and incoming(nid): liars.add(pid)
                else: err.append("mudança de versão sem pista %s.%s" % (pid, nid))
            if cf != "full": continue
            if mode == "multi" or d["difficulty"] >= 3: err.append("confissão completa proibida aqui %s.%s" % (pid, nid)); continue
            for e in t["entries"]:
                if e["node"] == nid and not set(e.get("if", [])) <= set(nd.get("sets", [])): err.append("entrada direta para confissão %s.%s" % (pid, nid))
            for c in incoming(nid):
                req = [r for r in c.get("requires", []) if r in clues]
                chain = set(req)
                for f in c.get("if", []):
                    for src in flag_src.get(f, []):
                        for x in incoming(src): chain |= {r for r in x.get("requires", []) if r in clues}
                if not req or all(clues[r]["release"].startswith("t+") for r in chain): err.append("confissão sem pista achada pelo jogador %s.%s" % (pid, nid))
                if d["difficulty"] == 2:
                    ok2 = False
                    for f in c.get("if", []):
                        for src in flag_src.get(f, []):
                            prev = [set(x.get("requires", [])) for x in incoming(src)]
                            if prev and all(p and not (p & set(req)) for p in prev): ok2 = True
                    if not ok2: err.append("nível 2: confissão sem duas provas encadeadas %s.%s" % (pid, nid))
    need_l = 2 if mode == "multi" else (1 if d["difficulty"] >= 2 else 0)
    if len(liars) < need_l: err.append("testemunhas que mentem: %d (mínimo %d)" % (len(liars), need_l))
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
    need = {"solo": {1: 2, 2: 3, 3: 4}, "multi": {1: 3, 2: 4, 3: 5}}[mode][d["difficulty"]]
    if len(sol["categories"]) != need: err.append("objetivos secundários %d (regra: %d)" % (len(sol["categories"]), need))
    for c in sol["categories"]:
        fios = [e for e in sol["edges"] if e["category"] == c["id"]]
        if not fios or not any(e.get("evidence") for e in fios): err.append("objetivo sem fio com prova " + c["id"])
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
    GENT = {"g_estava_com", "g_viu", "g_mentiu", "g_mentiu_sobre", "g_acobertou", "g_alibi", "g_brigou", "g_amigo", "g_sabia", "g_motivo", "g_nao_fez", "g_esteve", "g_aconteceu"}
    for e in sol["edges"]:
        for at in e.get("alt_types", []):
            if at not in lts and at not in GENT: err.append("alt_types desconhecido %s em %s>%s" % (at, e["from"], e["to"]))
        if "any_direction" in e and not isinstance(e["any_direction"], bool): err.append("any_direction não é booleano")
        if len(set(e["evidence"])) != len(e["evidence"]): err.append("prova repetida no fio %s>%s" % (e["from"], e["to"]))
    for e in sol["edges"]:
        ev = e["evidence"]
        if not any(x in worst for x in ev): err.append("edge sem prova no pior caminho %s>%s" % (e["from"], e["to"]))
        if not any(clues[x]["release"] != "interrogatorio" for x in ev): err.append("edge só por interrogatório %s>%s" % (e["from"], e["to"]))
    # panorama: ligações não obrigatórias
    GEN = {"g_estava_com": "pp", "g_mentiu": "pp", "g_acobertou": "pp", "g_alibi": "pp", "g_brigou": "pp", "g_amigo": "pp",
           "g_viu": "pp|pf", "g_mentiu_sobre": "pf", "g_sabia": "pf", "g_motivo": "pf", "g_nao_fez": "pf", "g_esteve": "pl", "g_aconteceu": "fl"}
    K = {"pessoa": "p", "fato": "f", "lugar": "l"}
    pano = sol.get("panorama", [])
    lo, hi = (6, 12) if mode == "multi" else (4, 8)
    if not lo <= len(pano) <= hi: err.append("panorama %d (regra %d a %d)" % (len(pano), lo, hi))
    req_keys = {(e["from"], e["to"], e["type"]) for e in sol["edges"]}
    for l in pano:
        if l["from"] not in cards or l["to"] not in cards: err.append("panorama ids " + str(l)); continue
        if l["type"] in GEN:
            pair = K[cards[l["from"]]["kind"]] + K[cards[l["to"]]["kind"]]
            if pair not in GEN[l["type"]].split("|"): err.append("panorama tipo x cartas %s %s>%s" % (l["type"], l["from"], l["to"]))
        elif l["type"] not in lts: err.append("panorama tipo desconhecido " + l["type"])
        if (l["from"], l["to"], l["type"]) in req_keys: err.append("panorama repete fio obrigatório " + str(l))
        for x in l.get("evidence", []):
            if x not in clues: err.append("panorama evidence " + x)
    ce = sol.get("culprit_evidence", [])
    if not ce or any(x not in clues for x in ce): err.append("culprit_evidence")
    elif not any(clues[x]["release"] != "interrogatorio" and x in worst for x in ce): err.append("culpado sem prova no pior caminho")
    tg = d.get("teacher_guide")
    if not tg: err.append("sem teacher_guide")
    else:
        for k in ("summary", "twist"):
            if not tg.get(k): err.append("teacher_guide." + k)
        if not 5 <= len(tg.get("solution_steps", [])) <= 8: err.append("solution_steps")
        if not 3 <= len(tg.get("pacing", [])) <= 6 or any(not all(x.get(k) for k in ("when", "aha", "if_stuck")) for x in tg.get("pacing", [])): err.append("pacing")
        cm = tg.get("clue_map", [])
        if {x["clue"] for x in cm} != set(clues) or any(not x.get("where") or not x.get("proves") for x in cm): err.append("clue_map incompleto")
        if not tg.get("red_herrings"): err.append("red_herrings")
        if not 4 <= len(tg.get("faq", [])) <= 8: err.append("faq")
        if not 5 <= len(tg.get("panorama_story", [])) <= 10: err.append("panorama_story")
        if len(tg.get("talking_points", [])) != 3: err.append("talking_points")
        if "—" in json.dumps(tg, ensure_ascii=False): err.append("travessão no guia")
    print("%-18s %-5s dif %d %4ds | locs %d pessoas %d pistas %2d split %d itens %d edges %d | %s" % (
        n, mode, d["difficulty"], d["duration_sec"], len(locs), len(people), len(clues), splits, len(items), len(sol["edges"]), err or "OK"))
    return not err

if __name__ == "__main__":
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(os.path.dirname(__file__), "..", "server", "cases", "*.json")))
    res = [check(f) for f in files]
    sys.exit(0 if all(res) else 1)
