# Omni Lar — pendências para a próxima sessão

Atualizado em 13/10/2026. Este arquivo resume onde o trabalho parou, o que falta e como trabalhar no projeto. Ele substitui, para fins de continuidade, o `o_que_falta_fazer.md`, que está desatualizado e marca como concluído o que não está.

## Estado atual

- **Código:** `main` local e `origin/main` no commit `40ed34d`, sincronizadas. O código depende das migrations até a 0037, todas já no banco.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`):** migrations 0001 a 0037 aplicadas. Só as 0022 a 0027 e as 0030 a 0037 constam no histórico de migrations do Supabase; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor (o conector recusou a aplicação da 0028 pelo assistente).
- **Edge Functions:** `capture-read` versão 8 e `assistant` versão 5, ambas com `verify_jwt=true` e exigindo usuário logado que more na casa.
- **Qualidade:** `flutter analyze` com 0 erros (4 warnings antigos) e 314 testes passando (conferido em 13/10/2026). Os testes rodam só contra os datasources mock.
- **Dados de teste no banco:** uma casa ("Nossa Casa") com 3 moradores (kelvynn, dono; Cristiano e Joao, membros), rateio 23,33 / 43,34 / 33,33, e 3 empréstimos ativos. Existe uma segunda casa no banco. Desde a migration 0033 toda casa tem ao menos uma caixinha: as novas nascem com a "Reserva da Casa" e a que não tinha nenhuma recebeu uma.

## O que foi feito nesta sessão

1. **Projetos compartilhados só funcionavam no modo demo (corrigido em 13/10/2026, falta testar no app).** A tela e o seletor de projeto do formulário de despesa passaram a usar a casa e o usuário da sessão no lugar de `'house_demo'` e `'user_1'`. Projeto novo nasce com todos os moradores como participantes, cada um com o seu percentual padrão. Não há tela para editar participantes depois.
2. **Rateio e fechamento (0023):** percentuais normalizados; fechamento do ciclo atômico pela RPC `confirm_cycle_settlement`; só admin fecha ou reabre.
3. **Correções de dados:** IDs não-uuid, rateio gravado ao criar despesa, Pix inventado removido, fuso horário (0024).
4. **Editar uma compra no cartão a empurrava para a fatura seguinte (corrigido em 13/10/2026, falta testar no app).** O formulário agora abre uma compra no cartão na data da compra, não no vencimento da fatura. Em recorrentes, editar uma ocorrência mantém o vencimento no mês dela. Compras já gravadas com a data errada por edições anteriores não foram corrigidas. Salvar a edição também regravava o rateio pelo padrão atual da casa (uma despesa lançada em 50/50 virava 60/40 se o padrão tivesse mudado); agora o rateio do lançamento é mantido e só é refeito quando a categoria muda. O formulário não tem campo para rateio personalizado por despesa.
5. **Regra de ciclo único e data da baixa (0025):** cada despesa conta em um ciclo só; `paid_at` define o ciclo de uma conta que estava pendente.
6. **Modelo de rateio "Por categoria" (corrigido em 13/10/2026, falta testar no app).** Decisão do dono: implementar. O modelo gravado em `houses.default_split_model` passou a ser lido e a tela reabre em "Por Categoria de Gasto", mostrando as categorias com dono (100% para o dono) e a divisão igual das demais. A regra em si já era aplicada pelo formulário de despesa; os outros caminhos de lançamento continuam ignorando o dono da categoria (item 5). No modelo de aportes fixos a categoria com dono não tem efeito.
7. **Aportes fixos: quem entra depois não paga nada (corrigido em 13/10/2026, falta testar no app).** Decisão do dono: o valor é ajustado à mão. O novo morador continua nascendo com valor fixo 0, mas a tela de Modelos de Rateio passou a mostrar esse 0 (antes exibia R$ 1.000 que não valiam) com o aviso "Sem aporte definido", aceita gravar 0 de propósito e o fechamento avisa quem está sem aporte antes de fechar o ciclo. Só dono ou admin consegue gravar (regra do banco); para os demais a tela não avisa que não salvou.
8. **O planejador de aportes da Home não batia com o fechamento (corrigido em 13/10/2026, falta testar no app).** A conta passou a ser a do ciclo inteiro: tudo o que o ciclo custa (pago e a vencer), menos a sobra do ciclo anterior, e só então o que cada um já aportou é abatido da cota dele. Antes as contas pendentes entravam duas vezes e os aportes eram abatidos duas vezes. Cada despesa lançada entra pelo rateio dela, conta paga do próprio bolso abate a cota de quem pagou, e compra já lançada em categoria variável conta dentro da estimativa. Trocar o modo (econômico/confortável) mantém o histórico do ciclo anterior. No modelo de aportes fixos a cota continua sendo o valor fixo.

## Pendente: testes manuais no app

Nada disto foi exercitado com usuário logado; só passou por teste automatizado (mock) e por testes de banco com rollback.

- Fechar um ciclo como dono, tentar fechar como membro comum, reabrir, lançar uma despesa esquecida e fechar de novo (o Super Pix deve mostrar só a diferença).
- Fechar um ciclo com conta pendente e com gasto acima do balde (modelo de aportes fixos).
- Criar despesa com rateio personalizado (ex.: 70/30) e de responsável único; reabrir e conferir.
- Registrar e desfazer o pagamento de uma fatura de cartão; tentar com o ciclo fechado.
- Evento recorrente: criar, editar e excluir nos três escopos.
- Conta pendente atrasada sendo arrastada para o ciclo seguinte.
- Horários: evento com hora marcada e tarefa concluída batendo com o relógio.
- Fila offline com o aparelho realmente sem rede (o aviso de "Sem conexão" deve substituir o de sucesso).
- Com o fechamento aberto no aparelho do admin, lançar uma despesa por outro aparelho e confirmar: deve pedir para revisar; confirmar de novo deve fechar.
- Com um ciclo fechado, tentar lançar despesa paga e aporte com data dentro dele (deve recusar) e uma conta pendente atrasada (deve aceitar).
- Fechamento visto por membro comum: aviso no lugar do botão de fechar, sem botão de reabrir.
- Caixinha: depositar, resgatar e tentar resgatar acima do saldo (agora dá erro em vez de zerar).
- Excluir "todas" de uma despesa recorrente quando existe outra com o mesmo nome (a outra deve ficar).
- Assistente e leitura de documento com usuário logado (nunca testados com sessão real).

## Pendente: decisões do dono do projeto

- O devedor ainda pode excluir o empréstimo inteiro (política da migration 0018).
- As opções de sobra "deixar no Caixa para o próximo mês" (fica como folga: cobre o excedente do balde antes da Caixinha e do rateio) e "devolver aos membros" (abate do aporte, proporcional ao aporte) foram implementadas e dependem da migration 0031. A escolha de crédito do morador continua removida: quem aporta acima do devido não recebe a diferença de volta e esse valor fica no Caixa sem entrar na sobra do fechamento.

## Pendente: limites conhecidos

- **Reabrir ciclo:** com a migration 0029, excluir despesa já acertada passa a ser recusado (a correção é um lançamento de ajuste), mas alterar o valor de uma despesa já acertada continua possível e não gera acerto; trocar a divisão do excedente do balde no segundo fechamento redistribui o excedente inteiro; parcelas P2P e acordos do primeiro fechamento não são desfeitos.
- **Fatura de cartão:** com a migration 0028 o bloqueio de ciclo fechado passa a ser feito no banco, pelas funções `pay_card_invoice` e `undo_card_invoice_payment`; gravar `paid_at` direto na tabela de despesas continua possível para qualquer morador; só funciona para cartão com fechamento e vencimento cadastrados.
- **Dia de início do ciclo:** o painel financeiro e o fechamento passaram a usar o dia configurado na casa (9), no lugar do 5 fixo. Falta conferir no app. O assistente (`assistant_interpreter_service.dart`) ainda usa 5 quando não recebe o ciclo atual.
- **Fila offline:** não há cache local (sem rede as listas não carregam); a tela ainda mostra "adicionada com sucesso" por um instante antes do aviso de "Sem conexão", porque várias telas não esperam a gravação terminar (vale também para erro do servidor); empréstimos, pagamento de parcela e marcar item como comprado ficam de fora.
- **Recorrência de eventos:** horizonte fixo (14 diárias, 8 semanais, 4 quinzenais, 6 mensais, 2 anuais) e a data final da repetição não é gravada.
- **Fechamento:** com a migration 0029 o banco confere o plano (despesas da casa, rateio congelado somando o valor da despesa, transferências, acordos e totais de caixinha), mas o cálculo do rateio continua sendo do app do admin. A migration 0030 acrescenta duas travas: o fechamento é recusado se os dados da casa mudaram desde o cálculo (`settlement_data_version`), e ciclo fechado não aceita despesa paga nem aporte, nem alteração de valor, datas, situação, pagador ou forma de pagamento. Continua sem cobertura: parte de cada morador calculada errado pelo app, admin alterando os valores de propósito, edição ou exclusão de aporte e alteração de itens ou rateio de despesa em ciclo fechado. O `arquitetura_tecnica.md` (princípio 2) prevê o cálculo no banco; levar o motor de compensação para lá fica como etapa futura, antes do uso real.
- **Itens médios da análise ainda abertos:** caixinha pode ser criada pelo cliente já com saldo inicial; a sobrecarga antiga `delete_house_expense(uuid)` continua no banco; categorias e formas de pagamento padrão duplicadas; `category_id` de compras nunca gravado; participantes removidos de evento não são apagados; "testar chave" de IA usa `dart:io` (não deve funcionar na web); colunas duplicadas no schema.
- **Documentação:** `o_que_falta_fazer.md` precisa ser reescrito.

## Pendente: inconsistências de funcionalidades já implementadas

Análise feita em 12/10/2026 por leitura do código e das migrations, e reavaliada em 13/10/2026 contra o código da `main` (commit `e4ff129`), de novo só por leitura: nenhum item foi reproduzido no app. Resultado da reavaliação: o item 3 foi corrigido (com pontas em aberto), o item 5 foi corrigido em parte (scanner) e os outros 13 continuavam como descritos; os itens 6, 7 e 11 foram corrigidos em seguida, no mesmo dia. Não repete o que já está em "limites conhecidos".

### Graves: o recurso existe na tela mas não funciona com sessão real

1. **Projetos compartilhados só funcionam no modo demo.** A casa está fixa como `'house_demo'` e o usuário como `'user_1'` ao carregar e ao criar projeto (`projects_cubit.dart:19`, `projects_hub_page.dart:453`). No Supabase isso vira erro de uuid inválido. O seletor de projeto do formulário de despesa tem o mesmo problema e fica vazio em silêncio (`add_expense_page.dart:113`).
2. **Despesa recorrente era só uma marcação (corrigido em 13/10/2026, migration 0036; falta testar no app).** O banco passa a criar a ocorrência de cada mês (RPC `generate_recurring_expenses`, chamada ao abrir o ciclo atual ou um futuro, no máximo dois meses à frente), como conta pendente, copiando valor, categoria, forma de pagamento, rateio e sub-itens da ocorrência mais recente. A série é a primeira despesa (matriz) mais as ocorrências ligadas por `recurring_series_id`; excluir "só esta" não recria a ocorrência, e "esta e as próximas" ou "todas" encerram a série. Conta variável nasce com o valor do mês anterior, para ser ajustada. A tela "Recorrentes" dos Ajustes lista as séries ativas da casa (uma linha por série, com a ocorrência mais recente), não só as do ciclo carregado. Em aberto: uma série cuja primeira despesa foi excluída com "só esta" continua gerando contas, mas some dessa lista.
3. **Pagamento parcial no fechamento (corrigido em 13/10/2026, migration 0032).** "Financiar via P2P" e "Manter como pendência" criam o acordo também quando o credor é o Caixa da Casa (a pendência vence no início do ciclo seguinte), o que deixou de entrar no Caixa sai da sobra, e o fechamento grava quanto ficou a receber, quanto foi perdoado e quanto entrou de acordos com o Lar, de modo que reabrir o ciclo não recria sobra. As quatro pontas que ficaram em aberto foram decididas pelo dono em 13/10/2026: (a) acordo com o Lar pago fora do fechamento: quem paga escolhe a Caixinha que recebe o valor (RPC `pay_house_loan_to_vault`; a tela sugere a "Reserva da Casa"), em vez de o dinheiro não entrar na sobra de nenhum ciclo; (b) "Reposição da Caixinha": o acordo guarda a Caixinha que cobriu (`p2p_loans.repay_to_vault_id`) e cada pagamento volta para ela, no fechamento ou fora dele, sem contar como sobra do Caixa; (c) "Devolver a sobra aos membros" com pagamento parcial ao Caixa continua recusado, com a mensagem que já explica o motivo; (d) Super Pix não marcado como parcial continua sendo tratado como pago. As pontas (a) e (b) usam a migration 0037 e faltam ser testadas no app. Em aberto: acordos de reposição criados antes da 0037 não têm Caixinha de origem (ao pagar fora do fechamento a tela pergunta a Caixinha; no fechamento contam como entrada do Caixa); acordo com o Lar pago por uma instância antiga do app, sem escolher Caixinha, continua fora da sobra.
4. **Editar uma compra no cartão a empurra para a fatura seguinte.** O formulário abre com a data igual ao vencimento da fatura e, ao salvar, usa essa data como data da compra e recalcula o vencimento (`add_expense_page.dart:87` e `:247`). Em recorrentes, editar uma ocorrência antiga traz o vencimento para o mês atual (`add_expense_page.dart:241`).

### A mesma regra implementada de formas diferentes

5. **"Pago do próprio bolso", categoria e forma de pagamento dependiam de onde a despesa foi lançada (corrigido em 13/10/2026, falta testar no app).** Assistente, compra do mercado e importação de fatura passaram a usar a mesma regra (`expense_launch_defaults.dart`): pago do bolso só quando a forma de pagamento tem dono, categoria real da casa (por nome) e categoria com dono indo 100% para o dono. A importação de fatura usa o cartão cujo nome bate com o da fatura. O formulário e o scanner mantêm a lógica própria, com o mesmo resultado. A tabela abaixo descreve como era antes.

   | Caminho | Pago do bolso | Categoria gravada no Supabase |
   |---|---|---|
   | Formulário | conforme o dono da forma de pagamento | a escolhida |
   | Assistente | sempre sim | nenhuma |
   | Fechar compra do mercado | sempre sim | nenhuma |
   | Scanner | conforme o dono da forma de pagamento (corrigido em 13/10/2026) | por nome ("mercado"/"conta") |
   | Importar fatura | sempre não | nenhuma |

   Os caminhos "nenhuma" usam ids de demonstração (`cat_mercado`, `cat_contas`, `cat_groceries`), que o Supabase descarta; o assistente ainda recebe `categoryHint` da Edge Function e lê `categoryId` no app. O scanner passou a pedir a forma de pagamento na revisão e a usar o dono dela como pagador; a importação de fatura continua usando a primeira forma de pagamento da lista, não a real. Só o formulário respeita o dono da categoria.
6. **Modelo de rateio "Por categoria" não existe de fato.** O valor é gravado em `houses.default_split_model` e nunca lido. Ao reabrir a tela ele aparece como "Porcentagem", porque o modelo ativo é deduzido dos valores fixos (`settings_page.dart:1069`).
7. **Aportes fixos: quem entra depois não paga nada.** O novo morador nasce com valor fixo 0 e só entra na lista de metas quem tem valor maior que zero (`supabase_settlement_datasource.dart:161`, usada em `global_clearing_engine.dart:75`). No modelo percentual o mesmo morador recebe 1/n automaticamente.
8. **O planejador de aportes da Home não bate com o fechamento.** Soma as contas pendentes e depois abate o fôlego, que já as descontou; abate os aportes de novo por morador; ignora o rateio por despesa. Trocar o modo (econômico/confortável) muda o histórico do ciclo anterior para o atual (`finance_cubit.dart:125`).
9. **Relatórios: totais que não fechavam (corrigido em 13/10/2026, falta testar no app).** O gráfico por categoria divide pelo total do próprio gráfico (pagas e pendentes) e soma 100%. O CSV traz "Total Pago", "Total Pendente" e "Total Lançado", calculados das linhas listadas.
10. **Ciclo fechado aparecia empobrecido em produção (corrigido em 13/10/2026, migration 0035; falta testar no app).** Logo depois de fechar o ciclo, o app grava um retrato do fechamento (`settlements.summary_snapshot`, pela RPC `save_settlement_snapshot`, só admin): saldos por morador, todas as transferências (inclusive as com o Caixa, com o valor efetivamente pago) e a memória de cálculo. A tela do ciclo fechado passa a ser montada a partir dele. Ciclos fechados antes disso continuam resumidos, mas com os nomes dos moradores no lugar de "Membro". Se a gravação do retrato falhar, o ciclo fica fechado e aparece resumido. Reabrir e fechar de novo regrava o retrato.
11. **Dia de início do ciclo entre 29 e 31 (corrigido em 13/10/2026, migration 0034; falta testar no app).** Decisão do dono: em mês que não tem o dia, o ciclo começa no último dia do mês. `FinancialCycle.fromDate` foi corrigido (dia 31, data 30/04: ciclo de 30/04 a 30/05) e a migration 0034 faz o banco usar o mesmo fim de ciclo na trava de ciclo fechado. Os acordos gerados no fechamento passam a vencer no dia 10 seguinte ao fim do ciclo, nunca dentro dele. Não cobre: trocar o dia de início da casa depois de já ter ciclos fechados.

### Menores

12. **Mock e Supabase divergiam (corrigido em parte em 13/10/2026).** Igualados: resgate acima do saldo da caixinha é recusado no demo; empréstimo criado sem parcelas ganha as parcelas no demo; "esta e as próximas" vale a partir do vencimento nos dois; atualizar uma série no Supabase regrava as regras de rateio das outras ocorrências. O demo também passou a gerar as contas recorrentes do mês seguinte e a depositar em Caixinha o pagamento de acordo com o Lar. Continua: os testes rodam só no mock.
13. **"Atrasado" tinha duas definições (corrigido em 13/10/2026).** Parcela P2P passa a ficar atrasada só no dia seguinte ao vencimento, como as contas da casa.
14. **Código morto e fluxos incompletos (corrigido em parte em 13/10/2026).** `ShoppingListPage` foi removida. Tarefas e itens de compra ganharam edição (menu "Editar" na tarefa e botão de lápis no item; tarefa: título, descrição, prazo, responsável, prioridade e custo; item: nome, quantidade e se é pessoal), ainda sem teste no app. O prompt do assistente deixou de citar perdão, renegociação e exclusão como ações (o app nunca as executou): agora manda explicar em que tela fazer; publicado na versão 5 da Edge Function `assistant`, sem teste com sessão real. Continua: a edição não passa pela fila offline; o selo de "exceção da série" na agenda nunca aparece em produção.
15. **Fechar compra no mercado não ligava a viagem à despesa (corrigido em 13/10/2026, falta testar no app).** A despesa nasce com id real e `shopping_trips.expense_id` passa a ser gravado. Continua: despesa, empréstimo, viagem e limpeza da lista são quatro gravações separadas, sem transação.

**Ordem sugerida (reavaliada em 13/10/2026).** Critério: primeiro o que grava dinheiro errado sem avisar, depois o que quebra à vista, deixando por último o que exige decisão do dono ou muito esforço.

1. **Corrigidos em 13/10/2026 (falta teste no app):** 4, 5, 1 e 9.
2. **Decididos e corrigidos em 13/10/2026:** 11, 7 e 6 (falta teste no app).
3. **Maiores:** 10 (corrigido em 13/10/2026), pontas do item 3 (decididas e corrigidas em 13/10/2026), 8 (corrigido em 13/10/2026), 2 (corrigido em 13/10/2026, gerando no banco).
4. **Limpeza:** 15 e 13 corrigidos, 12 e 14 em parte (13/10/2026).

## Como trabalhar neste projeto

- **Fluxo de git:** criar uma branch a partir da `main`, commitar nela e, quando o dono pedir, fazer merge fast-forward na `main` e push. Commit e push só a pedido.
- **Banco:** qualquer alteração no Supabase é confirmada com o dono antes de aplicar. Migrations ficam em `supabase/migrations/` e são aplicadas pelo conector do Supabase.
- **Validação de SQL:** rodar a migration e os testes dentro de um bloco `DO` que termina em `RAISE EXCEPTION` com os resultados, o que desfaz tudo (rollback). Para simular um usuário: `set_config('request.jwt.claims', ...)` com o `sub` do usuário e `set local role authenticated`.
- **Contas e login:** o assistente não cria contas nem faz login no Supabase hospedado. Fluxos que exigem sessão real são testados pelo dono no app; depois dá para conferir no banco e nos logs.
- **Depois de mudar código que depende de migration:** reiniciar por completo as instâncias abertas do app. A migration 0024 (fuso) só pode rodar uma vez.
- **Não há Deno nem Supabase CLI na máquina.** As Edge Functions são publicadas pelo conector, enviando o conteúdo dos arquivos.
