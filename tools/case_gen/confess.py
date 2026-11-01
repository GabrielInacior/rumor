"""Confissões controladas (full | partial | slip) e testemunhas que mentem (contradiction)."""
from kit import L, C, BYE

def W(who, text, expr, anim, react): return {"who": who, "text": text, "expr": expr, "anim": anim, "react": react}

# ---------------------------------------------------------------------------
# Culpado: tipo de confissão, falas do nó 'conta', novo texto da pista de confissão, fios que ela ainda prova.
CULPRIT = {
 "solo_bilhete": {"type": "full"},
 "solo_muro": {"type": "full"},
 "solo_vestiario": {"type": "full"},
 "solo_invasao": {"type": "full"},
 "solo_taca": {"type": "partial",
   "lines": [("Tá. Peguei a chave da vitrine sexta, às 18h. Pra limpeza. Isso é crime agora?", "bravo", "apontando"),
             ("A taça? Pra mim ela já era falsa havia anos. Ninguém nunca olhou de perto.", "nervoso", "negando")],
   "title": "Versão da Profa. Marta", "text": "A vice admite que pegou a chave da vitrine sexta às 18h, 'para limpeza', e diz que a taça já devia ser falsa havia anos.",
   "keep": [("marta", "sala_diretor", "estava")]},
 "solo_armacao": {"type": "partial",
   "lines": [("Fiquei na sala no almoço, sim. Estudando. E comprei uma cópia da prova com a Mel. Pra estudar.", "bravo", "apontando"),
             ("A mochila do Davi? Nunca toquei. A denúncia? Não fui eu. Me prova.", "nervoso", "negando")],
   "title": "Versão do Bento", "text": "Bento admite que comprou uma cópia da prova da Mel e ficou sozinho na sala no almoço, mas nega ter mexido na mochila ou mandado a denúncia.",
   "keep": [("bento", "sala_aula", "estava"), ("mel", "bento", "entregou")]},
 "cofre_formatura": {"type": "partial",
   "lines": [("Tá bom. Eu abri o cofre às 17h52. Pra conferir as contas antes da auditoria.", "nervoso", "pensando"),
             ("Mas o dinheiro já tava faltando! Alguém mexeu antes de mim. Bilhete? Nunca vi.", "bravo", "negando")],
   "title": "Versão da Lari", "text": "Lari admite que abriu o cofre às 17h52 'para conferir', mas jura que o dinheiro já estava faltando e nega o bilhete.",
   "keep": [("lari", "sala_diretor", "estava")]},
 "urna_gremio": {"type": "partial",
   "lines": [("Tá, eu chamei o Kauã na cantina. Pra pedir um salgado. Crime?", "bravo", "dando_de_ombros"),
             ("Urna? Nunca toquei. Bloco de papel é pra panfleto. Me prova o contrário.", "nervoso", "negando")],
   "title": "Versão do Téo", "text": "Téo admite que tirou o mesário da urna às 12h02 'para pedir um salgado', mas nega ter tocado nas cédulas.",
   "keep": [("teo", "biblioteca", "estava")]},
 "gabarito_vazado": {"type": "partial",
   "lines": [("Imprimi, sim, quinta 13h48. A professora pediu uma cópia extra. Eu só obedeço.", "nervoso", "pensando"),
             ("Esse @fantasma eu não conheço. E-mail parecido não é prova. Tchau.", "bravo", "negando")],
   "title": "Versão do Nico", "text": "Nico admite que imprimiu o gabarito às 13h48, dizendo que a professora pediu, e nega ser o @fantasma.",
   "keep": [("nico", "coordenacao", "estava")]},
 "conta_sem_rosto": {"type": "partial",
   "lines": [("Tá, eu olho as coisas dos achados. Pra achar o dono! Isso é meu trabalho.", "nervoso", "pensando"),
             ("Cobri o plantão, sim. Mas qualquer um via aquele post-it. A @ninguém não sou eu.", "bravo", "negando")],
   "title": "Versão do Caíque", "text": "Caíque admite que mexia nos celulares e diários dos achados e que cobriu o plantão, mas nega ser a @ninguém.",
   "keep": [("caique", "segredos", "leu")]},
 "final_no_escuro": {"type": "partial",
   "lines": [("Peguei as chaves do Jorge às 19h40, sim. Pra buscar cadeiras no depósito. Esqueci de devolver.", "nervoso", "pensando"),
             ("Disjuntor? Eu nem sei onde fica. Eu ORGANIZEI esse festival, detetive.", "bravo", "negando")],
   "title": "Versão da Profa. Marta", "text": "A organizadora admite que pegou as chaves do zelador às 19h40, 'para buscar cadeiras', e nega ter ido ao disjuntor.",
   "keep": [("marta", "chaves", "pegou")]},
 "garota_que_nao_existe": {"type": "partial",
   "lines": [("Usei o computador às 14h10, tá. Pra olhar o Instagram do time. Proibido?", "nervoso", "dando_de_ombros"),
             ("Luiza? Nunca falei com ela. E 'excessão' muita gente erra.", "bravo", "negando")],
   "title": "Versão do Léo", "text": "Léo admite que usou o computador da biblioteca às 14h10, mas nega qualquer ligação com a Luiza.",
   "keep": [("leo", "biblioteca", "estava")]},
}

