# Plano: próximas frentes de código

Escrito em 17/10/2026, a pedido do dono, a partir da lista do que ainda falta escrever no app ou no banco (seção 3 de [plano_diretor_unificado.md](plano_diretor_unificado.md) e "Em aberto" de [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md)). Cada frente diz como está hoje, o que propõe e as decisões do dono, com a recomendação marcada com ⭐.

## Andamento (17/10/2026)

O dono seguiu todas as recomendações ⭐. Feito na branch `feat/proximas-frentes`, com 622 testes passando; merge na `main`, migrations 0076 a 0082 aplicadas e `delete-account` publicada em 17/10/2026:

| Frente | Situação |
|---|---|
| 1. Ciclos de antes da casa | Feito (só app) |
| 2. Alertas do Supabase | Migrations 0076 a 0078 escritas e ensaiadas |
| 3. Exclusão de conta | Migration 0081 e função `delete-account` escritas, ensaiadas no banco |
| 4.1 Preferências de notificação | Feito (tela nos Ajustes) |
| 4.2 Resumo semanal | Migration 0079. Mudou do plano: o Fôlego ficou fora do texto (a conta dele é do app); semana sem gasto e sem conta não gera aviso |
| 4.3 Gatilhos informativos | Migration 0080 (`expense_added`, `shopping_completed`, `import_confirmed`) |
| 4.4 Aceite de empréstimo | Migration 0082 e telas |
| 4.5, 5, 6.3, 7, 8 | Ficaram para depois, como recomendado |
| 6.1 e 6.2 | Feitos (arrastar arquivo na importação; `Ctrl + F` nos Ajustes e no painel do administrador; lançamentos não têm busca) |
| 9 | Feito (seção 10 da importação atualizada) |

Detalhes que o plano não previa:
- **Exclusão de conta:** apagar o usuário do Auth apagaria por cascata o rateio (`split_rules`) e os aportes dele nas casas dos outros, e despesas, empréstimos e transferências impedem a exclusão. Por isso, quando ele divide ou dividiu casa, a conta fica sem e-mail, sem senha e bloqueada, e o perfil vira "Ex-morador"; só quem não mora nem morou com ninguém é apagado do Auth. Apagar uma casa esbarrava na auditoria e no bloqueio do livro-razão: as duas travas passaram a liberar só durante a exclusão (marca `omnilar.deleting_house`, válida dentro da transação). A conta ganhou a situação "Excluída" (`deleted`).
- **Aceite de empréstimo:** recusar cancela o empréstimo (status `cancelled`, que o app deixa fora da lista); pagar uma parcela vale como aceite; empréstimos criados pelas funções do banco (fechamento, fatura paga pelo Caixa) nascem aceitos. O fechamento do banco não precisou mudar: quem monta o plano é o app, que deixa o não aceito de fora e avisa na tela.

O cálculo do fechamento no banco fica de fora (adiado por decisão do dono, em [fechamento_no_banco.md](fechamento_no_banco.md)).

## 1. Ciclos de antes da casa existir (novo)

**Como está:** as setas de ciclo da Home (Fôlego), dos Relatórios e do Fechamento voltam sem limite (`previousCycle` em `home_page.dart`, `reports_page.dart` e `settlement_hub_page.dart`, sem conferir data mínima). Dá para chegar a ciclos de antes da criação da casa: aparecem vazios, o selo do Fôlego mostra "Em aberto" e o Fechamento trata o ciclo como um ciclo comum que ainda não foi fechado. O banco guarda `houses.created_at`, mas o app não lê (`House` não tem esse campo). O agendador das notificações já ignora ciclos de antes da casa (`cycle_ended` só sai "se a casa já existia").

**Proposta:** o app passa a conhecer o **primeiro ciclo da casa** e não navega para antes dele.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 1.1 | Qual é o primeiro ciclo | **a)** ⭐ O mais antigo entre o ciclo da criação da casa e o ciclo do lançamento mais antigo (despesa, aporte ou empréstimo). Assim uma fatura ou despesa antiga lançada com data retroativa continua visível | b) Só o ciclo da criação da casa (lançamento retroativo ficaria escondido); c) só o do lançamento mais antigo (casa nova sem lançamento não teria início) |
| 1.2 | O que a seta "anterior" faz no primeiro ciclo | **a)** ⭐ Fica desabilitada, com a dica "Primeiro ciclo da casa" | b) Some; c) continua navegando, mas mostra "A casa ainda não existia neste ciclo" |
| 1.3 | Lançar despesa com data anterior ao primeiro ciclo | **a)** ⭐ Continua permitido; o primeiro ciclo passa a ser o dessa data (regra 1.1) | b) Recusar datas anteriores à criação da casa |

**Como fazer:** ler `created_at` junto com a casa; a data do lançamento mais antigo vem de uma consulta simples (o menor entre `house_expenses`, `contributions` e `p2p_loans` da casa), sem migration. O limite vale nos três lugares das setas e no atalho `/fechamento?ciclo=`. No modo demo, o primeiro ciclo é o do lançamento mais antigo da casa demo. Testes de tela para as três setas.

