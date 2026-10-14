# Plano — Relatórios com prévia do ciclo e calendário de pagamentos

Escrito em 13/10/2026 e revisado duas vezes em 14/10/2026, depois das mudanças no fechamento das migrations 0054 a 0057 (ver "Mudanças no fechamento desde a primeira versão"). Fases 0, 1 e 2 implementadas em 14/10/2026 na branch `feat/relatorios-previa-ciclo` (ver "Situação"); as demais continuam como plano.

## Situação

**Feito (fases 0 a 2).** As fases 0 e 1 foram testadas pelo dono no app em 14/10/2026; a fase 2 só tem testes automatizados e conferência visual no modo demo.

- Fase 0: rótulo do seletor ("Ciclo atual", "Ciclo encerrado", "Próximo ciclo"); cartões "Pago", "A vencer" e "Total do ciclo", somando as mesmas despesas do gráfico, mais "Aportes" e "Fôlego"; a média do planejador divide pelo número de ciclos do histórico (`historicalCyclesCount`); o planejador vê faturas e contas pendentes como o fechamento vê (`FinanceCubit._estimate` aplica `applyOpenInvoiceChoices` com as escolhas padrão, e o estimador abate o que foi pago do bolso sem exigir status pago, como o motor).
- Fase 1: seção "Prévia do fechamento" no topo dos Relatórios, com "Minha prévia" e "Todos". Código em `lib/features/reports/`: `CyclePreviewBuilder` (domínio), `ReportsCubit` (lê `SettlementRepository.getSettlementSummary` sem opções, o mesmo resumo do Hub) e `CyclePreviewSection`. Mostra por morador o aporte que falta, o reembolso do que pagou do bolso, a sobra devolvida, as parcelas a pagar e a receber (com as atrasadas), para quem paga ou de quem recebe, as faturas e contas em aberto consideradas pagas por ele e a projeção até o fim do ciclo. Abre a memória de cálculo do Hub.
- Fase 2: seção "Próximos pagamentos" logo abaixo da prévia, que segue a mesma escolha "Minha prévia" ou "Todos". `PaymentCalendarBuilder` junta as faturas e contas em aberto (com o pagador da prévia e "volta no fechamento" quando é um morador), as parcelas de empréstimos que não passam pelo fechamento, os empréstimos sem prazo e o Super Pix no último dia do ciclo. Parcela cobrada no fechamento não vira linha própria. Grupos: atrasados, próximos 7 dias, até o fim do ciclo e sem prazo; na visão do morador, o total que ele paga e recebe até o fechamento. Conta e fatura com código guardado têm o botão "Copiar código". O `ReportsCubit` lê os empréstimos pelo `P2PRepository`; se falhar, o calendário sai sem eles. Não há saldo do Caixa por dia (o "fôlego por data" do plano ficou de fora).
- Testes em `test/features/reports/cycle_preview_test.dart`.

**Não feito:** CSV (fase 5), fôlego do Caixa por data e as fases 3 e 4.

## Objetivo

Hoje a aba Relatórios mostra o que já aconteceu no ciclo. O pedido é que ela passe a responder, para cada morador:

1. **Quanto vou pagar (ou receber) no fechamento deste ciclo**, já somando casa e empréstimos (P2P).
2. **Em que datas** vou ter de desembolsar: fechamento, parcelas, faturas e contas.
3. **O que já está contratado para os próximos ciclos.**
4. Mais dados de leitura do ciclo (comparativos, pago x pendente, posição dos empréstimos).

## O que existe hoje

`lib/features/reports/presentation/pages/reports_page.dart` é uma única tela sem estado próprio, que lê só o `FinanceCubit`:

- três cartões (Despesas, Aportes, Fôlego);
- barra e lista de gastos por categoria;
- aportes realizados por morador;
- atalho para o Hub de Liquidação;
- botão de exportar CSV.

Não há nada de empréstimos, nenhuma data e nenhuma visão por pessoa.

### Problemas encontrados na tela atual

