-- ==============================================================================
-- 0117: Compra parcelada lançada à mão
-- Descrição:
--   Até aqui a compra parcelada só nascia na importação da fatura. Agora a
--   Nova despesa lança a compra no cartão em N vezes:
--   - `installment_plans.origin` diz de onde o plano veio: da importação
--     (`import`) ou lançado à mão (`manual`). A fatura casa a parcela com o
--     plano lançado à mão mesmo que o nome digitado não seja o do banco;
--   - `create_installment_purchase` grava o plano e, na mesma transação, as
--     parcelas da Casa como previstas (a fatura de cada mês só as confirma) ou
--     os empréstimos do morador que deve a compra. No cartão de um morador é
--     um empréstimo com N parcelas; no cartão da Casa, um por fatura, cada um
--     saindo do Caixa do ciclo em que a fatura vence;
--   - aceitar um dos empréstimos de uma compra parcelada lançada à mão aceita
--     os outros dela, que esperavam o mesmo aceite.
-- ==============================================================================

-- 1. Origem do plano
alter table public.installment_plans
  add column if not exists origin text not null default 'import'
    check (origin in ('import', 'manual'));

-- 2. Lança a compra parcelada
--    {
--      "plan": {id, house_id, payment_method_id, merchant_key, title,
--               installments_total, installment_cents, anchor_number (a
--               próxima parcela, numa compra já em andamento), anchor_line_date,
--               anchor_due_date, destination, category_id?, assigned_member_id?},
--      "expenses": [payload de create_house_expense + "installment_number"],
--      "loans": [payload de create_p2p_loan]
--    }
create or replace function public.create_installment_purchase(p_purchase jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_plan jsonb := p_purchase->'plan';
  v_house_id uuid := (p_purchase->'plan'->>'house_id')::uuid;
  v_plan_id uuid := coalesce((p_purchase->'plan'->>'id')::uuid, gen_random_uuid());
  v_destination text := coalesce(p_purchase->'plan'->>'destination', 'house');
  v_item jsonb;
  v_expense_id uuid;
begin
  if v_house_id is null or not public.is_house_member(v_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa.';
  end if;
  if v_destination not in ('house', 'p2p_loan') then
    raise exception 'A compra parcelada lançada à mão é da Casa ou de um morador.';
  end if;
  if v_destination = 'p2p_loan' and (v_plan->>'assigned_member_id') is null then
    raise exception 'Diga qual morador deve a compra parcelada.';
  end if;

  insert into public.installment_plans (
    id, house_id, payment_method_id, merchant_key, title, installments_total,
    installment_cents, anchor_number, anchor_line_date, anchor_due_date, destination,
    category_id, assigned_member_id, origin
  ) values (
    v_plan_id,
    v_house_id,
    (v_plan->>'payment_method_id')::uuid,
    v_plan->>'merchant_key',
    v_plan->>'title',
    (v_plan->>'installments_total')::integer,
    (v_plan->>'installment_cents')::bigint,
    coalesce((v_plan->>'anchor_number')::integer, 1),
    (v_plan->>'anchor_line_date')::date,
    (v_plan->>'anchor_due_date')::date,
    v_destination,
    (v_plan->>'category_id')::uuid,
    case when v_destination = 'p2p_loan' then (v_plan->>'assigned_member_id')::uuid end,
    'manual'
  );

  -- Parcelas da Casa: todas previstas, cada fatura confirma a sua
  for v_item in select * from jsonb_array_elements(coalesce(p_purchase->'expenses', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A compra parcelada tem uma despesa de outra casa.';
    end if;
    v_expense_id := public.create_house_expense(v_item);
    update public.house_expenses
    set installment_plan_id = v_plan_id,
        installment_number = (v_item->>'installment_number')::integer,
        is_forecast = true
    where id = v_expense_id and house_id = v_house_id;
  end loop;

  -- Empréstimos do morador, ligados ao plano para o aceite único
  for v_item in select * from jsonb_array_elements(coalesce(p_purchase->'loans', '[]'::jsonb)) loop
    if (v_item->>'house_id')::uuid is distinct from v_house_id then
      raise exception 'A compra parcelada tem um empréstimo de outra casa.';
    end if;
    perform public.create_p2p_loan(
      v_item || jsonb_build_object('installment_plan_ids', jsonb_build_array(v_plan_id))
    );
  end loop;

  return v_plan_id;
end;
$$;

revoke execute on function public.create_installment_purchase(jsonb) from public, anon;
grant execute on function public.create_installment_purchase(jsonb) to authenticated;

-- 3. Aceitar o empréstimo (0116) aceita também as compras parceladas dele e,
--    nas lançadas à mão, os outros empréstimos da mesma compra
create or replace function public.accept_p2p_loan(p_loan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_user uuid := auth.uid();
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found or not public.is_house_member(v_loan.house_id) then
    raise exception 'Empréstimo não encontrado.';
  end if;
  if v_loan.borrower_id is distinct from v_user then
    raise exception 'Só quem deve pode aceitar o empréstimo.';
  end if;

  -- As próximas parcelas destas compras já nascem aceitas
  update public.installment_plans
     set accepted_by = v_user, accepted_at = now(), updated_at = now()
   where id = any(v_loan.installment_plan_ids)
     and house_id = v_loan.house_id
     and assigned_member_id = v_user
     and accepted_by is distinct from v_user;

  -- Compra lançada à mão no cartão da Casa: um empréstimo por fatura, um aceite só
  update public.p2p_loans l
     set awaiting_acceptance = false, accepted_at = now()
   where l.id <> p_loan_id
     and l.house_id = v_loan.house_id
     and l.borrower_id = v_user
     and l.awaiting_acceptance
     and l.installment_plan_ids <@ coalesce(
       array(
         select p.id from public.installment_plans p
         where p.id = any(v_loan.installment_plan_ids)
           and p.house_id = v_loan.house_id
           and p.origin = 'manual'
           and p.assigned_member_id = v_user
       ),
       '{}'::uuid[]
     )
     and cardinality(l.installment_plan_ids) > 0;

  if not v_loan.awaiting_acceptance then
    return;
  end if;

  update public.p2p_loans set awaiting_acceptance = false, accepted_at = now() where id = p_loan_id;

  perform public.enqueue_notification(
    v_loan.house_id,
    case when v_loan.lender_is_house then public.notification_house_admin_ids(v_loan.house_id)
         else array[v_loan.lender_id] end,
    'loan_accepted', 'emprestimos',
    'Empréstimo aceito',
    public.notification_first_name(v_user) || ' aceitou o empréstimo ' || v_loan.title || ': '
      || public.notification_brl(v_loan.total_amount_cents),
    '/pessoal/emprestimo/' || p_loan_id, 'p2p_loan', p_loan_id,
    'loan_accepted:' || p_loan_id, false
  );
end;
$$;

revoke execute on function public.accept_p2p_loan(uuid) from public, anon;
grant execute on function public.accept_p2p_loan(uuid) to authenticated, service_role;
