# Omni Lar — painel administrativo

Ideia registrada em 15/10/2026 e revista em 16/10/2026. **Decisões do dono tomadas em 16/10/2026 (seção 9): todas as recomendações, com uma mudança — o PDF dos relatórios não é limitado no Free.** Um painel para o dono do Omni Lar (não o dono de uma casa) gerenciar todas as contas do app: aprovar contas novas, marcar contas como Premium ou Free e acompanhar o uso. Peça aprovação antes de cada migration, como sempre.

**Prioridade (revisão de 16/10/2026):** o site agora está aberto em https://omnilar.web.app e qualquer pessoa consegue se cadastrar. Por isso a **fase A** (base, aprovação de contas e painel parte 1, seção 10) deixa de esperar as outras pendências. A **fase B** (planos Free e Premium) continua para depois, quando houver uso que justifique: hoje são 2 contas e 1 casa.

## 0. Andamento (16/10/2026, branch `feat/painel-admin-fase-a`)

Fase A feita no código, com ensaio no banco (rollback):
- **Migration 0068**: `platform_admins`, `account_status` (contas atuais como `active`, tempo real na própria linha), `app_settings` (aprovação ligada, convite aprova direto), `admin_audit_log`; `is_platform_admin()`, `is_account_active()` (para as Edge Functions) e `account_is_active(user_id)` (interna); `handle_new_user` grava o status inicial e avisa os administradores; gatilhos em `houses` e `house_members` recusam conta não liberada (vale para as funções e para a inserção direta); `join_house_with_invite` aprova a conta pendente com convite válido; categoria `conta` nas notificações (`notify_account`, sempre essencial e fora de casa); funções do painel `my_account_access`, `admin_overview`, `admin_list_accounts`, `admin_account_detail`, `admin_set_account_status` (em lote, motivo obrigatório para recusar e suspender, ninguém muda o próprio status), `admin_get_settings`, `admin_update_settings`, `admin_list_audit` e `admin_set_platform_admin` (só conta liberada; ninguém muda o próprio acesso).
- **Edge Functions**: `_shared/auth.ts` chama `is_account_active` antes de qualquer leitura de IA (`assistant`, `capture-read`, `import-read`).
- **App**: `AccountAccessCubit` (status da conta, tempo real), tela `/conta/em-analise` (em análise, recusada ou suspensa, com campo de convite e sair), rota `/admin` só para administradores, botão "Administração do Omni Lar" nos Ajustes, painel com Visão geral, Contas (busca e filtro), detalhe da conta (aprovar, recusar, suspender, reativar, tornar ou tirar administrador), Aprovações (em lote), Configurações e Histórico; modo demo com contas de exemplo.
- **No ar (16/10/2026)**: 0068 aplicada; `assistant`, `capture-read` e `import-read` publicadas com a conferência (chamada sem sessão devolve a mensagem da própria função); a conta do dono incluída em `platform_admins` (registro no histórico). As duas contas que já existiam ficaram `active`; a aprovação está ligada.
- **App na `main`** desde 16/10/2026. Falta o teste com sessão real (seção 11). A tela de espera passou a conferir o status também ao voltar ao app, a cada 15 s e pelo botão "Verificar agora" (commit `44ccb23`), e o modo demo não mostra o painel (`0f5c296`).
Fase B (16/10/2026, branch `feat/painel-admin-fase-b`), com ensaio no banco (rollback):
- **Migration 0069**: `account_status.plan`, `plan_expires_at` e `plan_note` (contas existentes viram Premium "conta inicial"); `plan_limits` com os limites da seção 5.2 (o PDF fica de fora, decisão 3); `account_plan(user_id)` (Premium vencido conta como Free), `house_plan(house_id)` (plano do dono no momento), `plan_limit(plan, resource)` e `house_ai_daily_limit(house_id)` (para as Edge Functions, só para quem mora na casa); limites nos gatilhos de `houses` (casas como dono), `house_members` (moradores, também na inserção direta e no convite) e `shared_projects` (projeto ativo novo ou reaberto); `my_account_access` devolve o plano; painel com `admin_set_plan` (em lote, validade futura, observação, aviso "Plano alterado" à pessoa), `admin_get_plan_limits`, `admin_set_plan_limit` e o plano em `admin_list_accounts`, `admin_account_detail` e `admin_overview` (contas por plano, Premium vencendo em 30 dias).
- **Edge Functions**: `_shared/usage.ts` lê a cota do plano da casa (`house_ai_daily_limit`; sem resposta do banco, 10).
- **App**: plano na lista e no detalhe da conta (e o plano de cada casa), "Mudar plano" com validade e observação, contas por plano na visão geral, tabela de limites editável em Configurações, "Seu plano" nos Ajustes. As mensagens de limite vêm do banco ("No plano Free a casa tem até 4 moradores.").
- **No ar (16/10/2026)**: 0069 aplicada (as duas contas viraram Premium "conta inicial", a casa ficou Premium); `assistant`, `capture-read` e `import-read` republicadas com a cota do plano.
- **Avisos de Premium vencendo e vencido** (16/10/2026): feitos pelo agendador das notificações (migration 0070, ver `plano_notificacoes.md`). O vencimento já valia na hora de usar.
- **Aviso diário** "N contas esperando aprovação": feito pelo agendador (0070). Além dele, cada conta nova pendente continua avisando os administradores na hora.

