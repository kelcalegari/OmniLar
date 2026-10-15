# Omni Lar — plano das notificações

Escrito em 15/10/2026. Junta o que estava espalhado (seção 9 da [arquitetura_tecnica.md](arquitetura_tecnica.md), a Frente 2 do [plano_diretor_unificado.md](plano_diretor_unificado.md) e os avisos citados em cada `modulo_*.md`) e confere com o que existe hoje no banco e no código. **Fica para depois das pendências de [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md)**: quando o dono pedir para começar, este é o ponto de partida. Peça aprovação antes de cada migration, como sempre.

## 1. O que existe hoje (conferido em 15/10/2026)

| Peça | Situação |
|---|---|
| Tabela `notifications` | Existe (migration 0001): `id`, `house_id`, `user_id`, `type`, `title`, `body`, `payload`, `deeplink`, `read_at`, `created_at`. Vazia. O morador lê e marca como lida só as dele; **ninguém consegue gravar** (não há regra de inserção) e ela **não está no tempo real** |
| Preferências | Só `assistant_preferences` (`is_enabled`, `proactive_summaries`, `quiet_hours_start`, `quiet_hours_end`), sem tela: os interruptores do Assistente foram removidos em 13/10 porque não gravavam nada |
| Tokens de aparelho | Não existe `device_tokens` |
| Envio | Não existe a função `notify` nem o `scheduler`; `pg_cron` e `pg_net` estão disponíveis no Supabase, mas não ligados |
| App | Sem Firebase no `pubspec.yaml`. O sino da Home não faz nada. `web/manifest.json` ainda tem nome, descrição e cor padrão do Flutter, e não há `web/firebase-messaging-sw.js` |
| Rotas | As telas têm rota (`/casa`, `/fechamento`, `/caixinhas`, `/importar`, `/projetos`, `/tarefas`, `/compras`, `/agenda`, `/pessoal`, `/relatorios`, `/ajustes`), mas **nenhuma abre um item específico** (não há `/pessoal/emprestimo/{id}` nem parecido) |

## 2. Princípios

Valem para toda notificação; os da seção 9 da arquitetura continuam valendo.

1. **Histórico primeiro.** Toda notificação é gravada em `notifications` e aparece no sino; o push é um envio a mais. Se o push se perder, o aviso continua no app.
2. **Quem gera é o banco, não o app.** Notificação de um acontecimento sai de um gatilho no banco (ou do agendador), nunca do aparelho de quem fez a ação: assim ela sai mesmo se o app fechar no meio, vale para a fila offline e não depende da versão do app.
3. **Quem fez a ação não é avisado dela.** O autor fica de fora dos destinatários.
4. **Uma vez só.** Cada notificação tem uma chave de repetição (`dedupe_key`, por exemplo `loan_installment_due:{parcela}:{dia}`); gravar de novo a mesma chave não cria outra. Os lembretes agendados usam a janela no lugar do dia.
5. **Respeita a visibilidade.** Evento restrito só avisa quem participa; item pessoal da compra não vira aviso para os outros; valores seguem o modo privacidade da tela só dentro do app (o texto do push é decidido na seção 7).
6. **Deeplink em toda notificação**, como rota do GoRouter que abre o item (seção 5). A mesma rota serve no Android, no navegador e no iPhone instalado.
7. **Um canal de envio: FCM** (Android, navegador e iPhone com o site instalado, iOS 16.4+). Sem APNs nativo, porque o app não vai para a App Store.
8. **Permissão só depois de um toque** num botão "Ativar notificações", nunca ao abrir o app. No iPhone fora do modo instalado, o app mostra o passo a passo para instalar.
9. **Sem push silencioso.** Todo push mostra algo visível; não há sincronização em segundo plano.
10. **O morador decide.** Preferência por grupo (seção 4) e horário silencioso. O que é essencial (seção 6) pode ter o push desligado, mas continua no sino.
11. **Agrupar o que vem em rajada.** Vários lançamentos seguidos da mesma pessoa (uma importação, uma compra fechada) viram um aviso só ("Ana lançou 12 despesas").

## 3. Arquitetura proposta

