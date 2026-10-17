# Omni Lar — ponto de partida para a próxima sessão

Reescrito em 13/10/2026, no fim de uma sessão longa de correções, e atualizado no mesmo dia ao fim de uma segunda sessão (banco zerado, correções relatadas pelo dono no app, tempo real, categoria com dono e Ajustes refeitos). Atualizado em 15/10/2026 depois de implementadas as decisões pendentes do dono (as recomendações com ⭐), e em 17/10/2026 com a nota fiscal pelo QR (`nfce-read`, caso de SC), a tela de espera, o ícone do Android e o modo demo. Substitui a versão anterior deste arquivo e o antigo `o_que_falta_fazer.md`, que foi apagado. Leia este arquivo inteiro antes de propor trabalho.

## Estado atual

- **Código:** `main` local e `origin/main` sincronizadas em 17/10/2026, com tudo das branches de decisões, notificações, login e `fix/push-registro`. Confira com `git log --oneline -5` e `git status`.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`, acessível pelo conector do Supabase):** migrations 0001 a 0071 aplicadas (as 0059, 0060 e 0061 em 15/10/2026; as 0062 e 0063 em 16/10/2026, antes do merge do código; as 0064 a 0066, das notificações, em 16/10/2026 a partir da branch `feat/notificacoes`, hoje já na `main`; a 0067, das caixinhas, a 0068, do painel administrativo (conta nova passa a esperar aprovação), e a 0069, dos planos Free e Premium, em 16/10/2026; a 0070, do agendador das notificações, em 16/10/2026 a partir da branch `feat/notificacoes-agendador`, com o job do `pg_cron` ligado; a 0071, que mantém `profiles.email` igual ao e-mail de acesso, em 16/10/2026 a partir da branch `feat/auth-conta-seguranca`). As 0072 a 0075 foram aplicadas em 17/10/2026, a partir da branch `feat/pendencias-recomendadas`. As 0076 a 0082 foram aplicadas em 17/10/2026 (ver [plano_proximas_frentes.md](plano_proximas_frentes.md), "Andamento"), com o `md5` das funções conferido. A Edge Function `delete-account` foi publicada (versão 1, `verify_jwt=true`). No histórico de migrations do Supabase constam só as 0022 a 0027 e as 0030 a 0075; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor. A 0083 (alertas de gasto por categoria) foi aplicada em 17/10/2026, a partir da branch `feat/ajustes-alertas`, com o `md5` conferido. A 0084 (marca "Pix enviado") foi aplicada em 17/10/2026, com o `md5` conferido. A próxima migration é a 0085.
- **Edge Functions** (versões conferidas em 17/10/2026)**:** `capture-read` versão 12, `assistant` versão 9 e `import-read` versão 5, todas com `verify_jwt=true`, exigindo usuário logado que more na casa e conta liberada, e com a cota de IA do plano. `nfce-read` versão 3 (16/10/2026), também com `verify_jwt=true` e usuário da casa: consulta a NFC-e na Sefaz pelo link do QR (ver "Escâner" em "Como o sistema está montado hoje"); é publicada com `nfce-read/index.ts`, `nfce-read/page.ts` e os arquivos de `_shared` que ela importa. `notify` versão 3 (16/10/2026), com `verify_jwt=false`: chamada pelo banco, não recebe dados e envia os push pendentes pelo FCM; os secrets `FCM_SERVICE_ACCOUNT` e `FCM_PROJECT_ID` foram configurados pelo dono (feito, informado em 17/10/2026). Conferência de 17/10/2026: o job `omnilar-notifications-hourly` do `pg_cron` roda sem erro e há um aparelho Android registrado em `device_tokens` (17/10, 01:14 UTC), mas os 21 avisos do banco estão como `skipped` porque foram criados antes desse registro. Nenhum push saiu ainda, então o envio pelo FCM só fica comprovado quando um aviso novo chegar ao aparelho. A branch `fix/push-registro` entrou na `main` em 17/10/2026 (pede a permissão de notificação do navegador dentro do toque; o Android release declara acesso à internet e o nome "Omni Lar"). Também na `main` desde 17/10/2026: `android/app/proguard-rules.pro`, aplicado no build de release, impede o R8 de remover as classes do Firebase (sem ele, o Firebase não inicializa no APK de release).
- **Site:** publicado em https://omnilar.web.app (Firebase Hosting, projeto `omnilar-ef002`; última publicação em 17/10/2026, com o compartilhar pelo menu do aparelho/WhatsApp, já testado no site). Para publicar: `bash scripts/publicar_web.sh` (análise, testes, build e deploy), com o Firebase CLI logado na conta dona do projeto.
- **APK Android:** `flutter build apk --release` gera `build/app/outputs/flutter-apk/app-release.apk` (cerca de 87 MB, não chega ao celular pelo envio de arquivos do Claude, que aceita até 30 MB). O release ainda é assinado com a chave de debug (`android/app/build.gradle.kts`): instala direto no celular, mas a Play Store não aceita. O último APK gerado (16/10/2026) também ficou sem os commits `0dd5ae5` e `0f5c296` e sem o compartilhar pelo menu do aparelho (17/10/2026).
- **Login e cadastro (16/10/2026):** confirmação de e-mail por código, "Esqueci minha senha", "Conta e segurança" (trocar e-mail e senha) estão prontos e configurados; "Continuar com Google" também está no código, mas escondido e adiado até a publicação (decisão do dono). As branches do login e das notificações já entraram na `main` (conferido em 17/10/2026). O que o dono precisa configurar no Supabase e no Google Cloud está em `Documentacao/plano_autenticacao.md`.
- **Qualidade:** `flutter analyze` com 0 erros e 0 warnings, e 636 testes passando (17/10/2026, branch `feat/ajustes-alertas`). Os testes automatizados rodam só contra os datasources mock (modo demo); nenhum roda contra o Supabase.
- **Dados no banco:** em 13/10/2026 o dono apagou todos os dados de teste (todas as tabelas de `public` e as contas de login) e recomeçou do zero; a estrutura, as funções e o histórico de migrations não mudaram. Logo depois foi criada de novo a casa "Nossa Casa", com as contas novas de kelvynn e Cristiano; o dono já lançou algumas despesas de teste nela (entre elas a recorrente "Internet", todo dia 25). Em 14/10/2026 já havia 3 fechamentos de ciclo confirmados e 3 importações feitos pelo dono com sessão real.

## O ponto mais importante

**Os roteiros de teste manual foram executados pelo dono com sessão real até 14/10/2026.** O que muda depois disso continua sendo testado só no modo demo e em ensaio no banco com rollback; o dono testa no app, e qualquer relato de erro dele é prioridade. Os roteiros do que ainda não foi testado ficam em "Testes manuais pendentes", mais abaixo.

## Como trabalhar neste projeto

- **Idioma:** o dono escreve em português e quer respostas em português.
- **Git:** criar uma branch a partir da `main`, commitar nela e só fazer merge fast-forward na `main` e push quando o dono pedir (o merge `3fe37f7`, do compartilhar, saiu por engano com commit de merge; o resultado é o mesmo). Perguntar antes de commitar, de fazer merge e de dar push.
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
- **Compartilhar (17/10/2026):** os botões de compartilhar abrem o menu do aparelho, com WhatsApp e cópia quando não há menu; o dono testou e aprovou no site.
- **Nota fiscal pelo QR (16 e 17/10/2026):** o visor lê boleto e QR da nota, e a foto também procura o QR antes da IA. O dono mora em SC, onde a consulta automática não existe: a nota de SC vai para a foto sem janela nem aviso (escolheu esta entre as alternativas). Não tentar passar pelo captcha da Sefaz nem usar serviço pago que faça isso. Erros aparecem em palavras simples, sem o detalhe técnico.

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
- **Tempo real:** tarefas, itens de compra, despesas, moradores, aportes, empréstimos (e parcelas) e caixinhas avisam os outros aparelhos (migrations 0015, 0050 e 0061). O `FinanceCubit` recarrega o ciclo e o `P2PCubit` relê os empréstimos pelo mesmo `watchHouseChanges` (cada assinatura abre o próprio canal); as parcelas não têm `house_id` e são assinadas sem filtro (o RLS entrega só as da casa). A agenda (eventos e participantes, 0074) tem assinatura própria no `CalendarCubit` (`watchEventChanges`).
- **Situação do ciclo no Fôlego:** `SettlementRepository.isCycleSettled` lê só o `status` em `settlements`; a Home consulta a cada carga do ciclo fora do ciclo atual.
- **Categoria:** `categories.is_variable_spend` (0060, nulo = adivinha pelo nome, `ExpenseCategory.countsAsVariableSpend`). Excluir categoria passa pela RPC `delete_category_moving_expenses` (0059), que move despesas, sub-itens, itens de compra, linhas e regras da importação e exclui na mesma transação; o rateio das despesas movidas não muda.
- **Escâner:** nota e cupom têm "Já paguei" / "A pagar" e data editável; `SmartScannerPage.initialProposal` existe só para os testes.
- **Nota fiscal pelo QR (NFC-e, 16/10/2026):** o QR da NFC-e só traz o link da consulta pública da Sefaz (o valor só vem no QR de contingência). A função `nfce-read` baixa essa página (só endereços `.gov.br`, seguindo redirecionamentos, 15 s por página) e lê o layout comum das Sefaz (`txtTit`, `Rqtd`, `RvlUnit`, `valor`, `totalNumb`) sem IA; layout desconhecido vai para a IA como texto, contando na cota diária. Na falha devolve um motivo (`unavailable`, `captcha`, `not_found`, `invalid_qr`, `quota`) com mensagem simples, e o detalhe técnico fica só no log da função. No app, `CaptureService.lookupNfce` monta a proposta (produto pesado vira 1 unidade pelo valor total) e `NfceLookupError` traduz o motivo. Fluxos:
  - **Visor ao vivo:** lê o código de barras do boleto e o QR da nota. QR de outros estados consulta a Sefaz; se ela não entrega, uma janela oferece "Tirar foto" (vai direto para a IA) ou "Digitar valor". O mesmo QR não é consultado de novo enquanto continua na frente da câmera.
  - **Santa Catarina:** a Sefaz de SC pede verificação de pessoa (Cloudflare Turnstile) antes de mostrar a nota, e o app não tenta passar por ela. A nota de SC é reconhecida pela chave (começa com 42, `CaptureService.photoOnlyState`): no visor abre a câmera direto, sem janela, com a dica "Fotografe o cupom inteiro"; na foto vai para a IA sem aviso.
  - **Tirar Foto / Galeria:** procura o QR da Sefaz na foto (`analyzeImage` do `mobile_scanner`, só no Android, iOS e macOS); se achar, tenta a Sefaz por até 10 s e, se não der, a mesma foto vai para a IA. Na web não há leitura de QR em foto: vai direto para a IA.
- **Tela de espera da conta (16/10/2026):** além do aviso em tempo real, consulta o status ao voltar ao app, a cada 15 s enquanto está aberta e pelo botão "Verificar agora" (o aviso em tempo real se perde com o app em segundo plano).
- **Ícone e nome do Android (16/10/2026):** o nome é "Omni Lar"; os ícones saem de `assets/launcher/` (quadrados com margem, fora do pacote do app) pelo `flutter_launcher_icons`. A tela de abertura do Android 12 ou mais novo ainda usa `icon_dark.png` (ver "Em aberto").
- **Compartilhar (17/10/2026):** os botões de compartilhar texto (resumo do fechamento, cobrança de uma transferência, rateio e cobrança do projeto, memória de cálculo da auditoria) usam `shareText` (`lib/core/utils/share_helper.dart`): abre o menu de compartilhamento do aparelho (Web Share API, em `share_web.dart`); fechar o menu sem escolher não mostra nada. Sem esse menu (Firefox no PC, por exemplo), oferece "Enviar no WhatsApp" (link `wa.me`, texto muito longo pode ser cortado) ou "Copiar texto". O menu só existe em HTTPS ou localhost. Chave Pix, linha digitável e código de convite continuam só copiando (`copyWithFeedback`).
- **Modo demo:** a conta do demo não é administradora (sem o atalho do painel; `/admin` volta para a casa).
- **Série de eventos:** `seriesEndChange` (`event_recurrence.dart`) diz o que sai e o que entra ao trocar o "repetir até"; no Supabase, editar "esta e as próximas" ou "todas" passa pela função `update_event_series` (0073), que grava o plano do app numa transação e cria as ocorrências novas no nome de quem criou a série.
- **Caixinhas:** nascem zeradas (o saldo inicial vira depósito), toda casa nova recebe a "Reserva da Casa", e cada caixinha tem o histórico de entradas e saídas. O resgate exige o motivo e pode só sacar ou devolver ao ciclo em andamento (0062): o valor devolvido fica marcado em `savings_transactions.cycle_start_date` e entra no Caixa como dinheiro da casa, somado à sobra do ciclo anterior em `getOpeningBalance` (não vira aporte de ninguém). Ele só cobre falta de caixa: não abate os aportes sugeridos pelo planejador (`FinancialCycleSummary.rolledOverBalance`) nem o excedente do balde no fechamento com aportes fixos (`vaultReturns` no motor); no fechamento ele aparece como sobra e segue a opção escolhida para ela. O Fechamento mostra a parte "Devolvido das caixinhas" (`SettlementSummary.vaultReturns`). O depósito pode sair do Caixa do ciclo em andamento (0063), até o que as caixinhas devolveram a ele no ciclo; `getVaultReturnsForCycle` dá esse saldo (devoluções menos depósitos tirados do Caixa). Caixinha pode ser editada (nome, meta, prazo, ícone), excluída só zerada e sem acordo com o Lar ativo devolvendo para ela (`delete_savings_vault`), e transferir para outra (`transfer_between_vaults`, lançamentos ligados por `counterpart_vault_id`); depósito também exige motivo; prazo da meta mostra quanto guardar por mês e o ritmo; histórico relê sozinho, pagina e filtra; avisos `vault_movement` e `vault_goal_reached` (0067); `/caixinhas/{id}` abre o histórico.
- **Projetos compartilhados:** usam a casa e o usuário da sessão; o acerto divide entre os participantes (`project_settlement_service.dart`); há um diálogo para editar participantes e percentuais.
- **Agenda:** evento recorrente aceita "repetir até" (máximo de 200 ocorrências); tarefas e itens de compra podem ser editados.
- **Fila offline:** `lib/core/network/`. Entram na fila: lançar despesa, adicionar item de compra, criar evento, criar tarefa, editar tarefa, editar item de compra, criar empréstimo, marcar item como comprado, concluir tarefa e excluir item de compra ou tarefa. Marcar e concluir gravam o estado desejado (`setItemBought`, `setTaskCompleted`), para o reenvio não inverter de novo; sem conexão a tela atualiza o item ou a tarefa sozinha.
- **Formas de pagamento:** `payment_methods` tem duas colunas de dono (`owner_id` e `owner_member_id`), mantidas iguais por gatilho desde a migration 0046.

## Em aberto

### Limites conhecidos
- **Cópia local (sem rede):** mostra o que foi lido com rede da última vez neste aparelho, só para leitura. Lançamento feito sem rede vai para a fila, mas a lista da Casa só o mostra depois que a fila envia (as compras e as tarefas já se atualizam na hora). Cada ciclo aberto com rede fica guardado; não há limpeza automática dos antigos (no navegador, o espaço é de alguns MB; se acabar, a cópia nova só deixa de ser gravada). Recorrentes, códigos das faturas, auditoria, fechamento, importação e IA precisam de rede.
- **Fora da fila offline:** pagamento de parcela (de propósito) e exclusões.
- **Importar fatura ou extrato:** página própria em `/casa/importar` (cartão "Importar fatura ou extrato" na Casa, atalho em cada fatura e menu de cada cartão ou conta nos Ajustes; `/importar` redireciona para lá). Escolhe-se a origem e o arquivo OFX/CSV; o app compara com o que já foi lançado, e cada linha nova da Casa vira uma despesa. A confirmação grava tudo de uma vez e entra no histórico da página, de onde pode ser desfeita; a revisão em andamento fica guardada neste aparelho (ao voltar, "Revisão em andamento" oferece Retomar ou Descartar), mas não aparece em outro aparelho. A fatura de exemplo aparece só no modo demo.
- **Ciclo reaberto:** trocar a divisão do excedente do balde no segundo fechamento redistribui o excedente inteiro; parcelas e acordos do primeiro fechamento não são desfeitos.
- **Consulta da NFC-e nunca testada com nota real:** só com chave falsa, que confirmou que as Sefaz de SP e RS respondem ao servidor e que a de SC exige captcha. A leitura do layout foi conferida com uma página montada a partir do layout conhecido, não com uma nota de verdade. A Sefaz de MG derrubou a conexão no teste feito da máquina do dono; não se sabe se bloqueia robôs. Também não se sabe se alguma Sefaz bloqueia o servidor das Edge Functions.
- **Chave de assinatura do Android:** o release usa a chave de debug. Criar a chave própria antes de distribuir o APK para mais gente; quem instalou com a chave de debug precisa desinstalar antes de instalar uma versão com a chave nova. O dono precisa guardar a chave e a senha.

### Registros da importação e dos boletos
- **Importação de fatura e extrato:** está em `main` (código em `lib/features/reconciliation/`). A confirmação e o desfazer usam as funções `confirm_import` e `undo_import` da migration 0052; as regras aprendidas ficam em `import_rules` (0053). PDF e foto são lidos pela função `import-read`, publicada no servidor (versão 1), que também sugere nome e categoria. Em 15/10/2026 o dono testou a importação com sessão real, inclusive a leitura por IA e arquivos de banco de verdade. O que falta está na seção "Situação atual" do `plano_importacao_conciliacao.md`. A seção 12 do plano guarda a discussão com o dono sobre a fatura na Casa: o agrupamento por fatura está feito; decidiu-se a alternativa C, "fatura como conta pendente" (seção 13), implementada com a migration 0054: compra no cartão nasce pendente, a fatura é paga com data e origem (titular ou Caixa) e o fechamento pergunta o que fazer com fatura em aberto, e a fatura pode ser paga inteira pelo titular ou pelo Caixa da Casa (migration 0055: em fatura importada paga pelo Caixa, o que não era da casa vira dívida com o Caixa; no modo demo, não).
- **Boleto pelo escâner e pagamento de contas pendentes:** em main (`feat/boleto-pending-payment`). O leitor `boleto_code.dart` lê código de barras (44 dígitos, câmera), linha digitável de 47 e conta de consumo de 48, conferindo os dígitos verificadores (o dono testou o leitor com boletos reais em 15/10/2026). O boleto nasce como conta a pagar com vencimento (editável; obrigatório quando o código não traz) e com a linha digitável guardada para copiar depois (coluna `barcode`, migration 0056); pode nascer já pago, com data e meio. Conta já prevista (mesmo código, ou vencimento próximo com o mesmo valor ou conta variável/recorrente) é atualizada em vez de duplicada. O "Pagar" de qualquer conta pendente pede dia e meio de pagamento: meio da casa = casa; meio com responsável = ele, reembolsado; cartão = vira compra da fatura (`pending_payment.dart`). O fechamento lista as contas pendentes do ciclo com o meio da baixa ou "levar para o próximo ciclo" (padrão: o meio que a conta já tinha, senão o da casa).
- **Código do boleto e meio da fatura:** em main. Apagar o campo do código ao editar remove o código. Conta pendente com código mostra "copiar" no card e no detalhe; o formulário de despesa tem o campo "Código do boleto", que confere o código, preenche o valor (se vazio) e o vencimento. A fatura do cartão (tela "Pagar fatura" e "Fatura já paga?" da importação) é paga escolhendo o meio: meio da casa = pago pelo Caixa; meio do titular = pago por ele, reembolsado. Meio de outro morador pagando a fatura de alguém não entra (`invoicePaymentOptions` em `pending_payment.dart`).
- **Código do boleto da fatura:** em main, migration 0057 (tabela `card_invoice_codes`: cartão + vencimento + linha digitável). A tela "Pagar fatura" informa, troca, apaga e copia o código; o card da fatura copia. O escâner reconhece o boleto da fatura em aberto (vencimento a até 5 dias, total até 30% diferente) e guarda o código nela, sem lançar despesa (`knownInvoicesFor`). A tela de pagar conta pendente também informa ou troca o código (`BillCodeField`). O formulário esconde o campo de código em compra no cartão. As faturas em aberto e os códigos não têm limite de data (só "Pagamentos registrados" mostra 62 dias).
- **Acesso à importação:** card "Importar fatura ou extrato" na Casa, acima do fechamento; atalho dentro de cada fatura; menu de cada cartão ou conta nos Ajustes. Saiu do Smart FAB e do painel geral dos Ajustes.

### Decisões de 15/10/2026, implementadas em 17/10/2026
O dono seguiu todas as recomendações (⭐) da lista de 15/10. O que foi feito, na branch `feat/pendencias-recomendadas` (merge na `main` em 17/10/2026), com as migrations 0072 a 0075 aplicadas e conferidas (`md5` das funções igual ao dos arquivos):

- **1. Excluir categoria:** `delete_category_moving_expenses` passou a `security definer` (0072) e move também as despesas excluídas; a checagem `is_house_admin` continua. Ensaio: morador comum recusado; nenhuma despesa excluída ficou sem categoria.
- **2. "Repetir até" com "só esta":** ao salvar "só esta" com a data final mudada, o formulário avisa ("A data final não muda só esta") e deixa "Escolher de novo" ou "Salvar só esta" (`add_event_sheet.dart`).
- **3 e 4. Série de eventos:** a edição de "esta e as próximas" ou "todas" vai inteira para a função `update_event_series` (0073), numa transação só. O app calcula o plano (`seriesEndChange`, horário de cada ocorrência, o que sai e o que entra) e a função grava. Ocorrências novas ficam no nome de quem criou a série; pode editar o criador ou um administrador. "Só esta" continua gravando direto em `events`.
- **5. Agenda em tempo real:** `events` e `event_participants` entraram no tempo real (0074). O `CalendarCubit` assina `watchEventChanges` e relê os eventos (espera 600 ms para juntar os avisos de uma série). O histórico da caixinha continua sendo relido ao abrir.
- **9. Fila offline:** exclusão de item de compra e de tarefa entra na fila (`deleteShoppingItem`, `deleteTask`); sem conexão o item sai da tela na hora. Pagar parcela e as demais exclusões continuam fora.
- **10. Fatura do cartão:** o banco exige dia de fechamento e de vencimento em todo cartão (`payment_methods_card_needs_days`, 0075; o formulário já pedia os dois). O gatilho `trg_house_expenses_card_payment_guard` recusa mudar `status` ou `paid_at` (e `paid_out_of_pocket` de compra já paga) numa compra no cartão gravada direto pelo app. As funções do banco (pagar ou desfazer fatura, fechamento) passam porque rodam como dona das tabelas. Compra que passa a ser no cartão numa edição volta a ficar pendente. "Reverter para pendente" numa compra no cartão agora mostra o erro: o caminho é desfazer o pagamento da fatura.
- **12.** Saiu da lista (não havia nenhum acordo assim).
- **17. Lista de moradores:** conferida, sem mudança. O formulário de despesa usa a lista do `FinanceCubit` (tempo real) e monta o rateio na hora de salvar; agenda e tarefas buscam os moradores no servidor a cada abertura.
- **18. Conferência do banco:** os índices batem com as migrations. Das regras de acesso, só as de editar e excluir forma de pagamento diferem: a parte de RLS da 0017 nunca foi aplicada, então valem as da 0001 (dono do cartão, quem criou ou administrador), mais restritas que as da 0017 (qualquer morador). Ficaram assim, de propósito. Relatório de alertas do Supabase: funções `security definer` de gatilho executáveis por `anon` (19) e por `authenticated` (54, quase todas RPCs de propósito), `pg_net` no schema `public`, proteção contra senha vazada desligada (ligar no painel do Supabase, em Auth), 54 regras de acesso que reavaliam `auth.uid()` por linha, 66 chaves estrangeiras sem índice e 13 índices não usados. Nada disso foi alterado; ver "Pontas pequenas".
- **19. Testes de tela:** histórico da caixinha (`test/features/finance/vault_history_dialog_widget_test.dart`), "repetir até" (`test/features/calendar/event_recurrence_end_widget_test.dart`), dia de início do ciclo (em `settings_page_test.dart`), participantes do projeto (`test/features/projects/project_participants_dialog_widget_test.dart`) e fechar compra (`test/features/shopping/finish_trip_dialog_widget_test.dart`). Dois deles ignoram só o erro de estouro de layout causado pela fonte de teste (letras quadradas).
- **Tela de abertura do Android 12+:** usa `assets/launcher/splash_android12.png` (1152×1152, logo inteiro dentro do círculo central).
- Ficaram como estão: 8 (cópia local), 11 (ciclo reaberto), 13 (revisão da importação só no aparelho) e 16 (leitura repetida na troca de ciclo).

### Pontas pequenas, nunca tratadas
- **Alertas do Supabase (17/10/2026):** revogar `execute` de `anon` nas funções de gatilho `security definer`; trocar `auth.uid()` por `(select auth.uid())` nas regras de acesso; criar índice nas chaves estrangeiras mais consultadas; ligar a proteção contra senha vazada (painel do Supabase). Nenhum é urgente com uma casa só; vale fazer antes de abrir o app para outras casas.

## Testes manuais pendentes

### Ajustes de 17/10 (branch `feat/ajustes-alertas`, ainda sem merge)
- **Busca nos lançamentos:** em "Gastos do Ciclo", buscar por nome, categoria, quem pagou, forma de pagamento ou valor ("312,40"); no computador, `Ctrl + F` leva ao campo.
- **Tabela no computador:** o botão ao lado da contagem de lançamentos troca para a tabela; tocar no título da coluna ordena; tocar na linha abre o detalhe.
- **Troca de ciclo:** deve ficar mais rápida (o resumo deixou de reler despesas e aportes).
- **Super Pix (0084):** num ciclo fechado, quem paga vê "Já mandei o Pix" e quem recebe, "Recebi o Pix"; depois da marca, o selo "Pix enviado em dd/MM" e quem recebe ganha o aviso. Sem a marca, o lembrete sai 2, 5 e 8 dias depois do fechamento.
- **Sem internet:** abrir o app uma vez com rede, depois sem rede (modo avião): abre direto na casa, com a faixa laranja "Sem internet — mostrando os dados de ..."; compras, tarefas, a Casa (ciclos já abertos com rede) e os empréstimos aparecem, e as mudanças entram na fila.
- **Alertas de gasto (0083, aplicada):** com ciclos anteriores lançados, uma categoria variável que passa de 90% e de 100% da média gera aviso; desligável em "Alertas de gasto".

### Próximas frentes (17/10/2026; migrations 0076 a 0082 aplicadas, `delete-account` publicada)
- **Primeiro ciclo:** na Home, nos Relatórios e no Fechamento a seta para trás para no primeiro ciclo da casa (na casa real, fevereiro de 2026, pela despesa de 04/02).
- **Preferências de notificação:** desligar o sino de um grupo e conferir que o aviso informativo daquele grupo não chega; ligar o horário silencioso.
- **Avisos novos:** um morador lança uma despesa, fecha uma compra e confirma uma importação; o outro recebe um aviso de cada (a despesa com a sua parte).
- **Resumo semanal:** domingo depois das 18h chega "Resumo da semana".
- **Aceite de empréstimo:** um lança que o outro deve; o devedor vê "Aguardando aceite", aceita (o credor recebe o aviso) ou recusa (o empréstimo some); o fechamento avisa e não cobra o não aceito.
- **Arrastar arquivo:** soltar um OFX ou PDF na página de importação, no navegador do computador.
- **`Ctrl + F`:** nos Ajustes, leva ao campo de busca.
- **Excluir conta:** só com uma conta de teste criada para isso (nunca com as contas reais): a prévia mostra a casa e os empréstimos; depois de excluir, a conta não entra mais e, na casa, aparece "Ex-morador".

Os roteiros anteriores foram executados pelo dono até 14/10/2026. Ficam aqui só os do que entrou depois.

### Decisões implementadas em 17/10 (migrations 0072 a 0075)
Reinicie o app (ou instale o APK novo) antes.
- **Excluir categoria** que tem despesa excluída: nada muda na tela; a exclusão continua funcionando.
- **"Repetir até" com "só esta":** mudar a data final e salvar "Apenas este evento" mostra o aviso; "Escolher de novo" volta à escolha.
- **Série estendida por outra pessoa:** quem criou a série estende o "repetir até" (ou um administrador estende a série de outro morador); depois, quem criou consegue editar as ocorrências novas.
- **Agenda em tempo real:** com dois aparelhos abertos, criar, editar e excluir um evento; o outro aparelho atualiza sozinho.
- **Fila offline:** sem internet, excluir um item de compra e uma tarefa; somem na hora e, ao voltar a conexão, somem no outro aparelho.
- **Compra no cartão:** "Reverter para pendente" numa compra no cartão paga mostra o aviso de usar a fatura; pagar e desfazer a fatura continuam funcionando.
- **Tela de abertura (Android 12+):** o logo aparece inteiro, sem corte.

### Nota pelo QR, tela de espera, ícone e demo (16 e 17/10/2026)
Reinicie o app (ou instale o APK novo) antes; o site já está com essas mudanças desde 17/10/2026.
- **QR de nota de SC no visor:** abre a câmera direto, sem janela; a foto vira uma proposta lida pela IA.
- **Foto de cupom de SC:** sem aviso; a revisão abre com os dados lidos pela IA.
- **QR de nota de outro estado** (SP ou RS, se houver um cupom): a revisão abre com loja, data, total e itens vindos da Sefaz. Se a Sefaz falhar, a janela mostra uma mensagem simples, sem código técnico.
- **Tela de espera:** com uma conta em análise aberta no celular, aprovar pelo painel; a tela muda em até 15 s, ou ao voltar para o app, ou pelo "Verificar agora".
- **Ícone e nome:** no celular aparecem "Omni Lar" e o logo inteiro (pode ser preciso desinstalar a versão antiga antes).
- **Modo demo:** os Ajustes não mostram "Administração do Omni Lar".

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
| 0071 | `profiles.email` igual ao e-mail de acesso (branch `feat/auth-conta-seguranca`) |
| 0072 | Excluir categoria move também as despesas excluídas (`delete_category_moving_expenses` em `security definer`) |
| 0073 | Edição de série de eventos numa transação (`update_event_series`), ocorrências novas no nome de quem criou a série |
| 0074 | Tempo real para eventos e participantes da agenda |
| 0075 | Cartão exige dias de fechamento e vencimento; pagamento de compra no cartão só pela fatura (`guard_card_purchase_payment`) |
| 0076 | Funções `security definer` fora do alcance de `anon` |
| 0077 | Regras de acesso com `(select auth.uid())` |
| 0078 | Índices nas chaves estrangeiras mais consultadas |
| 0079 | Resumo semanal |
| 0080 | Avisos de despesa lançada, compra fechada e importação confirmada |
| 0081 | Exclusão de conta: prévia, exclusão dos dados e situação "Excluída" |
| 0082 | Aceite do empréstimo pelo devedor |
| 0083 | Alertas de gasto por categoria (`proactive_alert`): 90% e 100% da média dos 3 ciclos anteriores |
| 0084 | Marca "Pix enviado" no Super Pix e lembrete até a marca |

## Documentos relacionados

A lista completa, com o papel de cada documento, está na seção 4 de `plano_diretor_unificado.md` (o painel de "onde estamos e o que falta"). Em resumo:
- `plano_diretor_unificado.md`: o que funciona, o que falta e para qual documento olhar.
- `README_documento_mestre.md`: visão do produto, glossário e regras transversais.
- `arquitetura_tecnica.md`: arquitetura proposta e, na seção 0, como ficou.
- `plano_notificacoes.md`, `plano_painel_admin.md`, `plano_autenticacao.md`, `plano_importacao_conciliacao.md` e `plano_relatorios_previa_ciclo.md`: andamento e decisões de cada frente.
- `fechamento_no_banco.md`: o trabalho adiado de levar o cálculo do fechamento para o banco.
- `modulo_*.md` e `integracao_modulo_financeiro.md`: especificação original de cada módulo; podem divergir do que está implementado, e em caso de dúvida vale o código.
