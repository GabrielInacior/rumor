"""Movimentos (scene_people condicional) e conversas a dois (cast/who/react)."""

def W(who, text, expr, anim, react):
    return {"who": who, "text": text, "expr": expr, "anim": anim, "react": react}
def CH(text, kind, next=None, requires=None):
    c = {"text": text, "kind": kind}
    if next: c["next"] = next
    else: c["end"] = True
    if requires: c["requires"] = requires
    return c
BYE = lambda t="Deixa os dois conversarem.": CH(t, "neutra")

def duo(owner, cast, if_, ifnot, done, lines, choices, outs=None):
    return {"owner": owner, "cast": cast, "if": if_, "ifnot": ifnot, "done": done, "lines": lines, "choices": choices, "outs": outs or {}}
def out(lines, sets=None, unlock=None, choices=None):
    n = {"lines": lines, "choices": choices or [BYE("Valeu, os dois.")]}
    if sets: n["sets"] = sets
    if unlock: n["unlock"] = unlock
    return n

SPEC = {
 # ---------------------------------------------------------------- solos
 "solo_bilhete": {"moves": [("lu", "corredor", ["duda_falou"])]},
 "solo_muro": {"moves": [("thiago", "deposito", ["jorge_falou"])]},
 "solo_vestiario": {"moves": [("gui", "cantina", ["pedro_falou"])],
  "duos": [duo("pedro", ["gui"], ["pedro_falou"], ["duo_vest"], "duo_vest",
    [W("gui", "Vai acreditar num cara que mata aula de física pra comer coxinha?", "bravo", "apontando", "bravo"),
     W("pedro", "Eu vi a lanterna, Gui. No armário 12. O do Gabriel.", "bravo", "apontando", "nervoso"),
     W("gui", "Era... o meu armário. Eu confundi.", "nervoso", "negando", "desconfiado")],
    [CH("O seu armário é no corredor, Gui", "boa", "duo_fim"), BYE()],
    {"duo_fim": out([W("gui", "...Tá. Tá bom. Eu devo dinheiro, mano. Muito.", "triste", "pensando", "surpreso"),
                     W("pedro", "Devolve o celular dele, Gui. Ele é teu amigo.", "triste", "falando", "triste")],
                    sets=["gui_encurralado"], choices=[CH("Mostrar o papel com o segredo 0408", "boa", "duo_conf", ["c_papel"]), BYE()]),
     "duo_conf": out([W("gui", "Fui eu. Peguei e anunciei. Desculpa, Pedro. Desculpa pro Gabriel também.", "triste", "negando", "triste")], unlock="c_confissao")})]},
 "solo_invasao": {"moves": [("ana", "patio", ["ana_bravo"])],
  "duos": [duo("lari", ["ana"], ["jorge_falou"], ["duo_inv", "ana_bravo"], "duo_inv",
    [W("lari", "Profa., sexta às 16h30 eu fui limpar o armário. O microscópio já não tava lá.", "desconfiado", "apontando", "nervoso"),
     W("ana", "Você se confundiu, querida. Devia ser outro armário.", "nervoso", "negando", "desconfiado"),
     W("lari", "Só existe UM armário de microscópio nesse laboratório.", "bravo", "apontando", "nervoso")],
    [CH("A Lari tem razão, professora", "boa", "duo_fim"), BYE()],
    {"duo_fim": out([W("ana", "Eu... levei pra manutenção. Sexta. É isso. Manutenção.", "nervoso", "nervoso", "desconfiado"),
                     W("lari", "Manutenção não quebra janela domingo de madrugada.", "desconfiado", "dando_de_ombros", "nervoso")],
                    sets=["ana_contradita"], choices=[CH("Mostrar o alarme e os códigos", "boa", "duo_conf", ["c_alarme", "c_codigos"]), BYE()]),
     "duo_conf": out([W("ana", "...Quebrou no meu cursinho. Eu entrei em pânico. Desculpa, Lari.", "triste", "negando", "triste")], unlock="c_confissao")})]},
 "solo_taca": {"moves": [("sofia", "sala_professores", ["nogueira_papo"]), ("jorge", "sala_diretor", ["jorge_falou"])],
  "duos": [duo("marta", ["sofia"], ["nogueira_papo"], ["duo_taca", "marta_falou"], "duo_taca",
    [W("sofia", "A peça dos 60 anos não tem taça, professora. A senhora mentiu pra mim.", "bravo", "apontando", "nervoso"),
     W("marta", "Sofia, querida... pensa na sua bolsa do teatro.", "nervoso", "pensando", "bravo"),
     W("sofia", "Minha bolsa não vale uma taça de quinze mil.", "bravo", "negando", "triste")],
    [CH("Sofia, conta tudo agora", "boa", "duo_fim"), BYE()],
    {"duo_fim": out([W("sofia", "Ela encomendou a réplica e me prometeu a bolsa se eu ficasse quieta.", "triste", "apontando", "nervoso"),
                     W("marta", "Sofia! Você não sabe o que está dizendo.", "bravo", "negando", "bravo")],
                    sets=["marta_encurralada", "sofia_falou"], unlock="c_dep_sofia",
                    choices=[CH("Mostrar o caderno da chave", "boa", "duo_conf", ["c_chave_log"]), BYE()]),
     "duo_conf": out([W("marta", "...Eu caí num golpe. Doze mil. Vendi no sábado. Pronto.", "triste", "pensando", "surpreso")], unlock="c_confissao")})]},
 "solo_armacao": {"moves": [("bento", "sala_professores", ["mel_falou"])],
  "duos": [duo("vera", ["bento"], ["mel_falou"], ["duo_arm"], "duo_arm",
    [W("bento", "Coordenadora, vim só reforçar: o Davi sempre foi falso. Todo mundo sabe.", "desconfiado", "apontando", "desconfiado"),
     W("vera", "Curioso, Bento. A Mel disse que vendeu uma cópia da prova. Pra você.", "desconfiado", "pensando", "nervoso"),
     W("bento", "A Mel mente! Ela sempre me odiou.", "nervoso", "negando", "desconfiado")],
    [CH("Você ficou sozinho na sala no almoço", "boa", "duo_fim", ["c_lousa"]), BYE()],
    {"duo_fim": out([W("vera", "A lousa diz: 'só o Bento, 12h15 às 12h45'. Explique.", "bravo", "apontando", "nervoso"),
                     W("bento", "Eu... estudava. Sozinho. Isso não prova nada.", "nervoso", "nervoso", "desconfiado")],
                    sets=["bento_encurralado"], choices=[CH("Mostrar o registro da rede", "boa", "duo_conf", ["c_rede"]), BYE()]),
     "duo_conf": out([W("bento", "...Fui eu. A bolsa era minha única chance. O Davi não merecia isso.", "triste", "negando", "triste")], unlock="c_confissao")})]},
 # ---------------------------------------------------------------- multis
 "cofre_formatura": {"moves": [("rafa", "sala_professores", ["rafa_bravo"]), ("lari", "sala_diretor", ["joana_papo"]), ("bia", "biblioteca", ["bia_falou"])],
  "duos": [
   duo("lari", ["bia"], ["bia_falou"], ["joana_papo", "duo_amigas", "lari_falou"], "duo_amigas",
    [W("bia", "Amiga, eu contei dos oitocentos. Não dava mais pra segurar.", "triste", "negando", "bravo"),
     W("lari", "Você me VENDEU? Por um chocolate?", "bravo", "apontando", "triste"),
     W("bia", "Eu te vendi por consciência, Lari.", "triste", "falando", "surpreso")],
    [CH("Lari, a Bia está tentando te ajudar", "boa", "duo_fim"), CH("Bia, você também escondeu tudo", "neutra", "duo_culpa")],
    {"duo_fim": out([W("lari", "...Tá. Eu peguei. O bilhete foi raiva. Ele terminou comigo por MENSAGEM.", "triste", "pensando", "triste")],
                    sets=["lari_encurralada"], choices=[CH("Mostrar o relatório do cofre", "boa", "duo_conf", ["c_log_cofre"]), BYE()]),
     "duo_culpa": out([W("bia", "Escondi. E vou pagar por isso também. Mas ela precisa falar.", "triste", "negando", "nervoso")], sets=["bia_culpada"]),
     "duo_conf": out([W("lari", "17h52. Código da tesouraria. Levei tudo. Desculpa, Bia.", "triste", "negando", "triste")], unlock="c_confissao")}),
   duo("caio", ["rafa"], ["rafa_falou"], ["rafa_bravo", "duo_cr"], "duo_cr",
    [W("caio", "Você invadiu a escola e EU levo a culpa?", "bravo", "apontando", "nervoso"),
     W("rafa", "Eu peguei MEU celular, presidente. Teu cofre eu nem vi.", "bravo", "negando", "desconfiado"),
     W("caio", "Prova.", "desconfiado", "dando_de_ombros", "bravo")],
    [CH("O vulto da câmera não vai à diretoria", "boa", "duo_fim", ["c_camera"]), BYE()],
    {"duo_fim": out([W("caio", "Então o cofre foi aberto à tarde... Quem saiu cedo da assembleia?", "surpreso", "pensando", "feliz"),
                     W("rafa", "Pergunta pra tua ex, presidente.", "desconfiado", "apontando", "surpreso")], sets=["caio_desconfia"])})]},
 "urna_gremio": {"moves": [("teo", "sala_professores", ["teo_bravo"]), ("caio", "biblioteca", ["caio_falou"])],
  "duos": [
   duo("caio", ["teo"], ["kaua_falou"], ["caio_falou", "teo_bravo", "duo_urna"], "duo_urna",
    [W("caio", "Téo, o Kauã disse que você tirou ele da urna ao meio-dia.", "desconfiado", "apontando", "nervoso"),
     W("teo", "E daí? Eu fiz por VOCÊ, Caio. Pela chapa!", "bravo", "apontando", "surpreso"),
     W("caio", "Eu disse 'se perder, perdeu'.", "triste", "negando", "bravo"),
     W("teo", "E me deu a chave do armário mesmo assim.", "bravo", "dando_de_ombros", "nervoso")],
    [CH("Caio, você deu a chave pra ele?", "boa", "duo_fim"), BYE()],
    {"duo_fim": out([W("caio", "...Dei. Ele disse 'plano B'. Eu não quis saber qual. Que vergonha.", "triste", "negando", "nervoso")],
                    sets=["caio_falou"], unlock="c_dep_caio", choices=[CH("Téo, mostra o bloco da mochila", "boa", "duo_conf", ["c_bloco"]), BYE()]),
     "duo_conf": out([W("teo", "Catorze cédulas pra Rosa. Pra anular. Era o único jeito de não perder.", "triste", "pensando", "triste")], unlock="c_confissao")}),
   duo("bela", ["rui"], ["bela_papo"], ["duo_rosa"], "duo_rosa",
    [W("rui", "Eu te disse que a gente ganhava, Bela!", "feliz", "rindo", "desconfiado"),
     W("bela", "Por catorze votos de papel grosso, Rui? Olha pra mim.", "desconfiado", "apontando", "nervoso"),
     W("rui", "Eu não sei de cédula nenhuma! Eu tava no microfone!", "nervoso", "negando", "desconfiado")],
    [CH("Sem as falsas, vocês ganham igual", "boa", "duo_fim", ["c_cedulas"]), BYE()],
    {"duo_fim": out([W("bela", "Então a fraude não era pra gente ganhar... era pra anular.", "surpreso", "pensando", "surpreso"),
                     W("rui", "Quem ganha com anular é quem perdeu.", "desconfiado", "apontando", "desconfiado")], sets=["rosa_inocente"])})]},
 "gabarito_vazado": {"moves": [("nico", "quadra", ["pedro_falou"]), ("lia", "sala_professores", ["lia_falou"])],
  "duos": [duo("pedro", ["nico"], ["pedro_falou"], ["duo_gab"], "duo_gab",
    [W("nico", "E aí, Pedro. Tudo tranquilo? Nada pra contar pra ninguém, né?", "feliz", "rindo", "nervoso"),
     W("pedro", "Você disse que era foto da internet, Nico! Agora a prova foi cancelada!", "bravo", "apontando", "bravo"),
     W("nico", "Fala baixo. Sério. Fala baixo.", "nervoso", "negando", "bravo")],
    [CH("Nico, você é o @fantasma?", "boa", "duo_fim"), BYE()],
    {"duo_fim": out([W("nico", "Prova. Cadê a prova? Ninguém tem prova de nada.", "bravo", "dando_de_ombros", "desconfiado"),
                     W("pedro", "Teu e-mail tá no perfil, gênio. A coordenação vai achar.", "desconfiado", "apontando", "surpreso")],
                    sets=["nico_exposto"], choices=[CH("Mostrar o e-mail do @fantasma", "boa", "duo_conf", ["c_email"]), BYE()]),
     "duo_conf": out([W("nico", "...Imprimi às 13h48. A Rosa me reprovou. O resto vocês sabem.", "triste", "pensando", "triste")], unlock="c_confissao")})]},
 "conta_sem_rosto": {"moves": [("caique", "biblioteca", ["kevin_falou"]), ("pedro", "corredor", ["pedro_falou"])],
  "duos": [duo("joana", ["caique"], ["joana_falou", "kevin_falou"], ["duo_conta"], "duo_conta",
    [W("joana", "Caíque. Você cobriu meu plantão. Você viu meu post-it.", "bravo", "apontando", "nervoso"),
     W("caique", "Todo mundo via teu post-it, Joana! Tava colado no monitor!", "nervoso", "negando", "bravo"),
     W("joana", "Mas só você sentou aqui na terça. Às 14h05.", "bravo", "apontando", "nervoso")],
    [CH("Mostrar o rastreio e a troca de escala", "boa", "duo_fim", ["c_coord_log", "c_escala_troca"]), BYE()],
    {"duo_fim": out([W("caique", "...O Kevin me humilhou na frente de todo mundo. Eu só quis que ele sentisse.", "triste", "pensando", "surpreso"),
                     W("joana", "E usou meu nome pra isso.", "triste", "negando", "triste")], unlock="c_confissao")})]},
 "final_no_escuro": {"moves": [("enzo", "corredor", ["enzo_bravo"]), ("marta", "sala_professores", ["helio_falou"]), ("juju", "teatro", ["kevin_falou"])],
  "duos": [
   duo("marta", ["juju"], ["kevin_falou"], ["helio_falou", "marta_falou", "duo_mae"], "duo_mae",
    [W("juju", "Mãe. 'Hoje é seu dia, confia na mãe.' O que isso queria dizer?", "triste", "apontando", "nervoso"),
     W("marta", "Filha, não é hora pra isso...", "nervoso", "negando", "triste"),
     W("juju", "Eu não quero uma bolsa ganha no escuro.", "bravo", "negando", "surpreso")],
    [CH("Professora, sua filha merece a verdade", "boa", "duo_fim", ["c_bolsa_marta"]), BYE()],
    {"duo_fim": out([W("marta", "...Fui eu, Juju. As chaves, o disjuntor, o bilhete. Fiz por você.", "triste", "pensando", "triste"),
                     W("juju", "Você não fez por mim. Você fez por você.", "triste", "negando", "triste")], unlock="c_confissao")}),
   duo("enzo", ["gabi"], ["iris_falou"], ["enzo_bravo", "duo_banda", "enzo_falou"], "duo_banda",
    [W("gabi", "Enzo, a Íris disse que tua voz no camarim tava repetida.", "desconfiado", "pensando", "nervoso"),
     W("enzo", "Gabi... você sabe por quê. Você sempre soube.", "nervoso", "negando", "triste"),
     W("gabi", "Sei. Playback. Mas você não apagou a luz. Apagou?", "triste", "apontando", "nervoso")],
    [CH("Enzo, onde você estava às 20h06?", "boa", "duo_fim"), CH("Você tava no camarim às 20h12?", "neutra", "papo"), BYE()],
    {"duo_fim": out([W("enzo", "No banheiro, vomitando de nervoso. Eu nem sei onde fica o disjuntor.", "triste", "negando", "triste"),
                     W("gabi", "Então alguém usou teu segredo. Quem sabia do playback?", "bravo", "pensando", "surpreso")],
                    sets=["enzo_falou"], unlock="c_dep_enzo_verdade")})]},
 "garota_que_nao_existe": {"moves": [("leo", "quadra", ["leo_bravo"]), ("kevin", "biblioteca", ["kevin_falou"])],
  "duos": [duo("leo", ["kevin"], ["nanda_papo", "kevin_falou"], ["leo_falou", "duo_luiza", "leo_bravo"], "duo_luiza",
    [W("kevin", "Léo, eu contei das fotos. Acabou, mano.", "triste", "negando", "bravo"),
     W("leo", "Você me entregou? Por um CHOCOLATE?", "bravo", "apontando", "desconfiado"),
     W("kevin", "Você usou minha prima, Léo. Ela chorou.", "bravo", "apontando", "nervoso")],
    [CH("Léo, você escreve 'excessão', né?", "boa", "duo_fim", ["c_redacao"]), BYE()],
    {"duo_fim": out([W("leo", "...Dois anos no banco. Eu só queria um jogo. A Luiza era eu.", "triste", "pensando", "triste"),
                     W("kevin", "E eu deixei. Também tenho culpa.", "triste", "negando", "triste")], unlock="c_confissao")})]},
}

