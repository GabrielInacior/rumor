"""Visual de cada pista: {"model": ...} ou {"art": "ransom"|"cctv"|"pix", ...}."""
import re, unicodedata

MODELS = set("celular mensagem onibus trofeu livro carta chocolate carregador baqueta fita computador pizza chave mochila coroa camera papel "
              "microfone bola prancheta caixa cartaz wifi relogio sacola cofre urna microscopio spray cadeado revista recorte dinheiro tenis "
              "pegada pendrive envelope cracha camera_seg impressora prova luva bolsa ingresso".split())

def _n(s): return unicodedata.normalize("NFD", s.lower()).encode("ascii", "ignore").decode()

KEYS = [  # (palavras, model) na ordem de prioridade, procuradas em id+título+texto
 (["impressora", "impresso por", "imprimiu"], "impressora"),
 (["camera do corredor", "print da camera", "camera_seg"], "camera_seg"),
 (["cofre"], "cofre"), (["urna", "cedula", "lacre"], "urna"), (["microscopio"], "microscopio"),
 (["spray"], "spray"), (["tenis"], "tenis"), (["pegada"], "pegada"), (["cadeado"], "cadeado"),
 (["revista"], "revista"), (["pendrive", "playback"], "pendrive"), (["luvas"], "luva"), (["envelope"], "envelope"),
 (["taca", "trofeu"], "trofeu"), (["chaves", "chave "], "chave"), (["dinheiro", "notas novas", "r$ 300"], "dinheiro"),
 (["bala ", "balas"], "caixa"), (["bolsa da", "bolsa do"], "bolsa"), (["mochila"], "mochila"), (["prova "], "prova"),
 (["computador", "rede ", "wifi"], "computador"), (["atestado", "ata ", "chamada", "escala", "lista", "registro", "ficha", "livro do", "agenda",
   "caderno", "sumula", "notas parciais", "regulamento", "relatorio", "laudo", "ocorrencia", "comanda", "reserva"], "prancheta"),
]

def guess(c):
    k = c["kind"]
    if k == "mensagem": return {"model": "mensagem"}
    if k == "post": return {"model": "celular"}
    if k == "depoimento": return {"model": "microfone"}
    hay = _n(" ".join([c["id"], c["title"], c["text"]]))
    for words, m in KEYS:
        if any(re.search(r"\b" + re.escape(w.strip()) + r"\b", hay) for w in words): return {"model": m}
    return {"model": "papel" if k in ("bilhete", "registro") else "caixa"}