### 3.1. Banco
- **`notifications`** ganha `dedupe_key` (único por destinatário), `entity_type` e `entity_id` (para marcar como lida quando o item é resolvido), `category` (o grupo da seção 4), `actor_id` e `push_status` (`pending`, `sent`, `skipped`, `failed`) com `pushed_at`. Entra no tempo real, filtrada por `user_id`.
- **`device_tokens`** (`user_id`, `token`, `platform`: `android`, `web`, `ios_pwa`, `last_seen_at`), com regra de acesso só do próprio usuário.
- **`notification_preferences`** (`user_id`, `house_id`, `category`, `in_app`, `push`) e o horário silencioso. O horário silencioso hoje está em `assistant_preferences`; a proposta é ele valer para todas as notificações (decisão 2 da seção 7).
- **`enqueue_notification(...)`**: função do banco (`security definer`) que os gatilhos chamam. Calcula os destinatários, tira o autor, aplica a visibilidade, grava com a `dedupe_key` e marca `push_status`.
- **Gatilhos** nas tabelas dos acontecimentos (seção 6). Os lembretes saem de um job do `pg_cron` que chama `run_scheduled_notifications()` de hora em hora (vencimentos, ciclo fechando, resumo).

### 3.2. Envio
- Cada linha nova com `push_status = 'pending'` chama a Edge Function **`notify`** (pelo `pg_net` ou por um Database Webhook). Ela confere preferência e horário silencioso, envia pelo FCM (API HTTP v1) para os tokens do usuário, apaga o token que o FCM disser que é inválido e grava o resultado.
- Fora do horário silencioso, o que caiu nele é enviado no fim do horário, num aviso só.
- Segredos do FCM nos *secrets* do Supabase.

### 3.3. App
- **Sino** na Home com a contagem de não lidas e a lista (agrupada por dia), "marcar todas como lidas" e toque abrindo o deeplink.
- **Ativar notificações** nos Ajustes (grupo Aplicativo): botão de permissão, passo a passo do iPhone, preferências por grupo e horário silencioso. Os interruptores do Assistente voltam aqui, agora gravando de verdade.
- **Pacotes:** `firebase_core`, `firebase_messaging` (Android e web) e `flutter_local_notifications` (só Android, para avisar com o app aberto). Na web, `web/firebase-messaging-sw.js` e o `manifest.json` com nome, ícones e cores do Omni Lar.
- **Número no ícone** (Badging API) com as não lidas, onde houver suporte.
- No modo demo, notificações de exemplo só no sino, sem push.

## 4. Grupos (para as preferências)

| Grupo | O que entra |
|---|---|
| Casa | Moradores, convites, papéis |
| Contas e despesas | Despesas lançadas por outros, contas a vencer e vencidas, faturas |
| Fechamento do ciclo | Ciclo terminando, fechamento confirmado ou reaberto, Super Pix |
| Empréstimos | Novo empréstimo, aceite, parcelas, pagamento, perdão, renegociação |
| Aportes e caixinhas | Aporte registrado, aporte pendente, depósitos e resgates, meta atingida |
| Compras | Compra iniciada ou concluída, item pedido |
| Tarefas | Tarefa atribuída, troca, atraso, concluída |
| Agenda | Convite, resposta, evento em risco, alterado ou cancelado, lembrete |
| Projetos | Participação, despesa e acerto do projeto |
| Assistente | Resumo semanal e alertas proativos |

## 5. Deeplinks

Hoje as rotas só abrem a tela. Para a notificação abrir o item, as rotas passam a aceitar o id (o formato exato é a decisão 3 da seção 7). Proposta:

| Item | Rota |
|---|---|
| Despesa ou conta | `/casa/despesa/{id}` |
| Fatura do cartão | `/casa/fatura/{cartão}/{vencimento}` |
| Fechamento do ciclo | `/fechamento?ciclo={início}` |
| Empréstimo | `/pessoal/emprestimo/{id}` |
| Caixinha | `/caixinhas/{id}` |
| Lista de compras | `/compras` |
| Tarefa | `/tarefas/{id}` |
| Evento | `/agenda/evento/{id}` |
| Projeto | `/projetos/{id}` |
| Importação | `/casa/importar` |
| Moradores | `/ajustes?grupo=casa` |

Item que não existe mais (excluído) abre a tela da lista com o aviso "Este item não existe mais".

## 6. Catálogo

Coluna **Quando**: *na hora* (gatilho no banco) ou *agendada* (`pg_cron`). Coluna **Peso**: *essencial* (pede ação ou mexe com dinheiro: push ligado por padrão, não some do sino até ser resolvida) ou *informativa* (push ligado por padrão, pode ser desligada). Os textos são exemplos.