# Deslizes nas acareações: dono da árvore -> nó -> novas falas (sem unlock). 'drop' remove nós.
SLIPS = {
 "solo_vestiario": {"pedro": {"duo_fim": [W("gui", "Eu devo dinheiro, mano. Muito... quer dizer, isso não tem nada a ver.", "nervoso", "negando", "surpreso"),
                                          W("pedro", "Ninguém falou em dinheiro, Gui.", "desconfiado", "apontando", "nervoso")], "drop": ["duo_conf"]}},
 "solo_invasao": {"lari": {"duo_fim": [W("ana", "Eu levei pra manutenção sexta... quer dizer, domingo. Domingo roubaram.", "nervoso", "nervoso", "desconfiado"),
                                       W("lari", "A senhora acabou de dizer sexta, professora.", "desconfiado", "apontando", "nervoso")], "drop": ["duo_conf"]}},
 "solo_taca": {"marta": {"duo_conf": [W("marta", "Sábado eu só levei a peça pra avaliar... quer dizer, que peça? Eu não levei nada.", "nervoso", "negando", "surpreso")]}},
 "solo_armacao": {"vera": {"duo_conf": [W("bento", "Eu só pus a prova lá pra... quer dizer, eu nunca vi prova nenhuma!", "nervoso", "negando", "desconfiado"),
                                        W("vera", "'Pus a prova lá', Bento?", "bravo", "apontando", "nervoso")]}},
 "cofre_formatura": {"lari": {"duo_fim": [W("lari", "Eu nem queria pôr o nome dele no... quer dizer, que bilhete? Eu nem sei de bilhete.", "nervoso", "negando", "surpreso"),
                                          W("bia", "Ninguém falou em bilhete, amiga.", "triste", "apontando", "nervoso")],
                               "duo_conf": [W("lari", "Às 17h52 eu só conferi! O cofre já tava... tava leve, sabe?", "nervoso", "nervoso", "desconfiado")]}},
 "urna_gremio": {"caio": {"duo_conf": [W("teo", "Catorze cédulas não é nada... quer dizer, eu nem sei quantas cédulas tinha!", "nervoso", "negando", "surpreso"),
                                       W("caio", "Quem falou em catorze, Téo?", "bravo", "apontando", "nervoso")]}},
 "gabarito_vazado": {"pedro": {"duo_conf": [W("nico", "Às 13h48 a coordenação tava vazia, ninguém... quer dizer, eu não sei de horário nenhum.", "nervoso", "negando", "surpreso"),
                                            W("pedro", "Ninguém falou 13h48, Nico.", "desconfiado", "apontando", "nervoso")]}},
 "conta_sem_rosto": {"joana": {"duo_fim": [W("caique", "O Kevin mereceu ser exposto... quer dizer, quem quer que tenha feito, né?", "nervoso", "negando", "surpreso"),
                                           W("joana", "'Exposto' por quem, Caíque?", "bravo", "apontando", "nervoso")]}},
 "final_no_escuro": {"marta": {"duo_fim": [W("marta", "Filha, eu só queria que você ganhasse... quer dizer, eu não fiz nada! Nada.", "nervoso", "negando", "triste"),
                                           W("juju", "'Que eu ganhasse' como, mãe?", "triste", "apontando", "nervoso")]}},
 "garota_que_nao_existe": {"leo": {"duo_fim": [W("leo", "Ela só respondia às 23h porque... quer dizer, sei lá quando ela respondia.", "nervoso", "negando", "surpreso"),
                                               W("kevin", "Você sabe exatamente quando ela respondia, Léo.", "bravo", "apontando", "nervoso")]}},
}

