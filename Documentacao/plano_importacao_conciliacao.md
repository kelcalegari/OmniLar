# Plano: Importação de Fatura e Extrato com Conciliação

Plano de implementação do módulo descrito em [modulo_importacao_conciliacao.md](modulo_importacao_conciliacao.md). Escrito em 13/10/2026; a seção 1 descreve o código da branch `feat/import-reconciliation`.

## 1. Situação atual

A tela antiga "Rachar a Fatura" (`split_invoice_modal.dart`) foi substituída pela página de importação. As migrations 0052 (`import_history_confirm_and_undo`) e 0053 (`import_rules`) estão aplicadas, e a função `import-read` está publicada no servidor.

**Implementado**
- **Página própria** em `/casa/importar` (`presentation/pages/import_page.dart`), aberta pelo Smart FAB ("Importar Fatura"), por Ajustes > Pagamentos e contas e pelo menu de cada cartão ou conta (chega com a origem escolhida).
- **Origem obrigatória**: cartão ou conta cadastrado. Para cartão, o vencimento da fatura é sugerido pelas datas das compras e pode ser trocado; quem paga vem do dono do cartão.
- **Leitura** (`statement_parser.dart`): OFX de cartão e de conta (com o identificador da transação), CSV com `,`, `;` ou tabulação, datas e valores no formato brasileiro, arquivo em Latin-1. Pagamento, estorno e entrada são reconhecidos pelo sinal e ficam de fora; parcela ("03/10") é identificada. Aviso quando o OFX não é do tipo da origem escolhida.
- **Detecção do que já foi lançado** (`statement_matcher.dart`): as quatro faixas da seção 3, cada despesa casando com uma linha só. "Já lançado" vem aceito; "provável" e "valor diferente" esperam a resposta do usuário e bloqueiam a confirmação.
- **Revisão** (`import_session.dart`): destino por linha, categoria (sugerida por despesa parecida ou pelo nome da categoria), devedor entre todos os moradores, nome e data da compra, filtros por situação e totais.
- **Gravação atômica** (`confirm_import`): uma despesa por linha da Casa, com cartão, vencimento da fatura e rateio padrão; um empréstimo por devedor, vencendo com a fatura; correção da despesa existente (valor real, ou troca para o cartão do arquivo). Se algo falha, nada é gravado.
- **Histórico e desfazer**: cada importação confirmada fica em `import_batches`/`import_lines`, com o que cada linha virou, e aparece na página. Desfazer (`undo_import`) exclui as despesas e os empréstimos criados.
- **Reimportação**: cada linha tem uma assinatura (data, valor, descrição e ordem entre linhas iguais). Linha já importada do mesmo cartão ou conta aparece como "Já importada" e não é lançada de novo, a menos que o usuário mande.
- **Edição em lote**: marcar várias linhas e trocar destino, categoria ou devedor de uma vez; ao decidir uma linha, o app oferece repetir nas outras do mesmo estabelecimento.
- **Extrato de conta** (`statement_extras.dart`): a saída que paga uma fatura pode marcar a fatura do cartão como paga (reconhecida pelo total do arquivo importado daquela fatura); a entrada pode virar aporte (só na conta da casa) ou abater um empréstimo de quem é dono da conta. O usuário escolhe; nada disso é automático.
- **Regras aprendidas** (`import_rules`): o que foi decidido para um estabelecimento (destino, categoria, devedor) é guardado ao confirmar e aplicado na próxima importação do mesmo cartão ou conta. A página lista as regras e deixa excluir. Só vira regra o estabelecimento em que todas as linhas tiveram a mesma decisão.
- **PDF e foto por IA** (`import-read` e `import_ai_service.dart`): a função devolve as linhas e o cabeçalho (vencimento, total, final do cartão); o app confere a soma das linhas com o total impresso e avisa quando não bate. O vencimento lido preenche o da fatura.
- **Sugestão de nome e categoria por IA**: botão na revisão, para as linhas da Casa ainda sem categoria; uma chamada para todas. A IA não decide o destino.
- **Seletor de destino com todos os moradores**: cada morador aparece pelo nome ("Marina deve"), sem um segundo campo para escolher o devedor.
- **Fatura agrupada na Casa** (`cycle_expense_grouping.dart`, `card_invoice_group_tile.dart`): em "Gastos do Ciclo", compras do mesmo cartão e vencimento aparecem como uma fatura, que abre para mostrar cada compra com a data da compra e o botão de registrar o pagamento. É só exibição.
- **Ciclo fechado**: as linhas afetadas são avisadas e o usuário escolhe lançar como ajuste no ciclo atual ou deixar de fora.
- **Testes**: `test/features/reconciliation/` (leitura, duplicidade, plano de gravação e a página).