## 2. Alertas do Supabase

**Como está:** relatório de 17/10/2026, sem nada alterado. Nenhum alerta é urgente com uma casa só; todos valem antes de abrir para outras casas.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 2.1 | Funções de gatilho `security definer` executáveis por `anon` (19) | **a)** ⭐ Uma migration que revoga `execute` de `anon` e de `public` nessas 19 (gatilho não é chamado direto por ninguém). As RPCs que o app chama continuam com `authenticated` | b) Revogar também das RPCs que só o banco usa, conferindo uma a uma (mais trabalho, pouco ganho) |
| 2.2 | `auth.uid()` reavaliado por linha nas regras de acesso (54) | **a)** ⭐ Uma migration que recria as 54 regras trocando por `(select auth.uid())`, gerada a partir de `pg_policies` e conferida no ensaio (a regra recriada tem de devolver as mesmas linhas para os dois moradores) | b) Só nas tabelas grandes (`house_expenses`, `expense_splits`, `notifications`, `audit_log`) |
| 2.3 | Chaves estrangeiras sem índice (66) | **a)** ⭐ Índice só nas mais consultadas (as de `house_id`, `expense_id`, `loan_id`, `vault_id`, `category_id`, `payment_method_id` e `user_id`), cerca de 20 | b) Todas as 66 (mais espaço e escrita mais lenta, sem uso); c) nenhuma por enquanto |
| 2.4 | 13 índices não usados | **a)** ⭐ Deixar: com uma casa só, "não usado" não quer dizer inútil | b) Apagar |
| 2.5 | Proteção contra senha vazada | Ligar no painel do Supabase (Auth); é do dono. Conferir se o plano atual oferece a opção | — |

**Como fazer:** três migrations (0076 a 0078), cada uma com ensaio com rollback antes e pedido de aplicação ao dono. Depois, rodar o relatório de alertas de novo.

## 3. Exclusão de conta (LGPD)

**Como está:** não existe; o painel administrativo só suspende (decisão 10 de [plano_painel_admin.md](plano_painel_admin.md): Edge Function `delete-account` com confirmação dupla, que apaga perfil e dados pessoais e tira a pessoa das casas sem apagar o histórico financeiro dos outros moradores).

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 3.1 | Onde fica o botão | **a)** ⭐ Ajustes › Aplicativo › Conta e segurança, no fim, em vermelho | b) Só pelo suporte (e-mail) |
| 3.2 | Confirmação | **a)** ⭐ Digitar a senha e a palavra "EXCLUIR" | b) Só a senha; c) código por e-mail |
| 3.3 | Pessoa é o único morador da casa | **a)** ⭐ A casa é apagada junto, com aviso antes | b) A casa fica órfã para um administrador do Omni Lar apagar |
| 3.4 | Pessoa é dona da casa e há outros moradores | **a)** ⭐ A propriedade passa ao administrador mais antigo da casa (ou ao morador mais antigo, se não houver); a tela diz para quem antes de confirmar | b) Exigir que a pessoa passe a propriedade antes de excluir |
| 3.5 | Dívidas em aberto ou ciclo não fechado | **a)** ⭐ Não bloqueia, mas avisa com a lista; os empréstimos ficam no histórico com o nome "Ex-morador" e continuam cobráveis pelos outros | b) Bloquear até quitar ou perdoar tudo |
| 3.6 | Nome no histórico dos outros | **a)** ⭐ Trocar por "Ex-morador" (o histórico financeiro fica, os dados pessoais saem) | b) Manter o nome |
| 3.7 | Prazo | **a)** ⭐ Imediata | b) 7 dias para desistir, com a conta suspensa no meio |

**Como fazer:** Edge Function `delete-account` (`verify_jwt=true`, só a própria conta) que chama uma função do banco numa transação (casas, propriedade, anonimização, tokens de aparelho, avisos) e depois apaga o usuário do Auth. Migration para a função do banco, com ensaio. O modo demo só mostra o fluxo.

## 4. Notificações

