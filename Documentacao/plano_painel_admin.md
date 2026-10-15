# Omni Lar — painel administrativo

Ideia registrada em 15/10/2026. Um painel para o dono do Omni Lar (não o dono de uma casa) gerenciar todas as contas do app: aprovar contas novas, marcar contas como Premium ou Free e acompanhar o uso. **Fica para depois das pendências de [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md) e do [plano_notificacoes.md](plano_notificacoes.md).** Peça aprovação antes de cada migration, como sempre.

## 1. Objetivo

1. **Controlar quem entra** enquanto o app está em teste: conta nova fica esperando aprovação, com um interruptor para aprovar tudo automaticamente quando fizer sentido abrir.
2. **Separar Free e Premium**: marcar à mão (sem pagamento por enquanto), com data de validade opcional.
3. **Ver o app de cima**: quantas contas e casas existem, quem está esperando, uso de IA.
4. **Agir numa conta**: aprovar, recusar, suspender, reativar, trocar o plano.

Fora do escopo agora: cobrança automática (cartão, Pix recorrente, loja), que pode vir depois em cima do mesmo campo de plano.

## 2. O que já existe (conferido em 15/10/2026)

| Peça | Situação |
|---|---|
| Contas | Supabase Auth (`auth.users`) e `profiles` (`id`, `full_name`, `email`, `phone`, `avatar_url`, `pix_key`, `created_at`). O gatilho `on_auth_user_created` (`handle_new_user`) cria o perfil ao cadastrar |
| Papéis | Só dentro da casa (`house_members.role`: dono, administrador, morador). **Não existe** papel de administrador do app |
| Uso de IA | Tabela `ai_usage` e cota diária de **50 leituras por casa** (`DEFAULT_DAILY_QUOTA_PER_HOUSE` em `supabase/functions/_shared/usage.ts`); quem informa a própria chave de IA (BYOK) não tem limite |
| Auditoria | Tabela `audit_log`, com gatilhos nas tabelas financeiras |
| Plano ou status da conta | Não existe |

## 3. Quem é administrador do app

- **Tabela `platform_admins`** (`user_id`, `created_at`, `created_by`). O primeiro registro é feito à mão no SQL Editor pelo dono (a conta dele); depois, um administrador pode incluir outro pelo painel.
- **Função `is_platform_admin()`** (`security definer`) usada pelas regras de acesso e pelas funções do painel.
- **Ninguém do app vira administrador sozinho**: não há caminho na tela para se incluir, e a tabela não aceita escrita direta.
- **A chave de serviço do Supabase nunca vai para o app.** Toda ação do painel é uma função do banco ou uma Edge Function que confere `is_platform_admin()`.

## 4. Status da conta e aprovação

### 4.1. Estados
| Status | O que a pessoa consegue fazer |
|---|---|
| `pending` | Entra no app e vê a tela "Sua conta está em análise" (com o e-mail e um botão de sair). Não cria casa nem entra em casa |
| `active` | Usa o app normalmente |
| `rejected` | Vê "Seu acesso não foi aprovado" e o motivo, se houver |
| `suspended` | Vê "Sua conta está suspensa"; os dados continuam guardados. As casas onde ela é moradora continuam funcionando para os outros |

### 4.2. Parâmetros (tabela `app_settings`, uma linha só)
- **`require_approval`** (liga/desliga): ligado, conta nova nasce `pending`; desligado, nasce `active`.
- **`auto_approve_invited`**: conta nova que chega por um **convite de casa válido** nasce `active` mesmo com a aprovação ligada (quem convidou já respondeu por ela). Ver decisão 2.
- **`auto_approve_domains`** e **`auto_approve_emails`**: listas de domínios e e-mails aprovados direto (por exemplo, a família).
- **`default_plan`** para contas novas (`free`) e **`trial_days`** de Premium para contas novas (0 = sem teste). Ver decisão 4.
- Mudar um parâmetro vale para as contas novas; as que já estão esperando continuam esperando (o painel tem "Aprovar todas as pendentes").

### 4.3. Onde a regra é aplicada
- O `handle_new_user` passa a gravar o status inicial conforme os parâmetros.
- **No banco, não só na tela**: as funções e regras de acesso que criam casa (`create_house_with_owner`) e entram em casa (`join_house_with_invite`) recusam conta que não está `active`. Uma função `is_account_active()` concentra a regra.
- **Contas que já existem** viram `active` na migration (não ficam presas esperando).
- O app consulta o status ao abrir e quando a sessão muda; a tela de espera atualiza sozinha quando o administrador aprova (tempo real na própria linha).

