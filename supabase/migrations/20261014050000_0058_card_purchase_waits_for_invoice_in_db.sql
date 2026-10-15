-- ==============================================================================
-- 0058: Compra no cartão nasce pendente também no banco
-- Descrição:
--   A 0054 decidiu que a compra no cartão (com fechamento e vencimento) fica
--   pendente até a fatura ser paga. A regra estava só no app: o banco aceitava
--   uma compra de cartão já paga, sem pagamento da fatura, se alguém a enviasse
--   assim.
--
--   Agora, ao criar a despesa, o banco aplica a mesma regra do app
--   (ExpenseLaunchDefaults.waitsForInvoice), com as mesmas exceções:
--   - despesa de projeto nasce como foi enviada (não entra em fatura da casa);
--   - conta recorrente segue o vencimento da própria série;
--   - cartão sem fechamento ou vencimento cadastrado não tem fatura.
--   Só vale na criação: pagar e desfazer o pagamento da fatura continuam
--   mudando o status depois. O nome do gatilho faz ele rodar antes da trava de
--   ciclo fechado, que já recebe a compra como pendente.
-- ==============================================================================

create or replace function public.card_purchase_waits_for_invoice()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.project_id is null
     and not coalesce(new.is_recurring, false)
     and new.payment_method_id is not null
     and exists (
       select 1 from public.payment_methods pm
       where pm.id = new.payment_method_id
         and pm.type = 'card'
         and pm.closing_day is not null
         and pm.due_day is not null
     ) then
    new.status := 'pending';
    new.paid_at := null;
    new.paid_out_of_pocket := false;
  end if;
  return new;
end;
$$;

-- Função de gatilho: não é para ser chamada pela API
revoke execute on function public.card_purchase_waits_for_invoice() from public, anon, authenticated;

drop trigger if exists trg_house_expenses_card_waits_for_invoice on public.house_expenses;
create trigger trg_house_expenses_card_waits_for_invoice
  before insert on public.house_expenses
  for each row execute function public.card_purchase_waits_for_invoice();

-- ------------------------------------------------------------------------------
-- Pagar e desfazer a fatura mexem só nas compras da fatura
--   Despesa de projeto e conta recorrente no mesmo cartão e vencimento não fazem
--   parte da fatura (são as mesmas exceções acima e as do app, em
--   isOpenInvoicePurchase). Antes, pagar a fatura dava baixa numa conta
--   recorrente pendente com o mesmo vencimento, e desfazer voltava para
--   pendente a recorrente e a despesa de projeto. O resto das duas funções é
--   igual ao da 0055.
-- ------------------------------------------------------------------------------

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
  v_by_house boolean;
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

  -- Cartão sem dono só pode ter sido pago pelo Caixa
  v_by_house := coalesce(p_paid_by_house, false) or v_owner_id is null;

  update public.house_expenses
  set status = 'paid',
      paid_at = p_paid_at,
      paid_out_of_pocket = not v_by_house
  where house_id = v_house_id
    and payment_method_id = p_payment_method_id
    and due_date = p_due_date
    and deleted_at is null
    and settled_at is null
    and paid_at is null
    and project_id is null
    and not is_recurring;
  get diagnostics v_count = row_count;

  if v_by_house then
    perform public.apply_invoice_paid_by_house(v_house_id, p_payment_method_id, p_due_date, p_paid_at);
  end if;

  return v_count;
end;
$$;

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
         and e.project_id is null
         and not e.is_recurring
         and e.paid_at is not null
         and (e.settled_at is not null
              or public.is_date_in_closed_cycle(v_house_id, (e.paid_at at time zone v_timezone)::date))
     ) then
    raise exception 'O ciclo já foi fechado. Reabra esse ciclo no Fechamento para alterar o pagamento desta fatura.';
  end if;

  perform public.revert_invoice_paid_by_house(v_house_id, p_payment_method_id, p_due_date);

  update public.house_expenses
  set status = 'pending',
      paid_at = null,
      paid_out_of_pocket = false
  where house_id = v_house_id
    and payment_method_id = p_payment_method_id
    and due_date = p_due_date
    and deleted_at is null
    and settled_at is null
    and paid_at is not null
    and project_id is null
    and not is_recurring;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;
