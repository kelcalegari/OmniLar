-- 0087: create_p2p_loan é security invoker e chamava is_date_in_closed_cycle,
-- que só o service_role executa. Quem confirmava uma importação com empréstimo
-- do Caixa recebia "permission denied for function is_date_in_closed_cycle".
-- Passa a usar house_date_is_closed (security definer, liberada para authenticated).
create or replace function public.create_p2p_loan(p_loan jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_house uuid := (p_loan->>'house_id')::uuid;
  v_funding text := nullif(p_loan->>'house_funding', '');
  v_funded_on date := (p_loan->>'funded_on')::date;
begin
  if jsonb_array_length(coalesce(p_loan->'installments', '[]'::jsonb)) = 0 then
    raise exception 'O empréstimo precisa de ao menos uma parcela.';
  end if;
  if v_funding is not null then
    if v_funding <> 'cycle' then
      raise exception 'Empréstimo de caixinha é criado por create_house_loan.';
    end if;
    if not coalesce((p_loan->>'lender_is_house')::boolean, false) then
      raise exception 'Só o Caixa da Casa empresta dinheiro do ciclo.';
    end if;
    if v_funded_on is null then
      raise exception 'Informe o dia em que o dinheiro saiu do Caixa.';
    end if;
    if public.house_date_is_closed(v_house, v_funded_on) then
      raise exception 'Este ciclo já foi fechado. Reabra o ciclo no Fechamento para tirar dinheiro do Caixa dele.';
    end if;
  end if;

  insert into public.p2p_loans (
    id, house_id, lender_id, lender_is_house, repayment_mode, settle_in_cycle,
    borrower_id, title, description, total_amount_cents, installments_count,
    status, created_by, created_at, house_funding, funded_on
  ) values (
    coalesce((p_loan->>'id')::uuid, gen_random_uuid()),
    v_house,
    (p_loan->>'lender_id')::uuid,
    coalesce((p_loan->>'lender_is_house')::boolean, false),
    coalesce(p_loan->>'repayment_mode', 'installments'),
    coalesce((p_loan->>'settle_in_cycle')::boolean, true),
    (p_loan->>'borrower_id')::uuid,
    p_loan->>'title',
    p_loan->>'description',
    (p_loan->>'total_amount_cents')::bigint,
    coalesce((p_loan->>'installments_count')::integer, 1),
    coalesce(p_loan->>'status', 'active'),
    auth.uid(),
    coalesce((p_loan->>'created_at')::timestamptz, now()),
    v_funding,
    case when v_funding is not null then v_funded_on end
  )
  returning id into v_id;

  insert into public.p2p_installments (
    id, loan_id, installment_number, amount_cents, paid_cents, due_date, status, paid_at
  )
  select
    coalesce((inst->>'id')::uuid, gen_random_uuid()),
    v_id,
    (inst->>'installment_number')::integer,
    (inst->>'amount_cents')::bigint,
    coalesce((inst->>'paid_cents')::bigint, 0),
    (inst->>'due_date')::date,
    coalesce(inst->>'status', 'pending'),
    (inst->>'paid_at')::timestamptz
  from jsonb_array_elements(p_loan->'installments') as inst;

  return v_id;
end;
$$;
revoke execute on function public.create_p2p_loan(jsonb) from public, anon;
grant execute on function public.create_p2p_loan(jsonb) to authenticated;

notify pgrst, 'reload schema';