## 1. Objetivo

1. **Controlar quem entra** enquanto o app está em teste: conta nova fica esperando aprovação, com um interruptor para aprovar tudo automaticamente quando fizer sentido abrir.
2. **Separar Free e Premium**: marcar à mão (sem pagamento por enquanto), com data de validade opcional.
3. **Ver o app de cima**: quantas contas e casas existem, quem está esperando, uso de IA.
4. **Agir numa conta**: aprovar, recusar, suspender, reativar, trocar o plano.

Fora do escopo agora: cobrança automática (cartão, Pix recorrente, loja), que pode vir depois em cima do mesmo campo de plano.

## 2. O que existia antes do painel (conferido em 16/10/2026)

> Registro do ponto de partida. O que foi feito está na seção 0; a exclusão de conta (`delete-account`) continua sem existir.

| Peça | Situação |
|---|---|
| Contas | Supabase Auth (`auth.users`) e `profiles` (`id`, `full_name`, `email`, `phone`, `avatar_url`, `pix_key`, `created_at`). O gatilho `on_auth_user_created` (`handle_new_user`) cria o perfil ao cadastrar. O último acesso fica em `auth.users.last_sign_in_at`, que o app não lê |
| Papéis | Só dentro da casa (`house_members.role`: dono, administrador, morador). **Não existe** papel de administrador do app |
| Entrar numa casa | Pelas funções `create_house_with_owner` e `join_house_with_invite`, **mas também direto nas tabelas**: a regra `houses_insert_authenticated` deixa qualquer usuário logado inserir em `houses`, e `house_members_insert_owner_or_admin` deixa o dono ou administrador de uma casa incluir alguém em `house_members` |
| `profiles` | A pessoa lê o próprio perfil e o dos moradores das casas dela, e altera o próprio perfil (`profiles_update_own`) |
| Uso de IA | Tabela `ai_usage` e cota diária de **50 leituras por casa** (`DEFAULT_DAILY_QUOTA_PER_HOUSE` em `supabase/functions/_shared/usage.ts`), contada nas Edge Functions `assistant`, `capture-read` e `import-read`; quem informa a própria chave de IA (BYOK) não tem limite. As funções conferem a casa, não o status da conta |
| Notificações | Existem (migrations 0064 a 0066): `enqueue_notification`, sino no app, push pelo FCM. As categorias aceitas são `casa`, `despesas`, `fechamento`, `emprestimos`, `caixinhas`, `compras`, `tarefas`, `agenda`, `projetos` e `assistente`; **não há categoria de conta** |
| E-mail | Só os do Supabase Auth (confirmação de cadastro, link mágico, troca de senha). Não há serviço de e-mail para avisos do app |
| Exclusão de conta | **Não existe** a função `delete-account` (as Edge Functions são `assistant`, `capture-read`, `import-read` e `notify`) |
| Auditoria | Tabela `audit_log`, com gatilhos nas tabelas financeiras |
| Plano ou status da conta | Não existe |
| Site | Público em https://omnilar.web.app (Firebase Hosting) |

