# Plano: Importação de Fatura e Extrato com Conciliação

Plano de implementação do módulo descrito em [modulo_importacao_conciliacao.md](modulo_importacao_conciliacao.md). Escrito em 13/10/2026; a seção 1 descreve o código da branch `feat/import-reconciliation`.

## 1. Situação atual

A tela antiga "Rachar a Fatura" (`split_invoice_modal.dart`) foi substituída pela página de importação. A migration 0052 (`import_history_confirm_and_undo`) foi validada no banco em bloco com rollback, mas **ainda não foi aplicada**: com conta real, confirmar e desfazer só funcionam depois dela.

**Implementado**
- **Página própria** em `/casa/importar` (`presentation/pages/import_page.dart`), aberta pelo Smart FAB ("Importar Fatura"), por Ajustes > Pagamentos e contas e pelo menu de cada cartão ou conta (chega com a origem escolhida).
- **Origem obrigatória**: cartão ou conta cadastrado. Para cartão, o vencimento da fatura é sugerido pelas datas das compras e pode ser trocado; quem paga vem do dono do cartão.
- **Leitura** (`statement_parser.dart`): OFX de cartão e de conta (com o identificador da transação), CSV com `,`, `;` ou tabulação, datas e valores no formato brasileiro, arquivo em Latin-1. Pagamento, estorno e entrada são reconhecidos pelo sinal e ficam de fora; parcela ("03/10") é identificada. Aviso quando o OFX não é do tipo da origem escolhida.
- **Detecção do que já foi lançado** (`statement_matcher.dart`): as quatro faixas da seção 3, cada despesa casando com uma linha só. "Já lançado" vem aceito; "provável" e "valor diferente" esperam a resposta do usuário e bloqueiam a confirmação.
- **Revisão** (`import_session.dart`): destino por linha, categoria (sugerida por despesa parecida ou pelo nome da categoria), devedor entre todos os moradores, nome e data da compra, filtros por situação e totais.
- **Gravação atômica** (`confirm_import`): uma despesa por linha da Casa, com cartão, vencimento da fatura e rateio padrão; um empréstimo por devedor, vencendo com a fatura; correção da despesa existente (valor real, ou troca para o cartão do arquivo). Se algo falha, nada é gravado.
- **Histórico e desfazer**: cada importação confirmada fica em `import_batches`/`import_lines`, com o que cada linha virou, e aparece na página. Desfazer (`undo_import`) exclui as despesas e os empréstimos criados.
- **Reimportação**: cada linha tem uma assinatura (data, valor, descrição e ordem entre linhas iguais). Linha já importada do mesmo cartão ou conta aparece como "Já importada" e não é lançada de novo, a menos que o usuário mande.
- **Ciclo fechado**: as linhas afetadas são avisadas e o usuário escolhe lançar como ajuste no ciclo atual ou deixar de fora.
- **Testes**: `test/features/reconciliation/` (leitura, duplicidade, plano de gravação e a página).

**Limites do que foi feito**
- **Sem rascunho**: a revisão vive só na tela; sair da página antes de confirmar perde tudo.
- **Desfazer não reverte correções**: valor ou cartão trocado em despesa que já existia continua como ficou. Despesa já acertada em um fechamento e empréstimo que já teve pagamento impedem o desfazer; só quem emprestou (ou um administrador) desfaz um empréstimo.
- **A assinatura depende do arquivo**: se o banco mudar a descrição ou a data de uma linha entre um arquivo e outro, ela não é reconhecida como já importada (aí vale a comparação com as despesas do app).
- **Conta pendente** que casa com uma linha só é vinculada: a baixa continua sendo feita na Casa.
- **Estorno** não gera lançamento; **pagamento de fatura** no extrato não marca a fatura como paga; **Pix recebido** não vira aporte nem parcela.
- **Sem edição em lote**, sem dividir linha, sem regras aprendidas e sem IA (PDF e foto não são aceitos).
- **Vínculo "já lançado" pode errar** quando duas compras diferentes têm o mesmo valor, no mesmo cartão, em até 3 dias; o usuário desfaz com "São diferentes".

**A verificar**
- Se a trava de ciclo fechado se aplica a empréstimo entre moradores (a importação cria o empréstimo normalmente).
- O fluxo com conta real e um arquivo de banco de verdade: os testes usam arquivos fictícios e a casa demo.

## 2. Fluxo proposto

A importação começa pela escolha do cartão ou da conta; vencimento, ciclo e duplicidade derivam disso.

