# Omni Lar — pendências para a próxima sessão

Atualizado em 12/10/2026. Este arquivo resume onde o trabalho parou, o que falta e como trabalhar no projeto. Ele substitui, para fins de continuidade, o `o_que_falta_fazer.md`, que está desatualizado e marca como concluído o que não está.

## Estado atual

- **Código:** `main` local e `origin/main` no commit `3789193`, sincronizadas. O código depende das migrations 0027 a 0030, todas já no banco.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`):** migrations 0001 a 0030 aplicadas. Só as 0022 a 0027 e a 0030 constam no histórico de migrations do Supabase; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor (o conector recusou a aplicação da 0028 pelo assistente).
- **Edge Functions:** `capture-read` versão 8 e `assistant` versão 4, ambas com `verify_jwt=true` e exigindo usuário logado que more na casa.
- **Qualidade:** `flutter analyze` com 0 erros (4 warnings antigos de import não usado) e 264 testes passando. Os testes rodam só contra os datasources mock.
- **Dados de teste no banco:** uma casa ("Nossa Casa") com 3 moradores (kelvynn, dono; Cristiano e Joao, membros), rateio 23,33 / 43,34 / 33,33, e 3 empréstimos ativos. Existe uma segunda casa órfã, sem moradores.

## O que foi feito nesta sessão

1. **Segurança (migration 0022):** entrada em casa só por convite válido de uso único (RPC `join_house_with_invite`); convites não listáveis; perdão e renegociação de empréstimo por RPC com checagem de papel; confirmação de transferência só por RPC; Edge Functions autenticadas e com cota.
2. **Rateio e fechamento (0023):** percentuais normalizados; fechamento do ciclo atômico pela RPC `confirm_cycle_settlement`; só admin fecha ou reabre.
3. **Correções de dados:** IDs não-uuid, rateio gravado ao criar despesa, Pix inventado removido, fuso horário (0024).
4. **Itens 14, 15 e 16 da análise:** recorrência de eventos no Supabase, contas atrasadas e competência de cartão, fila offline (4 ações).
5. **Regra de ciclo único e data da baixa (0025):** cada despesa conta em um ciclo só; `paid_at` define o ciclo de uma conta que estava pendente.
6. **Fatura de cartão:** registrar e desfazer o dia do pagamento; bloqueio quando o ciclo está fechado.
7. **Reabrir ciclo (0026):** fechar de novo cobra só a diferença; rateio congelado no fechamento.
8. **Telas:** rateio padrão para 3+ moradores; escolha de como cobrir o excedente do balde no fechamento.

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

Análise feita em 12/10/2026 por leitura do código e das migrations. Nada foi executado (app, testes ou banco), então cada item precisa ser confirmado antes da correção. Não repete o que já está em "limites conhecidos".

### Graves: o recurso existe na tela mas não funciona com sessão real

1. **Projetos compartilhados só funcionam no modo demo.** A casa está fixa como `'house_demo'` e o usuário como `'user_1'` ao carregar e ao criar projeto (`projects_cubit.dart:19`, `projects_hub_page.dart:453`). No Supabase isso vira erro de uuid inválido. O seletor de projeto do formulário de despesa tem o mesmo problema e fica vazio em silêncio (`add_expense_page.dart:113`).
2. **Despesa recorrente é só uma marcação.** Nada gera a ocorrência do ciclo seguinte: `getRecurringExpenses` nunca é chamado e `recurringSeriesId` nunca é preenchido na criação. O `modulo_despesas_de_casa.md` diz que contas fixas "são geradas sozinhas". "Esta e as próximas" e "todas" agem sobre uma série de um item só, e a tela "Recorrentes" dos Ajustes lista apenas as do ciclo carregado (`settings_page.dart:2485`). Falta decidir: gerar as ocorrências no app ao abrir o ciclo ou no banco.
3. **Pagamento parcial no fechamento: três das quatro opções não fazem o que dizem.** O aporte do morador é registrado integral em qualquer caso (`supabase_settlement_datasource.dart:221`), então a diferença some. "Manter como pendência no próximo ciclo" e "Perdoar" não são tratadas por nenhum datasource (as duas se comportam como perdão). "Financiar via P2P", a opção padrão, é pulada quando o credor é o Caixa da Casa (`supabase_settlement_datasource.dart:335`), que é o caso mais comum.
4. **Editar uma compra no cartão a empurra para a fatura seguinte.** O formulário abre com a data igual ao vencimento da fatura e, ao salvar, usa essa data como data da compra e recalcula o vencimento (`add_expense_page.dart:87` e `:247`). Em recorrentes, editar uma ocorrência antiga traz o vencimento para o mês atual (`add_expense_page.dart:241`).

### A mesma regra implementada de formas diferentes

5. **"Pago do próprio bolso", categoria e forma de pagamento dependem de onde a despesa foi lançada.** O campo "pago do bolso" é o que gera reembolso no fechamento.

   | Caminho | Pago do bolso | Categoria gravada no Supabase |
   |---|---|---|
   | Formulário | conforme o dono da forma de pagamento | a escolhida |
   | Assistente | sempre sim | nenhuma |
   | Fechar compra do mercado | sempre sim | nenhuma |
   | Scanner | sempre não | por nome ("mercado"/"conta") |
   | Importar fatura | sempre não | nenhuma |

   Os caminhos "nenhuma" usam ids de demonstração (`cat_mercado`, `cat_contas`, `cat_groceries`), que o Supabase descarta; o assistente ainda recebe `categoryHint` da Edge Function e lê `categoryId` no app. Scanner e importação usam a primeira forma de pagamento da lista, não a real. Só o formulário respeita o dono da categoria.
6. **Modelo de rateio "Por categoria" não existe de fato.** O valor é gravado em `houses.default_split_model` e nunca lido. Ao reabrir a tela ele aparece como "Porcentagem", porque o modelo ativo é deduzido dos valores fixos (`settings_page.dart:1069`).
7. **Aportes fixos: quem entra depois não paga nada.** O novo morador nasce com valor fixo 0 e o motor só cria meta para quem tem valor maior que zero (`global_clearing_engine.dart:69`). No modelo percentual o mesmo morador recebe 1/n automaticamente.
8. **O planejador de aportes da Home não bate com o fechamento.** Soma as contas pendentes e depois abate o fôlego, que já as descontou; abate os aportes de novo por morador; ignora o rateio por despesa. Trocar o modo (econômico/confortável) muda o histórico do ciclo anterior para o atual (`finance_cubit.dart:125`).
9. **Relatórios: totais que não fecham.** O gráfico por categoria soma pagas e pendentes, mas divide só pelo total pago, e pode passar de 100% (`reports_page.dart:213`). O CSV lista todas as despesas e o "Total gasto" conta só as pagas.
10. **Ciclo fechado aparece empobrecido em produção.** As transferências mostram "Membro transfere para Membro" (`supabase_settlement_datasource.dart:74`), as que envolvem o Caixa não são gravadas, e saldos por morador e memória de cálculo vêm vazios. No modo demo tudo aparece completo.
11. **Dia de início do ciclo entre 29 e 31** (o onboarding permite até 31). `FinancialCycle.fromDate` devolve um ciclo que não contém a própria data no último dia de meses curtos (dia 31, data 30/04: resultado 31/03 a 29/04). O banco define ciclo fechado como "início + 1 mês", o que deixa dias finais destravados. Os acordos gerados no fechamento vencem sempre no dia 10 do mês final do ciclo; com início depois do dia 10, a parcela cai dentro do ciclo que acabou de fechar.

### Menores

12. **Mock e Supabase divergem, e os testes rodam só no mock.** Resgate acima do saldo da caixinha zera no mock e dá erro no banco; empréstimo criado sem parcelas (importação de fatura) aparece como quitado no demo; "esta e as próximas" filtra por data no mock e por vencimento no banco; atualizar uma série no Supabase troca o tipo de rateio sem copiar as regras.
13. **"Atrasado" tem duas definições.** Parcela P2P fica atrasada no próprio dia do vencimento; conta da casa, só no dia seguinte.
14. **Código morto e fluxos incompletos.** `ShoppingListPage` (532 linhas) não é usada (a tela viva é a de Tarefas & Compras); tarefas e itens de compra não têm edição; o prompt do assistente menciona perdão, renegociação e exclusão, mas o app não executa essas ações; o selo de "exceção da série" na agenda nunca aparece em produção.
15. **Fechar compra no mercado não liga a viagem à despesa.** O id gerado não é uuid, então `shopping_trips.expense_id` fica sempre nulo. Despesa, empréstimo, viagem e limpeza da lista são quatro gravações separadas, sem transação.

**Ordem sugerida:** 1, 4, 3, 5 (erro visível ou dinheiro calculado errado com usuário real; nenhum exige migration). O item 2 é o maior em esforço.

## Como trabalhar neste projeto

- **Fluxo de git:** criar uma branch a partir da `main`, commitar nela e, quando o dono pedir, fazer merge fast-forward na `main` e push. Commit e push só a pedido.
- **Banco:** qualquer alteração no Supabase é confirmada com o dono antes de aplicar. Migrations ficam em `supabase/migrations/` e são aplicadas pelo conector do Supabase.
- **Validação de SQL:** rodar a migration e os testes dentro de um bloco `DO` que termina em `RAISE EXCEPTION` com os resultados, o que desfaz tudo (rollback). Para simular um usuário: `set_config('request.jwt.claims', ...)` com o `sub` do usuário e `set local role authenticated`.
- **Contas e login:** o assistente não cria contas nem faz login no Supabase hospedado. Fluxos que exigem sessão real são testados pelo dono no app; depois dá para conferir no banco e nos logs.
- **Depois de mudar código que depende de migration:** reiniciar por completo as instâncias abertas do app. A migration 0024 (fuso) só pode rodar uma vez.
- **Não há Deno nem Supabase CLI na máquina.** As Edge Functions são publicadas pelo conector, enviando o conteúdo dos arquivos.
