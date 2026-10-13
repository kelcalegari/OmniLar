-- ==============================================================================
-- 0051: Dono da categoria vale para as despesas em aberto
-- Descrição:
--   O rateio é gravado na despesa quando ela é lançada. Definir ou trocar o
--   dono de uma categoria não mexia no que já existia, e as contas recorrentes
--   seguintes copiavam o rateio antigo.
--   Agora, ao mudar o dono, as despesas da categoria que ainda não entraram em
--   um fechamento passam a ser 100% do dono novo (e os sub-itens dela também).
--   Tirar o dono devolve ao rateio padrão da casa as que eram do dono antigo.
--   Despesa de ciclo fechado e despesa de projeto nunca mudam.
-- ==============================================================================

create or replace function public.apply_category_owner_to_open_expenses()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exp public.house_expenses%rowtype;
begin
  if new.owner_member_id is not distinct from old.owner_member_id then
    return new;
  end if;

  -- Espera um fechamento em andamento nesta casa
  perform pg_advisory_xact_lock_shared(hashtextextended('house-ledger:' || new.house_id::text, 0));

  -- Sub-itens da categoria: os que eram do dono antigo (ou de ninguém) seguem o novo.
  -- Sub-item marcado para outro morador continua dele.
  update public.house_expense_items i
  set responsible_member_id = new.owner_member_id
  from public.house_expenses e
  where e.id = i.expense_id
    and i.category_id = new.id
    and e.house_id = new.house_id
    and e.deleted_at is null
    and e.project_id is null
    and e.settled_at is null
    and not public.expense_counts_in_closed_cycle(e)
    and (i.responsible_member_id is null
         or i.responsible_member_id is not distinct from old.owner_member_id)
    and i.responsible_member_id is distinct from new.owner_member_id;

  for v_exp in
    select e.* from public.house_expenses e
    where e.category_id = new.id
      and e.house_id = new.house_id
      and e.deleted_at is null
      and e.project_id is null
      and e.settled_at is null
      and not public.expense_counts_in_closed_cycle(e)
  loop
    if new.owner_member_id is not null then
      update public.house_expenses set split_type = 'category_owner'
      where id = v_exp.id and split_type <> 'category_owner';

      delete from public.split_rules where expense_id = v_exp.id;
      insert into public.split_rules (expense_id, member_id, percentage_basis_points, calculated_cents)
      values (v_exp.id, new.owner_member_id, 10000, v_exp.amount_cents);

    elsif v_exp.split_type = 'category_owner' and exists (
      select 1 from public.split_rules
      where expense_id = v_exp.id and member_id = old.owner_member_id
    ) then
      -- A categoria ficou sem dono: volta ao percentual padrão dos moradores.
      -- Os centavos do arredondamento vão para quem ficou com a maior fração.
      update public.house_expenses set split_type = 'percentage' where id = v_exp.id;

      delete from public.split_rules where expense_id = v_exp.id;
      insert into public.split_rules (expense_id, member_id, percentage_basis_points, calculated_cents)
      with m as (
        select hm.user_id, hm.joined_at,
               round(coalesce(hm.default_split_percent, 0) * 100)::bigint as bp
        from public.house_members hm
        where hm.house_id = new.house_id and hm.left_at is null
      ),
      w as (
        -- Sem percentual definido para ninguém, divide em partes iguais
        select m.*, case when sum(m.bp) over () > 0 then m.bp else 1 end as weight
        from m
      ),
      base as (
        select w.*,
               v_exp.amount_cents * w.weight / (sum(w.weight) over ())::bigint as cents,
               v_exp.amount_cents * w.weight % (sum(w.weight) over ())::bigint as remainder
        from w
      ),
      ranked as (
        select base.*,
               row_number() over (order by base.remainder desc, base.joined_at, base.user_id) as pos,
               v_exp.amount_cents - sum(base.cents) over () as leftover
        from base
      )
      select v_exp.id, user_id, least(bp, 10000)::integer,
             cents + case when pos <= leftover then 1 else 0 end
      from ranked;
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_categories_owner_to_open_expenses on public.categories;
create trigger trg_categories_owner_to_open_expenses
  after update of owner_member_id on public.categories
  for each row execute function public.apply_category_owner_to_open_expenses();