1. **Escolher a origem**: cartão ou conta já cadastrado em Ajustes (o cadastro já tem dia de fechamento e vencimento).
2. **Enviar o arquivo**: OFX/CSV lidos por código; PDF e foto vão para a IA.
3. **Identificar fatura ou período**: para cartão, o app propõe o vencimento a partir das datas das linhas e do dia de fechamento, e o usuário confirma ou troca. Para extrato, usa a conta e o período do arquivo.
4. **Conciliar**: cada linha é comparada com o que já existe e recebe um status.
5. **Rachar**: só as linhas novas vão para a distribuição (Casa / pessoa / pessoal / ignorar).
6. **Confirmar**: grava tudo de uma vez, com opção de desfazer.

Até o passo 6 nada toca o Caixa nem os empréstimos; as linhas ficam em rascunho em `import_batches`/`import_lines`.

## 3. Detecção de lançamento já feito no app

A comparação é feita por código, não por IA, porque valor e data são exatos.

| Sinal | Peso |
|---|---|
| Valor idêntico em centavos | obrigatório (salvo o caso "valor diferente") |
| Mesmo cartão/conta | forte |
| Data da compra até 3 dias de distância | forte |
| Descrição parecida após normalizar | desempate |

Faixas de resultado:

- **Já lançado**: valor igual, mesmo cartão, data próxima. Vem vinculado e não cria nada.
- **Provável**: valor igual, mas lançado em outro meio de pagamento ou sem cartão. O app pergunta e, se confirmado, corrige meio de pagamento e vencimento da despesa existente.
- **Valor diferente**: mesmo lugar e data, valor levemente diferente. Oferece atualizar para o valor real.
- **Nova**: sem correspondência; segue para o rachar.

Regras complementares:
- Cada despesa só casa com uma linha (duas compras de mesmo valor no mesmo dia não se confundem).
- Reimportar o mesmo arquivo não duplica: cada linha tem uma assinatura (origem, data, valor, descrição, ordem; ou o identificador do OFX quando existe).

### Exemplo: fatura Nubank, vencimento 10/11

Já lançado no app: "Mercado" R$ 485,60 em 11/10 no Nubank; "Farmácia" R$ 62,90 em 08/10 sem cartão; "Jantar" R$ 140,00 em 05/10 no Nubank.

| Linha da fatura | Resultado | Ao confirmar |
|---|---|---|
| 12/10 PAO DE ACUCAR LJ 1234 · 485,60 | Já lançado ("Mercado" 11/10) | Só vincula |
| 09/10 DROGASIL 0456 · 62,90 | Provável ("Farmácia" 08/10, sem cartão) | Pergunta; se sim, associa ao Nubank e ao vencimento 10/11 |
| 05/10 RESTAURANTE SABOR · 154,00 | Valor diferente ("Jantar" 140,00) | Oferece atualizar para 154,00 |
| 07/10 FARM RIO · 320,00 | Nova | Rachar: morador (P2P) → empréstimo |
| 03/10 ENEL · 210,00 | Nova | Rachar: Casa → despesa com rateio |
| 02/10 MAGALU 03/10 · 99,90 | Nova, parcela 3 de 10 | Despesa desta fatura |
| 01/10 PAGAMENTO RECEBIDO · -1.200,00 | Pagamento | Ignorada |

Resumo antes de confirmar: "7 linhas: 1 já lançada, 2 para revisar, 3 novas, 1 ignorada. Soma bate com o total da fatura ✔".

## 4. Extrato de conta

Mesmo fluxo, com três casos próprios:

- **"PAGTO FATURA NUBANK 1.482,40"**: não vira despesa. É reconhecido pelo total do banco e oferece marcar a fatura correspondente como paga na data do extrato.
- **Pix recebido de um morador**: sugerido como aporte do ciclo ou parcela de empréstimo em aberto de mesmo valor.
- **Débito ou Pix enviado**: passa pela mesma detecção de duplicidade, comparando com despesas pagas por aquela conta.

## 5. Edição na revisão

**Por linha nova**
- Destino: Casa, um morador (vira empréstimo), pessoal do titular, ignorar.
- Categoria.
- Responsável / devedor: qualquer morador da casa.
- Rateio: padrão da casa, o da categoria, ou personalizado.
- Título (nome limpo no lugar da descrição do banco).
- Data da compra.
- Projeto.
- Vínculo: trocar a despesa casada ou desfazer ("são diferentes").

**Para a fatura toda**: cartão ou conta, vencimento e quem pagou.

**Não editável**: valor da linha. Para repartir uma compra, a opção é dividir a linha em duas, mantendo a soma igual ao total da fatura.

**Em lote**: aplicar categoria, destino ou responsável a várias linhas; "aplicar a todas deste estabelecimento" e "lembrar nas próximas faturas".