O = {  # sobrescritas à mão: case -> clue -> visual
 "solo_bilhete": {"c_bilhete": {"art": "ransom", "text": "SAI DO TIME ATÉ SEXTA"}, "c_armario": {"model": "recorte"},
                  "c_bolsa": {"model": "revista"}, "c_treino": {"model": "prancheta"}, "c_ficha": {"model": "prancheta"}},
 "solo_muro": {"c_foto_muro": {"model": "spray"}, "c_pegada": {"model": "pegada"}, "c_livro": {"model": "prancheta"}, "c_live_kevin": {"model": "celular"},
               "c_confissao": {"model": "spray"}, "c_dep_jorge": {"model": "pegada"}, "c_dep_kevin": {"model": "spray"}},
 "solo_vestiario": {"c_papel": {"model": "papel"}, "c_comanda": {"model": "sacola"}, "c_recibo": {"model": "tenis"},
                    "c_anuncio": {"model": "celular"}, "c_dep_kaua": {"model": "tenis"}, "c_dep_pedro": {"model": "cadeado"}, "c_confissao": {"model": "celular"}},
 "solo_invasao": {"c_alerta": {"model": "mensagem"}, "c_poeira": {"model": "microscopio"}, "c_vidro": {"model": "caixa"},
                  "c_alarme": {"model": "relogio"}, "c_codigos": {"model": "papel"}, "c_story_theo": {"art": "cctv", "stamp": "2h04", "caption": "Luz acesa no laboratório e uma silhueta do lado de dentro"},
                  "c_cursinho": {"model": "microscopio"}, "c_ronda": {"model": "prancheta"}, "c_dep_lari": {"model": "microscopio"}, "c_dep_theo": {"model": "celular"}},
 "solo_taca": {"c_laudo": {"model": "trofeu"}, "c_vitrine": {"model": "trofeu"}, "c_chave_log": {"model": "chave"}, "c_encomenda": {"model": "prancheta"},
               "c_molde": {"model": "trofeu"}, "c_cartao": {"model": "envelope"}, "c_foto_marco": {"model": "camera"}, "c_antiquario": {"model": "celular"},
               "c_dep_sofia": {"model": "coroa"}, "c_dep_nogueira": {"model": "livro"}, "c_dep_nanda": {"model": "bolsa"}, "c_dep_jorge": {"model": "chave"}},
 "solo_armacao": {"c_denuncia": {"model": "computador"}, "c_mochila": {"model": "dinheiro"}, "c_lousa": {"model": "papel"},
                  "c_ranking": {"model": "prancheta"}, "c_impressora": {"model": "impressora"}, "c_bilhete_mel": {"model": "carta"},
                  "c_recibo": {"model": "dinheiro"}, "c_rede": {"model": "wifi"}, "c_dep_mel": {"model": "impressora"}, "c_dep_joana": {"model": "celular"},
                  "c_dep_caique": {"model": "sacola"}, "c_dep_davi": {"model": "livro"}},
 "cofre_formatura": {"c_bilhete": {"model": "carta"}, "c_codigos": {"model": "cofre"},
                     "c_camera": {"art": "cctv", "stamp": "23h17", "caption": "Vulto de moletom laranja entrando na sala dos professores"},
                     "c_armario_cel": {"model": "celular"}, "c_log_cofre": {"model": "cofre"}, "c_rascunho": {"model": "dinheiro"},
                     "c_auditoria": {"model": "prancheta"}, "c_dep_rafa": {"model": "celular"}, "c_dep_jorge": {"model": "mochila"},
                     "c_dep_bia": {"model": "dinheiro"}, "c_dep_joana": {"model": "impressora"}, "c_dep_caio": {"model": "cracha"}},
 "urna_gremio": {"c_resultado": {"model": "urna"}, "c_cedulas": {"model": "urna"}, "c_bloco": {"model": "papel"}, "c_lousa": {"model": "papel"}, "c_regra": {"model": "prancheta"},
                 "c_cartaz": {"model": "cartaz"}, "c_comanda": {"model": "prancheta"}, "c_assinaturas": {"model": "prancheta"},
                 "c_dep_kaua": {"model": "urna"}, "c_dep_caio": {"model": "chave"}, "c_dep_rui": {"model": "microfone"}, "c_dep_bela": {"model": "urna"},
                 "c_confissao": {"model": "urna"}},
 "gabarito_vazado": {"c_venda": {"model": "prova"}, "c_aviso": {"model": "prancheta"}, "c_story_nico": {"model": "computador"},
                     "c_celular_pedro": {"model": "celular"},
                     "c_comprovante": {"art": "pix", "valor": "R$ 20,00", "de": "Kauã", "para": "Pedro H. Souza", "hora": "19h03"},
                     "c_foto_gabarito": {"model": "prova"}, "c_classificado": {"model": "cartaz"}, "c_email": {"model": "computador"},
                     "c_dep_pedro": {"model": "celular"}, "c_dep_rosa": {"model": "impressora"}, "c_dep_lia": {"model": "livro"},
                     "c_dep_kaua": {"model": "prova"}, "c_dep_mari": {"model": "prova"}, "c_confissao": {"model": "impressora"}},
 "conta_sem_rosto": {"c_post": {"model": "celular"},
                     "c_pix_pedro": {"art": "pix", "valor": "R$ 50,00", "de": "Pedro", "para": "C. Monteiro", "hora": "14h30"},
                     "c_story_caique": {"model": "ingresso"}, "c_comanda": {"model": "wifi"}, "c_senha": {"model": "computador"}, "c_achados": {"model": "caixa"},
                     "c_bilhete_kevin": {"model": "carta"}, "c_atestado": {"model": "prancheta"}, "c_coord_log": {"model": "computador"},
                     "c_dep_joana": {"model": "computador"}, "c_dep_kevin": {"model": "celular"}, "c_dep_lia": {"model": "papel"},
                     "c_dep_pedro": {"model": "dinheiro"}, "c_confissao": {"model": "caixa"}},
 "final_no_escuro": {"c_post_show": {"model": "celular"}, "c_bilhete_camarim": {"model": "carta"},
                     "c_caixinha": {"model": "microfone"}, "c_log_luz": {"model": "prancheta"}, "c_bala": {"model": "caixa"},
                     "c_porta": {"model": "chave"}, "c_kit_enzo": {"model": "pendrive"}, "c_ordem": {"model": "prancheta"}, "c_balde": {"model": "pegada"},
                     "c_notas": {"model": "prancheta"}, "c_bolsa_marta": {"model": "bolsa"}, "c_audio": {"model": "celular"},
                     "c_dep_iris": {"model": "microfone"}, "c_dep_jorge": {"model": "chave"}, "c_dep_enzo": {"model": "microfone"},
                     "c_dep_enzo_verdade": {"model": "pendrive"}, "c_dep_gabi": {"model": "caixa"}, "c_dep_kevin": {"model": "trofeu"},
                     "c_dep_juju": {"model": "mensagem"}, "c_dep_helio": {"model": "prancheta"}, "c_confissao": {"model": "chave"}},
 "garota_que_nao_existe": {"c_perfil": {"model": "celular"}, "c_story_kevin": {"model": "celular"}, "c_sumula": {"model": "prancheta"},
                           "c_prancheta": {"model": "prancheta"}, "c_redacao": {"model": "papel"}, "c_campeonato": {"model": "cartaz"},
                           "c_computador": {"model": "computador"}, "c_shopping": {"model": "camera"}, "c_busca": {"model": "computador"},
                           "c_redacao_lista": {"model": "prancheta"}, "c_dep_ivo": {"model": "prancheta"}, "c_dep_gabriel": {"model": "mensagem"},
                           "c_dep_mel": {"model": "camera"}, "c_dep_kevin": {"model": "camera"}, "c_dep_nanda": {"model": "computador"},
                           "c_dep_ana": {"model": "papel"}, "c_confissao": {"model": "computador"}},
}

