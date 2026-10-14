-- ==============================================================================
-- 0054: Compra no cartão fica pendente até a fatura ser paga
-- Descrição:
--   A compra no cartão nascia "paga" e só a data de pagamento da fatura dizia
--   se ela tinha sido quitada. Na Casa, uma fatura em aberto aparecia como
--   despesa paga e não havia como dizer com que dinheiro ela foi paga.
--
--   Decisão do dono: a fatura funciona como uma conta pendente (o boleto da
--   internet). A compra nasce pendente, com o vencimento da fatura, e vira paga
--   quando o pagamento da fatura é registrado, na data informada.
--
--   - pay_card_invoice recebe a origem do dinheiro: o titular (reembolsado no
--     fechamento) ou o Caixa da Casa (sem reembolso), e marca as compras como
--     pagas;
--   - undo_card_invoice_payment volta as compras para pendentes;
--   - as compras de cartão já lançadas, sem pagamento registrado e fora de
--     ciclo fechado, passam a pendentes.
-- ==============================================================================

-- 1. Registrar o pagamento da fatura, com a origem do dinheiro.
--    A versão de três parâmetros sai: com o novo parâmetro opcional, a chamada
--    antiga (sem a origem) continua funcionando e vale como paga pelo titular.
drop function if exists public.pay_card_invoice(uuid, date, timestamptz);

create or replace function public.pay_card_invoice(
  p_payment_method_id uuid,
  p_due_date date,
  p_paid_at timestamptz,
  p_paid_by_house boolean default false
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_timezone text;
  v_owner_id uuid;
  v_paid_on date;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_due_date is null or p_paid_at is null then
    raise exception 'Informe o vencimento da fatura e o dia do pagamento.';
  end if;

  select pm.house_id, h.timezone, pm.owner_member_id into v_house_id, v_timezone, v_owner_id
  from public.payment_methods pm
  join public.houses h on h.id = pm.house_id
  where pm.id = p_payment_method_id;
  if not found or not public.is_house_member(v_house_id) then
    raise exception 'Forma de pagamento não encontrada nesta casa.';
  end if;

  -- Nem o ciclo de onde as compras saem nem o de destino podem estar fechados
  v_paid_on := (p_paid_at at time zone v_timezone)::date;
  if public.is_date_in_closed_cycle(v_house_id, p_due_date)
     or public.is_date_in_closed_cycle(v_house_id, v_paid_on) then
    raise exception 'O ciclo já foi fechado. Reabra esse ciclo no Fechamento para alterar o pagamento desta fatura.';
  end if;

  -- Pago pelo titular: ele é reembolsado no fechamento. Pelo Caixa (ou cartão
  -- sem dono): sai do caixa, sem reembolso.
  update public.house_expenses
  set status = 'paid',
      paid_at = p_paid_at,
      paid_out_of_pocket = (not coalesce(p_paid_by_house, false)) and v_owner_id is not null
  where house_id = v_house_id
    and payment_method_id = p_payment_method_id
    and due_date = p_due_date
    and deleted_at is null
    and settled_at is null
    and paid_at is null;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

-- 2. Desfazer o pagamento: as compras voltam a ser uma fatura em aberto.
create or replace function public.undo_card_invoice_payment(
  p_payment_method_id uuid,
  p_due_date date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_timezone text;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_due_date is null then
    raise exception 'Informe o vencimento da fatura.';
  end if;

  select pm.house_id, h.timezone into v_house_id, v_timezone
  from public.payment_methods pm
  join public.houses h on h.id = pm.house_id
  where pm.id = p_payment_method_id;
  if not found or not public.is_house_member(v_house_id) then
    raise exception 'Forma de pagamento não encontrada nesta casa.';
  end if;

  if public.is_date_in_closed_cycle(v_house_id, p_due_date)
     or exists (
       select 1 from public.house_expenses e
       where e.house_id = v_house_id
         and e.payment_method_id = p_payment_method_id
         and e.due_date = p_due_date
         and e.deleted_at is null
         and e.paid_at is not null
         and (e.settled_at is not null
              or public.is_date_in_closed_cycle(v_house_id, (e.paid_at at time zone v_timezone)::date))
     ) then
    raise exception 'O ciclo já foi fechado. Reabra esse ciclo no Fechamento para alterar o pagamento desta fatura.';
  end if;

  update public.house_expenses
  set status = 'pending',
      paid_at = null,
      paid_out_of_pocket = false
  where house_id = v_house_id
    and payment_method_id = p_payment_method_id
    and due_date = p_due_date
    and deleted_at is null
    and settled_at is null
    and paid_at is not null;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke execute on function public.pay_card_invoice(uuid, date, timestamptz, boolean) from public, anon;
grant execute on function public.pay_card_invoice(uuid, date, timestamptz, boolean) to authenticated;
revoke execute on function public.undo_card_invoice_payment(uuid, date) from public, anon;
grant execute on function public.undo_card_invoice_payment(uuid, date) to authenticated;

-- 3. Compras de cartão já lançadas e ainda sem pagamento da fatura passam a
--    pendentes. Ficam como estão: as já acertadas em um fechamento, as de ciclo
--    fechado, as de projeto e as contas recorrentes (que seguem o vencimento
--    da própria série, e não o da fatura).
update public.house_expenses e
set status = 'pending',
    paid_out_of_pocket = false
from public.payment_methods pm
where pm.id = e.payment_method_id
  and pm.type = 'card'
  and pm.closing_day is not null
  and pm.due_day is not null
  and e.status = 'paid'
  and e.paid_at is null
  and e.settled_at is null
  and e.deleted_at is null
  and e.project_id is null
  and not e.is_recurring
  and e.due_date is not null
  and not public.is_date_in_closed_cycle(e.house_id, e.due_date);