## 5. Planos Free e Premium

### 5.1. Onde o plano fica
- Colunas na conta: `plan` (`free` ou `premium`), `plan_expires_at` (vazio = sem validade), `plan_note` (motivo, por exemplo "família", "testador").
- Vencida a validade, a conta volta a Free sozinha (conferido na hora de usar; um job diário só arruma o que aparece no painel).
- **Qual plano vale numa casa**: ver decisão 1 (a recomendação é a casa ser Premium quando o dono dela é Premium).

### 5.2. O que muda entre os planos (proposta, ver decisão 3)
| Recurso | Free | Premium |
|---|---|---|
| Leituras de IA (escâner, importação por PDF/foto, assistente) com a chave do app | 10 por dia por casa | 100 por dia por casa |
| Usar a própria chave de IA (sem limite) | Sim | Sim |
| Casas que a conta pode criar | 1 | Até 3 |
| Moradores por casa | Até 4 | Sem limite prático (20) |
| Importação de fatura e extrato (OFX/CSV) | Sim | Sim |
| Relatórios: prestação de contas em PDF | Não | Sim |
| Projetos compartilhados | 1 ativo | Sem limite |
| Notificações | Todas | Todas |

O que é essencial para dividir as contas da casa (lançar, fechar o ciclo, empréstimos, compras, tarefas, agenda) nunca é cortado no Free.

### 5.3. Onde o limite é aplicado
- **Cota de IA**: a função que hoje usa `DEFAULT_DAILY_QUOTA_PER_HOUSE` passa a ler o plano da casa (`plan_limits` por plano).
- **Casas, moradores e projetos**: nas funções do banco que criam (`create_house_with_owner`, convite, `set_project_participants`), com mensagem clara ("No plano Free a casa tem até 4 moradores").
- **Recursos de tela** (PDF dos relatórios): o app esconde o botão e mostra "Recurso Premium"; o que gasta servidor também é conferido no servidor.
- Os limites ficam numa tabela **`plan_limits`** (plano × recurso × valor), editável no painel, em vez de números no código.
- **Rebaixar** de Premium para Free nunca apaga nada: o que passou do limite continua visível e editável, só não dá para criar mais.

## 6. O painel

### 6.1. Onde fica
Recomendação (decisão 5): **rota `/admin` dentro do próprio app**, que só aparece para administradores do app (item "Administração" nos Ajustes). Funciona no navegador do computador, que é onde o painel vai ser mais usado.

### 6.2. Telas
1. **Visão geral**: contas por status e por plano, contas novas na semana, casas ativas (com lançamento nos últimos 30 dias), leituras de IA no dia e no mês, contas esperando aprovação (com atalho).
2. **Contas**: lista com busca (nome, e-mail) e filtros (status, plano, criada entre datas). Colunas: nome, e-mail, status, plano e validade, casas, criada em, último acesso.
3. **Detalhe da conta**: dados do perfil, casas e papel em cada uma, plano e histórico de mudanças, uso de IA, e as ações: **Aprovar**, **Recusar** (com motivo), **Suspender** e **Reativar**, **Tornar Premium** (com validade e observação), **Voltar para Free**.
4. **Aprovações pendentes**: fila com aprovar ou recusar em lote.
5. **Configurações**: os parâmetros da seção 4.2 e a tabela de limites da seção 5.2.
6. **Histórico**: tudo o que os administradores fizeram (quem, o quê, em quem, quando).

### 6.3. Privacidade
- O painel mostra **dados da conta e números de uso**, nunca os dados financeiros das casas (despesas, valores, empréstimos). Isso fica escrito nas regras: as funções do painel só devolvem contagens e metadados.
- Toda ação do painel fica registrada (tabela `admin_audit_log`) e não pode ser apagada pelo painel.
- Excluir conta (LGPD) segue o fluxo próprio `delete-account` previsto na arquitetura, com confirmação dupla; o painel só dispara.

## 7. Avisos para a pessoa

Ligados ao [plano_notificacoes.md](plano_notificacoes.md) (grupo novo "Conta"), e por e-mail enquanto as notificações não existem:
- Conta aprovada ("Sua conta foi aprovada. Bem-vindo ao Omni Lar").
- Conta recusada ou suspensa, com o motivo.
- Plano mudou ("Sua conta agora é Premium até 31/12/2026").
- Premium vencendo em 7 dias e vencido.
- Para os administradores: "3 contas esperando aprovação" (uma vez por dia, se houver).