## 3. Quem é administrador do app

- **Tabela `platform_admins`** (`user_id`, `created_at`, `created_by`). O primeiro registro é feito à mão no SQL Editor pelo dono (a conta dele); depois, um administrador pode incluir outro pelo painel.
- **Função `is_platform_admin()`** (`security definer`) usada pelas regras de acesso e pelas funções do painel.
- **Ninguém do app vira administrador sozinho**: não há caminho na tela para se incluir, e a tabela não aceita escrita direta.
- **A chave de serviço do Supabase nunca vai para o app.** Toda ação do painel é uma função do banco ou uma Edge Function que confere `is_platform_admin()`.
- **Ser administrador do app não abre os dados das casas**: `is_platform_admin()` não entra nas regras de acesso das tabelas financeiras.

## 4. Status da conta e aprovação

### 4.1. Estados
| Status | O que a pessoa consegue fazer |
|---|---|
| `pending` | Entra no app e vê a tela "Sua conta está em análise" (com o e-mail e um botão de sair). Não cria casa, não entra em casa e não usa a IA |
| `active` | Usa o app normalmente |
| `rejected` | Vê "Seu acesso não foi aprovado" e o motivo, se houver |
| `suspended` | Vê "Sua conta está suspensa"; os dados continuam guardados. As casas onde ela é moradora continuam funcionando para os outros. Ela não usa a IA nem entra em outra casa |

### 4.2. Parâmetros (tabela `app_settings`, uma linha só)
- **`require_approval`** (liga/desliga): ligado, conta nova nasce `pending`; desligado, nasce `active`.
- **`auto_approve_invited`**: conta nova que chega por um **convite de casa válido** nasce `active` mesmo com a aprovação ligada (quem convidou já respondeu por ela). Ver decisão 2.
- **`auto_approve_domains`** e **`auto_approve_emails`**: listas de domínios e e-mails aprovados direto (por exemplo, a família).
- **`default_plan`** para contas novas (`free`) e **`trial_days`** de Premium para contas novas (0 = sem teste). Ver decisão 4.
- Mudar um parâmetro vale para as contas novas; as que já estão esperando continuam esperando (o painel tem "Aprovar todas as pendentes").

### 4.3. Onde a regra é aplicada
Uma função `is_account_active(user_id)` concentra a regra, e ela vale **no banco, não só na tela**, em todos os caminhos:
- **Status inicial**: o `handle_new_user` grava o status conforme os parâmetros.
- **Criar casa**: `create_house_with_owner` **e** a regra `houses_insert_authenticated` (inserção direta em `houses`) recusam conta que não está `active`.
- **Entrar em casa**: `join_house_with_invite` **e** a regra `house_members_insert_owner_or_admin` recusam incluir uma conta que não está `active`, mesmo quando quem inclui é o dono da casa.
- **IA**: `_shared/usage.ts` confere o status de quem chama antes de contar a cota; conta `pending`, `rejected` ou `suspended` recebe "Sua conta não está liberada para usar a IA".
- **Contas que já existem** viram `active` na migration (não ficam presas esperando).
- O app consulta o status ao abrir e quando a sessão muda; a tela de espera atualiza sozinha quando o administrador aprova (tempo real na própria linha).

## 5. Planos Free e Premium (fase B)

