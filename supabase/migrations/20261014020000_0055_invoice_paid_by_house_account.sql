-- ==============================================================================
-- 0055: Fatura paga pelo Caixa da Casa
-- Descrição:
--   Decisão do dono: quem paga a fatura paga ela inteira. Quando o Caixa da
--   Casa paga, ele também pagou o que não era da casa, e isso volta para ele:
--   - o que outro morador devia ao titular (empréstimo criado na importação)
--     passa a ser devido ao Caixa;
--   - os gastos pessoais do titular (linhas "pessoal" da importação) viram uma
--     dívida dele com o Caixa, em parcela única cobrada no fechamento do ciclo
--     do pagamento.
--   Desfazer o pagamento desfaz as duas coisas, enquanto nada tiver sido pago.
--
--   Só a fatura importada tem esse detalhe: em fatura lançada à mão o app só
--   conhece as compras da casa, e o Caixa paga sem criar dívida nenhuma.
-- ==============================================================================

alter table public.import_batches
  add column if not exists house_paid_at timestamptz,
  add column if not exists house_loan_id uuid references public.p2p_loans(id) on delete set null;

-- 1. Fatura importada paga pelo Caixa: os empréstimos e a dívida do titular
create or replace function public.apply_invoice_paid_by_house(
  p_house_id uuid,
  p_payment_method_id uuid,
  p_due_date date,
  p_paid_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch record;
  v_personal bigint;
  v_loan_id uuid;
  v_timezone text;
begin
  select timezone into v_timezone from public.houses where id = p_house_id;

  for v_batch in
    select * from public.import_batches
    where house_id = p_house_id
      and payment_method_id = p_payment_method_id
      and invoice_due_date = p_due_date
      and status = 'confirmed'
      and house_paid_at is null
    for update
  loop
    -- Morador que já pagou parte ao titular: a dívida não pode mudar de credor
    if exists (
      select 1
      from public.import_lines l
      join public.p2p_installments i on i.loan_id = l.loan_id
      where l.batch_id = v_batch.id and l.decision = 'created' and i.paid_cents > 0
    ) then
      raise exception 'Um empréstimo desta fatura já teve pagamento ao titular. Registre o pagamento como feito pelo titular.';
    end if;

    -- Quem devia ao titular passa a dever ao Caixa
    update public.p2p_loans
    set lender_id = null,
        lender_is_house = true
    where id in (
        select loan_id from public.import_lines
        where batch_id = v_batch.id and decision = 'created' and loan_id is not null
      )
      and not lender_is_house;

    -- Os gastos pessoais do titular viram dívida dele com o Caixa
    select coalesce(sum(amount_cents), 0) into v_personal
    from public.import_lines
    where batch_id = v_batch.id
      and kind = 'purchase'
      and split_destination = 'personal'
      and decision = 'ignored';

    v_loan_id := null;
    if v_personal > 0 and v_batch.payer_id is not null then
      insert into public.p2p_loans (
        house_id, lender_id, lender_is_house, borrower_id, title, description,
        total_amount_cents, installments_count, status, created_by, repayment_mode, settle_in_cycle
      ) values (
        p_house_id, null, true, v_batch.payer_id,
        'Fatura ' || v_batch.account_name || ' paga pelo Caixa — gastos pessoais',
        'Gastos pessoais da fatura que vence em ' || to_char(p_due_date, 'DD/MM/YYYY') ||
          ', pagos pelo Caixa da Casa',
        v_personal, 1, 'active', auth.uid(), 'installments', true
      )
      returning id into v_loan_id;

      insert into public.p2p_installments (loan_id, installment_number, amount_cents, paid_cents, due_date, status)
      values (v_loan_id, 1, v_personal, 0, (p_paid_at at time zone coalesce(v_timezone, 'America/Sao_Paulo'))::date, 'pending');
    end if;

    update public.import_batches
    set house_paid_at = p_paid_at,
        house_loan_id = v_loan_id
    where id = v_batch.id;
  end loop;
end;
$$;

-- 2. Desfaz o que o pagamento pelo Caixa criou ou trocou
create or replace function public.revert_invoice_paid_by_house(
  p_house_id uuid,
  p_payment_method_id uuid,
  p_due_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch record;
begin
  for v_batch in
    select * from public.import_batches
    where house_id = p_house_id
      and payment_method_id = p_payment_method_id
      and invoice_due_date = p_due_date
      and house_paid_at is not null
    for update
  loop
    if exists (
      select 1 from public.p2p_installments i
      where i.paid_cents > 0
        and (
          i.loan_id = v_batch.house_loan_id
          or i.loan_id in (
            select loan_id from public.import_lines
            where batch_id = v_batch.id and decision = 'created' and loan_id is not null
          )
        )
    ) then
      raise exception 'Parte do que esta fatura gerou de dívida com o Caixa já foi paga. Não dá para desfazer o pagamento da fatura.';
    end if;

    if v_batch.house_loan_id is not null then
      delete from public.p2p_loans where id = v_batch.house_loan_id;
    end if;

    -- A dívida volta a ser com quem pagou a fatura na importação
    if v_batch.payer_id is not null then
      update public.p2p_loans
      set lender_is_house = false,
          lender_id = v_batch.payer_id
      where id in (
          select loan_id from public.import_lines
          where batch_id = v_batch.id and decision = 'created' and loan_id is not null
        )
        and lender_is_house
        and borrower_id <> v_batch.payer_id;
    end if;

    update public.import_batches
    set house_paid_at = null,
        house_loan_id = null
    where id = v_batch.id;
  end loop;
end;
$$;

revoke execute on function public.apply_invoice_paid_by_house(uuid, uuid, date, timestamptz) from public, anon, authenticated;
revoke execute on function public.revert_invoice_paid_by_house(uuid, uuid, date) from public, anon, authenticated;

-- 3. Registrar o pagamento: pelo Caixa (ou cartão sem dono), aplica o item 1
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
    and paid_at is null;
  get diagnostics v_count = row_count;

  if v_by_house then
    perform public.apply_invoice_paid_by_house(v_house_id, p_payment_method_id, p_due_date, p_paid_at);
  end if;

  return v_count;
end;
$$;

-- 4. Desfazer o pagamento: desfaz também o que o pagamento pelo Caixa gerou
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
    and paid_at is not null;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke execute on function public.pay_card_invoice(uuid, date, timestamptz, boolean) from public, anon;
grant execute on function public.pay_card_invoice(uuid, date, timestamptz, boolean) to authenticated;
revoke execute on function public.undo_card_invoice_payment(uuid, date) from public, anon;
grant execute on function public.undo_card_invoice_payment(uuid, date) to authenticated;

-- 5. Desfazer a importação de uma fatura paga pelo Caixa: primeiro o pagamento
create or replace function public.undo_import(p_batch_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_house_id uuid;
  v_status text;
  v_house_paid_at timestamptz;
  v_expense_id uuid;
  v_loans uuid[];
  v_deleted integer;
begin
  select house_id, status, house_paid_at into v_house_id, v_status, v_house_paid_at
  from public.import_batches
  where id = p_batch_id
  for update;

  if v_house_id is null then
    raise exception 'Importação não encontrada.';
  end if;
  if v_status = 'undone' then
    raise exception 'Esta importação já foi desfeita.';
  end if;
  if v_house_paid_at is not null then
    raise exception 'Esta fatura foi paga pelo Caixa da Casa. Desfaça antes o pagamento da fatura.';
  end if;

  -- Recusa despesa já acertada em um fechamento (a mensagem vem da função)
  for v_expense_id in
    select l.expense_id
    from public.import_lines l
    join public.house_expenses e on e.id = l.expense_id
    where l.batch_id = p_batch_id and l.decision = 'created' and e.deleted_at is null
  loop
    perform public.delete_house_expense(v_expense_id, 'thisInstanceOnly');
  end loop;

  select array_agg(distinct l.loan_id) into v_loans
  from public.import_lines l
  join public.p2p_loans p on p.id = l.loan_id
  where l.batch_id = p_batch_id and l.decision = 'created';

  if v_loans is not null then
    with deleted as (
      delete from public.p2p_loans where id = any(v_loans) returning id
    )
    select count(*) into v_deleted from deleted;

    -- A regra de acesso não dá erro: só deixa de apagar
    if v_deleted <> array_length(v_loans, 1) then
      raise exception 'Um empréstimo desta importação já teve pagamento ou não é seu. Só quem emprestou (ou um administrador) desfaz, e apenas enquanto nada foi pago.';
    end if;
  end if;

  update public.import_batches
  set status = 'undone', undone_at = now(), undone_by = auth.uid()
  where id = p_batch_id;
end;
$$;

revoke execute on function public.undo_import(uuid) from public, anon;
grant execute on function public.undo_import(uuid) to authenticated;