**Limites do que foi feito**
- **Sem rascunho**: a revisão vive só na tela; sair da página antes de confirmar perde tudo.
- **Desfazer não reverte correções**: valor ou cartão trocado em despesa que já existia continua como ficou. Despesa já acertada em um fechamento e empréstimo que já teve pagamento impedem o desfazer; só quem emprestou (ou um administrador) desfaz um empréstimo.
- **A assinatura depende do arquivo**: se o banco mudar a descrição ou a data de uma linha entre um arquivo e outro, ela não é reconhecida como já importada (aí vale a comparação com as despesas do app).
- **Conta pendente** que casa com uma linha só é vinculada: a baixa continua sendo feita na Casa.
- **Movimentos do extrato são gravados depois da importação, um a um**: se um falhar (ciclo fechado, por exemplo), a importação continua gravada e a tela avisa qual não entrou. Desfazer a importação não reverte pagamento de fatura, aporte nem abatimento.
- **Estorno** não gera lançamento: aparece só para conferência.
- **A leitura por IA não foi testada com arquivo real**: a função está publicada e recusa quem não está logado, mas nenhuma fatura de verdade passou por ela ainda. PDF com senha não é lido.
- **O PDF vai inteiro para o provedor de IA**: não dá para mascarar CPF e número de cartão dentro de um arquivo binário. O mascaramento vale para o texto que volta e para as descrições enviadas na sugestão de categoria.
- **Sem cache da leitura por IA**: ler o mesmo PDF de novo gasta outra chamada.
- **CSV com colunas fora do comum** pode não ser lido (seção 11).
- **Sem dividir linha.**
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
- **Quem paga o banco**: hoje o app assume o titular (despesas pagas do próprio bolso, reembolso no fechamento). O dono decidiu que a fatura também pode ser paga pelo Caixa da Casa: ver seção 12.
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
4. **Conciliação**: feita (motor, tela, ciclo fechado, assinatura por linha e edição em lote). Falta dividir linha.
5. **Extrato**: pagamento de fatura, aporte e abatimento de empréstimo feitos. Falta o estorno.
6. **IA e outros formatos**: regras aprendidas, sugestão de categoria e leitura de PDF/foto feitas. Falta o mapeamento de colunas de CSV (seção 11).
7. **Histórico e desfazer**: feitos (migration 0052).

A etapa 6 exige publicar uma função nova (`import-classify`). O rascunho da revisão (etapa 3) exigiria outra mudança no banco.

## 10. Decisões em aberto

- **Vínculo automático**: recomendação de que o "Já lançado" venha pré-marcado, visível e desfazível.
- **Parcelas futuras**: criar as restantes nos próximos ciclos ou só a da fatura atual (recomendação: só a atual).
- **Linhas pessoais do titular**: ficam só no histórico da importação, sem virar despesa (como na especificação)?
- **Dividir a linha**: entra na primeira versão ou depois da conciliação?

## 11. Formatos de arquivo (fim do plano)

Nem todo banco exporta OFX ou CSV, e os CSV não têm colunas padronizadas; muitos só entregam PDF. Só a leitura muda: qualquer formato vira a mesma lista de linhas, e a conciliação, a revisão, a confirmação e o desfazer servem como estão. Fica para o fim do plano, depois das outras etapas.