### 6.1. Casa
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `member_joined` | Alguém entra pela casa com o convite | Moradores | "Cristiano entrou na Nossa Casa" | na hora | informativa |
| `member_left` | Morador sai ou é removido | Moradores (e quem saiu) | "Ana saiu da casa" | na hora | informativa |
| `member_role_changed` | Papel muda (administrador) | O morador | "Você agora é administrador da Nossa Casa" | na hora | informativa |
| `split_model_changed` | Modelo de rateio ou aporte fixo muda | Moradores | "O rateio da casa mudou para Aportes fixos" | na hora | essencial |
| `cycle_day_changed` | Dia de início do ciclo muda | Moradores | "O ciclo passa a começar no dia 10 a partir de novembro" | na hora | informativa |

### 6.2. Contas e despesas
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `expense_added` | Despesa da casa lançada por outro (agrupada) | Moradores com parte no rateio | "Ana lançou Mercado: R$ 312,40 (sua parte R$ 156,20)" | na hora | informativa |
| `expense_changed` | Valor, rateio ou pagador muda em despesa com parte sua | Quem tem parte | "Kelvynn alterou Internet: de R$ 99,90 para R$ 119,90" | na hora | informativa |
| `expense_deleted` | Despesa com parte sua excluída | Quem tem parte | "Ana excluiu Farmácia (R$ 45,00)" | na hora | informativa |
| `bill_due_soon` | Conta pendente vence em 3 dias e no dia | Moradores (ou o dono da categoria) | "Luz vence amanhã: R$ 180,00" | agendada | essencial |
| `bill_overdue` | Conta pendente passou do vencimento (no dia seguinte e a cada 3 dias, até 3 vezes) | Moradores | "Luz está vencida há 2 dias" | agendada | essencial |
| `recurring_generated` | Ocorrência de conta recorrente gerada sem valor (conta variável) | Moradores | "Água de novembro precisa do valor" | agendada | essencial |
| `invoice_closing` | Fatura do cartão fecha em 2 dias | Titular | "Fatura Nubank fecha sexta: R$ 1.240,00 até agora" | agendada | informativa |
| `invoice_due_soon` | Fatura em aberto vence em 3 dias e no dia | Titular (e moradores, se o cartão é da casa) | "Fatura Nubank vence dia 5: R$ 1.480,00" | agendada | essencial |
| `invoice_paid` | Fatura paga | Titular e moradores com compras nela | "A fatura Nubank de outubro foi paga pelo Caixa" | na hora | informativa |
| `reimbursement_due` | Despesa paga do bolso entrou no ciclo | Quem pagou | "Você será reembolsado de R$ 80,00 no fechamento" | na hora | informativa |

### 6.3. Fechamento do ciclo
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `cycle_closing_soon` | Faltam 3 dias para o fim do ciclo | Moradores | "O ciclo fecha em 3 dias. Confira seus lançamentos" | agendada | informativa |
| `cycle_ended` | O ciclo terminou e não foi fechado (no dia seguinte e 3 dias depois) | Dono e administradores | "O ciclo de outubro terminou. Faça o fechamento" | agendada | essencial |
| `settlement_confirmed` | Fechamento confirmado | Moradores | "Ciclo de outubro fechado. Você paga R$ 420,00 a Ana" | na hora | essencial |
| `settlement_reopened` | Ciclo reaberto | Moradores | "Kelvynn reabriu o ciclo de outubro" | na hora | essencial |
| `transfer_pending` | Super Pix seu ainda não confirmado (2 dias depois do fechamento e a cada 3 dias) | Quem paga | "Falta pagar R$ 420,00 a Ana do ciclo de outubro" | agendada | essencial |
| `transfer_confirmed` | Quem recebe confirma a transferência | Quem pagou | "Ana confirmou o recebimento de R$ 420,00" | na hora | informativa |
| `transfer_resolved` | Transferência perdoada ou renegociada | Quem paga | "Ana perdoou R$ 20,00 do ciclo de outubro" | na hora | essencial |

### 6.4. Aportes e caixinhas
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `contribution_added` | Aporte registrado por outro em seu nome ou no Caixa | O morador do aporte | "Aporte de R$ 1.500,00 registrado em seu nome" | na hora | informativa |
| `contribution_pending` | No modelo de aportes fixos, morador sem aporte 5 dias depois do início do ciclo | O morador | "Seu aporte de R$ 1.500,00 de novembro ainda não entrou" | agendada | essencial |
| `funding_short` | O Fôlego ficou negativo | Dono e administradores | "O Caixa ficou R$ 200,00 no vermelho neste ciclo" | na hora (uma vez por ciclo) | essencial |
| `vault_movement` | Depósito ou resgate feito por outro | Moradores | "Ana resgatou R$ 300,00 da Reserva da Casa" | na hora | informativa |
| `vault_goal_reached` | Caixinha atingiu a meta | Moradores | "Viagem atingiu a meta de R$ 5.000,00" | na hora | informativa |