# Objetos que fariam mais sentido e ainda não existem (caso, pista, objeto ideal); o mais próximo foi usado.
MISSING = [
 ("solo_muro", "c_foto_muro", "muro pichado"), ("solo_invasao", "c_vidro", "cacos de vidro / janela quebrada"),
 ("solo_invasao", "c_alarme", "painel de alarme"), ("solo_taca", "c_molde", "molde de resina"),
 ("solo_armacao", "c_lousa", "lousa"), ("urna_gremio", "c_lousa", "lousa"), ("urna_gremio", "c_bloco", "bloco de papel com tesoura"),
 ("final_no_escuro", "c_bala", "bala / pacote de balas de mel"), ("final_no_escuro", "c_caixinha", "caixinha de som"),
 ("final_no_escuro", "c_balde", "balde e esfregão"), ("final_no_escuro", "c_porta", "disjuntor / caixa de fusíveis"),
 ("conta_sem_rosto", "c_achados", "caixa de achados e perdidos com diário"), ("conta_sem_rosto", "c_senha", "post-it no monitor"),
 ("garota_que_nao_existe", "c_redacao", "redação corrigida em vermelho"), ("solo_vestiario", "c_comanda", "comanda da cantina"),
]

def apply(case):
    over = O.get(case["id"], {})
    for c in case["clues"]:
        c["visual"] = over.get(c["id"]) or guess(c)
    return case