| Formato | Como é lido | Situação |
|---|---|---|
| OFX | Por código; é um padrão | Feito |
| CSV com colunas reconhecíveis | Por código, detectando data, descrição e valor | Feito |
| CSV fora do padrão | Tela de mapear colunas, salva por cartão ou conta | A fazer |
| PDF digital | IA lê e devolve as linhas estruturadas | Feito, sem teste com arquivo real |
| PDF escaneado ou foto | A mesma função, com leitura de imagem | Feito, sem teste com arquivo real |

**CSV fora do padrão.** Quando o leitor não tiver certeza das colunas, a página mostra as primeiras linhas e o usuário indica qual é data, descrição e valor (e se débito e crédito vêm em colunas separadas). O mapeamento fica salvo para aquele cartão ou conta. Não usa IA.

**PDF.**
1. O arquivo vai para a função `import-read` no servidor (mesma estrutura de `capture-read`), que chama a IA. O arquivo é binário e segue como está; CPF e número de cartão são mascarados no texto que volta.
2. A resposta é estruturada: linhas (data, descrição, valor, parcela, tipo) e cabeçalho (final do cartão, vencimento, total, período).
3. O código confere se a soma das linhas bate com o total impresso; se não bater, a página avisa a diferença antes da revisão.
4. O vencimento lido preenche o da importação e o final do cartão confirma a origem escolhida.
5. Sem IA (limite, erro ou sem chave), a página avisa e sugere OFX ou CSV.

**Pontos de atenção.**
- PDF com senha (comum nas faturas enviadas por e-mail) não é aberto pela IA: pedir o PDF baixado pelo app do banco, ou incluir uma biblioteca para destravar.
- A fatura inteira vai para o provedor de IA: no plano gratuito o conteúdo pode ser usado pelo Google, então exige o plano pago antes de convidar outros usuários.
- Uma chamada por arquivo. O cache pelo conteúdo ainda não existe.
- Linha lida por IA entra na revisão como as outras, nunca direto no banco.

## 12. A fatura na Casa: em aberto ou paga, e com que dinheiro

Discussão de 14/10/2026 com o dono, depois de ele importar uma fatura real e ver as compras soltas e todas como pagas em "Gastos do Ciclo". O agrupamento por fatura já foi feito (seção 1). O resto desta seção ainda não foi implementado.

### 12.1. Como é hoje

- Compra no cartão nasce com status "paga", mesmo com a fatura em aberto. O que diz se a fatura foi quitada é a data de pagamento da fatura (`paid_at`), registrada pelo menu do cartão em Ajustes ou, agora, pela fatura agrupada na Casa.
- **Competência**: a compra conta no ciclo do pagamento registrado; sem registro, no ciclo do vencimento. Ex.: ciclo fecha dia 10, fatura vence dia 15. Marcada como paga no dia 9, entra no ciclo que fecha dia 10; marcada no dia 11 ou não marcada, entra no seguinte.
- **Fôlego**: fatura em aberto aparece em "Despesas Pagas". O saldo está certo (ele desconta pagas e a vencer), mas a coluna engana.
- **Fechamento**: ao fechar um ciclo, o app dá baixa em todas as contas pendentes dele e reembolsa quem pagou do bolso, sem olhar se a fatura foi paga. O registro de pagamento precisa ser feito antes de fechar; depois, só reabrindo o ciclo.
- **Quem paga**: se o cartão tem dono, toda compra é "paga do bolso do titular" e vira reembolso no fechamento. Não há como dizer que a fatura saiu do Caixa.

O boleto da internet serve de referência: em aberto, entra no ciclo do vencimento, aparece em "A Vencer", tem botão "Pagar" e, ao ser pago, passa a contar no ciclo do pagamento.

### 12.2. Em aberto ou paga: alternativas

