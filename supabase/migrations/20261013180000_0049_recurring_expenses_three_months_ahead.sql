-- ==============================================================================
-- 0049: Contas recorrentes geradas até três meses à frente
-- Descrição:
--   O limite de dois meses da 0036 cortava no meio o ciclo que começa dentro
--   desse prazo: cadastrada em 13/10 com vencimento no dia 25, a conta de 25/12
--   não nascia e o ciclo de 09/12 a 08/01 aparecia sem ela.
--   Com três meses, todo ciclo que começa em até dois meses aparece completo.
--   O resto da função é igual ao da 0038.
-- ==============================================================================

create or replace function public.generate_recurring_expenses(p_house_id uuid, p_until date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_timezone text;
  v_until date;
  v_series public.house_expenses%rowtype;
  v_template public.house_expenses%rowtype;
  v_last_due date;
  v_next_due date;
  v_month date;
  v_due_day integer;
  v_new_id uuid;
  v_created integer := 0;
  v_guard integer;
begin
  if not public.is_house_member(p_house_id) then
    raise exception 'Acesso negado: você não é membro desta casa';
  end if;

  select timezone into v_timezone from public.houses where id = p_house_id;

  -- Nunca gera além de três meses à frente, por mais longe que a tela navegue
  v_until := least(p_until, (current_date + interval '3 months')::date);

  -- Duas telas abertas ao mesmo tempo não geram a mesma conta em dobro
  perform pg_advisory_xact_lock(hashtextextended('recurring-expenses:' || p_house_id::text, 0));

  for v_series in
    select * from public.house_expenses
    where house_id = p_house_id
      and is_recurring
      and is_active
      and recurring_series_id is null
      and project_id is null
  loop
    select max(due_date) into v_last_due
    from public.house_expenses
    where id = v_series.id or recurring_series_id = v_series.id;

    v_guard := 0;
    loop
      v_guard := v_guard + 1;
      exit when v_guard > 12;

      -- Modelo: a ocorrência mais recente ainda existente (carrega edições
      -- feitas com "esta e as próximas"); sem nenhuma, a matriz.
      select * into v_template
      from public.house_expenses
      where (id = v_series.id or recurring_series_id = v_series.id)
        and deleted_at is null
      order by due_date desc
      limit 1;
      if not found then
        v_template := v_series;
      end if;

      -- O dia de vencimento também vem do modelo: mudá-lo com "esta e as
      -- próximas" vale para as contas dos meses seguintes
      v_due_day := coalesce(
        v_template.due_day,
        v_series.due_day,
        extract(day from v_series.due_date)::integer
      );
      v_month := (date_trunc('month', v_last_due) + interval '1 month')::date;
      v_next_due := least(
        v_month + (v_due_day - 1),
        (v_month + interval '1 month - 1 day')::date
      );
      exit when v_next_due > v_until;

      insert into public.house_expenses (
        house_id, title, amount_cents, category_id, payment_method_id, paid_by_id,
        paid_out_of_pocket, due_date, cycle_start_date, split_type, notes, status,
        created_by, is_recurring, is_variable, due_day, is_active,
        recurring_series_id, date
      ) values (
        p_house_id, v_template.title, v_template.amount_cents, v_template.category_id,
        v_template.payment_method_id, v_template.paid_by_id,
        v_template.paid_out_of_pocket, v_next_due, v_next_due, v_template.split_type,
        v_template.notes, 'pending',
        coalesce(auth.uid(), v_series.created_by), true, v_template.is_variable, v_due_day, true,
        v_series.id, (v_next_due::timestamp + interval '12 hours') at time zone coalesce(v_timezone, 'America/Sao_Paulo')
      )
      on conflict (recurring_series_id, due_date) where recurring_series_id is not null do nothing
      returning id into v_new_id;

      if v_new_id is not null then
        insert into public.split_rules (
          expense_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
        )
        select v_new_id, member_id, percentage_basis_points, fixed_amount_cents, calculated_cents
        from public.split_rules
        where expense_id = v_template.id;

        insert into public.house_expense_items (
          expense_id, title, amount_cents, category_id, responsible_member_id, split_type
        )
        select v_new_id, title, amount_cents, category_id, responsible_member_id, split_type
        from public.house_expense_items
        where expense_id = v_template.id;

        v_created := v_created + 1;
      end if;

      v_new_id := null;
      v_last_due := v_next_due;
    end loop;
  end loop;

  return v_created;
end;
$$;