## 8. Estrutura no banco (resumo)

| Peça | O que é |
|---|---|
| `platform_admins` | Quem administra o app |
| `account_status` (ou colunas em `profiles`) | `status`, `status_reason`, `approved_by`, `approved_at`, `plan`, `plan_expires_at`, `plan_note` (decisão 6) |
| `app_settings` | Parâmetros da aprovação e do plano inicial |
| `plan_limits` | Limites por plano e recurso |
| `admin_audit_log` | Histórico das ações do painel |
| `is_platform_admin()`, `is_account_active()`, `house_plan(house_id)` | Funções usadas pelas regras de acesso |
| `admin_list_accounts`, `admin_set_account_status`, `admin_set_plan`, `admin_update_settings`, `admin_overview` | Funções do painel, todas conferindo `is_platform_admin()` e gravando no histórico |

As colunas de status e plano **não podem ser alteradas pelo próprio usuário** (a regra de atualização de `profiles` hoje deixa a pessoa editar o próprio perfil; por isso a recomendação é uma tabela separada).

## 9. Decisões pendentes do dono

**Antes de começar, pergunte se ele segue as recomendações (⭐) ou escolhe outra letra.**

1. **O plano vale para quem?**
   - a) ⭐ Para a conta, e a casa é Premium quando o dono dela é Premium (os moradores usam o que o dono tem)
   - b) Para a casa, independente das contas
   - c) Para cada conta, separadamente (cada morador vê os recursos do próprio plano dentro da mesma casa)
2. **Quem chega por convite de uma casa precisa de aprovação?**
   - a) ⭐ Não: convite válido aprova direto (`auto_approve_invited` ligado)
   - b) Sim, como qualquer conta nova
3. **Limites do Free** (seção 5.2)
   - a) ⭐ Como na tabela: o essencial da casa nunca é cortado; o limite fica em IA, número de casas, moradores, projetos e PDF
   - b) Free só com limite de IA, todo o resto igual
   - c) Definir outra tabela
4. **Teste de Premium para contas novas**
   - a) ⭐ Não por enquanto (`trial_days = 0`); Premium só marcado à mão
   - b) 30 dias de Premium para toda conta nova
5. **Onde fica o painel**
   - a) ⭐ Rota `/admin` dentro do app, visível só para administradores do app
   - b) Um site separado (outro projeto Flutter web ou uma página simples)
   - c) Só pelo painel do Supabase (sem tela própria)
6. **Onde guardar status e plano**
   - a) ⭐ Tabela separada (`account_status`), que o usuário não consegue editar
   - b) Colunas em `profiles`, com gatilho bloqueando a edição pelo próprio usuário
7. **Conta esperando aprovação**
   - a) ⭐ Entra no app e vê a tela de espera
   - b) Nem consegue entrar (o login é recusado com a mensagem)
8. **Aviso por e-mail** de aprovação e recusa antes das notificações existirem
   - a) ⭐ Sim, pelo e-mail do Supabase Auth (modelo próprio)
   - b) Não; a pessoa descobre ao abrir o app

## 10. Ordem de implementação sugerida

1. **Base** (migration): `platform_admins`, `account_status`, `app_settings`, `admin_audit_log`, funções de conferência; contas atuais como `active` e Free; a conta do dono como administrador (feito à mão por ele).
2. **Aprovação**: status inicial no `handle_new_user`, bloqueio no banco para criar e entrar em casa, tela de espera no app.
3. **Painel, parte 1**: visão geral, lista de contas, detalhe, aprovar, recusar, suspender e configurações.
4. **Planos**: `plan_limits`, `house_plan()`, cota de IA por plano, limites de casas, moradores e projetos, e "Recurso Premium" nas telas.
5. **Painel, parte 2**: trocar plano com validade, histórico e aprovação em lote.
6. **Avisos** (e-mail agora, notificações quando existirem).

## 11. Testes

- Banco: ensaio com rollback de cada função do painel como administrador e como usuário comum (recusado); conta `pending` tentando criar e entrar em casa (recusada); usuário tentando mudar o próprio status ou plano (recusado); limites de cada plano.
- App: tela de espera, rota `/admin` invisível e recusada para quem não é administrador, telas do painel no modo demo.
- O dono testa com sessão real: cadastrar uma conta nova com a aprovação ligada e desligada, aprovar pelo painel e ver a tela mudar sozinha.