# Testemunhas que mentem: (pessoa, nova fala de abertura ou None, escolha, exige, falas da nova versão, unlock)
LIES = {
 "solo_vestiario": [("gabriel", [("Arrombaram meu cadeado, mano! Na força! Três mil reais!", "bravo", "negando")],
     "Mostrar o cadeado aberto sem força", ["c_cadeado"],
     [("Tá... não tava arrombado. Falei aquilo porque fiquei com vergonha.", "triste", "negando"),
      ("A senha é o aniversário da Mari. Só meus amigos sabem. Tipo o Gui.", "nervoso", "pensando")], None)],
 "solo_invasao": [("jorge", None, "Mostrar o story do Theo das 2h04", ["c_story_theo"],
     [("Tá bom. Eu disse que não vi nada, mas vi um carro prata entrar pela rua de trás às 2h.", "nervoso", "pensando"),
      ("Fiquei quieto porque achei que era gente da diretoria.", "triste", "dando_de_ombros")], "c_dep_jorge")],
 "solo_taca": [("sofia", None, "Mostrar o molde de resina", ["c_molde"],
     [("Tá. Eu fiz uma taça. Disse que só fazia coroa, mas fiz uma taça.", "nervoso", "nervoso"),
      ("Foi encomenda. Da Profa. Marta. 'Pra peça.'", "triste", "pensando")], None)],
 "solo_armacao": [("mel", None, "Mostrar o registro do computador", ["c_impressora"],
     [("Tá, imprimi a prova quinta 17h10. Mas era pra mim, pra estudar!", "nervoso", "negando"),
      ("...Ou quase. Alguém me pediu uma cópia. Não vou dizer quem.", "nervoso", "pensando")], None)],
 "cofre_formatura": [
   ("bia", [("A Lari tava comigo contando rifa a tarde toda. Deixa ela em paz, detetive.", "bravo", "apontando")],
     "Mostrar a ata da assembleia", ["c_ata"],
     [("Tá... ela não tava comigo. Saiu 17h45 e sumiu. Eu disse aquilo porque ela me pediu.", "triste", "negando")], None),
   ("rafa", None, "Mostrar o print da câmera", ["c_camera"],
     [("Tá, o moletom laranja era eu. Disse que dormi cedo, mas pulei o muro.", "nervoso", "pensando"),
      ("Só que eu fui na sala dos professores, não na diretoria. Olha o print de novo.", "desconfiado", "apontando")], "c_dep_rafa")],
 "urna_gremio": [
   ("kaua", [("A urna nunca ficou sozinha, nem um segundo. Mesário raiz.", "desconfiado", "apontando")],
     "Mostrar a ata da urna", ["c_urna"],
     [("Tá... ficou dez minutos sozinha. Me chamaram urgente na cantina. Eu menti por vergonha.", "triste", "negando")], None),
   ("rui", [("Nem falei com o mesário hoje. Coordenador de campanha não se mistura.", "desconfiado", "dando_de_ombros")],
     "Mostrar a sua DM para o Kauã", ["c_dm_rui"],
     [("Tá, mandei mensagem. Mas era pra ele CUIDAR da urna, não pra fraudar.", "nervoso", "pensando")], None)],
 "gabarito_vazado": [
   ("kaua", [("Eu? Comprar gabarito? Jamais. Eu estudo.", "nervoso", "negando")],
     "Mostrar o comprovante do seu Pix", ["c_comprovante"],
     [("Tá, comprei. Vinte reais pro Pedro. E chegou borrado.", "triste", "dando_de_ombros")], "c_dep_kaua"),
   ("lia", [("Domingo eu nem falei com a professora. Fiquei estudando o dia todo.", "desconfiado", "dando_de_ombros")],
     "Mostrar sua mensagem para a professora", ["c_chat_lia"],
     [("Tá, mandei. Ofereci ajuda pra refazer a prova. Por uma carta de recomendação. Ambição não é crime.", "nervoso", "pensando")], None)],
 "conta_sem_rosto": [
   ("pedro", None, "CONTA", None,
     [("Tá. Eu disse que não paguei, mas paguei. Cinquenta, para 'C. Monteiro'.", "triste", "negando")], "c_dep_pedro"),
   ("kevin", [("Ninguém mexeu no meu celular. Ele nunca sai do meu bolso.", "bravo", "negando")],
     "CONTA", None,
     [("Tá. Perdi semana passada. Voltou dos achados desbloqueado. E esse bilhete é assinado 'C.'.", "surpreso", "pensando")], "c_dep_kevin")],
 "final_no_escuro": [
   ("enzo", None, "CONTA", None,
     [("Tá. Eu disse que tava no camarim. Não tava. O áudio era o teste do meu playback.", "triste", "negando")], None),
   ("gabi", [("O Enzo canta de verdade, tá? Para de ouvir fofoca.", "bravo", "apontando")],
     "Mostrar o pendrive PLAYBACK_FINAL", ["c_kit_enzo"],
     [("...Tá. Ele canta de playback. Eu sabia e protegi. Mas ele não apagou luz nenhuma.", "triste", "pensando")], None)],
 "garota_que_nao_existe": [
   ("gabriel", [("Eu? Faltar treino por uma menina? Eu tava doente, mano.", "nervoso", "negando")],
     "Mostrar a foto do mural", ["c_shopping"],
     [("Tá... eu tava no shopping. Esperando ela. Com flores. Duas horas.", "triste", "negando")], "c_dep_gabriel"),
   ("kevin", None, "CONTA", None,
     [("Eu disse que não sabia de nada. Mentira. As fotos são da minha prima.", "nervoso", "pensando"),
      ("Mas o perfil não era meu. Juro.", "bravo", "negando")], None)],
}