### 6.5. Empréstimos
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `loan_created` | Empréstimo criado com você como devedor (pede aceite) | Devedor | "Kelvynn registrou que você deve R$ 50,00. Aceitar?" | na hora | essencial |
| `loan_accepted` / `loan_declined` | Devedor aceita ou recusa | Credor | "Cristiano aceitou o empréstimo de R$ 50,00" | na hora | informativa |
| `installment_due_soon` | Parcela vence em 3 dias e no dia (se não é cobrada no fechamento) | Devedor | "Parcela 2/3 a Kelvynn vence amanhã: R$ 100,00" | agendada | essencial |
| `installment_overdue` | Parcela vencida (no dia seguinte e a cada 5 dias, até 3 vezes) | Devedor e credor | "Parcela 2/3 está vencida há 1 dia" | agendada | essencial |
| `loan_payment` | Pagamento ou abatimento registrado | A outra parte | "Cristiano pagou R$ 100,00 do empréstimo" | na hora | informativa |
| `loan_paid_off` | Empréstimo quitado | As duas partes | "Empréstimo Conserto do carro quitado" | na hora | informativa |
| `loan_forgiven` | Empréstimo perdoado | Devedor | "Kelvynn perdoou os R$ 300,00 restantes" | na hora | informativa |
| `loan_renegotiated` | Renegociação feita | A outra parte | "Novas parcelas: 6x de R$ 50,00 a partir de 10/12" | na hora | essencial |
| `loan_deleted` | Empréstimo excluído | A outra parte | "Kelvynn excluiu o empréstimo de R$ 50,00" | na hora | informativa |

### 6.6. Compras
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `shopping_started` | Alguém entra no modo compra | Moradores | "Ana está no mercado. Falta algo?" | na hora | informativa |
| `shopping_item_added_during_trip` | Item adicionado enquanto alguém está comprando | Quem está comprando | "Kelvynn pediu Café" | na hora | informativa |
| `shopping_completed` | Compra fechada | Moradores (e quem pediu item pessoal) | "Ana fechou a compra: R$ 312,40. Seu item pessoal: R$ 18,00" | na hora | informativa |

### 6.7. Tarefas
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `task_assigned` | Tarefa atribuída por outro | Responsável | "Nova tarefa: Comprar pó de café, até sexta" | na hora | essencial |
| `task_swap_requested` | Responsável pede troca | Quem criou | "Cristiano pediu para trocar Lavar o carro" | na hora | essencial |
| `task_swap_answered` | Troca aprovada ou recusada | Quem pediu | "Kelvynn aprovou a troca" | na hora | informativa |
| `task_due_soon` | Vence hoje | Responsável | "Lavar o carro vence hoje" | agendada | informativa |
| `task_overdue` | Venceu sem conclusão (uma vez) | Responsável e quem criou | "Lavar o carro está atrasada" | agendada | essencial |
| `task_completed` | Concluída por outro | Quem criou | "Cristiano concluiu Lavar o carro" | na hora | informativa |

### 6.8. Agenda
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `event_invite` | Marcado num evento | Participantes | "Jantar com a família, sábado 20h. Você foi marcado como necessário" | na hora | essencial |
| `event_rsvp` | Participante responde | Quem criou | "Ana confirmou presença no Jantar" | na hora | informativa |
| `event_at_risk` | Um necessário recusou | Quem criou | "Jantar está em risco: Ana não pode ir" | na hora | essencial |
| `event_changed` | Data, hora ou local muda | Participantes | "Jantar mudou para domingo 19h" | na hora | essencial |
| `event_cancelled` | Evento cancelado ou excluído | Participantes | "Jantar foi cancelado" | na hora | essencial |
| `event_reminder` | Começa em 1 hora (ou na véspera, se for o dia inteiro) | Participantes que não recusaram | "Consulta começa às 15h" | agendada | informativa |

### 6.9. Projetos compartilhados
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `project_added` | Incluído como participante | O participante | "Você entrou no projeto Viagem à praia (25%)" | na hora | informativa |
| `project_expense_added` | Despesa lançada no projeto por outro | Participantes | "Ana lançou Hotel no projeto: R$ 800,00 (sua parte R$ 200,00)" | na hora | informativa |
| `project_settled` | Acerto do projeto feito | Participantes | "Viagem à praia acertada: você recebe R$ 150,00" | na hora | essencial |

