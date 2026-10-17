# Omni Lar — levar o cálculo do fechamento para o banco

Escrito em 13/10/2026. Trabalho adiado por decisão do dono do projeto: fica para o final, antes de o app ter usuários de fora. Este documento é a referência dele e substitui as menções a este assunto nas listas de pendências e de inconsistências.

## Situação atual

Quem faz a conta do fechamento do ciclo é o app, no aparelho de quem fecha.

1. O app lê despesas, aportes e empréstimos do ciclo e calcula tudo no motor de compensação (`lib/features/settlement/domain/services/global_clearing_engine.dart`, cerca de 580 linhas): quanto cada morador deve, quem recebe de volta, o Super Pix, a sobra do Caixa, o que vai para caixinha e o que vira acordo.
2. O app monta um "plano de fechamento" e o envia para a RPC `confirm_cycle_settlement` (versão atual na migration 0044; conferido em 17/10/2026).
3. O banco confere o plano e grava tudo em uma transação: ou o ciclo fecha por inteiro, ou nada muda.

O princípio 2 do `arquitetura_tecnica.md` já prevê o cálculo no banco.

## O que o banco confere hoje

- Só dono ou admin fecha (`is_house_admin`).
- Os dados da casa não mudaram desde o cálculo (`settlement_data_version`); se mudaram, recusa e pede revisão.
- As despesas citadas existem e são da casa.
- O rateio congelado de cada despesa soma o valor dela e só envolve moradores da casa.
- Transferências, aportes, devoluções e acordos têm valores positivos e são entre moradores.
- O que ficou a receber pelo Caixa está coberto por acordos com o Lar.
- Os totais de caixinha batem com as movimentações.
- Ciclo fechado não aceita despesa paga nem aporte, nem alteração de valor, datas, situação, pagador ou forma de pagamento (travas da migration 0030).

## O que o banco não confere

A conta em si. O banco aceita os valores do plano desde que passem nas conferências acima. Ficam duas brechas:

- **Erro de cálculo no app.** Um defeito no motor grava valores errados sem o banco perceber.
- **Plano adulterado.** Quem fecha pode enviar um plano com valores alterados e o banco aceita. Também ficam sem cobertura a edição ou exclusão de aporte e a alteração de itens ou do rateio de despesa em ciclo fechado.

## O que precisa ser reescrito em SQL

Regras que o motor implementa hoje e que a função do banco teria de reproduzir:

- **Dois modelos de rateio:** percentual (cada despesa pelo rateio dela, sub-itens pelo rateio do item) e aportes fixos (balde comum).
- **Aportes fixos:** balde, excedente do balde, cobertura do excedente pela sobra do ciclo anterior, por uma caixinha e por rateio (proporcional ao aporte ou igual), sub-itens pessoais e despesas de responsável único cobrados por cima do aporte.
- **Reembolso** de despesa da casa paga do próprio bolso, sem reembolsar de novo o que já entrou em um fechamento anterior do mesmo ciclo.
- **Sobra do Caixa:** guardar em caixinha, deixar de folga para o ciclo seguinte ou devolver aos moradores na proporção do aporte.
- **Empréstimos entre moradores:** parcelas que vencem no ciclo e as atrasadas, com compensação no Super Pix.
- **Acordos com o Lar:** parcelas cobradas no fechamento entram no Caixa; reposição de caixinha volta para a caixinha de origem e não conta como sobra.
- **Pagamento parcial do Super Pix:** financiar, manter como pendência, perdoar ou cobrir com caixinha, com o efeito de cada escolha na sobra.
- **Ciclo reaberto:** fechar de novo cobra só a diferença; o que o fechamento anterior já guardou, cobriu, devolveu, deixou a receber, perdoou ou recebeu não volta a ser contado.
- **Super Pix:** o conjunto mínimo de transferências que zera os saldos, incluindo as que envolvem o Caixa.
- **Competência das despesas** (`cycle_expense_filter.dart`): compra no cartão pelo vencimento ou pagamento da fatura, despesa paga pela baixa, pendente atrasada arrastada para os ciclos seguintes, despesa de projeto fora do Caixa.
- **Fim do ciclo** com dia de início 29, 30 ou 31 (`next_cycle_start`, migration 0034).
- **Memória de cálculo** por morador e retrato do fechamento (`summary_snapshot`, migration 0035), que hoje o app monta.

## Caminho sugerido

1. **Função de cálculo só de leitura.** `compute_cycle_settlement(p_house_id, p_cycle_start_date, p_options jsonb)` devolve o mesmo que o motor: saldos, transferências, totais e memória de cálculo. Não grava nada.
2. **Comparação em paralelo.** O app continua calculando e fechando como hoje, mas também chama a função e registra qualquer diferença. Rodar assim por alguns ciclos reais.
3. **Testes de banco.** Portar para SQL os cenários dos testes do motor (`test/features/settlement/`), rodando com rollback, e incluir os casos de ciclo reaberto e de pagamento parcial.
4. **Troca.** `confirm_cycle_settlement` passa a receber só as escolhas de quem fecha (o que fazer com a sobra, como cobrir o que faltou, como resolver cada pagamento parcial) e calcula o resto sozinha. O app deixa de enviar valores.
5. **Limpeza.** O motor em Dart fica só para o modo demo e para mostrar a prévia; a tela do ciclo aberto passa a ler o cálculo do banco.

## Riscos

- **Duas implementações da mesma regra** enquanto durar a comparação: toda mudança de regra tem de ser feita nas duas.
- **Arredondamento.** O motor distribui centavos pelo maior resto; a função do banco tem de usar a mesma regra, senão aparecem diferenças de 1 centavo.
- **Fuso horário** na competência das despesas (migration 0024).
- **Modo demo e testes.** Os testes automatizados rodam só contra o modo demo; a função do banco precisa de uma suíte própria.

## Quando fazer

Não é urgente enquanto o app está em desenvolvimento e quem fecha é o dono. Passa a importar quando houver casas de terceiros, porque aí as duas brechas ficam expostas.