def _choice_into(tree, nid):
    return [(oid, c) for oid, o in tree["nodes"].items() for c in o["choices"] if c.get("next") == nid]

def apply(case):
    cid = case["id"]; sol = case["solution"]; cards = {c["id"]: c for c in case["cards"]}
    spec = CULPRIT[cid]
    ct = cards[sol["culprit"]]["talk"]["tree"]
    # pista de confissão do culpado
    conf_clue = ct["nodes"]["conta"].get("unlock")
    if sol["culprit"] in ("lu", "thiago"):  # nível 1: confissão plena, nunca só com pista t+
        ct["nodes"]["conta"]["confession"] = "full"
        for _, c in _choice_into(ct, "conta"):
            if c.get("requires") == ["c_ficha"]: c["requires"] = ["c_armario"]
    elif cid in ("solo_vestiario", "solo_invasao"):
        first, second, recua_lines = {
            "solo_vestiario": (["c_papel"], ["c_anuncio"], [("Esse papel? Eu anotei porque o Gabriel vive esquecendo a senha. Eu AJUDO ele.", "nervoso", "rindo"),
                                                           ("Quem pegou foi o Kauã, aposto. Apareceu de tênis novo, né?", "desconfiado", "apontando")]),
            "solo_invasao": (["c_ficha_lab"], ["c_alarme", "c_codigos"], [("Tá, eu tirei o microscópio sexta. Pra manutenção numa oficina.", "nervoso", "pensando"),
                                                                         ("Domingo roubaram de lá! Ou daqui. Foi o Seu Jorge que não viu nada, né?", "desconfiado", "apontando")])}[cid]
        pid = sol["culprit"]; flag = pid + "_recuou"
        ct["nodes"]["recua"] = {"lines": [L(*x) for x in recua_lines], "sets": [flag], "confession": "partial",
                                "choices": [dict(C("Mostrar a segunda prova", "boa", "conta", second), **{"if": [flag]}), BYE()]}
        ct["nodes"]["recua"]["choices"][0]["text"] = {"solo_vestiario": "Mostrar o anúncio do celular", "solo_invasao": "Mostrar o alarme e os códigos"}[cid]
        for oid, c in _choice_into(ct, "conta"):
            if oid != "recua":
                c["next"] = "recua"; c["requires"] = first
                c["text"] = {"solo_vestiario": "Mostrar o papel do seu armário", "solo_invasao": "Mostrar a ficha do armário"}[cid]
        ct["entries"].insert(0, {"if": [flag], "ifnot": [pid + "_falou"], "node": "recua"})
        ct["nodes"]["conta"]["confession"] = "full"
    else:
        n = ct["nodes"]["conta"]
        n["lines"] = [L(*x) for x in spec["lines"]]; n["confession"] = "partial"
        clue = next(c for c in case["clues"] if c["id"] == conf_clue)
        clue["title"] = spec["title"]; clue["text"] = spec["text"]
        keep = set(spec["keep"])
        for e in sol["edges"]:
            if conf_clue in e["evidence"] and (e["from"], e["to"], e["type"]) not in keep: e["evidence"].remove(conf_clue)
        for f, t, ty in keep:
            e = next(e for e in sol["edges"] if (e["from"], e["to"], e["type"]) == (f, t, ty))
            if conf_clue not in e["evidence"]: e["evidence"].append(conf_clue)
        if conf_clue in sol["culprit_evidence"]: sol["culprit_evidence"].remove(conf_clue)
    # deslizes nas acareações
    for owner, nodes in SLIPS.get(cid, {}).items():
        tree = cards[owner]["talk"]["tree"]
        for nid in nodes.get("drop", []):
            tree["nodes"].pop(nid, None)
            for o in tree["nodes"].values():
                o["choices"] = [c for c in o["choices"] if c.get("next") != nid]
        for nid, lines in nodes.items():
            if nid == "drop": continue
            nd = tree["nodes"][nid]; nd["lines"] = lines; nd["confession"] = "slip"; nd.pop("unlock", None)
    # testemunhas que mentem
    for pid, start, text, req, lines, unlock in LIES.get(cid, []):
        tree = cards[pid]["talk"]["tree"]; nodes = tree["nodes"]
        if start: nodes["inicio"]["lines"] = [L(*x) for x in start]
        if text == "CONTA":
            nodes["conta"]["contradiction"] = True
            continue
        nv = {"lines": [L(*x) for x in lines], "contradiction": True, "sets": [pid + "_versao"], "choices": [BYE("Por que mentiu antes?")]}
        if unlock: nv["unlock"] = unlock
        nodes["versao"] = nv
        ch = C(text, "boa", "versao", req); ch["ifnot"] = [pid + "_versao"]
        placed = False
        for host in ("inicio", "papo", "depois", "conta", "fechado", "reage"):
            if host in nodes and not nodes[host].get("end") and len(nodes[host]["choices"]) < 4 and host != "versao":
                nodes[host]["choices"].insert(0, dict(ch)); placed = True
        assert placed, (cid, pid)
    return case
