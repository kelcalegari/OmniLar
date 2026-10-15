# Omni Lar — ponto de partida para a próxima sessão

Reescrito em 13/10/2026, no fim de uma sessão longa de correções, e atualizado no mesmo dia ao fim de uma segunda sessão (banco zerado, correções relatadas pelo dono no app, tempo real, categoria com dono e Ajustes refeitos). Substitui a versão anterior deste arquivo e o antigo `o_que_falta_fazer.md`, que foi apagado. Leia este arquivo inteiro antes de propor trabalho.

## Estado atual

- **Código:** `main` local e `origin/main` sincronizadas, diretório de trabalho limpo. Confira com `git log --oneline -5` e `git status`.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`, acessível pelo conector do Supabase):** migrations 0001 a 0058 aplicadas. No histórico de migrations do Supabase constam só as 0022 a 0027 e as 0030 a 0058; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor. A próxima migration é a 0059.
- **Edge Functions:** `capture-read` versão 8 e `assistant` versão 5, ambas com `verify_jwt=true` e exigindo usuário logado que more na casa.
- **Qualidade:** `flutter analyze` com 0 erros e 0 warnings, e 515 testes passando (14/10/2026). Os testes automatizados rodam só contra os datasources mock (modo demo); nenhum roda contra o Supabase.
- **Dados no banco:** em 13/10/2026 o dono apagou todos os dados de teste (todas as tabelas de `public` e as contas de login) e recomeçou do zero; a estrutura, as funções e o histórico de migrations não mudaram. Logo depois foi criada de novo a casa "Nossa Casa", com as contas novas de kelvynn e Cristiano; o dono já lançou algumas despesas de teste nela (entre elas a recorrente "Internet", todo dia 25). Em 14/10/2026 já havia 3 fechamentos de ciclo confirmados e 3 importações feitos pelo dono com sessão real.

## O ponto mais importante

**Os roteiros de teste manual foram executados pelo dono com sessão real até 14/10/2026.** O que muda depois disso continua sendo testado só no modo demo e em ensaio no banco com rollback; o dono testa no app, e qualquer relato de erro dele é prioridade. Os roteiros do que ainda não foi testado ficam em "Testes manuais pendentes", mais abaixo.

## Como trabalhar neste projeto

- **Idioma:** o dono escreve em português e quer respostas em português.
- **Git:** criar uma branch a partir da `main`, commitar nela e só fazer merge fast-forward na `main` e push quando o dono pedir. Perguntar antes de commitar, de fazer merge e de dar push.
- **Banco:** perguntar antes de aplicar qualquer migration ou alteração de dados no Supabase hospedado, toda vez. Migrations ficam em `supabase/migrations/`.
- **Validar SQL antes de aplicar:** rodar dentro de um bloco `DO` que termina em `RAISE EXCEPTION` com os resultados, o que desfaz tudo (rollback). Para simular um usuário: `set_config('request.jwt.claims', ...)` com o `sub` do usuário e `set local role authenticated`.
- **Conferir depois de aplicar:** comparar o `md5` do corpo da função no banco (`pg_proc.prosrc`, sem `\r`) com o do arquivo da migration.
- **Bloqueio do modo automático:** a ferramenta de aplicar migration às vezes é recusada pelo classificador de permissões. Quando acontecer, explicar ao dono; ele responde "Aplique" (costuma passar na segunda tentativa) ou cola o SQL no SQL Editor.
- **Contas e login:** não criar contas nem fazer login no Supabase hospedado. Fluxos que exigem sessão real são testados pelo dono no app.
- **Depois de mudar código que depende de migration:** a migration entra antes do push, ou junto, e o dono precisa reiniciar as instâncias abertas do app.
- **Não há Deno nem Supabase CLI na máquina.** As Edge Functions são publicadas pelo conector, enviando o conteúdo dos arquivos (inclusive os de `_shared`, com os mesmos nomes de pasta).
- **A migration 0024 (fuso horário) só pode rodar uma vez.**
- **Ids do modo demo** (`member_carlos`, `pm_caixa`, `cat_mercado` etc.) só existem no modo demo. O envio ao banco descarta o que não é UUID, então nunca usar um deles como valor de reserva num caminho que grava: sem forma de pagamento ou categoria da casa, a tela avisa em vez de inventar.

## Trabalho adiado por decisão do dono

**Levar o cálculo do fechamento do ciclo para o banco.** Hoje o app de quem fecha calcula tudo e o banco só confere o plano. Está descrito em `fechamento_no_banco.md` e fica para o final, antes de o app ter usuários de fora. Não trazer este item quando o dono perguntar se há pendências ou inconsistências; só tratar dele se ele pedir.

## Decisões do dono já tomadas

Para não perguntar de novo:

- **Dia de início 29, 30 ou 31:** em mês que não tem o dia, o ciclo começa no último dia do mês.
- **Trocar o dia de início do ciclo:** vale a partir do próximo ciclo. O ciclo em andamento termina no dia antigo, o seguinte é um ciclo de transição (de 15 a 45 dias) e depois dele vale o dia novo; os ciclos passados não mudam.
- **Aportes fixos de quem entra depois:** o valor é ajustado à mão; não há valor automático.
- **Rateio "Por categoria":** implementado.
- **Categoria com dono:** sobrepõe o rateio por porcentagem e os aportes fixos (a despesa é 100% do dono, cobrada por cima do aporte). Trocar o dono vale para as despesas novas e para as que ainda não entraram em fechamento; ciclo fechado e despesa de projeto não mudam.
- **Despesa recorrente:** as ocorrências são geradas no banco.
- **Acordo com o Lar pago fora do fechamento:** quem paga escolhe a caixinha que recebe o valor.
- **Reposição da Caixinha:** o pagamento volta sempre para a caixinha que cobriu.
- **"Devolver a sobra aos membros" com pagamento parcial ao Caixa:** continua recusado.
- **Super Pix não marcado como parcial:** tratado como pago.
- **Caixinha:** depósito e resgate saem sempre no nome de quem está logado. Chegou a ser escrita uma migration para depositar em nome de outro morador; foi descartada.
- **Item de compra "pessoal":** continua visível para todos; só o texto foi corrigido.
- **Fechar compra do mercado:** o dono dos itens pessoais abre em quem está logado e pode ser escolhido.
- **Excluir empréstimo:** só quem emprestou ou um administrador (no acordo com o Caixa, só o administrador), e só enquanto nada foi pago.
- **Despesa de projeto:** dividida entre os participantes do projeto, pelo percentual de cada um; não segue o rateio da casa.
- **Fila offline:** pagamento de parcela fica fora, de propósito; em edição simultânea vale a última que chegar.

## Como o sistema está montado hoje

Resumo dos mecanismos que mudaram nesta sessão, para localizar as coisas.

### Ciclo e fechamento
- **Calendário de ciclos:** `lib/core/domain/value_objects/cycle_schedule.dart` (`CycleSchedule`). A casa guarda as trocas de dia em `houses.cycle_day_schedule`; a troca passa pela RPC `change_house_cycle_start_day` e gravar o dia direto na tabela é recusado.
- **Motor de compensação:** `lib/features/settlement/domain/services/global_clearing_engine.dart`. No modelo de aportes fixos, sub-itens pessoais e despesas de responsável único são cobrados por cima do aporte, sem consumir o balde.
- **Fechamento atômico:** RPC `confirm_cycle_settlement` (versão atual na migration 0044). Guarda o fim do ciclo (`settlements.cycle_end_date`), usado pela trava de ciclo fechado (`is_date_in_closed_cycle`).
- **Retrato do fechamento:** `settlements.summary_snapshot`, gravado pela RPC `save_settlement_snapshot` logo depois de fechar; a tela do ciclo fechado é montada a partir dele (`settlement_summary_codec.dart`).
- **Despesa já acertada** (`settled_at`): não pode ser excluída nem mudar de valor ou de pagador; a correção é um lançamento de ajuste.
- **Acordos com o Lar:** parcela cobrada no fechamento entra no Caixa; reposição de caixinha (`p2p_loans.repay_to_vault_id`) volta para a caixinha. O depósito acontece por gatilho em `payment_allocations`.

### Lançamentos
- **Despesas de um morador só:** `exclusive_charges.dart` diz o que é cobrado por cima do aporte fixo (categoria com dono, sub-item pessoal); o motor do fechamento e o planejador usam a mesma regra. O gatilho `apply_category_owner_to_open_expenses` (migration 0051) reescreve o rateio das despesas em aberto quando o dono da categoria muda.
- **Regra única de lançamento:** `lib/features/finance/domain/services/expense_launch_defaults.dart` (pago do bolso, categoria e rateio), usada por assistente, mercado, importação de fatura e scanner. O formulário tem lógica própria com o mesmo resultado.
- **Gravações em uma transação:** `create_house_expense`, `create_p2p_loan`, `complete_shopping_trip`, `create_calendar_event` e `set_project_participants`. Todas rodam com as permissões de quem chama. Os dados são montados em `house_expense_payload.dart` e `p2p_loan_payload.dart`.
- **Despesa recorrente:** RPC `generate_recurring_expenses`, chamada ao abrir o ciclo atual ou um futuro, no máximo três meses à frente (migration 0049). A série é a primeira despesa (matriz) mais as ocorrências ligadas por `recurring_series_id`; `is_active = false` na matriz encerra a série.
- **Planejador de aportes da Home:** `cycle_funding_estimator.dart`, com a mesma conta do fechamento.

### Demais
- **Resultado das gravações:** os métodos de escrita do `FinanceCubit`, as tarefas do `CalendarCubit` e o `ShoppingCubit` devolvem `true` ou `false`; as telas esperam a resposta e mostram o resultado com `showSaveFeedback` (`lib/core/widgets/save_feedback.dart`). Formulário de despesa, de tarefa e de aporte ficam abertos quando a gravação falha. Eventos da agenda avisam por exceção (`addEvent`, `updateEvent`, `deleteEvent` relançam o erro).
- **Despesa de projeto:** o formulário grava sem rateio da casa (`SplitRule.percentage(null)`, sem linhas em `split_rules`) e sem aplicar o dono da categoria; o acerto do projeto usa os percentuais dos participantes. Mover uma despesa para dentro ou para fora de um projeto refaz o rateio.
- **Item de compra** não tem categoria: a compra fechada vira uma despesa na categoria de mercado da casa.
- **Participantes de evento:** editar um evento grava a lista inteira; quem foi desmarcado sai de `event_participants`.
- **Ajustes:** quatro grupos (Casa, Divisão das despesas, Pagamentos e contas, Aplicativo). No celular e no tablet o índice abre uma página por grupo; a partir de 1024 px os grupos ficam à esquerda e o conteúdo ao lado. Moradores e convites, categorias, modelo de rateio, formas de pagamento e contas fixas ficam dentro da página, assim como a chave de IA, o tema e a auditoria (a chave de IA e a auditoria usam o parâmetro `embedded`). A importação de fatura tem página própria (`/importar`): nos Ajustes ela aparece no menu de cada cartão ou conta, e o resultado da busca leva direto a ela. Só ciclo, chave Pix e perfil abrem janela (formulários curtos). Os interruptores "Assistente Ativo", "Alertas Proativos" e "Horário Silencioso" foram removidos: não gravavam nada. O código de convite só é criado quando o dono ou um administrador toca em "Gerar código de convite". O editor do rateio guarda a edição em variáveis do método que o cria, por isso é mantido pelo `_KeptEditor` e só é recriado quando moradores, categorias ou o modelo mudam. A busca do índice ignora acentos e acha as opções (por título ou sinônimo) e o que a casa cadastrou: moradores, categorias, formas de pagamento e contas fixas. O índice e o esqueleto ficam em `settings_page.dart`; o conteúdo dos grupos, em `settings_groups.dart`.
- **Tempo real:** tarefas, itens de compra, despesas e moradores avisam os outros aparelhos (migrations 0015 e 0050). Despesas e moradores recarregam o ciclo pelo `FinanceCubit` (`watchHouseChanges`); aportes, empréstimos, agenda e caixinhas só atualizam ao recarregar.
- **Caixinhas:** nascem zeradas (o saldo inicial vira depósito), toda casa nova recebe a "Reserva da Casa", e cada caixinha tem o histórico de entradas e saídas.
- **Projetos compartilhados:** usam a casa e o usuário da sessão; o acerto divide entre os participantes (`project_settlement_service.dart`); há um diálogo para editar participantes e percentuais.
- **Agenda:** evento recorrente aceita "repetir até" (máximo de 200 ocorrências); tarefas e itens de compra podem ser editados.
- **Fila offline:** `lib/core/network/`. Entram na fila: lançar despesa, adicionar item de compra, criar evento, criar tarefa, editar tarefa, editar item de compra e criar empréstimo.
- **Formas de pagamento:** `payment_methods` tem duas colunas de dono (`owner_id` e `owner_member_id`), mantidas iguais por gatilho desde a migration 0046.

## Em aberto

### Limites conhecidos
- **Sem rede as listas não carregam:** o app não guarda cópia local. A fila offline só ajuda quando a conexão cai no meio do uso.
- **Fora da fila offline:** pagamento de parcela (de propósito), marcar item como comprado, concluir tarefa e exclusões.
- **Importar fatura ou extrato:** página própria em `/casa/importar` (cartão "Importar fatura ou extrato" na Casa, atalho em cada fatura e menu de cada cartão ou conta nos Ajustes; `/importar` redireciona para lá). Escolhe-se a origem e o arquivo OFX/CSV; o app compara com o que já foi lançado, e cada linha nova da Casa vira uma despesa. A confirmação grava tudo de uma vez e entra no histórico da página, de onde pode ser desfeita; a revisão em si não é guardada e se perde ao sair da página. A fatura de exemplo aparece só no modo demo.
- **Série de eventos já criada** não pode ser estendida nem encurtada; só excluindo "esta e as próximas" e criando de novo.
- **Fatura de cartão:** só funciona para cartão com fechamento e vencimento cadastrados; gravar `paid_at` direto na tabela de despesas continua possível para qualquer morador.
- **Ciclo reaberto:** trocar a divisão do excedente do balde no segundo fechamento redistribui o excedente inteiro; parcelas e acordos do primeiro fechamento não são desfeitos.
- **Acordos de reposição criados antes da migration 0037** não têm caixinha de origem (não havia nenhum no banco).

### Oferecido ao dono e ainda sem decisão
Itens levantados na segunda sessão de 13/10; ele não pediu nenhum. Perguntar antes de fazer.
- **Selo "Saudável"** do cartão do Fôlego continua aparecendo em ciclo passado e vazio.
- **Cartão da despesa em tela estreita:** não estoura mais, mas fica apertado; a opção é passar o valor e o "Pagar" para uma segunda linha.
- **Revisão do scanner:** título e categoria são editáveis; data e status não (sai sempre como pago, na data do documento). O pedido do dono foi "alterar cadastro", entendido como categoria.
- **Excluir categoria com lançamentos:** hoje é recusado. A alternativa é arquivar (some das escolhas, continua nas despesas antigas).
- **Planejamento de Aportes:** "variável" é toda categoria cujo nome contém mercado, feira, luz, energia, água ou gás. Conta recorrente de valor fixo já conta como fixa, mas uma despesa avulsa numa dessas categorias (ex.: condomínio em "Contas (Luz, Água, Internet)") ainda entra como variável.
- **Tempo real** para aportes, empréstimos, agenda e caixinhas.
- **Relatórios:** tem as próprias setas de ciclo, sem o atalho "voltar ao ciclo atual" nem o esmaecimento na troca.
- **Troca de ciclo:** o resumo do ciclo ainda relê despesas e aportes por dentro; cortar isso é o próximo passo se a troca parecer lenta.
- **Busca nos ajustes:** leva até o grupo, não até o item.
- **Assistente:** "Assistente Ativo", "Alertas Proativos" e "Horário Silencioso" eram controles de enfeite e foram removidos; implementar de verdade é trabalho à parte.
- **Lista de moradores desatualizada** depois que alguém entra na casa: corrigido nos Ajustes e, pelo tempo real, no estado financeiro; outras telas (formulário de despesa, agenda) não foram conferidas.
- **Importação de fatura e extrato:** está em `main` (código em `lib/features/reconciliation/`). A confirmação e o desfazer usam as funções `confirm_import` e `undo_import` da migration 0052; as regras aprendidas ficam em `import_rules` (0053). PDF e foto são lidos pela função `import-read`, publicada no servidor (versão 1), que também sugere nome e categoria. Nada disso foi testado com conta real nem com arquivo de banco de verdade; a leitura por IA só foi conferida até a recusa de quem não está logado. O que falta está na seção "Situação atual" do `plano_importacao_conciliacao.md`. A seção 12 do plano guarda a discussão com o dono sobre a fatura na Casa: o agrupamento por fatura está feito; decidiu-se a alternativa C, "fatura como conta pendente" (seção 13), implementada com a migration 0054: compra no cartão nasce pendente, a fatura é paga com data e origem (titular ou Caixa) e o fechamento pergunta o que fazer com fatura em aberto, e a fatura pode ser paga inteira pelo titular ou pelo Caixa da Casa (migration 0055: em fatura importada paga pelo Caixa, o que não era da casa vira dívida com o Caixa; no modo demo, não).
- **Boleto pelo escâner e pagamento de contas pendentes:** em main (`feat/boleto-pending-payment`). O leitor `boleto_code.dart` lê código de barras (44 dígitos, câmera), linha digitável de 47 e conta de consumo de 48, conferindo os dígitos verificadores (o cálculo só foi conferido contra um código real de conta de consumo). O boleto nasce como conta a pagar com vencimento (editável; obrigatório quando o código não traz) e com a linha digitável guardada para copiar depois (coluna `barcode`, migration 0056); pode nascer já pago, com data e meio. Conta já prevista (mesmo código, ou vencimento próximo com o mesmo valor ou conta variável/recorrente) é atualizada em vez de duplicada. O "Pagar" de qualquer conta pendente pede dia e meio de pagamento: meio da casa = casa; meio com responsável = ele, reembolsado; cartão = vira compra da fatura (`pending_payment.dart`). O fechamento lista as contas pendentes do ciclo com o meio da baixa ou "levar para o próximo ciclo" (padrão: o meio que a conta já tinha, senão o da casa).
- **Código do boleto e meio da fatura:** em main. Apagar o campo do código ao editar remove o código. Conta pendente com código mostra "copiar" no card e no detalhe; o formulário de despesa tem o campo "Código do boleto", que confere o código, preenche o valor (se vazio) e o vencimento. A fatura do cartão (tela "Pagar fatura" e "Fatura já paga?" da importação) é paga escolhendo o meio: meio da casa = pago pelo Caixa; meio do titular = pago por ele, reembolsado. Meio de outro morador pagando a fatura de alguém não entra (`invoicePaymentOptions` em `pending_payment.dart`).
- **Código do boleto da fatura:** em main, migration 0057 (tabela `card_invoice_codes`: cartão + vencimento + linha digitável). A tela "Pagar fatura" informa, troca, apaga e copia o código; o card da fatura copia. O escâner reconhece o boleto da fatura em aberto (vencimento a até 5 dias, total até 30% diferente) e guarda o código nela, sem lançar despesa (`knownInvoicesFor`). A tela de pagar conta pendente também informa ou troca o código (`BillCodeField`). O formulário esconde o campo de código em compra no cartão. As faturas em aberto e os códigos não têm limite de data (só "Pagamentos registrados" mostra 62 dias).
- **Acesso à importação:** card "Importar fatura ou extrato" na Casa, acima do fechamento; atalho dentro de cada fatura; menu de cada cartão ou conta nos Ajustes. Saiu do Smart FAB e do painel geral dos Ajustes.

### Pontas pequenas, nunca tratadas
- **Conferência do banco contra as migrations:** gatilhos e funções foram conferidos e batem (só faltava um gatilho da 0017, criado na 0046), e todas as tabelas têm RLS ligado. Não foi conferido o conteúdo das regras de acesso nem os índices; como as migrations 0001 a 0021 foram aplicadas à mão, pode haver outra diferença.
- **Telas novas sem teste automatizado:** diálogo de participantes de projeto, "repetir até" do evento, diálogo do dia de início do ciclo, histórico da caixinha e diálogo de fechar compra. A regra de cada uma tem teste; a tela não.

## Testes manuais pendentes

Os roteiros anteriores foram executados pelo dono até 14/10/2026. Ficam aqui só os do que entrou depois.

### Correção de inconsistências de 14/10 (commit `42f33fd`, migration 0058)
- **Compra no cartão:** deve nascer pendente, dentro da fatura, por qualquer tela (formulário, escâner, assistente, compra do mercado, importação).
- **Fatura e conta recorrente:** com uma conta recorrente no mesmo cartão e vencimento, pagar e desfazer o pagamento da fatura não devem mexer nela; o total em "Pagar fatura" não deve somá-la.
- **Falha ao gravar:** com a internet desligada, lançar uma despesa, uma tarefa e um aporte: a tela fica aberta, mostra o erro e não diz "sucesso".
- **"Reverter para pendente"** numa despesa paga: ela deve sair do ciclo da baixa.
- **Evento:** editar e desmarcar um participante; ele deve sumir da lista.
- **Despesa de projeto** numa categoria com dono: o acerto do projeto divide entre os participantes, sem cobrar tudo do dono. Mover uma despesa para dentro ou para fora de um projeto refaz o rateio.
- **Casa sem forma de pagamento** (ou sem categoria): fechar compra, escâner e assistente avisam em vez de gravar sem ela.
- **Busca nos Ajustes:** "importar" leva direto à página de importação.

## Migrations desta fase

Uma linha por migration, para saber onde está cada regra.

| Nº | O que faz |
|---|---|
| 0022 | Segurança: entrada na casa só por convite de uso único; perdão, renegociação e confirmação de transferência por RPC; Edge Functions autenticadas |
| 0023 | Percentuais normalizados e fechamento do ciclo atômico |
| 0024 | Correção de fuso horário (só pode rodar uma vez) |
| 0025 | `paid_at`: cada despesa conta em um ciclo só |
| 0026 | Reabrir ciclo: fechar de novo cobra só a diferença |
| 0027 | Exclusão de série por id e saldo de caixinha atômico |
| 0028 | Pagamento de fatura de cartão respeita ciclo fechado |
| 0029 | Conferência do plano de fechamento e proteção de despesa acertada |
| 0030 | Travas do fechamento (`settlement_data_version`, ciclo fechado) |
| 0031 | Sobra do fechamento: deixar no Caixa ou devolver aos moradores |
| 0032 | O que o Caixa deixou a receber, perdoou e recebeu de acordos |
| 0033 | Caixinha padrão ao criar a casa |
| 0034 | Fim do ciclo fechado com dia de início 29, 30 ou 31 |
| 0035 | Retrato do fechamento |
| 0036 | Geração das despesas recorrentes |
| 0037 | Pagamento de acordo com o Lar vai para uma caixinha |
| 0038 | Conta recorrente segue o dia de vencimento mais recente |
| 0039 | Caixinha nasce com saldo zero |
| 0040 | Despesa acertada não muda de valor nem de pagador |
| 0041 | Unifica categorias e formas de pagamento duplicadas |
| 0042 | Despesa, empréstimo e compra do mercado em uma transação |
| 0043 | Quem pode excluir um empréstimo |
| 0044 | Troca do dia de início do ciclo a partir do próximo ciclo |
| 0045 | Evento da agenda em uma transação |
| 0046 | Colunas de dono da forma de pagamento sempre iguais |
| 0047 | Troca dos participantes de um projeto |
| 0048 | Data final da repetição de um evento |
| 0049 | Contas recorrentes geradas até três meses à frente |
| 0050 | Tempo real para despesas e moradores |
| 0051 | Dono da categoria vale para as despesas em aberto |
| 0052 | Histórico da importação, confirmação atômica e desfazer |
| 0053 | Regras aprendidas da importação (`import_rules`) |
| 0054 | Compra no cartão fica pendente até a fatura ser paga; pagamento com a origem do dinheiro |
| 0055 | Fatura paga pelo Caixa: empréstimos passam ao Caixa e os gastos pessoais do titular viram dívida com ele |
| 0056 | Código de barras do boleto na despesa |
| 0057 | Código do boleto da fatura do cartão (`card_invoice_codes`) |
| 0058 | Compra no cartão nasce pendente também no banco; pagar e desfazer a fatura só mexem nas compras dela (sem projeto e sem recorrente) |

## Documentos relacionados

- `fechamento_no_banco.md`: o trabalho adiado de levar o cálculo do fechamento para o banco.
- `plano_importacao_conciliacao.md`: plano da importação de fatura e conciliação, com o que já foi feito e o que falta.
- `arquitetura_tecnica.md` e os `modulo_*.md`: especificação original de cada módulo. Podem divergir do que está implementado; em caso de dúvida, vale o código.
- `plano_diretor_unificado.md` e `README_documento_mestre.md`: visão geral do produto.
