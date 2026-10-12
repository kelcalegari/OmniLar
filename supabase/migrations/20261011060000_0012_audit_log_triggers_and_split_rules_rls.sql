-- ==============================================================================
-- Migration: 0012_audit_log_triggers_and_split_rules_rls.sql
-- Module: Auditoria Automática & Políticas de Rateio
-- Description:
--   1. Políticas de UPDATE e DELETE para split_rules
--   2. Função genérica trigger public.fn_audit_record()
--   3. Triggers AFTER INSERT, UPDATE, DELETE em tabelas financeiras
--   4. View public.v_audit_timeline para visualização amigável de logs
-- ==============================================================================

-- 1. POLÍTICAS DE RLS PARA SPLIT_RULES (Permitir sincronização ao editar despesas)
create policy "split_rules_update_member" on public.split_rules for update
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ))
  with check (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

create policy "split_rules_delete_member" on public.split_rules for delete
  using (exists (
    select 1 from public.house_expenses e
    where e.id = expense_id and public.is_house_member(e.house_id)
  ));

-- 2. FUNÇÃO GENÉRICA DE AUDITORIA
create or replace function public.fn_audit_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_actor_id uuid;
  v_entity_id uuid;
  v_action text;
  v_diff jsonb;
  v_old_data jsonb;
  v_new_data jsonb;
begin
  if TG_OP = 'INSERT' then
    v_new_data := to_jsonb(NEW);
    v_house_id := (v_new_data->>'house_id')::uuid;
    v_actor_id := coalesce(auth.uid(), (v_new_data->>'created_by')::uuid, (v_new_data->>'paid_by_id')::uuid);
    v_entity_id := (v_new_data->>'id')::uuid;
    v_action := 'create';
    v_diff := jsonb_build_object('new', v_new_data);

  elsif TG_OP = 'DELETE' then
    v_old_data := to_jsonb(OLD);
    v_house_id := (v_old_data->>'house_id')::uuid;
    v_actor_id := coalesce(auth.uid(), (v_old_data->>'created_by')::uuid);
    v_entity_id := (v_old_data->>'id')::uuid;
    v_action := 'delete';
    v_diff := jsonb_build_object('old', v_old_data);

  elsif TG_OP = 'UPDATE' then
    v_old_data := to_jsonb(OLD);
    v_new_data := to_jsonb(NEW);
    v_house_id := coalesce((v_new_data->>'house_id')::uuid, (v_old_data->>'house_id')::uuid);
    v_actor_id := coalesce(auth.uid(), (v_new_data->>'updated_by')::uuid, (v_new_data->>'created_by')::uuid);
    v_entity_id := (v_new_data->>'id')::uuid;

    -- Detecta se é Soft Delete ou Restore
    if (v_new_data->>'deleted_at') is not null and (v_old_data->>'deleted_at') is null then
      v_action := 'soft_delete';
    elsif (v_old_data->>'deleted_at') is not null and (v_new_data->>'deleted_at') is null then
      v_action := 'restore';
    else
      v_action := 'update';
    end if;

    v_diff := jsonb_build_object(
      'old', v_old_data,
      'new', v_new_data
    );
  end if;

  -- Se não conseguiu house_id diretamente, tenta obter de tabelas pai para parcelas/itens
  if v_house_id is null and TG_TABLE_NAME = 'p2p_installments' then
    select house_id into v_house_id from public.p2p_loans where id = (coalesce(v_new_data, v_old_data)->>'loan_id')::uuid;
  end if;

  -- Grava na tabela audit_log
  if v_entity_id is not null then
    insert into public.audit_log (
      house_id,
      actor_id,
      entity_type,
      entity_id,
      action,
      diff,
      created_at
    ) values (
      v_house_id,
      v_actor_id,
      TG_TABLE_NAME,
      v_entity_id,
      v_action,
      v_diff,
      now()
    );
  end if;

  return coalesce(NEW, OLD);
end;
$$;

-- 3. GATILHOS (TRIGGERS) NAS TABELAS FINANCEIRAS
drop trigger if exists trg_audit_house_expenses on public.house_expenses;
create trigger trg_audit_house_expenses
  after insert or update or delete on public.house_expenses
  for each row execute function public.fn_audit_record();

drop trigger if exists trg_audit_contributions on public.contributions;
create trigger trg_audit_contributions
  after insert or update or delete on public.contributions
  for each row execute function public.fn_audit_record();

drop trigger if exists trg_audit_p2p_loans on public.p2p_loans;
create trigger trg_audit_p2p_loans
  after insert or update or delete on public.p2p_loans
  for each row execute function public.fn_audit_record();

drop trigger if exists trg_audit_savings_vaults on public.savings_vaults;
create trigger trg_audit_savings_vaults
  after insert or update or delete on public.savings_vaults
  for each row execute function public.fn_audit_record();

drop trigger if exists trg_audit_settlements on public.settlements;
create trigger trg_audit_settlements
  after insert or update or delete on public.settlements
  for each row execute function public.fn_audit_record();

-- 4. VIEW CONVENIENTE COM TIMELINE DE AUDITORIA
create or replace view public.v_audit_timeline
with (security_invoker = true) as
select
  a.id,
  a.house_id,
  a.actor_id,
  p.full_name as actor_name,
  p.avatar_url as actor_avatar_url,
  a.entity_type,
  a.entity_id,
  a.action,
  a.diff,
  a.created_at
from public.audit_log a
left join public.profiles p on a.actor_id = p.id
order by a.created_at desc;
