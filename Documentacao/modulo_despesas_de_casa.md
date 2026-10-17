> **Especificação original (06/10/2026).** Escrita antes do código. O que foi feito pode ser diferente: em caso de dúvida vale o código. O estado atual está em [plano_diretor_unificado.md](plano_diretor_unificado.md) e [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md).

Documentação Funcional: Módulo de Despesas da Casa
1. Visão Geral e Propósito
   Este módulo atua como o cérebro financeiro da residência. Ele substitui a lógica exaustiva de "dividir notinha por notinha" pelo conceito de Caixa da Casa (Fundo Comum). O sistema gerencia as contas recorrentes e despesas avulsas com base no Ciclo Financeiro real da família (quando o dinheiro entra vs. quando as contas vencem) e oferece flexibilidade total na divisão dos custos através de três modelos de rateio, garantindo que o orçamento seja justo e sem atritos.
2. Conceitos Essenciais
   2.1. O "Caixa da Casa" (Conta Conjunta Virtual)
   O sistema funciona como um "balde financeiro". O casal faz aportes (depósitos) para encher esse balde. Todas as despesas da casa retiram água desse balde, sem gerar dívidas fragmentadas entre os parceiros a cada compra.
   2.2. O Ciclo Financeiro (Fluxo de Caixa Real)
   O mês no aplicativo segue a realidade da família (ex: do dia 05 ao dia 04 do mês seguinte). O dinheiro que entra no dia 05 (recebimento do salário) tem a missão exclusiva de cobrir tudo que vence nesse intervalo, projetando o fôlego financeiro para as contas que vencem mais para o final do ciclo (como a internet no dia 25).
   2.3. Cartão de Crédito e VR/VA (Agrupadores Temporais)
* Cartões de Crédito: São métodos de pagamento com tempo de "virada". O app sabe a data de fechamento e calcula sozinho se uma compra feita hoje consome o dinheiro do ciclo atual ou do ciclo do mês que vem.
* Vale-Refeição: É um Sub-Caixa (Fundo Comum) independente. Compras de categorias alimentícias debitam o saldo do VR primeiro, poupando o dinheiro da conta bancária principal.
4. Regras de Negócio Fundamentais
   RN01: Os Três Modelos de Rateio (Divisão de Despesas)
   O sistema oferece três formas complementares de dividir as responsabilidades, que podem ser configuradas como regras gerais da casa ou ajustadas compra a compra:
* Por Porcentagem (A Regra Proporcional):
    * Como funciona: A família define um peso relativo. Ex: Cris paga 60% e Kelvynn 40% dos custos da casa. O sistema faz a matemática em reais automaticamente em cada despesa.
* Por Valores Fixos (A Regra Nominal):
    * Como funciona: O usuário informa o valor exato em Reais. Usado quando a família opera com aportes fixos (Ex: O balde do mês custa R$ 5.000, Cris deposita R$ 3.000 e Kelvynn R$ 2.000) ou em despesas específicas onde um consumiu mais (Ex: Conta deu R$ 150, João paga R$ 50 e Maria paga R$ 100).
* Por Categoria (A Responsabilidade Dirigida):
    * Como funciona: A divisão é baseada na "etiqueta" da despesa, ignorando a porcentagem padrão da casa. O sistema atribui um "Dono" à categoria. Exemplo: A regra da casa é 50/50, mas a categoria "Carro" foi configurada como 100% do Cris. Quando uma despesa do posto de gasolina é lançada, o custo é alocado integralmente para o aporte do Cris.
      RN02: Pagamento Cruzado (Inteligência de Compensação)
      Se a regra diz que "Supermercado" é responsabilidade do Cris (Regra de Categoria), mas o Kelvynn passou o próprio cartão no caixa por praticidade, o sistema registra a despesa na casa, mas entende automaticamente que o Cris deve aquele valor exato ao Kelvynn no Acerto de Contas.
      RN03: Fechamento do Ciclo (Sobras e Faltas)
      No último dia do Ciclo, o sistema faz o balanço (Aportes vs. Despesas):