### 5.1. Onde o plano fica
- Colunas na conta: `plan` (`free` ou `premium`), `plan_expires_at` (vazio = sem validade), `plan_note` (motivo, por exemplo "família", "testador", "conta inicial").
- Vencida a validade, a conta volta a Free sozinha (conferido na hora de usar; um job diário só arruma o que aparece no painel).
- **Qual plano vale numa casa** (decisão 1): a casa segue o plano de **quem é o dono dela no momento**: se o dono sai ou passa a casa para outra pessoa, vale o plano do novo dono.
- **Contas que já existem** (decisão 9): viram Premium sem validade, com a observação "conta inicial". Assim a casa atual não cai das 50 leituras de IA por dia de hoje para as 10 do Free.

### 5.2. O que muda entre os planos (decisão 3)
| Recurso | Free | Premium |
|---|---|---|
| Leituras de IA (escâner, importação por PDF/foto, assistente) com a chave do app | 10 por dia por casa | 100 por dia por casa |
| Usar a própria chave de IA (sem limite) | Sim | Sim |
| Casas que a conta pode criar | 1 | Até 3 |
| Moradores por casa | Até 4 | Sem limite prático (20) |
| Importação de fatura e extrato (OFX/CSV) | Sim | Sim |
| Relatórios: prestação de contas em PDF | Sim | Sim |
| Projetos compartilhados | 1 ativo | Sem limite |
| Anexo de comprovantes físicos (Storage) | Não (IA lê os dados na memória sem guardar o arquivo) | Sim (Modelo A: ciclo ativo + 30 dias após quitação) |
| Notificações | Todas | Todas |

O que é essencial para dividir as contas da casa (lançar, fechar o ciclo, empréstimos, compras, tarefas, agenda, caixinhas, relatórios e o PDF de prestação de contas) nunca é cortado no Free.

### 5.3. Onde o limite é aplicado
- **Cota de IA**: `_shared/usage.ts` passa a ler o plano da casa (`plan_limits` por plano) em vez de `DEFAULT_DAILY_QUOTA_PER_HOUSE`.
- **Casas, moradores e projetos**: nas funções do banco que criam (`create_house_with_owner`, convite, `set_project_participants`) **e nas regras de inserção direta** (as mesmas da seção 4.3), com mensagem clara ("No plano Free a casa tem até 4 moradores").
- **PDF dos relatórios**: sem limite (decisão 3). O que gasta servidor (IA) é sempre conferido no servidor.
- Os limites ficam numa tabela **`plan_limits`** (plano × recurso × valor), editável no painel, em vez de números no código.
- **Rebaixar** de Premium para Free nunca apaga nada: o que passou do limite continua visível e editável, só não dá para criar mais.

## 6. O painel

### 6.1. Onde fica
Recomendação (decisão 5): **rota `/admin` dentro do próprio app**, que só aparece para administradores do app (item "Administração" nos Ajustes). Funciona no navegador do computador, que é onde o painel vai ser mais usado.

### 6.2. Telas
1. **Visão geral**: contas por status e por plano, contas novas na semana, casas ativas (com lançamento nos últimos 30 dias), leituras de IA no dia e no mês, contas esperando aprovação (com atalho).
2. **Contas**: lista com busca (nome, e-mail) e filtros (status, plano, criada entre datas). Colunas: nome, e-mail, status, plano e validade, casas, criada em, último acesso (`auth.users.last_sign_in_at`, lido por uma função `security definer` do painel).
3. **Detalhe da conta**: dados do perfil, casas e papel em cada uma, plano e histórico de mudanças, uso de IA, e as ações: **Aprovar**, **Recusar** (com motivo), **Suspender** e **Reativar**, **Tornar Premium** (com validade e observação), **Voltar para Free**.
4. **Aprovações pendentes**: fila com aprovar ou recusar em lote.
5. **Configurações**: os parâmetros da seção 4.2 e a tabela de limites da seção 5.2.
6. **Histórico**: tudo o que os administradores fizeram (quem, o quê, em quem, quando).

