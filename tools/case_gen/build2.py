import warnings, glob, os; warnings.filterwarnings("ignore")
from kit import write, OUT
import s_solo, s_solo2, m_a, m_b
from guidekit import where, proves

TP = {
 "solo_bilhete": ("Plantado no grupo do time: a Lu é a única que pede calma ('somos um time ❤️') e é exatamente quem ganha a vaga. A chamada mostra que ela 'chegou' às 7h25, depois do bilhete. Segundo giro: a vítima também escondia um segredo, a recuperação.",
   [("0 a 3 min", "A capitã parece culpada pela briga no grupo.", "Onde a capitã estava quando o bilhete apareceu?"),
    ("3 a 6 min", "Aha: a Lu chegou tarde e quem ganha com a saída da Bia é ela.", "De onde vieram as letras recortadas?"),
    ("6 min em diante", "A ficha do técnico confirma o motivo.", "Que segredo da Bia a Lu usou?")]),
 "solo_muro": ("Plantado na lata de spray de papelaria (grafiteiro não usa), na pegada de raio 41 e na ocorrência de sexta. A live do Kevin (t+) só derruba a pista falsa. Segundo giro: a tranca dos fundos estava quebrada havia uma semana e ninguém consertou.",
   [("0 a 4 min", "A turma culpa o Kevin.", "O Kevin assina o que pinta? Esse recado tem assinatura?"),
    ("4 a 8 min", "Aha: a pegada e o tênis levam a um aluno, não a um grafiteiro.", "Quem perdeu um tênis respingado de vermelho?"),
    ("8 min em diante", "A ocorrência mostra o motivo; a live confirma o Kevin longe.", "Por que alguém escreveria 'ladrão de nota'?")]),
 "solo_vestiario": ("Plantado no cadeado aberto sem força (o ladrão conhecia o Gabriel), na chamada (quem saiu cedo) e no Gui consolando o amigo no grupo. O anúncio (t+) com o adesivo de leão fecha. Segundo giro: a testemunha, Pedro, também mentia, para esconder que matava aula.",
   [("0 a 4 min", "O preconceito aponta o Kauã.", "Como o tênis foi pago?"),
    ("4 a 10 min", "Aha 1: o segredo do cadeado é íntimo; o amigo de infância sabe.", "Quem saiu da aula antes das 10h?"),
    ("10 min em diante", "Aha 2: o papel com '0408' e o anúncio entregam o Gui.", "O que uma pessoa endividada faria com um celular caro?")]),
 "solo_invasao": ("Plantado em três detalhes físicos que parecem decoração: os cacos caídos para fora, a poeira grossa de dias e o alarme desligado com código. A vítima indignada é a autora. Segundo giro: o anúncio do cursinho (t+) mostra que o microscópio da escola trabalhava escondido havia semanas.",
   [("0 a 5 min", "A 'invasão' parece real; o zelador é suspeito.", "De que lado caíram os cacos?"),
    ("5 a 12 min", "Aha 1: o microscópio saiu na sexta, não no domingo.", "Quem assinou a ficha do armário?"),
    ("12 min em diante", "Aha 2: o código 07 é da professora; o anúncio dá o motivo.", "Quem ganha com o dinheiro do seguro?")]),
 "solo_taca": ("Plantado na comparação de duas pistas visuais (a alça lisa da vitrine e o amassado na foto de março) e numa frase do curador: a peça não tem taça. A encomenda 'para a peça' era mentira. Segundo giro: a Sofia percebeu a troca e ficou calada em troca de uma bolsa.",
   [("0 a 5 min", "O zelador, que limpa a vitrine, parece culpado.", "Quem pegou a chave na sexta?"),
    ("5 a 12 min", "Aha 1: existe uma réplica feita no teatro, encomendada por 'M.'.", "A peça dos 60 anos tem taça?"),
    ("12 a 20 min", "Aha 2: o caderno da chave e o cartão do antiquário apontam a vice-diretora.", "Para onde vai uma taça de prata roubada?"),
    ("20 min em diante", "O post do antiquário mostra o amassado. A Sofia conta o que escondeu.", "Ficar calada também é participar?")]),
 "solo_armacao": ("Plantado na própria denúncia (sabia o que e quando), no ranking (quem ganha a bolsa) e no 'que decepção' do Bento no grupo. O registro da rede (t+) confirma. Segundo giro: a monitora Mel vendeu a cópia, e a vítima, Davi, escondia uma monitoria paga.",
   [("0 a 5 min", "A mochila parece condenar o Davi.", "Onde o Davi estava enquanto a mochila ficou na sala?"),
    ("5 a 12 min", "Aha 1: o Davi tem sete testemunhas; o Bento ficou sozinho na sala.", "Quem ganha se o primeiro do ranking cair?"),
    ("12 a 20 min", "Aha 2: o bilhete 'valeu pela cópia, B.' liga a prova ao Bento.", "Como a prova saiu do laboratório?"),
    ("20 min em diante", "A rede mostra o celular do Bento mandando a denúncia.", "Por que alguém se faz de 'decepcionado'?")]),
}

EXTRA = {'cofre_formatura': {'c_dep_bia': 'Mostra o motivo da Lari (o rombo de R$ 800) e o silêncio da amiga.'}, 'conta_sem_rosto': {'c_dep_pedro': "Uma vítima pagou e mentiu; o recebedor 'C. Monteiro' aponta para um 'C.'."}, 'gabarito_vazado': {'c_dep_mari': 'O gabarito sempre vinha do @fantasma, não do Pedro.'}, 'garota_que_nao_existe': {'c_dep_ivo': "Só os titulares e o Léo ouviram a 'jogada 7': a Luiza é alguém de dentro.", 'c_dep_gabriel': "A Luiza perguntou da 'jogada 7', segredo do vestiário."}, 'solo_invasao': {'c_dep_theo': 'Havia uma pessoa DENTRO do laboratório, e um carro prata saiu sem pressa.'}, 'solo_taca': {'c_dep_jorge': 'A vice-diretora pegou a chave e mandou o zelador embora mais cedo.'}, 'solo_vestiario': {'c_recibo': 'Derruba a acusação contra o Kauã: o tênis veio da Bolsa Atleta.', 'c_dep_kaua': 'O Kauã explica o tênis e confirma que ficou na quadra.'}, 'urna_gremio': {'c_dep_bela': 'Até a vencedora estranhou tantos votos: a fraude não era dela.'}}
CASES = s_solo.SOLO_A + s_solo2.SOLO_B + m_a.MULTI_A + m_b.MULTI_B
for f in glob.glob(OUT + "*.json"): os.remove(f)
for case in CASES:
    g = case.pop("_guide"); g["proves"].update(EXTRA.get(case["id"], {}))
    tw, pc = (g.get("twist"), g.get("pacing")) if "twist" in g else TP[case["id"]]
    case["teacher_guide"] = {
        "summary": g["summary"], "twist": tw,
        "solution_steps": g["steps"],
        "pacing": [{"when": w, "aha": a, "if_stuck": q} for w, a, q in pc],
        "clue_map": [{"clue": c["id"], "where": where(case, c["id"]), "proves": proves(case, c["id"], g["proves"])} for c in case["clues"]],
        "red_herrings": g["red"], "faq": [{"q": q, "a": a} for q, a in g["faq"]], "talking_points": g["talk"]}
    write(case)
print("ok", len(CASES))
