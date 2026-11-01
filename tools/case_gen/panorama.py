"""Fatos que fecham a história, panorama (ligações não obrigatórias) e história completa no guia."""
from kit import fact

def P(f, t, ty, *ev):
    l = {"from": f, "to": t, "type": ty}
    if ev: l["evidence"] = list(ev)
    return l

SPEC = {
 "solo_bilhete": {
  "facts": [("recuperacao", "A recuperação da Bia", "papel"), ("vaga", "A vaga de titular", "trofeu")],
  "panorama": [P("lu", "vaga", "g_motivo", "c_ficha"), P("lu", "recuperacao", "g_sabia", "c_ficha"), P("lu", "bia", "g_mentiu", "c_chat_time"),
               P("duda", "bia", "g_brigou", "c_chat_time"), P("duda", "bilhetes", "g_nao_fez", "c_treino")],
  "close": "No quadro oficial: a Lu escreveu os bilhetes de olho na vaga; a capitã brigava, mas estava no treino."},
 "solo_muro": {
  "facts": [("zero", "A prova zerada e a viagem perdida", "papel"), ("tranca", "A tranca quebrada dos fundos", "chave")],
  "panorama": [P("thiago", "zero", "g_motivo", "c_ocorrencia"), P("nogueira", "thiago", "g_brigou", "c_ocorrencia"), P("kevin", "muro", "g_nao_fez", "c_live_kevin"),
               P("jorge", "thiago", "g_viu", "c_livro", "c_dep_jorge"), P("tranca", "deposito", "g_aconteceu", "c_pegada")],
  "close": "No quadro oficial: o Thiago entrou pela tranca quebrada e pichou por vingança; o Kevin estava na praça."},
 "solo_vestiario": {
  "facts": [("divida", "A dívida do Gui num site de jogo", "caixa"), ("segredo", "A senha do cadeado (0408)", "chave"), ("tenis", "O tênis novo do Kauã", "mochila")],
  "panorama": [P("gui", "segredo", "g_sabia", "c_papel"), P("gui", "gabriel", "g_amigo", "c_alerta"), P("gui", "gabriel", "g_mentiu", "c_alerta"),
               P("kaua", "celular", "g_nao_fez", "c_recibo"), P("pedro", "gui", "g_viu", "c_dep_pedro"), P("pedro", "celular", "g_nao_fez", "c_comanda"),
               P("gabriel", "segredo", "g_mentiu_sobre", "c_cadeado")],
  "close": "No quadro oficial: o melhor amigo sabia a senha, pegou o celular e fingiu solidariedade; o tênis do Kauã era da Bolsa Atleta."},
 "solo_invasao": {
  "facts": [("cursinho", "O cursinho particular da Profa. Ana", "livro"), ("seguro", "O dinheiro do seguro", "caixa"), ("janela", "A janela quebrada por dentro", "cartaz")],
  "panorama": [P("ana", "seguro", "g_motivo", "c_cursinho"), P("ana", "otavio", "g_mentiu", "c_alerta"), P("ana", "microscopio", "g_mentiu_sobre", "c_ficha_lab"),
               P("janela", "laboratorio", "g_aconteceu", "c_vidro"), P("jorge", "microscopio", "g_nao_fez", "c_ronda"), P("theo", "ana", "g_viu", "c_story_theo"),
               P("lari", "microscopio", "g_sabia", "c_dep_lari")],
  "close": "No quadro oficial: a professora tirou o microscópio na sexta, encenou a invasão no domingo e mentiu ao diretor."},
 "solo_taca": {
  "facts": [("antiquario", "A venda ao Antiquário Relíquia", "caixa")],
  "panorama": [P("marta", "antiquario", "g_motivo", "c_cartao"), P("marta", "sofia", "g_mentiu", "c_dep_nogueira"), P("sofia", "marta", "g_acobertou", "c_dep_sofia"),
               P("marta", "jorge", "g_mentiu", "c_livro_jorge"), P("jorge", "taca", "g_nao_fez", "c_livro_jorge"), P("nanda", "marta", "g_viu", "c_dep_nanda")],
  "close": "No quadro oficial: a vice mentiu para a Sofia e para o zelador, trocou a taça e vendeu a verdadeira; a Sofia acobertou."},
 "solo_armacao": {
  "facts": [("bolsa_intercambio", "A bolsa de intercâmbio", "trofeu"), ("dinheiro", "Os R$ 300 em notas novas", "caixa"), ("monitoria", "A monitoria paga do Davi", "livro")],
  "panorama": [P("bento", "bolsa_intercambio", "g_motivo", "c_ranking"), P("dinheiro", "sala_aula", "g_aconteceu", "c_mochila"), P("joana", "davi", "g_alibi", "c_registro_bib"),
               P("caique", "bento", "g_viu", "c_dep_caique"), P("mel", "bento", "g_acobertou", "c_dep_mel"), P("davi", "monitoria", "g_mentiu_sobre", "c_dep_davi"),
               P("joana", "bento", "g_viu", "c_dep_joana")],
  "close": "No quadro oficial: o Bento comprou a prova, plantou tudo e denunciou; o Davi escondia só a monitoria paga."},
 "cofre_formatura": {
  "facts": [("alarme", "O alarme das 23h17", "relogio"), ("festa", "A festa de quinze da Lari", "caixa"), ("auditoria", "A prestação de contas de sexta", "papel")],
  "panorama": [P("lari", "caio", "g_brigou", "c_dep_caio"), P("lari", "auditoria", "g_sabia", "c_auditoria"), P("bia", "lari", "g_acobertou", "c_dm_bia_lari"),
               P("bia", "festa", "g_sabia", "c_dm_bia_lari"), P("rafa", "dinheiro", "g_nao_fez", "c_camera"), P("caio", "dinheiro", "g_nao_fez", "c_ata"),
               P("alarme", "sala_professores", "g_aconteceu", "c_log_cofre", "c_camera"), P("jorge", "lari", "g_viu", "c_dep_jorge"), P("joana", "lari", "g_viu", "c_dep_joana"),
               P("lari", "bilhete", "g_mentiu_sobre", "c_impressora")],
  "close": "No quadro oficial: a Lari esvaziou o cofre à tarde e culpou o ex; a Bia acobertou; o alarme da noite foi o Rafa atrás do celular."},
 "urna_gremio": {
  "facts": [("anulacao", "A anulação da eleição", "papel"), ("plano_b", "O 'plano B' da Chapa Azul", "cartaz"), ("chamado", "O chamado falso ao mesário", "celular")],
  "panorama": [P("teo", "anulacao", "g_motivo", "c_regra"), P("caio", "plano_b", "g_sabia", "c_chat_azul"), P("teo", "kaua", "g_mentiu", "c_comanda"),
               P("caio", "teo", "g_acobertou", "c_dep_caio"), P("bela", "cedulas", "g_nao_fez", "c_cedulas"), P("rui", "cedulas", "g_nao_fez", "c_cartaz"),
               P("cida", "teo", "g_viu", "c_comanda"), P("kaua", "chamado", "g_mentiu_sobre", "c_urna"), P("chamado", "cantina", "g_aconteceu", "c_comanda")],
  "close": "No quadro oficial: o Téo fraudou para anular, com a chave que o Caio emprestou; a Rosa venceria de qualquer jeito."},
 "gabarito_vazado": {
  "facts": [("perfil_fantasma", "O perfil @fantasma", "celular"), ("setup", "O computador gamer do Nico", "computador"), ("pix", "Os 27 Pix de vinte reais", "caixa")],
  "panorama": [P("nico", "setup", "g_motivo", "c_story_nico"), P("nico", "rosa", "g_brigou", "c_dep_rosa"), P("nico", "perfil_fantasma", "g_mentiu_sobre", "c_email"),
               P("pedro", "perfil_fantasma", "g_sabia", "c_dm_fantasma"), P("pedro", "gabarito", "g_nao_fez", "c_dm_fantasma"), P("lia", "gabarito", "g_nao_fez", "c_registro_bib"),
               P("kaua", "gabarito", "g_mentiu_sobre", "c_comprovante"), P("mari", "perfil_fantasma", "g_sabia", "c_dep_mari"), P("pedro", "pix", "g_sabia", "c_celular_pedro"),
               P("joana", "lia", "g_alibi", "c_registro_bib")],
  "close": "No quadro oficial: o Nico tirou o gabarito e se escondeu atrás do @fantasma; o Pedro vendeu; a Lia só queria uma carta."},
 "conta_sem_rosto": {
  "facts": [("humilhacao", "A humilhação do Caíque no grupo", "mensagem"), ("postit", "A senha no post-it", "papel"), ("ameaca", "A ameaça dos R$ 50", "mensagem"), ("troca", "A troca de plantão", "prancheta")],
  "panorama": [P("kevin", "caique", "g_brigou", "c_story_caique"), P("caique", "humilhacao", "g_motivo", "c_story_caique"), P("caique", "postit", "g_sabia", "c_senha"),
               P("joana", "ninguem", "g_nao_fez", "c_atestado"), P("lia", "ninguem", "g_nao_fez", "c_chamada_aula"), P("pedro", "ameaca", "g_mentiu_sobre", "c_pix_pedro"),
               P("kevin", "segredos", "g_mentiu_sobre", "c_bilhete_kevin"), P("troca", "biblioteca", "g_aconteceu", "c_escala_troca"), P("cida", "caique", "g_viu", "c_comanda"),
               P("caique", "joana", "g_mentiu", "c_escala_troca", "c_coord_log")],
  "close": "No quadro oficial: o Caíque lia os achados, cobriu o plantão, usou a senha da Joana e chantageou; Pedro e Kevin mentiram por vergonha."},
 "final_no_escuro": {
  "facts": [("bolsa_premio", "A bolsa de R$ 5 mil", "trofeu"), ("playback", "O playback do Enzo", "microfone"), ("apagao", "O apagão das 20h12", "relogio"), ("bilhete", "O bilhete 'quem canta de mentira'", "carta")],
  "rename": {"alibi_audio": "O álibi da voz no camarim"},
  "panorama": [P("marta", "bolsa_premio", "g_motivo", "c_notas"), P("helio", "playback", "g_sabia", "c_dep_helio"), P("marta", "playback", "g_sabia", "c_dep_helio"),
               P("gabi", "enzo", "g_acobertou", "c_kit_enzo"), P("enzo", "playback", "g_mentiu_sobre", "c_audio"), P("enzo", "apagao", "g_nao_fez", "c_kit_enzo"),
               P("kevin", "apagao", "g_nao_fez", "c_comanda"), P("iris", "apagao", "g_nao_fez", "c_log_luz"), P("juju", "kevin", "g_estava_com", "c_chat_danca"),
               P("apagao", "deposito", "g_aconteceu", "c_bala", "c_porta"), P("bilhete", "teatro", "g_aconteceu", "c_bilhete_camarim"), P("marta", "juju", "g_mentiu", "c_dm_marta")],
  "close": "No quadro oficial: a organizadora apagou as luzes pela filha e usou o segredo do Enzo como isca; a Juju não sabia."},
 "garota_que_nao_existe": {
  "facts": [("jogada7", "A jogada 7", "prancheta"), ("fotos_prima", "As fotos da prima de Lisboa", "camera"), ("suspensao", "A suspensão dos titulares", "papel")],
  "panorama": [P("leo", "jogada7", "g_sabia", "c_prancheta"), P("leo", "suspensao", "g_motivo", "c_sumula"), P("kevin", "leo", "g_amigo", "c_campeonato"),
               P("leo", "gabriel", "g_mentiu", "c_dm_gabriel"), P("leo", "pedro", "g_mentiu", "c_dm_pedro"), P("mel", "luiza", "g_nao_fez", "c_dep_mel"),
               P("kevin", "fotos_prima", "g_sabia", "c_busca"), P("gabriel", "ivo", "g_mentiu", "c_shopping"), P("pedro", "gabriel", "g_estava_com", "c_shopping"),
               P("kaua", "gabriel", "g_estava_com", "c_shopping")],
  "close": "No quadro oficial: o reserva criou a Luiza com as fotos que o amigo Kevin deu, enganou três titulares e estreou no gol."},
}