### 6.3. Privacidade
- O painel mostra **dados da conta e números de uso**, nunca os dados financeiros das casas (despesas, valores, empréstimos). Isso fica escrito nas regras: as funções do painel só devolvem contagens e metadados.
- Toda ação do painel fica registrada (tabela `admin_audit_log`) e não pode ser apagada pelo painel.
- **Exclusão de conta (LGPD)**: o fluxo `delete-account` ainda não existe. Fica como trabalho próprio (decisão 10), fora das fases A e B; até lá, o painel só suspende.

## 7. Avisos para a pessoa

Pelas notificações que já existem (`enqueue_notification`), com uma **categoria nova `conta`** (a migration acrescenta à regra `notifications_category_check` e às preferências). Avisos de conta são essenciais (não dá para desligar):
- Conta aprovada ("Sua conta foi aprovada. Bem-vindo ao Omni Lar").
- Conta recusada ou suspensa, com o motivo.
- Plano mudou ("Sua conta agora é Premium até 31/12/2026").
- Premium vencendo em 7 dias e vencido (`premium_expiring` e `premium_expired`, migration 0070: saem a partir das 9h de Brasília, uma vez por validade; o vencido só avisa se venceu nos últimos 14 dias).
- Para os administradores: "3 contas esperando aprovação" (`accounts_pending_daily`, 0070: uma vez por dia a partir das 9h, só se houver contas pendentes; abre `/admin?aba=aprovacoes`).

**Limite:** quem está esperando aprovação ainda não ativou as notificações, então o aviso de aprovação aparece no sino quando ela abrir o app, e a tela de espera já muda sozinha. **E-mail** de aprovação ou recusa não sai pelo Supabase Auth (ele só manda os e-mails de login); precisaria de um serviço de e-mail (Resend, SendGrid ou outro) chamado por uma Edge Function, com conta e chave próprias. Ver decisão 8.

## 8. Estrutura no banco (resumo)

| Peça | O que é |
|---|---|
| `platform_admins` | Quem administra o app |
| `account_status` (ou colunas em `profiles`) | `status`, `status_reason`, `approved_by`, `approved_at`, `plan`, `plan_expires_at`, `plan_note` (decisão 6) |
| `app_settings` | Parâmetros da aprovação e do plano inicial |
| `plan_limits` | Limites por plano e recurso (fase B) |
| `admin_audit_log` | Histórico das ações do painel |
| `is_platform_admin()`, `is_account_active(user_id)`, `house_plan(house_id)` | Funções usadas pelas regras de acesso, pelas funções do banco e pelas Edge Functions |
| Regras `houses_insert_authenticated` e `house_members_insert_owner_or_admin` | Passam a exigir conta `active` (e, na fase B, os limites do plano) |
| Categoria `conta` em `notifications` | Avisos de aprovação, recusa, suspensão e plano |
| `admin_list_accounts`, `admin_set_account_status`, `admin_set_plan`, `admin_update_settings`, `admin_overview` | Funções do painel, todas conferindo `is_platform_admin()` e gravando no histórico |

As colunas de status e plano **não podem ser alteradas pelo próprio usuário** (a regra `profiles_update_own` deixa a pessoa editar o próprio perfil; por isso a recomendação é uma tabela separada).

## 9. Decisões do dono (16/10/2026)

O dono seguiu todas as recomendações, com uma mudança na decisão 3 (o PDF dos relatórios fica liberado no Free). As outras opções ficam registradas para o caso de alguma decisão ser revista.