def apply(case):
    spec = SPEC.get(case["id"], {})
    sp = case["scene_people"]
    for pid, scene, flags in spec.get("moves", []):
        i = next(k for k, e in enumerate(sp) if e["id"] == pid and "if" not in e)
        sp.insert(i, {"id": pid, "scene": scene, "if": flags})
    cards = {c["id"]: c for c in case["cards"]}
    for d in spec.get("duos", []):
        tree = cards[d["owner"]]["talk"]["tree"]
        nid = "duo_" + d["cast"][0]
        node = {"cast": d["cast"], "lines": d["lines"], "sets": [d["done"]], "choices": d["choices"]}
        tree["nodes"][nid] = node
        for oid, o in d["outs"].items():
            o["cast"] = d["cast"]
            tree["nodes"][oid] = o
        tree["entries"].insert(0, {"if": d["if"], "ifnot": d["ifnot"], "node": nid})
    return case

# adultos: (outfit, facial_hair ou None, hair, accessory)
ADULT = {
 "otavio": ("formal", "bigode", "calvo", "oculos_leitura"), "nogueira": ("formal", "barba", "grisalho_curto", "oculos_leitura"),
 "helio": ("formal", "nenhum", "calvo", "oculos"), "ivo": ("uniforme", "cavanhaque", "raspado", "cracha"),
 "jorge": ("uniforme", "bigode", "grisalho_curto", "cracha"),
 "marta": ("formal", None, "chanel", "cracha"), "ana": ("formal", None, "coque_baixo", "oculos"),
 "rosa": ("formal", None, "coque", "oculos_leitura"), "vera": ("formal", None, "longo", "cracha"),
 "cida": ("uniforme", None, "coque", "nenhum"), "lucia": ("formal", None, "coque_baixo", "oculos"),
}
def adults(case):
    for c in case["cards"]:
        if c["kind"] == "pessoa" and c["id"] in ADULT:
            outfit, fh, hair, acc = ADULT[c["id"]]
            c["adult"] = True
            lk = dict(c["look"]); lk.update({"hair": hair, "accessory": acc, "outfit": outfit})
            if c["gender"] == "m": lk["facial_hair"] = fh
            c["look"] = lk
    return case