**Linhas já lançadas**: não são reeditadas na revisão; o app só propõe os ajustes que a fatura revela (valor real, cartão, vencimento). Um toque abre a despesa original.

## 6. Linhas de ciclo já fechado

O banco recusa despesa paga com data dentro de ciclo fechado (migration 0030) e só administrador reabre o ciclo. A importação trata isso antes de confirmar: as linhas novas nessa situação ficam num grupo à parte, com três saídas.

1. **Lançar no ciclo atual como ajuste** (padrão). Entra com a data de hoje e título marcado ("Uber 28/09 (ajuste de setembro)"); a data original fica na linha importada. Qualquer morador pode fazer.
2. **Reabrir o ciclo e lançar na data certa.** Só administrador. Fechar de novo cobra só a diferença (migration 0026).
3. **Deixar de fora.** Ficam no histórico como "não lançadas".

O ajuste usa o rateio e os moradores do ciclo atual; reabrir usa os do ciclo original. Se a composição da casa mudou, o app avisa para preferir reabrir.

Sem problema: linha que casa com despesa já lançada naquele ciclo (só vincula), linha pessoal ou ignorada, conta pendente atrasada.

Mesma escolha: valor diferente em despesa de ciclo fechado (o ajuste lança só a diferença) e pagamento de fatura de ciclo fechado (já barrado pela migration 0028).

**A verificar antes de implementar:** se a trava de ciclo fechado se aplica a empréstimo entre moradores gerado por linha de ciclo fechado.

## 7. Pagamento da fatura

O app já trata a fatura como o conjunto das compras com mesmo cartão e mesmo vencimento (`card_invoice.dart`); registrar o pagamento marca todas de uma vez (`pay_card_invoice`) e dá para desfazer. A importação só precisa gravar cada linha da Casa com o cartão e o vencimento corretos.

- **Total do app menor que o do banco**: linhas pessoais e de outro morador não são despesa da Casa. A tela mostra os dois valores e a decomposição (Casa + empréstimos + pessoal = total do banco). O total do banco fica no registro da importação.
- **Quem paga o banco é o titular**: as despesas ficam como pagas por ele do próprio bolso; o reembolso sai no fechamento do ciclo.
- **Empréstimo segue separado**: não é quitado ao marcar a fatura como paga. O vencimento da parcela passa a ser o da fatura (hoje é a data atual + 30 dias).
- **A data do pagamento define o ciclo** em que as compras contam.
- **Juros, IOF e anuidade** vêm como linhas normais.

Fora da primeira versão: pagamento parcial e parcelamento de fatura.

## 8. Uso de IA

Segue as regras de `.agents/skills/omnilar-ai-pipeline/SKILL.md`: código primeiro, a IA propõe e a pessoa confirma, a IA não calcula valores finais.

- **Ler PDF e foto**: devolve linhas estruturadas, final do cartão, vencimento e total. O app confere se a soma das linhas bate com o total antes de aceitar.
- **Limpar e classificar**: nome do estabelecimento, categoria e destino sugeridos, em uma chamada para o lote inteiro.
- **Desempatar duplicidade**: só quando o valor bate e a descrição não ajuda.
- **Regras aprendidas antes da IA**: correções do usuário viram regra e são aplicadas sem chamada.

Sem IA (limite ou erro), OFX/CSV continuam funcionando e a classificação fica manual. A base existe em `supabase/functions/capture-read`; falta a função `import-classify`.

## 9. Etapas

1. **Corrigir os riscos de hoje**: feito.
2. **Origem e leitura confiável**: feito.
3. **Rascunho e gravação por linha**: gravação por linha e confirmação atômica feitas. Falta guardar o rascunho da revisão.
4. **Conciliação**: motor, tela, grupo de ciclo fechado e assinatura por linha feitos. Falta a edição em lote.
5. **Extrato**: só a leitura (saídas viram despesa). Falta pagamento de fatura, Pix recebido e estorno.
6. **IA**: leitura de PDF/foto, classificação em lote, regras aprendidas.
7. **Histórico e desfazer**: feitos (migration 0052).

A etapa 6 exige publicar uma função nova (`import-classify`). O rascunho da revisão (etapa 3) exigiria outra mudança no banco.

## 10. Decisões em aberto

- **Vínculo automático**: recomendação de que o "Já lançado" venha pré-marcado, visível e desfazível.
- **Parcelas futuras**: criar as restantes nos próximos ciclos ou só a da fatura atual (recomendação: só a atual).
- **Linhas pessoais do titular**: ficam só no histórico da importação, sem virar despesa (como na especificação)?
- **Dividir a linha**: entra na primeira versão ou depois da conciliação?
