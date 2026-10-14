# Omni Lar — ponto de partida para a próxima sessão

Reescrito em 13/10/2026, no fim de uma sessão longa de correções, e atualizado no mesmo dia ao fim de uma segunda sessão (banco zerado, correções relatadas pelo dono no app, tempo real, categoria com dono e Ajustes refeitos). Substitui a versão anterior deste arquivo e o antigo `o_que_falta_fazer.md`, que foi apagado. Leia este arquivo inteiro antes de propor trabalho.

## Estado atual

- **Código:** `main` local e `origin/main` sincronizadas, diretório de trabalho limpo. Confira com `git log --oneline -5` e `git status`.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`, acessível pelo conector do Supabase):** migrations 0001 a 0056 aplicadas. No histórico de migrations do Supabase constam só as 0022 a 0027 e as 0030 a 0056; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor. A próxima migration é a 0057.
- **Edge Functions:** `capture-read` versão 8 e `assistant` versão 5, ambas com `verify_jwt=true` e exigindo usuário logado que more na casa.
- **Qualidade:** `flutter analyze` com 0 erros (4 warnings antigos de import não usado) e 362 testes passando. Os testes automatizados rodam só contra os datasources mock (modo demo); nenhum roda contra o Supabase.
- **Dados no banco:** em 13/10/2026 o dono apagou todos os dados de teste (todas as tabelas de `public` e as contas de login) e recomeçou do zero; a estrutura, as funções e o histórico de migrations não mudaram. Logo depois foi criada de novo a casa "Nossa Casa", com as contas novas de kelvynn e Cristiano; o dono já lançou algumas despesas de teste nela (entre elas a recorrente "Internet", todo dia 25). Nunca houve um fechamento de ciclo confirmado com sessão real.

## O ponto mais importante

**Nada do que foi feito nesta sessão foi exercitado no app com sessão real.** Tudo passou por teste automatizado no modo demo e por testes de banco com rollback. O dono testa no app; quem continuar o trabalho deve tratar qualquer relato de erro dele como prioridade.

O que testar primeiro, depois de reiniciar por completo as instâncias abertas do app:

1. **Fechamento de ciclo de ponta a ponta**, com pagamento parcial e cobertura por caixinha. A função `confirm_cycle_settlement` foi recriada nas migrations 0037 e 0044 e só teve a sintaxe validada.
2. **Lançar despesa, criar empréstimo e fechar compra do mercado.** Os três passaram a ser uma chamada só ao banco (migration 0042). Repetir o lançamento de despesa com um morador comum.
3. **Criar evento na agenda**, com e sem repetição (migrations 0045 e 0048).
4. **Reabrir a tela do ciclo fechado** e conferir saldos, transferências e memória de cálculo (migration 0035).
5. **Despesa recorrente:** cadastrar e avançar para o ciclo seguinte (migrations 0036 e 0038).

Da segunda sessão de 13/10, o que mais depende de teste do dono:

1. **Copiar no navegador.** Não foi reproduzido: a hipótese é o site aberto por http fora de `localhost`, onde o navegador não deixa copiar. Entrou um plano B (`clipboard_helper.dart`) e a mensagem "copiado" só aparece se copiou. Falta o dono dizer se agora copia e por qual endereço abre o site.
2. **Tempo real de despesas e moradores** (migration 0050): só se confirma com dois aparelhos logados.
3. **Trocar o dono de uma categoria** (migration 0051): as despesas em aberto dela devem mudar de rateio; tirar o dono deve devolver ao percentual da casa.
4. **Ajustes novos:** índice de grupos, página por grupo no celular e duas colunas no PC, com edição dentro da página.

A lista completa de roteiros está em "Testes manuais pendentes", mais abaixo.

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
- **Ajustes:** quatro grupos (Casa, Divisão das despesas, Pagamentos e contas, Aplicativo). No celular e no tablet o índice abre uma página por grupo; a partir de 1024 px os grupos ficam à esquerda e o conteúdo ao lado. Moradores e convites, categorias, modelo de rateio, formas de pagamento e contas fixas ficam dentro da página, assim como a chave de IA, o tema, a auditoria e o atalho da importação de fatura (os três últimos widgets têm o parâmetro `embedded`). Só ciclo, chave Pix e perfil abrem janela (formulários curtos). Os interruptores "Assistente Ativo", "Alertas Proativos" e "Horário Silencioso" foram removidos: não gravavam nada. O código de convite só é criado quando o dono ou um administrador toca em "Gerar código de convite". O editor do rateio guarda a edição em variáveis do método que o cria, por isso é mantido pelo `_KeptEditor` e só é recriado quando moradores, categorias ou o modelo mudam. A busca do índice ignora acentos e acha as opções (por título ou sinônimo) e o que a casa cadastrou: moradores, categorias, formas de pagamento e contas fixas. O índice e o esqueleto ficam em `settings_page.dart`; o conteúdo dos grupos, em `settings_groups.dart`.
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
- **Mensagem de sucesso antes da hora:** várias telas mostram "adicionado com sucesso" sem esperar a gravação terminar; se der erro, o aviso aparece depois.
- **Importar fatura ou extrato:** página própria em `/casa/importar` (Smart FAB, Ajustes > Pagamentos e contas, e o menu de cada cartão ou conta). Escolhe-se a origem e o arquivo OFX/CSV; o app compara com o que já foi lançado, e cada linha nova da Casa vira uma despesa. A confirmação grava tudo de uma vez e entra no histórico da página, de onde pode ser desfeita; a revisão em si não é guardada e se perde ao sair da página. A fatura de exemplo aparece só no modo demo.
- **Série de eventos já criada** não pode ser estendida nem encurtada; só excluindo "esta e as próximas" e criando de novo.
- **Fatura de cartão:** só funciona para cartão com fechamento e vencimento cadastrados; gravar `paid_at` direto na tabela de despesas continua possível para qualquer morador.
- **Ciclo reaberto:** trocar a divisão do excedente do balde no segundo fechamento redistribui o excedente inteiro; parcelas e acordos do primeiro fechamento não são desfeitos.
- **Despesa de projeto** é lançada pelo formulário comum, que ainda grava o rateio da casa nela. O acerto do projeto ignora esse rateio, então o resultado está certo, mas o dado gravado não reflete a divisão real.
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
- **Boleto pelo escâner e pagamento de contas pendentes:** branch `feat/boleto-pending-payment`. O leitor `boleto_code.dart` lê código de barras (44 dígitos, câmera), linha digitável de 47 e conta de consumo de 48, conferindo os dígitos verificadores (o cálculo só foi conferido contra um código real de conta de consumo). O boleto nasce como conta a pagar com vencimento (editável; obrigatório quando o código não traz) e com a linha digitável guardada para copiar depois (coluna `barcode`, migration 0056); pode nascer já pago, com data e meio. Conta já prevista (mesmo código, ou vencimento próximo com o mesmo valor ou conta variável/recorrente) é atualizada em vez de duplicada. O "Pagar" de qualquer conta pendente pede dia e meio de pagamento: meio da casa = casa; meio com responsável = ele, reembolsado; cartão = vira compra da fatura (`pending_payment.dart`). O fechamento lista as contas pendentes do ciclo com o meio da baixa ou "levar para o próximo ciclo" (padrão: o meio que a conta já tinha, senão o da casa).

### Pontas pequenas, nunca tratadas
- **`category_id` dos itens de compra** nunca é gravado.
- **Participantes removidos de um evento** não são apagados ao editar (a edição só acrescenta ou atualiza).
- **Conferência do banco contra as migrations:** gatilhos e funções foram conferidos e batem (só faltava um gatilho da 0017, criado na 0046), e todas as tabelas têm RLS ligado. Não foi conferido o conteúdo das regras de acesso nem os índices; como as migrations 0001 a 0021 foram aplicadas à mão, pode haver outra diferença.
- **Telas novas sem teste automatizado:** diálogo de participantes de projeto, "repetir até" do evento, diálogo do dia de início do ciclo, histórico da caixinha e diálogo de fechar compra. A regra de cada uma tem teste; a tela não.

## Testes manuais pendentes

Nenhum destes roteiros foi executado com usuário logado.

### Segunda sessão de 13/10
- **Rateio com morador novo:** abrir Ajustes > Divisão das despesas logo depois de alguém entrar na casa; deve mostrar os dois moradores (antes quebrava com "Value 100 is not between 10 and 90").
- **Copiar:** código de convite, chave Pix e cobrança do Super Pix, no navegador e no celular. Se não copiar, deve aparecer o aviso de falha, não "copiado".
- **Fôlego do Caixa:** a faixa "Gasto diário seguro" só aparece no ciclo em andamento; fora dele aparece "Voltar ao ciclo atual".
- **Troca de ciclo:** ao passar de um ciclo para outro os números esmaecem até o novo chegar; clicar várias vezes seguidas deve parar no último ciclo pedido.
- **Recorrente em ciclo futuro:** com a "Internet" todo dia 25, o ciclo de 09/12 a 08/01 deve mostrar só a de 25/12, sem as de outubro e novembro.
- **Planejamento de Aportes:** conta recorrente fixa entra em "fixas"; em aportes fixos, a cota do dono de uma categoria sobe no valor das despesas dela e bate com o fechamento.
- **Scanner:** editar o título direto na revisão e trocar a categoria, por código de barras e por documento.
- **Painel de detalhes da despesa e cartão em "Gastos do Ciclo":** nome longo de morador e coluna estreita não devem estourar.
- **Categorias:** editar nome e dono; excluir uma sem lançamentos; tentar excluir uma com lançamentos (deve recusar dizendo quantos são); repetir como morador comum (deve recusar por permissão).
- **Dono da categoria:** definir um dono e conferir que as despesas em aberto viram 100% dele; tirar o dono e conferir a volta ao percentual da casa; despesa com sub-itens em aportes fixos deve ser cobrada do dono no fechamento.
- **Tempo real:** com dois aparelhos, lançar, pagar e excluir uma despesa em um e ver mudar no outro; entrar na casa com convite e aparecer na lista dos outros.
- **Ajustes:** índice com quatro grupos e busca ("cartao" sem acento, nome de um cartão, algo inexistente); no PC, grupos à esquerda e conteúdo ao lado; salvar o modelo de rateio dentro da página; editar forma de pagamento e conta fixa na lista; "Gerar código de convite" só cria o código ao tocar; trocar o tema pelos três botões; abrir a importação de fatura pelo bloco "Importar Fatura e Extratos" e pelo menu de um cartão (já chega com o cartão escolhido).
- **Visibilidade do evento:** a linha de ajuda abaixo de Casa / Restrito / Privado muda conforme a opção.

### Fechamento do ciclo
- Fechar um ciclo como dono, tentar fechar como membro comum, reabrir, lançar uma despesa esquecida e fechar de novo (o Super Pix deve mostrar só a diferença).
- Fechar com conta pendente e com gasto acima do balde (aportes fixos).
- Fechar com pagamento parcial ao Caixa nas quatro opções: financiar, manter como pendência, perdoar e cobrir com caixinha.
- Reabrir a tela do ciclo fechado: saldos por morador, transferências com nomes (inclusive as do Caixa) e memória de cálculo.
- Com o fechamento aberto no aparelho do admin, lançar uma despesa por outro aparelho e confirmar: deve pedir para revisar.
- Com um ciclo fechado, tentar lançar despesa paga e aporte com data dentro dele (deve recusar) e uma conta pendente atrasada (deve aceitar).
- Com o ciclo reaberto, tentar mudar o valor de uma despesa já acertada (deve recusar) e o título dela (deve aceitar).
- Definir um dono para uma categoria, lançar uma despesa nela e conferir no fechamento que é cobrada só do dono, sem consumir o balde.
- Morador sem aporte fixo definido: o fechamento deve mostrar o aviso com o nome dele.

### Lançamentos e despesas
- Lançar despesa pelo formulário, com sub-itens; editar o título de uma despesa antiga e conferir que o rateio não mudou.
- Editar uma compra no cartão sem mexer na data: deve continuar na mesma fatura.
- Lançar despesa pelo assistente e pelo scanner numa categoria com dono; fechar compra do mercado com cartão pessoal. Devem sair com categoria e gerar reembolso quando o cartão tem dono.
- Fechar compra do mercado com um item pessoal de outro morador (deve nascer o empréstimo) e com item pessoal de quem pagou (não deve nascer).
- Despesa recorrente: cadastrar, avançar um ciclo, excluir "só esta" e voltar (não deve reaparecer); mudar o dia de vencimento com "esta e as próximas" e avançar outro ciclo.
- Registrar e desfazer o pagamento de uma fatura de cartão; tentar com o ciclo fechado.
- Tirar uma despesa de um projeto pelo formulário.

### Empréstimos e caixinhas
- Criar empréstimo parcelado; como devedor, o botão de excluir não deve aparecer; como credor, só enquanto nada foi pago.
- Pagar um acordo com o Lar pela aba Pessoal: deve perguntar a caixinha e o saldo dela deve subir.
- Pagar um acordo de reposição de caixinha: deve voltar para a mesma caixinha, sem perguntar.
- Caixinha: criar com saldo inicial (deve aparecer "Saldo inicial" no histórico), depositar, resgatar, tentar resgatar acima do saldo e abrir o histórico.

### Ajustes
- Modelos de Rateio: salvar "Por Categoria de Gasto" e reabrir; em aportes fixos, gravar R$ 0 para um morador; abrir a tela com um morador comum (deve mostrar o aviso e desabilitar o botão).
- Dia de Início do Ciclo: escolher outro dia, conferir as datas que o diálogo mostra, salvar e navegar pelos próximos ciclos no painel financeiro. Voltar ao dia antigo antes de a troca valer cancela.
- Recorrentes: a lista deve mostrar as séries ativas da casa, uma linha por série.

### Agenda, tarefas, compras e projetos
- Evento recorrente: criar com e sem "repetir até"; editar e excluir nos três escopos.
- Tarefa: editar pelo menu "⋮"; o nome do responsável deve continuar aparecendo no cartão depois de alguns segundos na tela.
- Item de compra: editar pelo lápis. Repetir a edição de tarefa e de item com um morador que não os criou.
- Projeto: criar, lançar uma despesa, abrir "Participantes", incluir um convidado de fora e desmarcar um morador; o acerto deve mudar na hora.
- Relatórios: os percentuais do gráfico por categoria devem somar 100%; exportar o CSV.

### Outros
- Fila offline com o aparelho realmente sem rede: editar tarefa, editar item e criar empréstimo.
- Horários: evento com hora marcada e tarefa concluída batendo com o relógio.
- Assistente e leitura de documento com usuário logado (nunca testados com sessão real). Pedir ao assistente para perdoar uma dívida: ele deve explicar onde fazer, sem propor ação.
- "Testar chave" de IA no navegador.

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

## Documentos relacionados

- `fechamento_no_banco.md`: o trabalho adiado de levar o cálculo do fechamento para o banco.
- `plano_importacao_conciliacao.md`: plano da importação de fatura e conciliação, com o que já foi feito e o que falta.
- `arquitetura_tecnica.md` e os `modulo_*.md`: especificação original de cada módulo. Podem divergir do que está implementado; em caso de dúvida, vale o código.
- `plano_diretor_unificado.md` e `README_documento_mestre.md`: visão geral do produto.