| # | Problema | Onde |
|---|---|---|
| 1 | O CSV é montado em memória e descartado: o botão só abre um diálogo e mostra "pronto para download". Nenhum arquivo é salvo nem compartilhado. | `_exportReportCsv` |
| 2 | O cartão "Despesas" mostra só as **pagas** (`totalExpensesPaid`), e o gráfico por categoria soma **pagas e pendentes**. Os dois números não fecham entre si. Desde a migration 0054 ficou pior: toda compra no cartão nasce pendente e só vira paga quando a fatura é paga, então o cartão "Despesas" deixa de fora todas as compras de faturas em aberto. | `_buildExecutiveCards` x `_buildCategoriesSection` |
| 3 | O seletor mostra o texto fixo "Ciclo Atual" mesmo ao navegar para ciclos passados ou futuros. | `_buildCycleSelector` |
| 4 | A média histórica do planejador divide pelo número de **meses do calendário** que aparecem nas despesas, não pelo número de ciclos. Um ciclo que começa no dia 10 cruza dois meses e a média sai pela metade. Além disso, o histórico é só o ciclo anterior. Afeta qualquer projeção. Confirmar com um teste antes de corrigir. | `cycle_funding_estimator.dart`, `_computeVariableCategoryEstimates` |
| 5 | O planejador de aportes e o fechamento divergem para quem tem fatura ou conta pendente. O fechamento trata a fatura em aberto como paga pelo titular e a conta pendente como paga com a forma de pagamento padrão dela (escolhas padrão, `applyOpenInvoiceChoices`), e quem paga do bolso recebe o reembolso. O planejador só abate o que já está pago (`isPaid && paidOutOfPocket`), então mostra essa pessoa devendo mais do que o Hub mostra. Afeta a "Projeção até o fim do ciclo". | `cycle_funding_estimator.dart`, `_calculateMemberQuotes` |

### O que já dá para reaproveitar

- **A conta do fechamento já existe e é pura:** `GlobalClearingEngine.computeSettlement` devolve, por morador, aporte devido, aporte pago, reembolso do que pagou do bolso, parcelas P2P a receber e a pagar, saldo líquido e as transferências do Super Pix. O `SettlementRepository.getSettlementSummary(ciclo)` monta tudo isso para qualquer ciclo e, em ciclo fechado, devolve o retrato gravado.
- **Os empréstimos já estão carregados** no `P2PCubit` global (criado no `main.dart`).
- **As regras de data já existem:** `P2PLoan.installmentsChargedIn(ciclo)`, `entersCycleSettlement`, `isOpenEnded`; `expenseBelongsToCycle`; `CycleSchedule.next/previous`.
- **As faturas e as contas pendentes já são separadas:** em `settlement/domain/services/open_invoice_choices.dart`, `openInvoicesOf` devolve as faturas em aberto do ciclo como `CardInvoiceEntry` (cartão, vencimento, compras, total) e `openBillsOf` devolve as contas a pagar pendentes; `defaultOpenInvoiceChoice` e `defaultBillMethodId` dizem quem paga quando ninguém escolhe. `paidWith` (em `finance/domain/services/pending_payment.dart`) diz quem paga a partir da forma de pagamento.
- **Os códigos para pagar já ficam guardados:** a linha digitável do boleto em `HouseExpense.barcode` (migration 0056) e o código da fatura em `CardInvoiceCode` (`getCardInvoiceCodes`, migration 0057).
- **As contas recorrentes** já são geradas no banco até três meses à frente (migration 0049), então os próximos ciclos já têm as contas fixas lançadas.

Conclusão: as fases 1 a 3 **não precisam de migration**. É leitura e apresentação de dados que o app já busca.

## Mudanças no fechamento desde a primeira versão

Revisão de 14/10/2026. O plano continua válido; mudaram os pontos abaixo.

- **Compra no cartão nasce pendente (migration 0054).** A fatura funciona como uma conta pendente: tem vencimento, fica aberta, vencida ou paga, e o pagamento registra a data e a origem do dinheiro (o titular, que é reembolsado no fechamento, ou o Caixa da Casa).
- **O fechamento decide as faturas em aberto.** Para cada fatura em aberto que pesa no ciclo, o Hub pergunta: paga pelo titular, paga pelo Caixa ou levada para o próximo ciclo. Sem escolha, vale "paga pelo titular" se o cartão tem dono e "paga pelo Caixa" se não tem. O cálculo usa essas escolhas (`SettlementOptions.openInvoiceChoices`), e o pagamento de verdade é registrado ao confirmar.
- **Fatura importada paga pelo Caixa (migration 0055).** Quem paga a fatura paga ela inteira. Se o Caixa paga, o que outro morador devia ao titular passa a ser devido ao Caixa, e os gastos pessoais do titular viram um empréstimo dele com o Caixa, cobrado no fechamento do ciclo do pagamento. Fatura lançada à mão não gera dívida.

Efeito no plano:

