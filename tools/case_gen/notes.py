"""Avisos de confissão e de testemunhas mentirosas no guia do professor e nas dicas."""
from confess import CULPRIT, LIES

def _liars(case):
    cards = {c["id"]: c for c in case["cards"]}
    titles = {c["id"]: c["title"] for c in case["clues"]}
    out = []
    for pid, _, text, req, _, _ in LIES.get(case["id"], []):
        if text == "CONTA":
            tree = cards[pid]["talk"]["tree"]
            req = next(c.get("requires", []) for o in tree["nodes"].values() for c in o["choices"] if c.get("next") == "conta" and c.get("requires"))
        out.append((cards[pid]["name"], " + ".join("'%s'" % titles[r] for r in req)))
    return out

def apply(case, g):
    cards = {c["id"]: c for c in case["cards"]}
    sol = case["solution"]; cul = cards[sol["culprit"]]["name"]
    spec = CULPRIT[case["id"]]
    liars = _liars(case)
    lie_txt = "; ".join("%s (desmonte mostrando %s)" % l for l in liars)
    if spec["type"] == "full" and case["id"] in ("solo_vestiario", "solo_invasao"):
        conf = "%s mente no começo e só confessa depois de duas provas seguidas: a primeira faz recuar e jogar a culpa em outro, a segunda quebra." % cul
    elif spec["type"] == "full":
        conf = "%s confessa quando vê a pista achada na cena (a pista que chega com o tempo, sozinha, não basta)." % cul
    else:
        conf = "Atenção: %s NÃO confessa tudo. O máximo que se arranca é isto: %s O resto a equipe precisa provar no quadro." % (cul, spec["text"])
    g["summary"] = g["summary"] + " " + conf + ((" Quem mente: " + lie_txt + ".") if liars else "")
    if spec["type"] == "partial":
        g["steps"][-1] = g["steps"][-1].rstrip(".") + ". Não esperem confissão completa: o quadro é a prova."
    pc = g.get("twist") is not None
    pacing = g["pacing"] if "pacing" in g else None
    entry = ("Final", "O culpado admite só uma parte, ou nada." if spec["type"] == "partial" else "O culpado cede depois das provas certas.",
             "O que, no quadro, prova o que ele ainda nega?" if spec["type"] == "partial" else "Que prova vocês ainda não mostraram para ele?")
    g["_pacing_extra"] = entry
    faq = g["faq"]
    q = ("O culpado não confessa!" if spec["type"] == "partial" else "Mostramos a prova e ele mentiu de novo.")
    a = ("É assim mesmo: o culpado nunca confessa tudo. Não precisa: com os fios provados no quadro e o culpado apontado, a teoria está certa."
         if spec["type"] == "partial" else "Às vezes uma prova só faz a pessoa recuar. Procurem uma segunda prova diferente e mostrem depois.")
    if liars: a += " Atenção a quem mente: " + ", ".join(n for n, _ in liars) + "."
    if len(faq) >= 6: faq.insert(len(faq) - 1, (q, a)); del faq[-3]
    else: faq.insert(len(faq) - 1, (q, a))
    h = case["hints"]
    tip = "Ninguém vai confessar tudo: o quadro é a sua prova." if spec["type"] == "partial" else "Uma prova só pode não bastar. Junte duas."
    if spec["type"] != "full" or case["id"] in ("solo_vestiario", "solo_invasao"):
        if len(h) < 6: h.append(tip)
        else: h[-1] = tip
    if liars and len(h) < 6:
        h.insert(len(h) - 1, "Alguém está mentindo para proteger alguém, ou a si mesmo. Confronte com uma pista.")
