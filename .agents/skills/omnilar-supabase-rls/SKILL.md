---
name: omnilar-supabase-rls
description: >-
  Use when creating or changing Supabase migrations, tables, RLS policies,
  views, SQL functions, storage policies or database tests for Omni Lar.
  Enforces house-scoped security, immutable ledger and money in cents.
---

# Omni Lar: Supabase, Migrações e RLS

Referência: `novoSite/arquitetura_tecnica.md` seções 3 a 7.

## Convenções obrigatórias
- Tabelas e colunas em `snake_case`, inglês. PK `uuid default gen_random_uuid()`.
- Toda tabela de domínio: `house_id uuid not null`, `created_at timestamptz default now()`, `created_by uuid`. Alteráveis: `updated_at` por trigger.
- Dinheiro: `bigint` em centavos (`*_cents`). Nunca `numeric`/`float` para valor.
- Exclusão lógica (`deleted_at`) onde o histórico importa. **Sem DELETE físico** em tabelas financeiras.
- **RLS ativado em todas as tabelas.** Sem política, ninguém acessa.
- Status (parcela, evento, tarefa atrasada) são **views**, nunca colunas editadas à mão.

## Passo a passo para uma nova tabela
1. Criar a migração: `supabase migration new <nome>` (arquivo em `supabase/migrations`).
2. Criar a tabela com `house_id`, FKs, constraints (`check (amount_cents > 0)`), índices `(house_id, <data>)`.
3. `alter table ... enable row level security;`
4. Conceder permissões para a Data API: `grant select, insert, update, delete on public.<tabela> to authenticated, service_role;`
5. Escrever políticas separadas por operação, usando `public.is_house_member(house_id)`.
6. Adicionar triggers (`updated_at`, `audit_log` se for financeiro, bloqueio de UPDATE/DELETE se for ledger).
7. Escrever testes de RLS (pgTAP ou script com 2 usuários de casas diferentes).
8. Validar: `supabase db reset` local e rodar os testes.

## Padrões
Função base (fixar `search_path`):
```sql
create or replace function public.is_house_member(h uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from house_members
    where house_id = h and user_id = auth.uid() and left_at is null
  );
$$;
```
Política típica:
```sql
create policy "members read" on house_expenses for select
  using (public.is_house_member(house_id));
create policy "members insert" on house_expenses for insert
  with check (public.is_house_member(house_id) and created_by = auth.uid());
```
Ledger imutável:
```sql
create function prevent_mutation() returns trigger language plpgsql as $$
begin raise exception 'ledger is immutable'; end $$;
create trigger payments_immutable before update or delete on payments
  for each row execute function prevent_mutation();
```

## Matriz de visibilidade (resumo)
- Despesas, aportes, categorias, listas de compras, tarefas (não privadas), eventos `house`: membros da Casa.
- Empréstimos P2P: credor e devedor. A visibilidade do `admin` é decisão em aberto, trate como **não visível** até ser definida.
- Eventos `private` e tarefas `private`: só o criador. `restricted`: criador e participantes.
- Conversas do assistente: só o dono.
- Capturas e anexos: quem enviou e quem acessa o lançamento vinculado.

## Checklist antes de concluir
- [ ] `select * from pg_tables where schemaname='public' and not rowsecurity;` retorna vazio
- [ ] Usuário de outra Casa não lê nem escreve (teste)
- [ ] `service_role` não aparece em código do app
- [ ] Funções `security definer` validam `auth.uid()` e fixam `search_path`
- [ ] Nenhum `float`/`double` para dinheiro