| | O que muda | Risco |
|---|---|---|
| A. Só exibição | A fatura mostra "Em aberto" ou "Paga em"; as compras dentro dela deixam de parecer pagas; no Fôlego, fatura em aberto passa de "Despesas Pagas" para "A Vencer". Dados iguais. | Baixo |
| B. A + fatura como conta a pagar | Além de A: botão "Pagar" na fatura (pede a data e mostra em que ciclo ela cai), marca de atrasada depois do vencimento e aviso no fechamento quando uma fatura entra no ciclo sem pagamento registrado. Dados iguais. | Baixo |
| C. Só conta quando pagar | Fatura sem pagamento registrado não entra em fechamento nenhum e é carregada para os ciclos seguintes. | Alto |
| D. Fatura como registro próprio | Tabela de faturas com status, total do banco e pagamento; abre caminho para pagamento parcial e juros. | Alto, maior trabalho |

- **B e C só diferem em um caso**: o ciclo do vencimento fecha e a fatura não foi marcada. Na B ela entra pelo vencimento e o titular é reembolsado; na C fica de fora até alguém marcar.
- **C não é só trocar o status para pendente**: o fechamento dá baixa em toda conta pendente do ciclo. Exigiria mudar a regra de competência, o fechamento (pular faturas em aberto na baixa e no reembolso), a função do banco que decide se uma despesa conta em ciclo fechado, o planejamento de aportes e os dados já lançados.
- **Recomendação**: B, que deixa a fatura igual ao boleto. C fica registrada como alternativa; se for escolhida, é um trabalho próprio, planejado junto com o fechamento (`fechamento_no_banco.md`).
- **Decisão (14/10/2026)**: C, na forma "fatura como conta pendente" (seção 13). A B não será feita.

### 12.3. Com que dinheiro a fatura é paga (decidido; implementado na migration 0055)

Decisão do dono em 14/10/2026: **quem paga, paga a fatura inteira**. Ou o titular paga tudo com o próprio dinheiro, ou o Caixa da Casa paga tudo e depois é reembolsado do que não era da casa.

| Linha da fatura | Paga pelo titular (como é hoje) | Paga pelo Caixa da Casa |
|---|---|---|
| Da Casa | Despesa paga do bolso: o titular é reembolsado no fechamento | Despesa paga pelo Caixa: sem reembolso |
| De outro morador | Empréstimo: o morador deve ao titular | Empréstimo: o morador deve ao Caixa |
| Pessoal do titular | Nada | Empréstimo: o titular deve ao Caixa |

O app já tem empréstimo com o Caixa como credor ("acordo com o Lar"), usado na reposição de Caixinha.

**O que precisa ser feito**

1. **Origem do pagamento**: ao registrar o pagamento da fatura, perguntar "Do bolso de <titular>" (padrão) ou "Caixa da Casa". Na importação, "Quem paga" ganha a opção "Caixa da Casa".
2. **Despesas da casa**: com o Caixa, deixam de ser "pagas do próprio bolso".
3. **Linhas de outro morador**: o empréstimo passa a ter o Caixa como credor. Se a origem for escolhida depois da importação, o empréstimo já criado em nome do titular precisa trocar de credor; se já teve pagamento, a troca tem de ser recusada ou tratada à parte.
4. **Linhas pessoais do titular**: hoje não geram nada, ficam só no histórico da importação (`import_lines`). Com o Caixa pagando, viram um empréstimo do titular com o Caixa. O valor vem do histórico daquela fatura.
5. **Desfazer o pagamento** reverte a origem e os empréstimos que ela criou ou trocou.
6. **Banco**: a função `pay_card_invoice` passa a receber a origem e faz tudo em uma transação (migration 0054), respeitando as travas de ciclo fechado.
7. **Extrato**: pagamento de fatura achado no extrato da conta da casa já sugere "Caixa da Casa" como origem.

**Pontos em aberto (padrões adotados em 14/10/2026, a confirmar com o dono)**