* Sobra: Vira "Saldo Acumulado" (Reserva de Emergência da casa) e rola para o próximo mês.
* Falta: O sistema emite uma "Chamada de Capital", solicitando um Pix extra do casal (dividido conforme a Regra de Rateio configurada) para cobrir o buraco.
  RN04: Provisionamento de Contas Futuras (Dinheiro Carimbado)
  Se a família está no dia 12 e tem R$ 1.000 no Caixa, mas há uma conta de Luz de R$ 200 vencendo no dia 25, o sistema informa que o Saldo Livre é de R$ 800. O dinheiro da luz fica bloqueado virtualmente para garantir a segurança da casa.
5. Descrição de Funcionalidades (Features)
* Gestor de Regras e Categorias: Painel de configuração onde a família escolhe o Rateio Padrão (Fixo ou Porcentagem) e cria as Categorias, podendo atribuir Donos exclusivos a elas.
* Automação de Assinaturas e Recorrentes: Contas fixas (Netflix, Internet) são geradas sozinhas. Contas variáveis (Luz, Água) criam um "card" aguardando o usuário digitar o valor do boleto daquele mês.
* Smart Launch (Lançamento Inteligente): O formulário de nova despesa aprende com o tempo. Ao digitar "Condomínio", ele preenche a categoria, a regra de rateio e a data de vencimento padrão.
* Relatórios Analíticos (Analytics): Visão mensal de gastos por Categoria, mostrando comparações de consumo ("A conta de luz subiu 15% este mês") e acompanhando orçamentos (Budgets) pré-definidos.
* Configuração do Ciclo: Definição do dia em que o mês financeiro "vira", acompanhando o recebimento do salário da família.
6. Experiência do Usuário (UX) e Navegação
   6.1. Dashboard Principal: A Linha do Tempo e o Fôlego
   A tela principal abandona a visão de "dividas" e foca na saúde do ciclo atual:
* O Termômetro de Fôlego: Um gráfico de barra sempre visível no topo da tela: "Caixa da Casa: R$ 800 Livres / R$ 200 Comprometidos em boletos a vencer".
* Timeline de Compromissos: Uma linha temporal com as datas de vencimento. Dia 10 (Cartão, Condomínio) aparece como um grande obstáculo, Dia 25 (Internet) como um obstáculo menor.
* Minhas Responsabilidades (To-Do List): Um alerta direcionado: "Kelvynn, seu aporte de R$ 2.000 para este ciclo está pendente."
  6.2. UX da Tela de Lançamento (A Adição Rápida)
  O fluxo de adicionar um gasto deve levar menos de 5 segundos:
* Passo 1: Digite o nome da despesa e o valor.
* Passo 2: Escolha a Categoria. (Se a categoria tiver um Dono, o app avisa: "Categoria Carro: Alocado 100% para Cris").
* Passo 3 (Opcional - Alterar Rateio): Caso queiram mudar a regra apenas para essa compra, clicam no botão "Dividir" e escolhem visualmente entre as opções: ( % ) Porcentagem, ( $ ) Valores Fixos ou ( 🏠 ) Padrão da Casa.
* Passo 4: Escolha como pagou (Cartão Nubank, VR, Pix).
  6.3. Feedback Positivo (Nudges)
* Pagamento com Benefícios: Ao usar o VR/VA para pagar um lanche: "Despesa lançada! O custo foi absorvido pelo Saldo VR. A conta principal segue intacta."
* Conquista do Ciclo: Ao fechar um ciclo com sobra financeira: "Parabéns! Vocês gastaram menos que o previsto. R$ 300 foram guardados no Fundo de Reserva da Casa. 🎉"


7. Ganchos de Captura Inteligente, Importação e IA
* Captura (📷): foto de boleto ou conta (luz, água) lê valor, vencimento e beneficiário e cria a conta variável pendente de valor. Também lê comprovantes de Pix para registrar aportes.
* Importação: a fatura do cartão importada substitui a estimativa no ciclo pelo valor real e alimenta o Termômetro de Fôlego. O cartão de uso misto usa "Rachar a Fatura" (módulo de Importação e Conciliação).
* Regras aprendidas: o Smart Launch e a importação compartilham as mesmas regras de estabelecimento para categoria, dono e rateio.
* IA: previsão de contas variáveis, alerta de variação ("a conta de luz está 40% acima da média") e detecção de cobrança duplicada.
* Assistente: consultas de saldo livre, comprometido e vencimentos, e lançamento por linguagem natural ("Lança R$ 80 de gasolina, categoria Carro"), sempre com confirmação.