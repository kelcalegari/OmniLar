-- ==============================================================================
-- 0092: Regra por tipo de entrada no Caixa
-- Descrição:
--   1. opening_inflow_rules: a regra da 0091 (reduce_quotas, cover_excess,
--      keep) escolhida para cada tipo de dinheiro que já está no Caixa ou
--      entra nele no ciclo sem ser aporte (o cálculo é do app):
--      - rolled_surplus: sobra do ciclo anterior;
--      - house_loans_repaid: empréstimo do Caixa pago de volta;
--      - vault_withdrawals: resgate de caixinha (padrão da casa), com
--        vault_overrides { id da caixinha: regra } para cada caixinha;
--      - third_party: entrada de fora (reservado para depois).
--      Tipo sem escolha: sobra e empréstimo seguem opening_balance_rule (e,
--      nula, o comportamento anterior); resgate de caixinha fica no Caixa
--      (keep); entrada de fora segue a sobra.
--   2. update_house_settings passa a gravar e devolver opening_inflow_rules
--      (objeto inteiro, só administradores, como a regra da 0091).
-- ==============================================================================

create or replace function public.opening_inflow_rules_valid(p_rules jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_rules) = 'object'
    and not exists (
      select 1 from jsonb_each(p_rules) e
      where e.key not in ('rolled_surplus', 'house_loans_repaid', 'vault_withdrawals', 'vault_overrides', 'third_party')
        or (e.key <> 'vault_overrides'
            and (jsonb_typeof(e.value) <> 'string'
                 or e.value #>> '{}' not in ('reduce_quotas', 'cover_excess', 'keep')))
        or (e.key = 'vault_overrides' and jsonb_typeof(e.value) <> 'object')
    )
    and not exists (
      select 1 from jsonb_each(coalesce(p_rules->'vault_overrides', '{}'::jsonb)) v
      where jsonb_typeof(v.value) <> 'string'
        or v.value #>> '{}' not in ('reduce_quotas', 'cover_excess', 'keep')
    );
$$;

alter table public.houses
  add column if not exists opening_inflow_rules jsonb not null default '{}'::jsonb
    check (public.opening_inflow_rules_valid(opening_inflow_rules));

create or replace function public.update_house_settings(p_house_id uuid, p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.houses%rowtype;
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  if (p_settings ? 'opening_balance_rule' or p_settings ? 'opening_inflow_rules')
      and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam como a sobra entra no rateio.';
  end if;
  if p_settings ? 'opening_inflow_rules'
      and not public.opening_inflow_rules_valid(p_settings->'opening_inflow_rules') then
    raise exception 'Regra das entradas no Caixa inválida.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides)
  where id = p_house_id
  returning * into v_row;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'opening_inflow_rules', v_row.opening_inflow_rules,
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;