- **Fatura sem importação**: o app não sabe quanto era pessoal do titular. Padrão adotado: o Caixa paga e nenhuma dívida é criada.
- **Como o titular e os moradores devolvem ao Caixa**: padrão adotado: parcela única cobrada no fechamento do ciclo do pagamento; o empréstimo de outro morador mantém o vencimento que já tinha.
- **Caixa sem saldo**: padrão adotado: só registrar.
- **Total do banco**: padrão adotado: a diferença entre as linhas importadas e o que o banco cobrou não é registrada.

### 12.4. Ordem

1. Fatura como conta pendente (seção 13).
2. Pagamento pelo Caixa da Casa com os empréstimos da 12.3, depois de fechar os pontos em aberto.

## 13. Fatura como conta pendente (decisão C)

**Situação (14/10/2026): implementada na branch `feat/import-reconciliation`, com a migration 0054 aplicada.** Feito: compra no cartão nasce pendente em todos os caminhos de lançamento (importação, formulário, scanner, assistente, mercado e dados do modo demo); pagamento da fatura com a origem do dinheiro (titular ou Caixa da Casa) pela Casa, por Ajustes, pela importação ("Fatura já paga?") e pelo extrato; fatura agrupada com "Em aberto", "Atrasada" ou "Paga em" e botão "Pagar"; passo novo no fechamento com as três escolhas. Testado só no modo demo e em testes; nada disso foi exercitado com conta real.

**Limites do que foi feito**
- Ao registrar a baixa no fechamento, o app grava o pagamento das faturas antes de confirmar o fechamento. Se a confirmação falhar depois disso, as faturas ficam pagas (o fechamento pode ser confirmado de novo).
- Despesa que já existia e a importação passou para o cartão ("provável" aceito) continua com o status que tinha; só o "pago do bolso" é zerado até o pagamento da fatura.
- Pagamento pelo Caixa com os empréstimos da seção 12.3: feito na migration 0055, só no banco (no modo demo o Caixa paga sem criar dívidas).

Decisões do dono em 14/10/2026:
- **C**: a compra no cartão não é tratada como paga até a fatura ser paga. O momento do pagamento define o ciclo.
- **No fechamento**: o app pergunta, fatura por fatura, o que fazer com a fatura em aberto que vence no ciclo. Se o usuário não mudar nada, ela recebe baixa como um boleto (resposta "2: A B", lida como "b, com a como padrão"; confirmar com o dono).

A ideia é reaproveitar o que o app já faz com o boleto da internet: conta pendente com vencimento, que aparece em "A Vencer", tem botão "Pagar", conta no ciclo do pagamento e, vencida, continua pesando nos ciclos seguintes.

### 13.1. Como fica

| Momento | O que acontece |
|---|---|
| Compra lançada no cartão (à mão, importada, scanner, assistente, mercado) | Despesa **pendente**, com o vencimento da fatura e sem pagador definido (não é "paga do bolso" ainda) |
| Fatura em aberto | "A Vencer" no Fôlego; na lista, a fatura agrupada com o botão "Pagar"; atrasada depois do vencimento |
| Pagar a fatura | Pede a data e a origem (titular ou Caixa da Casa) e mostra em que ciclo ela vai cair. Todas as compras pendentes da fatura viram pagas naquela data |
| Desfazer o pagamento | As compras voltam a pendentes |
| Importação | Pergunta "A fatura já foi paga? Em que data e com que dinheiro?". Sem resposta, entra em aberto |
| Fechamento com fatura em aberto que vence no ciclo | Para cada fatura: **dar baixa, paga pelo titular** (padrão), **dar baixa, paga pelo Caixa** ou **levar para o próximo ciclo** |

### 13.2. O que foi verificado no código (levantamento de 14/10)