- A prévia continua sendo o `SettlementSummary` do Hub. Ela é calculada com as escolhas padrão das faturas e precisa dizer isso: "considera as faturas em aberto pagas por: Kelvynn (Nubank, vence 05/11)…".
- Fatura passa a ser um compromisso com data para **todo cartão**, não só para cartão com dono: o pagador é o titular ou o Caixa.
- Os empréstimos criados pela 0055 são empréstimos comuns com o Caixa como credor: já entram na prévia e no calendário pelo caminho dos acordos com o Lar, sem regra nova.
- Problemas 2 e 5 na tabela acima.
- Nenhuma das mudanças pede migration para os relatórios.

### Segunda revisão (14/10/2026): contas pendentes e códigos

- **Conta pendente é paga com uma forma de pagamento (migration 0056).** Ao pagar qualquer conta pendente, escolhe-se o dia e a forma. Forma da casa: o Caixa pagou. Forma com dono: o dono pagou e é reembolsado no fechamento. Cartão de crédito: a conta vira compra da fatura e só fica paga quando a fatura for paga. Boleto lido pelo scanner nasce como conta pendente, com vencimento e linha digitável.
- **O fechamento também decide as contas pendentes.** Cada conta pendente do ciclo recebe baixa com uma forma de pagamento ou é levada para o próximo ciclo (`SettlementOptions.openBillChoices`). Sem escolha, vale a forma que a conta já tinha (se não for cartão); senão, a conta da casa. O cálculo já usa essas escolhas pelo mesmo `applyOpenInvoiceChoices`.
- **Códigos de pagamento (migrations 0056 e 0057):** boleto e fatura de cartão guardam o código para copiar e pagar depois.

Efeito no plano:

- "Conta da casa a vencer" não é mais sempre do Caixa: o pagador é o dono da forma de pagamento padrão da conta, ou o Caixa. Conta com forma de dono vira desembolso do morador com reembolso no fechamento, como a fatura paga pelo titular.
- A prévia lista também as contas pendentes que considera pagas, e por quem.
- O problema 5 vale também para contas pendentes; a correção é a mesma.
- O calendário ganha o botão "Copiar código" nas contas e faturas que têm código guardado.
- Continua sem migration para os relatórios.

## Regra central: uma conta só

A prévia não pode virar uma terceira cópia da matemática do fechamento (já existem o motor e o planejador). A prévia do ciclo é **o mesmo `SettlementSummary` do Hub, em modo leitura**. O que o relatório acrescenta por cima é só:

- a camada de **datas** (quando cada valor vence);
- a camada de **estimativa** (o que ainda não foi lançado), sempre separada e rotulada como estimativa.

Teste obrigatório: com os mesmos dados, o saldo líquido por morador da prévia é igual ao do Hub de Liquidação.

## Desenho

### Camada de domínio (nova, pura, testável)

`lib/features/reports/domain/`

- `entities/payment_due_entry.dart` — um compromisso com data:
  - `date` (nulo = sem prazo), `memberId`, `direction` (paga / recebe), `amount`;
  - `kind`: fechamento do ciclo, parcela P2P fora do fechamento, empréstimo sem prazo, fatura de cartão, conta da casa a vencer;
  - `counterpartName`, `title`, `isEstimate`, `isOverdue`.
- `entities/member_cycle_forecast.dart` — por morador e por ciclo: os componentes do saldo (aporte pendente, reembolso, P2P a pagar, P2P a receber), o líquido do fechamento, a parte estimada e a lista de `PaymentDueEntry`.
- `services/cycle_forecast_builder.dart` — recebe `SettlementSummary`, empréstimos, despesas, formas de pagamento, calendário de ciclos e a data de hoje; devolve as previsões. Sem acesso a banco.

### Camada de apresentação

- `ReportsCubit` (factory no `service_locator`), que usa `SettlementRepository`, `FinanceRepository` e `P2PRepository`. A página deixa de calcular dentro do `build`.
- A página é quebrada em widgets por seção (hoje são 565 linhas num arquivo só).

## Fases

### Fase 0 — Acertos da tela atual (pequena, sem risco)

- Rótulo do seletor: "Ciclo atual", "Ciclo encerrado", "Próximo ciclo" conforme o caso.
- Cartões: separar **Pago**, **A vencer** e **Total do ciclo**, para bater com o gráfico.
- Problema 4 (média do planejador): escrever o teste que reproduz e corrigir a divisão para contar ciclos.
- Problema 5 (planejador x fechamento com fatura ou conta pendente): o planejador passa a ver as despesas como o fechamento vê, aplicando `applyOpenInvoiceChoices` com as escolhas padrão (faturas e contas) antes de calcular as cotas. Teste: mesma casa, mesma fatura em aberto e mesma conta pendente com forma de dono, mesma cota pendente no planejador e no Hub.

