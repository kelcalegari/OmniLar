# Omni Lar — ponto de partida para a próxima sessão

Reescrito em 13/10/2026, no fim de uma sessão longa de correções, e atualizado no mesmo dia ao fim de uma segunda sessão (banco zerado, correções relatadas pelo dono no app, tempo real, categoria com dono e Ajustes refeitos). Atualizado em 15/10/2026 depois de implementadas as decisões pendentes do dono (as recomendações com ⭐). Substitui a versão anterior deste arquivo e o antigo `o_que_falta_fazer.md`, que foi apagado. Leia este arquivo inteiro antes de propor trabalho.

## Estado atual

- **Código:** `main` local e `origin/main` sincronizadas, com as decisões de 15/10/2026 (merge da branch `feat/decisoes-recomendadas`). Confira com `git log --oneline -5` e `git status`.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`, acessível pelo conector do Supabase):** migrations 0001 a 0070 aplicadas (as 0059, 0060 e 0061 em 15/10/2026; as 0062 e 0063 em 16/10/2026, antes do merge do código; as 0064 a 0066, das notificações, em 16/10/2026 a partir da branch `feat/notificacoes`, ainda sem merge: o app antigo continua funcionando, só não tem o sino; a 0067, das caixinhas, a 0068, do painel administrativo (conta nova passa a esperar aprovação), e a 0069, dos planos Free e Premium, em 16/10/2026; a 0070, do agendador das notificações, em 16/10/2026 a partir da branch `feat/notificacoes-agendador`, com o job do `pg_cron` ligado). No histórico de migrations do Supabase constam só as 0022 a 0027 e as 0030 a 0070; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor. A próxima migration é a 0071.
- **Edge Functions:** `capture-read` versão 8 e `assistant` versão 5, ambas com `verify_jwt=true` e exigindo usuário logado que more na casa. `notify` versão 1 (16/10/2026), com `verify_jwt=false`: chamada pelo banco, não recebe dados e envia os push pendentes pelo FCM; precisa dos secrets `FCM_SERVICE_ACCOUNT` e `FCM_PROJECT_ID` (o dono configura; sem eles responde "FCM_SERVICE_ACCOUNT não configurado" e os avisos ficam só no sino).
- **Site:** publicado em https://omnilar.web.app (Firebase Hosting, projeto `omnilar-ef002`, 16/10/2026). Para publicar de novo: `bash scripts/publicar_web.sh` (análise, testes, build e deploy), com o Firebase CLI logado na conta dona do projeto.
- **Qualidade:** `flutter analyze` com 0 erros e 0 warnings, e 544 testes passando (16/10/2026). Os testes automatizados rodam só contra os datasources mock (modo demo); nenhum roda contra o Supabase.
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
- **Decisões de 14/10/2026, implementadas em 15/10/2026 (recomendações ⭐):**
  - Selo do Fôlego fora do ciclo atual mostra a situação do ciclo ("Fechado" ou "Em aberto"); no ciclo atual continua a saúde do caixa.
  - Cartão da despesa em tela estreita: valor e "Pagar" descem para uma segunda linha.
  - Revisão do escâner: nota e cupom escolhem "Já paguei" (data da compra editável) ou "A pagar" (com vencimento; o meio é escolhido ao pagar).
  - Excluir categoria com lançamentos: pede para qual categoria mover os lançamentos (sem estado de arquivada).
  - "Gasto variável": interruptor no cadastro da categoria; sem escolha, vale a adivinhação pelo nome.
  - Tempo real também para aportes, empréstimos (e parcelas) e caixinhas.
  - Relatórios com o atalho "Voltar ao ciclo atual" e o esmaecimento na troca de ciclo.
  - Busca nos Ajustes abre direto a edição de categoria, forma de pagamento e conta fixa; o resto abre o grupo.
  - Série de eventos: o "repetir até" pode ser mudado ao editar "esta e as próximas" (ou todas).
  - Fila offline inclui "marcar item como comprado" e "concluir tarefa".
  - Ficam como estão: interruptores do Assistente (dependem de notificações), cópia local para abrir sem internet e o segundo fechamento de ciclo reaberto.

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
- **Tempo real:** tarefas, itens de compra, despesas, moradores, aportes, empréstimos (e parcelas) e caixinhas avisam os outros aparelhos (migrations 0015, 0050 e 0061). O `FinanceCubit` recarrega o ciclo e o `P2PCubit` relê os empréstimos pelo mesmo `watchHouseChanges` (cada assinatura abre o próprio canal); as parcelas não têm `house_id` e são assinadas sem filtro (o RLS entrega só as da casa). A agenda só atualiza ao recarregar.
- **Situação do ciclo no Fôlego:** `SettlementRepository.isCycleSettled` lê só o `status` em `settlements`; a Home consulta a cada carga do ciclo fora do ciclo atual.
- **Categoria:** `categories.is_variable_spend` (0060, nulo = adivinha pelo nome, `ExpenseCategory.countsAsVariableSpend`). Excluir categoria passa pela RPC `delete_category_moving_expenses` (0059), que move despesas, sub-itens, itens de compra, linhas e regras da importação e exclui na mesma transação; o rateio das despesas movidas não muda.
- **Escâner:** nota e cupom têm "Já paguei" / "A pagar" e data editável; `SmartScannerPage.initialProposal` existe só para os testes.
- **Série de eventos:** `seriesEndChange` (`event_recurrence.dart`) diz o que sai e o que entra ao trocar o "repetir até"; no Supabase as ocorrências novas são inseridas direto em `events` por quem edita (fica sendo o criador delas).
- **Caixinhas:** nascem zeradas (o saldo inicial vira depósito), toda casa nova recebe a "Reserva da Casa", e cada caixinha tem o histórico de entradas e saídas. O resgate exige o motivo e pode só sacar ou devolver ao ciclo em andamento (0062): o valor devolvido fica marcado em `savings_transactions.cycle_start_date` e entra no Caixa como dinheiro da casa, somado à sobra do ciclo anterior em `getOpeningBalance` (não vira aporte de ninguém). Ele só cobre falta de caixa: não abate os aportes sugeridos pelo planejador (`FinancialCycleSummary.rolledOverBalance`) nem o excedente do balde no fechamento com aportes fixos (`vaultReturns` no motor); no fechamento ele aparece como sobra e segue a opção escolhida para ela. O Fechamento mostra a parte "Devolvido das caixinhas" (`SettlementSummary.vaultReturns`). O depósito pode sair do Caixa do ciclo em andamento (0063), até o que as caixinhas devolveram a ele no ciclo; `getVaultReturnsForCycle` dá esse saldo (devoluções menos depósitos tirados do Caixa). Caixinha pode ser editada (nome, meta, prazo, ícone), excluída só zerada e sem acordo com o Lar ativo devolvendo para ela (`delete_savings_vault`), e transferir para outra (`transfer_between_vaults`, lançamentos ligados por `counterpart_vault_id`); depósito também exige motivo; prazo da meta mostra quanto guardar por mês e o ritmo; histórico relê sozinho, pagina e filtra; avisos `vault_movement` e `vault_goal_reached` (0067); `/caixinhas/{id}` abre o histórico.
- **Projetos compartilhados:** usam a casa e o usuário da sessão; o acerto divide entre os participantes (`project_settlement_service.dart`); há um diálogo para editar participantes e percentuais.
- **Agenda:** evento recorrente aceita "repetir até" (máximo de 200 ocorrências); tarefas e itens de compra podem ser editados.
- **Fila offline:** `lib/core/network/`. Entram na fila: lançar despesa, adicionar item de compra, criar evento, criar tarefa, editar tarefa, editar item de compra, criar empréstimo, marcar item como comprado e concluir tarefa. As duas últimas gravam o estado desejado (`setItemBought`, `setTaskCompleted`), para o reenvio não inverter de novo; sem conexão a tela atualiza o item ou a tarefa sozinha.
- **Formas de pagamento:** `payment_methods` tem duas colunas de dono (`owner_id` e `owner_member_id`), mantidas iguais por gatilho desde a migration 0046.

## Em aberto

### Limites conhecidos
- **Sem rede as listas não carregam:** o app não guarda cópia local. A fila offline só ajuda quando a conexão cai no meio do uso.
- **Fora da fila offline:** pagamento de parcela (de propósito) e exclusões.
- **Importar fatura ou extrato:** página própria em `/casa/importar` (cartão "Importar fatura ou extrato" na Casa, atalho em cada fatura e menu de cada cartão ou conta nos Ajustes; `/importar` redireciona para lá). Escolhe-se a origem e o arquivo OFX/CSV; o app compara com o que já foi lançado, e cada linha nova da Casa vira uma despesa. A confirmação grava tudo de uma vez e entra no histórico da página, de onde pode ser desfeita; a revisão em andamento fica guardada neste aparelho (ao voltar, "Revisão em andamento" oferece Retomar ou Descartar), mas não aparece em outro aparelho. A fatura de exemplo aparece só no modo demo.
- **Fatura de cartão:** só funciona para cartão com fechamento e vencimento cadastrados; gravar `paid_at` direto na tabela de despesas continua possível para qualquer morador.
- **Ciclo reaberto:** trocar a divisão do excedente do balde no segundo fechamento redistribui o excedente inteiro; parcelas e acordos do primeiro fechamento não são desfeitos.
- **Acordos de reposição criados antes da migration 0037** não têm caixinha de origem (não havia nenhum no banco).

### Registros da importação e dos boletos
- **Importação de fatura e extrato:** está em `main` (código em `lib/features/reconciliation/`). A confirmação e o desfazer usam as funções `confirm_import` e `undo_import` da migration 0052; as regras aprendidas ficam em `import_rules` (0053). PDF e foto são lidos pela função `import-read`, publicada no servidor (versão 1), que também sugere nome e categoria. Em 15/10/2026 o dono testou a importação com sessão real, inclusive a leitura por IA e arquivos de banco de verdade. O que falta está na seção "Situação atual" do `plano_importacao_conciliacao.md`. A seção 12 do plano guarda a discussão com o dono sobre a fatura na Casa: o agrupamento por fatura está feito; decidiu-se a alternativa C, "fatura como conta pendente" (seção 13), implementada com a migration 0054: compra no cartão nasce pendente, a fatura é paga com data e origem (titular ou Caixa) e o fechamento pergunta o que fazer com fatura em aberto, e a fatura pode ser paga inteira pelo titular ou pelo Caixa da Casa (migration 0055: em fatura importada paga pelo Caixa, o que não era da casa vira dívida com o Caixa; no modo demo, não).
- **Boleto pelo escâner e pagamento de contas pendentes:** em main (`feat/boleto-pending-payment`). O leitor `boleto_code.dart` lê código de barras (44 dígitos, câmera), linha digitável de 47 e conta de consumo de 48, conferindo os dígitos verificadores (o dono testou o leitor com boletos reais em 15/10/2026). O boleto nasce como conta a pagar com vencimento (editável; obrigatório quando o código não traz) e com a linha digitável guardada para copiar depois (coluna `barcode`, migration 0056); pode nascer já pago, com data e meio. Conta já prevista (mesmo código, ou vencimento próximo com o mesmo valor ou conta variável/recorrente) é atualizada em vez de duplicada. O "Pagar" de qualquer conta pendente pede dia e meio de pagamento: meio da casa = casa; meio com responsável = ele, reembolsado; cartão = vira compra da fatura (`pending_payment.dart`). O fechamento lista as contas pendentes do ciclo com o meio da baixa ou "levar para o próximo ciclo" (padrão: o meio que a conta já tinha, senão o da casa).
- **Código do boleto e meio da fatura:** em main. Apagar o campo do código ao editar remove o código. Conta pendente com código mostra "copiar" no card e no detalhe; o formulário de despesa tem o campo "Código do boleto", que confere o código, preenche o valor (se vazio) e o vencimento. A fatura do cartão (tela "Pagar fatura" e "Fatura já paga?" da importação) é paga escolhendo o meio: meio da casa = pago pelo Caixa; meio do titular = pago por ele, reembolsado. Meio de outro morador pagando a fatura de alguém não entra (`invoicePaymentOptions` em `pending_payment.dart`).
- **Código do boleto da fatura:** em main, migration 0057 (tabela `card_invoice_codes`: cartão + vencimento + linha digitável). A tela "Pagar fatura" informa, troca, apaga e copia o código; o card da fatura copia. O escâner reconhece o boleto da fatura em aberto (vencimento a até 5 dias, total até 30% diferente) e guarda o código nela, sem lançar despesa (`knownInvoicesFor`). A tela de pagar conta pendente também informa ou troca o código (`BillCodeField`). O formulário esconde o campo de código em compra no cartão. As faturas em aberto e os códigos não têm limite de data (só "Pagamentos registrados" mostra 62 dias).
- **Acesso à importação:** card "Importar fatura ou extrato" na Casa, acima do fechamento; atalho dentro de cada fatura; menu de cada cartão ou conta nos Ajustes. Saiu do Smart FAB e do painel geral dos Ajustes.

### Decisões pendentes do dono, com opções e recomendação (15/10/2026)
Levantadas em 15/10/2026, depois do merge das decisões anteriores. A numeração é a da lista apresentada ao dono naquele dia: os itens 6 (merge e push, feito), 7 (testes manuais, ver "Testes manuais pendentes"), 14 e 15 (importação e leitor de boleto, testados pelo dono) não pedem decisão. **Antes de começar, pergunte se ele segue as recomendações (marcadas com ⭐) ou se escolhe outra letra**, e peça aprovação antes de cada migration.

1. **Despesas excluídas ficam sem categoria ao excluir a categoria** (detalhe em "Pontas deixadas pelas decisões de 15/10/2026")
   - a) ⭐ Migration 0062: a função também move as despesas excluídas, com a mesma checagem de dono ou administrador
   - b) Manter (despesa excluída não aparece em lugar nenhum)
2. **"Repetir até" mudado com "só esta" não faz nada**
   - a) ⭐ Ao escolher "só esta" com a data final mudada, avisar que ela só vale para "esta e as próximas" ou "todas" e deixar trocar a escolha
   - b) Esconder o campo na edição "só esta" (difícil: o alcance só é escolhido ao salvar)
   - c) Manter
3. **Ocorrências criadas ao estender uma série ficam no nome de quem editou.** Efeito prático: o banco só deixa editar um evento a quem o criou ou a um administrador, e recusa sem avisar; quem criou a série deixa de conseguir editar essas ocorrências, sem erro na tela
   - a) ⭐ Migration com uma função do banco que estende ou encurta a série, criando as ocorrências no nome de quem criou a série (resolve o item 4 junto)
   - b) Manter
4. **Estender ou encurtar uma série não é tudo-ou-nada**
   - a) ⭐ Junto com o item 3, na mesma função do banco
   - b) Manter
5. **Agenda e histórico da caixinha sem tempo real**
   - a) Ligar nos dois
   - b) ⭐ Só na agenda, que é compartilhada pela casa (precisa de migration); o histórico da caixinha já é relido ao abrir
   - c) Manter
8. **Sem internet as listas não carregam**
   - a) Guardar uma cópia local (trabalho grande)
   - b) ⭐ Manter por enquanto (como decidido em 14/10)
9. **Pagar parcela e exclusões fora da fila offline**
   - a) ⭐ Pôr na fila só a exclusão de item de compra e de tarefa (excluir de novo não causa problema; comum no mercado sem sinal). Pagar parcela continua fora
   - b) Pôr na fila todas as exclusões (risco: a exclusão de uma despesa ser recusada no reenvio por estar num ciclo fechado)
   - c) Manter
10. **Fatura depende do fechamento e do vencimento cadastrados; qualquer morador grava `paid_at` direto**
    - a) ⭐ O cadastro de cartão passa a exigir os dois dias, e uma migration faz o banco só aceitar mudança de pagamento numa compra no cartão vinda da tela de pagar a fatura
    - b) Só exigir os dias no cadastro
    - c) Manter
11. **Ciclo reaberto redistribui o excedente inteiro no segundo fechamento**
    - a) ⭐ Manter (caso raro, como decidido em 14/10)
    - b) Recalcular só a diferença
12. **Acordos de reposição de antes da 0037 sem caixinha de origem**
    - a) ⭐ Tirar da lista: não existia nenhum no banco
    - b) Migration para preencher
13. **"A revisão da importação se perde ao sair da página"** — o texto estava desatualizado: a revisão já fica guardada no aparelho (Retomar ou Descartar); só não passa para outro aparelho. O texto em "Limites conhecidos" foi corrigido em 15/10
    - a) ⭐ Manter como está (só no aparelho)
    - b) Guardar a revisão no servidor, para aparecer em qualquer aparelho (precisa de migration)
16. **A troca de ciclo relê despesas e aportes duas vezes**
    - a) Cortar a leitura repetida agora
    - b) ⭐ Só se a troca parecer lenta para o dono
17. **Lista de moradores desatualizada no formulário de despesa e na agenda**
    - a) ⭐ Conferir as duas telas e fazê-las usar a lista que já atualiza em tempo real
    - b) Manter
18. **Conferência do banco contra as migrations (regras de acesso e índices)**
    - a) ⭐ Comparar regras de acesso e índices com as migrations e rodar o relatório de alertas do Supabase (só leitura); se houver diferença, trazer a correção para aprovação
    - b) Manter
19. **Telas sem teste automatizado** (participantes de projeto, "repetir até", dia de início do ciclo, histórico da caixinha, fechar compra)
    - a) ⭐ Escrever testes de tela para as cinco
    - b) Manter

Ordem sugerida, se ele seguir as recomendações: 12, 1, 2, 17, 9, 19, 3 e 4 juntos, 5, 10 e 18. Precisam de migration o 1, o 3 com o 4, o 5 e o 10 (e o 18, só se houver diferença). Os itens 8, 11, 13 e 16 ficam como estão.

### Pontas deixadas pelas decisões de 15/10/2026
- **Excluir categoria deixa sem categoria as despesas já excluídas:** a função `delete_category_moving_expenses` (0059) roda com as permissões de quem chama, e o RLS esconde despesas com `deleted_at`; ao excluir a categoria, a chave estrangeira põe `category_id` nulo nelas. Não aparece no app (despesa excluída nunca é restaurada). Correção proposta: migration 0062 com a função em `security definer`, mantendo a checagem `is_house_admin`.
- **"Repetir até" com "só esta":** a data nova é aceita sem aviso e não muda nada; só vale para "esta e as próximas" e "todas".
- **Ocorrências criadas ao estender uma série** ficam com `created_by` de quem editou, não de quem criou a série.
- **Estender ou encurtar uma série não é atômico:** são várias gravações seguidas do app (como já era a edição de série); uma queda no meio deixa a série pela metade.
- **Sem tempo real:** agenda e histórico da caixinha só atualizam ao recarregar (o saldo da caixinha já atualiza).

### Pontas pequenas, nunca tratadas
- **Troca de ciclo:** o resumo do ciclo ainda relê despesas e aportes por dentro; cortar isso é o próximo passo se a troca parecer lenta.
- **Lista de moradores desatualizada** depois que alguém entra na casa: corrigido nos Ajustes e, pelo tempo real, no estado financeiro; outras telas (formulário de despesa, agenda) não foram conferidas.
- **Conferência do banco contra as migrations:** gatilhos e funções foram conferidos e batem (só faltava um gatilho da 0017, criado na 0046), e todas as tabelas têm RLS ligado. Não foi conferido o conteúdo das regras de acesso nem os índices; como as migrations 0001 a 0021 foram aplicadas à mão, pode haver outra diferença.
- **Telas novas sem teste automatizado:** diálogo de participantes de projeto, "repetir até" do evento, diálogo do dia de início do ciclo, histórico da caixinha e diálogo de fechar compra. A regra de cada uma tem teste; a tela não.

## Testes manuais pendentes

Os roteiros anteriores foram executados pelo dono até 14/10/2026. Ficam aqui só os do que entrou depois.

### Decisões implementadas em 15/10 (migrations 0059 a 0061)
- **Selo do Fôlego:** num ciclo passado já fechado aparece "Fechado"; num não fechado (ou futuro), "Em aberto"; no ciclo atual, a saúde do caixa.
- **Cartão da despesa no celular:** numa conta a pagar, valor e "Pagar" ficam numa segunda linha, sem apertar o título.
- **Escâner (nota ou cupom):** trocar a data; escolher "A pagar" e conferir que a despesa nasce pendente, com o vencimento escolhido.
- **Excluir categoria com lançamentos** (como dono ou administrador): escolher a categoria de destino; as despesas, inclusive de ciclo fechado, aparecem nela. Como morador comum, a exclusão é recusada e nada muda.
- **Gasto variável:** desligar em "Supermercado" e ligar noutra categoria; o Planejamento de Aportes passa a estimar só a ligada.
- **Tempo real:** com dois aparelhos abertos, registrar um aporte, pagar uma parcela e depositar numa caixinha; o outro aparelho atualiza sozinho (Home e Empréstimos).
- **Relatórios:** ir a outro ciclo, aparece "Voltar ao ciclo atual"; o conteúdo esmaece enquanto carrega.
- **Busca nos Ajustes:** buscar uma categoria, uma forma de pagamento e uma conta fixa; cada uma abre direto a edição.
- **Série de eventos:** editar "esta e as próximas" encurtando o "repetir até" (as ocorrências depois somem) e estendendo (as que faltam aparecem, com os mesmos participantes).
- **Fila offline:** sem internet, marcar um item como comprado e concluir uma tarefa; ao voltar a conexão, conferir no outro aparelho.

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
| 0059 | Excluir categoria movendo os lançamentos para outra (`delete_category_moving_expenses`) |
| 0060 | Interruptor "gasto variável" na categoria (`categories.is_variable_spend`) |
| 0061 | Tempo real para aportes, empréstimos, parcelas e caixinhas |
| 0062 | Resgate de caixinha devolvido ao ciclo e motivo obrigatório |
| 0063 | Depósito em caixinha tirando do Caixa do ciclo |
| 0064 | Base das notificações: colunas novas, tokens, preferências, `enqueue_notification`, tempo real (branch `feat/notificacoes`) |
| 0065 | Gatilhos das notificações na hora: empréstimos, fechamento, tarefa atribuída e agenda (branch `feat/notificacoes`) |
| 0066 | Envio do push: `pg_net`, `claim_pending_notifications` e chamada da função `notify` (branch `feat/notificacoes`) |
| 0067 | Caixinhas: prazo da meta, exclusão segura, transferência, motivo no depósito e avisos |
| 0068 | Painel administrativo, fase A: administradores, status da conta, aprovação e funções do painel |
| 0069 | Painel administrativo, fase B: planos Free e Premium, limites e troca de plano |
| 0070 | Agendador das notificações: `pg_cron`, lembretes de contas, faturas, ciclo, empréstimos, tarefas, agenda e conta, e liberação do push segurado (branch `feat/notificacoes-agendador`) |

## Documentos relacionados

- `fechamento_no_banco.md`: o trabalho adiado de levar o cálculo do fechamento para o banco.
- `plano_notificacoes.md`: plano das notificações (estrutura, catálogo e decisões pendentes). Fica para depois das pendências deste arquivo.
- `plano_painel_admin.md`: painel administrativo (aprovação de contas novas, planos Free e Premium, visão geral do app). Revisto em 16/10/2026, com as decisões do dono tomadas (todas as recomendações; o PDF dos relatórios fica liberado no Free): com o site aberto, a fase A (base, aprovação e painel parte 1) passa na frente; os planos (fase B) ficam para depois.
- `plano_importacao_conciliacao.md`: plano da importação de fatura e conciliação, com o que já foi feito e o que falta.
- `arquitetura_tecnica.md` e os `modulo_*.md`: especificação original de cada módulo. Podem divergir do que está implementado; em caso de dúvida, vale o código.
- `plano_diretor_unificado.md` e `README_documento_mestre.md`: visão geral do produto.
