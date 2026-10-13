-- ==============================================================================
-- 0028: Pagamento de fatura de cartão respeita ciclo fechado
-- Descrição:
--   Registrar ou desfazer o dia do pagamento de uma fatura muda o ciclo em que
--   as compras contam. O bloqueio para ciclo já fechado existia só no app, que
--   conferia e depois gravava direto na tabela. Agora a conferência e a
--   gravação acontecem juntas no banco.
--   Um ciclo é considerado fechado pelo fechamento gravado (settlements), sem
--   depender do dia de início configurado na casa.
-- ==============================================================================

-- A data cai em um ciclo com fechamento confirmado?
create or replace function public.is_date_in_closed_cycle(p_house_id uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.settlements s
    where s.house_id = p_house_id
      and s.status in ('confirmed', 'completed')
      and p_date >= s.cycle_start_date
      and p_date < (s.cycle_start_date + interval '1 month')::date
  );
$$;

-- Registra o dia em que a fatura que vence em p_due_date foi paga.
-- Devolve quantas compras foram marcadas.
create or replace function public.pay_card_invoice(
  p_payment_method_id uuid,
  p_due_date date,
  p_paid_at timestamptz
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_timezone text;
  v_paid_on date;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;
  if p_due_date is null or p_paid_at is null then
    raise exception 'Informe o vencimento da fatura e o dia do pagamento.';
  end if;

  select pm.house_id, h.timezone into v_house_id, v_timezone
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

  update public.house_expenses
  set paid_at = p_paid_at
  where house_id = v_house_id
    and payment_method_id = p_payment_method_id
    and due_date = p_due_date
    and deleted_at is null
    and paid_at is null;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

-- Desfaz o registro de pagamento da fatura que vence em p_due_date.
-- Devolve quantas compras voltaram a contar pelo vencimento.
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
         and public.is_date_in_closed_cycle(v_house_id, (e.paid_at at time zone v_timezone)::date)
     ) then
    raise exception 'O ciclo já foi fechado. Reabra esse ciclo no Fechamento para alterar o pagamento desta fatura.';
  end if;

  update public.house_expenses
  set paid_at = null
  where house_id = v_house_id
    and payment_method_id = p_payment_method_id
    and due_date = p_due_date
    and deleted_at is null
    and paid_at is not null;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke execute on function public.is_date_in_closed_cycle(uuid, date) from public, anon, authenticated;
revoke execute on function public.pay_card_invoice(uuid, date, timestamptz) from public, anon;
revoke execute on function public.undo_card_invoice_payment(uuid, date) from public, anon;
grant execute on function public.pay_card_invoice(uuid, date, timestamptz) to authenticated;
grant execute on function public.undo_card_invoice_payment(uuid, date) to authenticated;