**Como está:** fases 1 a 5 no ar ([plano_notificacoes.md](plano_notificacoes.md), seção 0). As tabelas de preferências (`notification_preferences`, `notification_settings`) já existem; falta a tela.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 4.1 | Preferências nos Ajustes (fase 6) | **a)** ⭐ Primeiro desta frente: em Ajustes › Aplicativo › Notificações, um interruptor por grupo (sino e push separados), horário silencioso, "esconder valores" e resumo semanal. Avisos essenciais aparecem travados | b) Só liga/desliga geral do push |
| 4.2 | Resumo semanal | **a)** ⭐ Domingo às 18h, no sino e no push, ligado por padrão e desligável na tela 4.1: gasto da semana, contas que vencem na próxima e o Fôlego | b) Desligado por padrão; c) não fazer |
| 4.3 | Gatilhos informativos que faltam | **a)** ⭐ Só os de pouco barulho: despesa lançada por outro (agrupada, já decidido), compra do mercado fechada e importação confirmada. Projetos e mudanças da casa ficam para depois | b) Todos os do catálogo |
| 4.4 | Aceite de empréstimo pelo devedor (decisão 5a já tomada) | **a)** ⭐ Empréstimo lançado por quem emprestou nasce "aguardando aceite" e avisa o devedor; lançado pelo próprio devedor já nasce aceito. O fechamento ignora o que não foi aceito e a tela do fechamento avisa. Recusar exclui o empréstimo e avisa quem lançou | b) Aceite só informativo (o empréstimo vale mesmo sem aceite); c) deixar para depois |
| 4.5 | Alertas do Assistente (fase 7) | **a)** ⭐ Deixar para depois das outras: dependem da IA e da cota do plano | b) Fazer junto |

**Como fazer:** 4.1 é só app. 4.2 e 4.3 são migrations no agendador e nos gatilhos. 4.4 é a maior: status novo no banco, gatilho, fechamento e telas de empréstimo. Antes de 4.4, decidir junto o que fazer com `transfer_pending` (as transferências do Super Pix nascem confirmadas).

## 5. Cópia local para abrir sem internet

**Como está:** o dono decidiu em 15/10/2026 deixar como está (item 8). A fila offline cobre a conexão que cai no meio do uso.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 5.1 | Fazer agora | **a)** ⭐ Continua adiado, até haver relato de uso sem internet | b) Cópia só de leitura do ciclo atual, da lista de compras e das tarefas (guardada no aparelho, atualizada a cada carga); c) cópia completa com sincronização |

## 6. Web e computador

**Como está:** nenhum dos três existe.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 6.1 | Arrastar o arquivo para a importação | **a)** ⭐ Fazer: área de soltura na página de importação, com o mesmo fluxo do "Escolher arquivo" (no navegador e no Windows) | b) Não fazer |
| 6.2 | `Ctrl + F` | **a)** ⭐ Fazer: abre a busca da tela atual (lançamentos, Ajustes); onde a tela não tem busca, não faz nada | b) Busca geral do app (trabalho maior) |
| 6.3 | Lançamentos em grade | **a)** ⭐ Deixar para depois: a lista atual já usa a largura no computador | b) Tabela com colunas e ordenação a partir de 1024 px |

## 7. Boleto de condomínio com os itens

**Como está:** o boleto vira uma despesa só; o código de barras não traz os itens. Despesa com sub-itens já existe.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 7.1 | De onde vêm os itens | **a)** ⭐ Da foto ou do PDF do boleto, lidos pela IA (conta na cota), que devolve os itens (água, gás, fundo de reserva…) como sub-itens; o código de barras continua dando valor e vencimento | b) Itens digitados à mão, com a lista do mês anterior sugerida |
| 7.2 | Quando fazer | **a)** ⭐ Só com um boleto real do dono para testar a leitura | b) Já, com um boleto de exemplo |

## 8. Troca de ciclo mais rápida

**Como está:** o resumo do ciclo relê despesas e aportes por dentro.

| Nº | Decisão | Recomendação | Alternativas |
|---|---|---|---|
| 8.1 | Fazer agora | **a)** ⭐ Não; só se a troca de ciclo parecer lenta | b) Fazer agora |

## 9. Importação: decisões da seção 10 do plano

**Como está:** as quatro já foram resolvidas na implementação; só o texto da seção 10 de [plano_importacao_conciliacao.md](plano_importacao_conciliacao.md) ficou velho.

| Pergunta | Como ficou no código |
|---|---|
| O "Já lançado" vem marcado? | Sim, aceito de saída e desfazível ("São diferentes") |
| Parcelas futuras | Só a parcela da fatura importada vira despesa; as próximas entram nas próximas faturas |
| Compras pessoais do titular | Ficam só no histórico da importação; se o Caixa paga a fatura, viram dívida do titular com o Caixa (migration 0055) |
| Dividir a linha | Feito (uma linha vira duas partes, com "Juntar") |

**Recomendação:** ⭐ só atualizar a seção 10 do plano para dizer que está resolvida.

## 10. Ordem sugerida

1. **Ciclos de antes da casa** (frente 1): pequena, só app, e mexe no que o dono vê todo dia.
2. **Alertas do Supabase** (frente 2): três migrations com ensaio.
3. **Preferências de notificação** (4.1), depois o resumo semanal (4.2) e os gatilhos (4.3).
4. **Exclusão de conta** (frente 3).
5. **Arrastar arquivo e `Ctrl + F`** (6.1 e 6.2).
6. **Aceite de empréstimo** (4.4).
7. **Boleto de condomínio** (frente 7), quando houver um boleto real.
8. **Atualizar a seção 10 da importação** (frente 9): junto com qualquer uma das anteriores.