- **Competência** (`cycle_expense_filter.dart`): compra de cartão conta em `paidAt ?? dueDate`; conta pendente vencida pesa nos ciclos seguintes. As duas regras já dão o comportamento acima sem mudança.
- **Leitura do ciclo** (`getExpensesForCycle`): já traz pendentes vencidas de ciclos anteriores.
- **Fôlego** (`getCycleSummary`): separa pagas e a vencer pelo status. Fatura pendente vai para "A Vencer" sozinha.
- **Trava de ciclo fechado no banco** (`expense_counts_in_closed_cycle`): ignora despesa pendente. Fatura antiga importada entra como atrasada no ciclo atual, sem o "lançar como ajuste".
- **Fechamento** (`global_clearing_engine.dart` e `confirm_cycle_settlement`): divide entre os moradores todas as despesas do ciclo, pagas e pendentes; reembolsa quem pagou do bolso sem olhar o status; e o banco dá baixa nas pendentes cujo id o app manda em `expense_ids`. O banco não exige que todas as pendentes do ciclo estejam no plano, então "levar para o próximo ciclo" é deixar a fatura fora do cálculo e das listas.
- **Planejamento de aportes** (`cycle_funding_estimator.dart`): só conta como "pago do bolso" despesa paga. Fatura pendente não vira crédito do titular antes do pagamento.
- **Pagamento de fatura no banco** (`pay_card_invoice`, migration 0028): hoje só grava `paid_at` em compras com `paid_at` nulo; não muda status nem origem.
- **Contas recorrentes**: o banco gera as ocorrências como pendentes com o vencimento da própria série (não o da fatura), mesmo quando a forma de pagamento é um cartão. Continuam como contas soltas.

### 13.3. O que muda

**Banco (migration 0054)**
1. `pay_card_invoice` recebe a origem (`p_paid_by_house`): marca as compras da fatura como pagas, grava `paid_at` e define `paid_out_of_pocket` (titular: sim, se o cartão tem dono; Caixa: não). Continua recusando ciclo fechado.
2. `undo_card_invoice_payment` volta as compras para pendentes, sem `paid_at` e sem "pago do bolso".
3. Dados existentes: compras de cartão com status pago, sem `paid_at`, sem `settled_at` e cujo ciclo não está fechado passam a pendentes. As já acertadas em fechamento ficam como estão.

**App**
1. **Caminhos de lançamento** (importação, formulário, scanner, assistente, mercado, dados do modo demo): compra no cartão com fechamento e vencimento nasce pendente. No formulário, o seletor "pago / a pagar" some para cartão e aparece "entra na fatura de dd/MM".
2. **Fatura agrupada**: passa a incluir as compras pendentes; "Pagar" abre o registro com data, origem e o ciclo em que vai cair; marca de atrasada.
3. **Compra dentro da fatura**: sem botão "Pagar" próprio (hoje ele trocaria a data da compra pela de hoje); o pagamento é da fatura.
4. **Fechamento**: passo novo na tela do fechamento listando as faturas em aberto do ciclo, com as três opções. "Dar baixa" registra o pagamento antes do cálculo; "levar para o próximo ciclo" tira as compras do cálculo e das listas do plano.
5. **Importação**: pergunta opcional "fatura já paga em / com" na revisão do cartão. O detector de duplicidade hoje só chama de "já lançado" despesa paga; precisa aceitar compra de cartão pendente, senão tudo vira "provável".
6. **Extrato**: o pagamento de fatura achado no extrato passa a origem (conta da casa = Caixa; conta de um morador = titular).

### 13.4. Riscos

- Mexe em dados existentes e no fechamento, a parte com mais regras do app. Migration validada em bloco com rollback antes de aplicar, e testes de fechamento novos (fatura paga antes do fechamento, baixa no fechamento pelo titular e pelo Caixa, fatura levada adiante, reabertura).
- Instâncias abertas do app com a versão antiga continuam criando compras pagas até serem reiniciadas.
- A fatura levada adiante continua aparecendo na lista do ciclo fechado (regra de conta vencida); a tela do ciclo fechado usa o retrato gravado no fechamento, então os valores acertados não mudam.

### 13.5. Fora desta etapa

- O pagamento pelo Caixa **com os empréstimos** da seção 12.3 (moradores e titular devendo ao Caixa). Nesta etapa, "Caixa da Casa" só tira o reembolso do titular.
- Pagamento parcial de fatura.