O CSV fica para a fase 5, junto com a exportação de verdade.

### Fase 1 — Prévia do fechamento, por pessoa

Seção nova no topo: **"Prévia do fechamento"**, com a data de fim do ciclo.

Para cada morador, um cartão com a decomposição que hoje só aparece na memória de cálculo do Hub:

```
Kelvynn                                   paga R$ 812,40
  Aporte do ciclo            R$ 1.200,00
  Já aportou               − R$   300,00
  Pagou do bolso           − R$   187,60
  Parcelas a pagar (P2P)   + R$   250,00
  Parcelas a receber (P2P) − R$   150,00
  → Para quem: Caixa da Casa R$ 712,40 · Cristiano R$ 100,00
```

- Vem direto de `MemberNetBalance` e das transferências do `SettlementSummary`.
- O reembolso de fatura em aberto aparece em linha própria ("Fatura Nubank 05/11, se paga por você: − R$ 430,00"), porque só vale se o titular pagar a fatura. Se a fatura for levada para o próximo ciclo ou paga pelo Caixa, a linha some e o valor muda. O mesmo vale para conta pendente cuja forma de pagamento padrão tem dono ("Conta de luz 20/10, se paga por você").
- Dois números, sempre separados:
  - **"Se fechasse hoje"**: o que está lançado (é o número do Hub).
  - **"Projeção até o fim do ciclo"**: soma o que falta das categorias variáveis, usando a estimativa do planejador. No modelo de aportes fixos o aporte não muda; a projeção vira um aviso de risco de estourar o balde, com o valor do excedente previsto.
- Parcelas atrasadas de ciclos anteriores entram (como no fechamento) e aparecem marcadas como atrasadas.
- Ciclo fechado: mostra o retrato gravado, com o rótulo "Fechado em dd/mm".
- Morador sem aporte fixo definido: mesmo aviso que o Hub mostra.

### Fase 2 — Calendário de pagamentos ("quando vou pagar")

Seção **"Próximos pagamentos"**: linha do tempo por data, com filtro por morador.

| Entra | Data | Quem paga | Fonte |
|---|---|---|---|
| Super Pix do fechamento | fim do ciclo | devedor líquido | transferências do `SettlementSummary` |
| Parcela P2P com cobrança **fora** do fechamento (`settleInCycle = false`) | vencimento da parcela | devedor | `P2PLoan.openInstallments` |
| Empréstimo sem prazo | sem data, em bloco separado "Sem prazo" | devedor | `isOpenEnded` |
| Acordo com o Lar e reposição de caixinha | conforme o caso acima | devedor | `isHouseLender`, `repayToVaultId` |
| Fatura de cartão em aberto | vencimento da fatura | quem o fechamento escolheria por padrão: o titular (cartão com dono, reembolsado no fechamento) ou o Caixa (cartão sem dono) | `openInvoicesOf`, `defaultOpenInvoiceChoice` |
| Conta pendente (boleto, conta fixa) | vencimento | dono da forma de pagamento padrão da conta (reembolsado no fechamento) ou o Caixa | `openBillsOf`, `defaultBillMethodId`, `paidWith` |

Regras:

- **Sem contar duas vezes.** Parcela com `settleInCycle = true` já está dentro do Super Pix; aparece só como detalhe dele, não como linha própria. A fatura paga pelo titular é desembolso em uma data e reembolso em outra: mostrar as duas pontas ("paga dia 05, volta no fechamento dia 09"). Fatura vencida e não paga fica em "Atrasados".
- Itens vencidos ficam no topo, em "Atrasados".
- Totais por semana e total até o fim do ciclo, por pessoa.
- Contas e faturas pagas pelo Caixa aparecem para mostrar se o Caixa tem saldo no dia (fôlego por data), mas não são cobrança de nenhum morador.
- Conta ou fatura com código guardado mostra "Copiar código" (`HouseExpense.barcode`, `CardInvoiceCode`).

### Fase 3 — Próximos ciclos

Seção **"Já contratado para os próximos ciclos"**: os três ciclos seguintes, por morador.

