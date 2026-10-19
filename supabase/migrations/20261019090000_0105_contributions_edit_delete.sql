-- 0105_contributions_edit_delete.sql
-- Criação completa e permissões de edição e exclusão de aportes (contributions).

-- 1. Cria a tabela caso ainda não exista no banco
create table if not exists public.contributions (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  amount_cents bigint not null,
  cycle_start_date date not null,
  paid_at timestamptz not null default now(),
  notes text,
  payment_method_id uuid references public.payment_methods(id) on delete set null,
  proof_attachment_id text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

-- 2. Índices de busca e filtros de ciclo
create index if not exists idx_contributions_house_cycle on public.contributions (house_id, cycle_start_date);
create index if not exists idx_contributions_member on public.contributions (member_id);

-- 3. Habilita Row Level Security
alter table public.contributions enable row level security;

-- 4. Tempo real e réplica completa
alter table public.contributions replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'contributions'
  ) then
    alter publication supabase_realtime add table public.contributions;
  end if;
end $$;

-- 5. Garante permissões completas na tabela para usuários autenticados
grant select, insert, update, delete on public.contributions to authenticated;

-- 6. Trigger para impedir alteração de casa ou do criador original
create or replace function public.contributions_keep_owner()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.house_id <> old.house_id or new.created_by <> old.created_by then
    raise exception 'O aporte não muda de casa nem de quem registrou.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_contributions_keep_owner on public.contributions;
create trigger trg_contributions_keep_owner
  before update on public.contributions
  for each row execute function public.contributions_keep_owner();

-- 7. Função de guarda para tratar INSERT, UPDATE e DELETE em ciclos fechados
create or replace function public.guard_closed_cycle_contribution()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or pg_trigger_depth() > 1 then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || old.house_id::text, 0));
    if public.house_date_is_closed(old.house_id, old.cycle_start_date) then
      raise exception 'O ciclo deste aporte já foi fechado. Reabra o ciclo no Fechamento para excluí-lo.';
    end if;
    return old;
  end if;

  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || new.house_id::text, 0));

  if tg_op = 'UPDATE' then
    if public.house_date_is_closed(old.house_id, old.cycle_start_date) then
      raise exception 'O ciclo original deste aporte já foi fechado. Reabra o ciclo no Fechamento para alterá-lo.';
    end if;
  end if;

  if public.house_date_is_closed(new.house_id, new.cycle_start_date) then
    raise exception 'O ciclo desta data já foi fechado. Reabra o ciclo no Fechamento para lançar ou mover um aporte para ele.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_contributions_guard_closed_cycle on public.contributions;
create trigger trg_contributions_guard_closed_cycle
  before insert or update or delete on public.contributions
  for each row execute function public.guard_closed_cycle_contribution();

-- 8. Políticas RLS (SELECT, INSERT, UPDATE, DELETE)

-- SELECT: Membros da casa podem visualizar os aportes da casa
drop policy if exists "contributions_select_member" on public.contributions;
create policy "contributions_select_member" on public.contributions
  for select using (public.is_house_member(house_id));

-- INSERT: Membros da casa registrando o próprio aporte ou no nome de morador
drop policy if exists "contributions_insert_member" on public.contributions;
create policy "contributions_insert_member" on public.contributions
  for insert with check (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()))
  );

-- UPDATE: Autor, morador dono do aporte ou admin, em ciclo aberto
drop policy if exists "contributions_update_member" on public.contributions;
create policy "contributions_update_member" on public.contributions
  for update using (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()) or member_id = (select auth.uid()) or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, cycle_start_date)
  )
  with check (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()) or member_id = (select auth.uid()) or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, cycle_start_date)
  );

-- DELETE: Autor, morador dono do aporte ou admin, em ciclo aberto
drop policy if exists "contributions_delete_member" on public.contributions;
create policy "contributions_delete_member" on public.contributions
  for delete using (
    public.is_house_member(house_id)
    and (created_by = (select auth.uid()) or member_id = (select auth.uid()) or public.is_house_admin(house_id))
    and not public.house_date_is_closed(house_id, cycle_start_date)
  );

-- 9. Recarrega o cache do PostgREST
notify pgrst, 'reload schema';