| # | Decisão | Escolha | Outras opções que existiam |
|---|---|---|---|
| 1 | O plano vale para quem | **a)** Para a conta; a casa é Premium quando quem é o dono dela no momento é Premium (os moradores usam o que o dono tem) | b) para a casa, independente das contas; c) para cada conta, separadamente, dentro da mesma casa |
| 2 | Quem chega por convite precisa de aprovação | **a)** Não: convite válido aprova direto (`auto_approve_invited` ligado) | b) sim, como qualquer conta nova |
| 3 | Limites do Free | **a, com mudança)** Como na tabela da seção 5.2: o essencial da casa nunca é cortado; o limite fica em IA, número de casas, moradores e projetos. **O PDF dos relatórios não é limitado** | b) só limite de IA; c) outra tabela |
| 4 | Teste de Premium para contas novas | **a)** Não por enquanto (`trial_days = 0`); Premium só marcado à mão | b) 30 dias de Premium para toda conta nova |
| 5 | Onde fica o painel | **a)** Rota `/admin` dentro do app, visível só para administradores do app | b) site separado; c) só pelo painel do Supabase |
| 6 | Onde guardar status e plano | **a)** Tabela separada (`account_status`), que o usuário não consegue editar | b) colunas em `profiles`, com gatilho bloqueando a edição |
| 7 | Conta esperando aprovação | **a)** Entra no app e vê a tela de espera, que muda sozinha ao ser aprovada | b) o login é recusado com a mensagem |
| 8 | Como a pessoa fica sabendo da aprovação ou recusa | **a)** Pelo app: a tela de espera muda sozinha e o aviso fica no sino (sem e-mail por enquanto) | b) também por e-mail, com um serviço de e-mail e uma Edge Function |
| 9 | Contas que já existem quando os planos chegarem | **a)** Viram Premium sem validade, com a observação "conta inicial" | b) Free com 50 leituras de IA por dia; c) Free com os limites da tabela |
| 10 | Exclusão de conta (LGPD) | **a)** Trabalho próprio depois das fases A e B: Edge Function `delete-account` com confirmação dupla, que apaga perfil e dados pessoais e tira a pessoa das casas sem apagar o histórico financeiro dos outros moradores; até lá, o painel só suspende | b) entrar já na fase A; c) só suspensão, exclusão à mão |

## 10. Ordem de implementação sugerida

**Fase A (agora, com o site aberto):**
1. **Base** (migration): `platform_admins`, `account_status`, `app_settings`, `admin_audit_log`, `is_platform_admin()` e `is_account_active()`; contas atuais como `active`; a conta do dono como administrador (feito à mão por ele).
2. **Aprovação**: status inicial no `handle_new_user`; bloqueio no banco em todos os caminhos da seção 4.3 (funções e regras de inserção direta); conferência em `_shared/usage.ts`; tela de espera no app.
3. **Painel, parte 1**: visão geral, lista de contas, detalhe, aprovar, recusar, suspender, reativar, aprovação em lote e configurações.
4. **Avisos no app**: categoria `conta` e os avisos de aprovação, recusa e suspensão.

**Fase B (quando houver uso que justifique):**
5. **Planos**: `plan_limits`, `house_plan()`, contas atuais como Premium "conta inicial" (decisão 9), cota de IA por plano, limites de casas, moradores e projetos (também nas regras de inserção direta) e "Recurso Premium" nas telas desses limites.
6. **Painel, parte 2**: trocar plano com validade, histórico de planos e avisos de plano (mudou, vencendo, vencido).

## 11. Testes

- **Banco** (ensaio com rollback): cada função do painel como administrador e como usuário comum (recusado); conta `pending` tentando criar casa pela função **e** inserindo direto em `houses` (recusada); dono de uma casa tentando incluir uma conta `pending` direto em `house_members` (recusado); `join_house_with_invite` com conta `pending` (recusado) e com convite válido e `auto_approve_invited` ligado (aprovada); usuário tentando mudar o próprio status ou plano (recusado); administrador do app tentando ler despesas de uma casa da qual não é morador (recusado); na fase B, os limites de cada plano.
- **Edge Functions**: conta `pending` ou `suspended` chamando `capture-read`, `import-read` e `assistant` recebe a recusa antes de gastar cota.
- **App**: tela de espera, rota `/admin` invisível e recusada para quem não é administrador, telas do painel no modo demo.
- **O dono testa com sessão real**: cadastrar uma conta nova com a aprovação ligada e desligada, aprovar pelo painel e ver a tela mudar sozinha e o aviso chegar no sino.