FAQ = ("Como montar o panorama?",
       "Além dos fios obrigatórios, liguem pessoas entre si (quem mentiu para quem, quem acobertou, quem estava com quem, quem é álibi de quem), "
       "marquem os inocentes com 'não fez' e a etiqueta INOCENTE, e prendam várias provas no mesmo fio. O panorama não vale nota, mas mostra se a história fecha sem furos.")

NAMES = {'solo_muro': ({'muro': 'O muro do pátio'}, {}), 'gabarito_vazado': ({}, {'entregou': 'repassou o gabarito para'}), 'solo_armacao': ({}, {'entregou': 'entregou a prova para'}), 'conta_sem_rosto': ({'ninguem': '@ninguém', 'dentista': 'Consultório do dentista'}, {}), 'garota_que_nao_existe': ({'quadra': 'Gol da semifinal'}, {})}

def apply(case, guide):
    s = SPEC[case["id"]]
    ren, labels = NAMES.get(case["id"], ({}, {}))
    for fid, name in ren.items(): next(c for c in case["cards"] if c["id"] == fid)["name"] = name
    for l in case["link_types"]:
        if l["id"] in labels: l["label"] = labels[l["id"]]
    for fid, name in s.get("rename", {}).items():
        next(c for c in case["cards"] if c["id"] == fid)["name"] = name
    for fid, name, icon in s["facts"]:
        case["cards"].append(fact(fid, name, icon))
    case["solution"]["panorama"] = s["panorama"]
    tl = [("%s: %s" % (t["time"], t["text"])) for t in case["reveal"]["timeline"]]
    story = (tl + [s["close"]])[-10:]
    guide["_panorama_story"] = story
    guide["faq"].append(FAQ)