### 6.10. Importação
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `import_confirmed` | Importação confirmada (um aviso por importação) | Moradores com parte nas despesas e devedores dos empréstimos criados | "Kelvynn importou a fatura Nubank: 12 despesas da casa, 2 empréstimos para você" | na hora | informativa |
| `import_undone` | Importação desfeita | Os mesmos | "Kelvynn desfez a importação da fatura Nubank" | na hora | informativa |

### 6.11. Assistente
| Tipo | Gatilho | Quem recebe | Exemplo | Quando | Peso |
|---|---|---|---|---|---|
| `weekly_summary` | Domingo às 19h, se ligado | Cada morador | "Semana: R$ 640,00 gastos, Fôlego R$ 1.200,00, 2 contas na semana que vem" | agendada | informativa |
| `proactive_alert` | Gasto de uma categoria passa da média do planejamento | Moradores | "Mercado já está em 90% do previsto para o ciclo" | na hora (uma vez por categoria e ciclo) | informativa |

## 7. Decisões pendentes do dono

**Antes de começar, pergunte se ele segue as recomendações (⭐) ou escolhe outra letra.**

1. **Aviso de despesa lançada por outro** (`expense_added`)
   - a) ⭐ Ligado, agrupado (várias seguidas da mesma pessoa viram um aviso)
   - b) Só no sino, sem push
   - c) Não avisar
2. **Horário silencioso**
   - a) ⭐ Um só, para todas as notificações; o que cair nele sai no fim, num aviso só
   - b) Só para o Assistente, como está no banco hoje
3. **Formato do deeplink**
   - a) ⭐ Rota com o id do item (`/pessoal/emprestimo/{id}`), como na seção 5
   - b) Tela com parâmetro (`/pessoal?emprestimo={id}`)
4. **Valores no texto do push** (aparece na tela bloqueada)
   - a) ⭐ Mostrar valores, com um interruptor "Esconder valores nas notificações"
   - b) Nunca mostrar valores no push (só no sino)
5. **Aceite de empréstimo pelo devedor** (`loan_created`): o status `pendingAcceptance` existe, mas o app não tem a tela de aceite
   - a) ⭐ Fazer o aceite junto com as notificações (o aviso tem os botões Aceitar e Recusar no Android; no iPhone, abre o empréstimo)
   - b) Só avisar, sem aceite
6. **Troca de tarefa** (`task_swap_requested`): o app ainda não tem o pedido de troca
   - a) Fazer o pedido de troca junto com as notificações
   - b) ⭐ Deixar para depois; avisar só a atribuição
7. **Lembretes repetidos de atraso** (contas, parcelas, transferências)
   - a) ⭐ Até 3 lembretes por item, como no catálogo
   - b) Um lembrete só
   - c) Todo dia até resolver
8. **Resumo semanal**
   - a) ⭐ Desligado por padrão, ligado nos Ajustes
   - b) Ligado por padrão

## 8. Ordem de implementação sugerida

1. **Base** (migration): colunas novas em `notifications`, `device_tokens`, `notification_preferences`, `enqueue_notification` e `notifications` no tempo real.
2. **Sino no app**: lista, não lidas, marcar como lida, deeplink com as rotas novas (seção 5). Já dá para testar sem push.
3. **Gatilhos na hora** começando pelos essenciais: empréstimos, fechamento e transferências, tarefas atribuídas, agenda. Depois os informativos.
4. **Push**: Firebase no app, `firebase-messaging-sw.js`, `manifest.json`, botão "Ativar notificações", passo a passo do iPhone e a função `notify`.
5. **Agendados**: `pg_cron` com `run_scheduled_notifications()` (vencimentos, atrasos, ciclo terminando, aporte pendente).
6. **Preferências e horário silencioso** nos Ajustes, com a volta dos interruptores do Assistente.
7. **Assistente**: resumo semanal e alertas proativos.

## 9. Testes

- Cada gatilho: um ensaio com rollback no banco, simulando o usuário, conferindo destinatários, que o autor fica de fora, a visibilidade e a `dedupe_key`.
- Agendados: chamar `run_scheduled_notifications()` com uma data simulada e conferir que rodar duas vezes não repete.
- App: testes do sino, do deeplink e das preferências no modo demo.
- Push: o dono testa no Android, no navegador e no iPhone com o site instalado (aberto pelo ícone), com sessão real.