- Parcelas P2P por ciclo de vencimento.
- Contas recorrentes já geradas (até três meses) e faturas de cartão que vencem neles (inclusive compras parceladas). Fatura ou conta que o fechamento levar adiante continua em aberto e aparece como atrasada no ciclo seguinte, uma vez só.
- Aporte fixo previsto (modelo de aportes fixos) ou a parte de cada um nas contas já lançadas (modelo por percentual).
- Data prevista de quitação de cada empréstimo.

Cuidado: `installmentsChargedIn(ciclo)` devolve **tudo** o que está em aberto até o fim daquele ciclo. Chamado para três ciclos seguidos, a mesma parcela apareceria nos três. O `CycleForecastBuilder` atribui cada parcela a **um** ciclo: o primeiro ainda não fechado cujo fim seja igual ou posterior ao vencimento (a atrasada cai no ciclo atual). O mesmo vale para conta pendente vencida, que o filtro de competência repete nos ciclos seguintes.

Custo: três leituras a mais de despesas (uma por ciclo). Carregar só quando a seção for aberta.

### Fase 4 — Mais dados de leitura

Em ordem de valor:

1. **Comparativo com o ciclo anterior** por categoria (subiu ou caiu, em R$ e em %). O ciclo anterior já é carregado pelo `FinanceCubit`.
2. **Posição dos empréstimos:** total a receber e a pagar por morador, quanto já foi pago, parcelas atrasadas.
3. **Quem pagou o quê:** por morador, pago do bolso x pago pelo Caixa; por forma de pagamento.
4. **Fixas x variáveis** e **pago x pendente** no ciclo.
5. **Evolução de 6 ciclos** (total e por categoria): seis leituras, feitas só quando a seção for aberta, sem migration (ver "Decisões").

### Fase 5 — Exportação de verdade

- Salvar ou compartilhar o CSV (web: download; celular: folha de compartilhamento).
- Incluir no arquivo a prévia por morador e o calendário de pagamentos.
- PDF de prestação de contas (está no plano diretor) fica como item separado, depois.

## Testes

- `cycle_forecast_builder_test.dart`: aporte por percentual e fixo; parcela dentro e fora do fechamento; sem prazo; atrasada; acordo com o Lar; fatura em aberto de cartão com dono e sem dono; fatura levada para o próximo ciclo; conta pendente com forma de dono, da casa e levada adiante; empréstimo com o Caixa criado pela fatura importada paga pelo Caixa (0055); parcela não repetida em ciclos seguidos; ciclo de transição (troca do dia de início).
- Igualdade com o Hub: mesmo cenário, mesmo saldo líquido por morador.
- Teste de widget da prévia e do calendário, com valores ocultos pelo modo privacidade.
- Como no resto do projeto, os testes rodam contra os datasources mock; o roteiro manual com sessão real entra em `pendencias_proxima_sessao.md`.

## Decisões

Recomendações feitas em 13/10/2026. O dono pediu para registrá-las aqui; confirmar com ele antes de implementar.

1. **Quem vê o quê:** a seção abre em "Minha prévia" e tem uma aba "Todos", liberada para todos os moradores. O Hub de Liquidação já mostra o saldo de todos, então esconder aqui criaria duas regras diferentes sem proteger nada.
2. **Data do fechamento:** mostrar "a partir de dd/mm (fim do ciclo)". O fechamento é manual, e o fim do ciclo é a única data certa.
3. **Onde fica:** só na aba Relatórios. A Home já tem o planejador de aportes, e dois cartões com números parecidos confundem. Um resumo na Home só depois de a prévia ser usada com sessão real, se fizer falta.
4. **Fatura de cartão:** entra no calendário como compromisso de quem o fechamento escolheria por padrão (o titular, se o cartão tem dono; o Caixa, se não tem). Quando é o titular, fica marcada como "volta no fechamento" e não entra no total devido. Revisado em 14/10/2026: antes valia só para cartão com dono; desde a 0054 toda fatura é uma conta pendente com pagador.
5. **Evolução de 6 ciclos:** seis consultas, carregadas só quando a seção for aberta, sem migration. Uma função no banco teria de repetir no SQL a regra de competência das despesas, que hoje vive só no app (`expenseBelongsToCycle`).

Com essas decisões, o plano inteiro fica sem nenhuma alteração no banco.

## Ordem sugerida

1. **Fase 0 e Fase 1 juntas**, numa branch nova a partir da `main`. Parar aqui para o dono testar no app com sessão real: a Fase 1 responde à pergunta principal, e o calendário depende de os números dela estarem confiáveis.
2. **Fase 2** e depois **Fase 3**, cada uma em um commit.
3. **Fases 4 e 5** depois de o dono usar a prévia.
