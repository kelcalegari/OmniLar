-- ==============================================================================
-- 0100: Parâmetros dos cartões e da importação de extrato
-- Descrição:
--   O que antes era fixo no código da importação e no pagamento de fatura passa
--   a ser escolha. Sem escolha vale o comportamento de sempre, então nada muda
--   até alguém ajustar nos Ajustes.
--
--   1. payment_methods.usual_invoice_payer (uuid de morador ou nulo): quem costuma
--      pagar a fatura do cartão. É só uma sugestão: o pagamento de fatura
--      (pay_card_invoice, 0054/0055/0058/0090) abre com os meios dele primeiro e
--      a importação abre com ele como pagador, mas a escolha manual sempre vence.
--      Precisa ser morador atual da mesma casa. Quem edita: quem hoje
--      edita formas de pagamento (qualquer morador, policy da 0017).
--   2. houses.import_matching (jsonb): janelas do casamento de linhas do extrato
--      com despesas já lançadas. Chave ausente vale o padrão:
--        date_window_days (3): dias de diferença aceitos entre a linha e a despesa;
--        other_method_window_days (2): o mesmo, para despesa em outra forma de
--          pagamento (precisa confirmar), nunca maior que date_window_days;
--        amount_differs_days (1): dias aceitos quando o valor difere (gorjeta,
--          taxa), nunca maior que date_window_days;
--        amount_drift_percent (25): diferença de valor aceita nesse caso, de 0 a 100;
--        min_similarity_percent (50): semelhança mínima do nome nesse caso, de 0 a 100;
--        invoice_window_days (45): distância máxima entre um pagamento de fatura
--          no extrato da conta e o vencimento da fatura, de 1 a 120.
--      Quem muda: administradores, por update_house_settings.
--   3. houses.import_defaults (jsonb): destino padrão das linhas novas importadas.
--      Chave ausente vale o comportamento de sempre:
--        category_id: categoria das linhas sem categoria sugerida (padrão: a
--          primeira da casa);
--        split_mode: 'category' (divisão da categoria ou da casa, padrão), 'equal'
--          (partes iguais) ou 'payer' (só quem paga). Categoria com dono segue
--          100% do dono em qualquer modo;
--        payment_method_id: cartão ou conta que a tela de importação abre
--          selecionado.
--      Um id que não existe mais é ignorado pelo app. Quem muda: administradores.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Quem costuma pagar a fatura do cartão
-- ------------------------------------------------------------------------------
alter table public.payment_methods
  add column if not exists usual_invoice_payer uuid references auth.users(id) on delete set null;

comment on column public.payment_methods.usual_invoice_payer is
  'Morador que costuma pagar a fatura deste cartão; só sugestão, a escolha manual vence (0100).';

create or replace function public.payment_methods_check_usual_payer()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.usual_invoice_payer is not null
     and (tg_op = 'INSERT' or new.usual_invoice_payer is distinct from old.usual_invoice_payer)
     and not exists (
       select 1 from public.house_members hm
       where hm.house_id = new.house_id
         and hm.user_id = new.usual_invoice_payer
         and hm.left_at is null
     ) then
    raise exception 'Quem costuma pagar a fatura precisa ser morador desta casa.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_payment_methods_check_usual_payer
  before insert or update of usual_invoice_payer on public.payment_methods
  for each row execute function public.payment_methods_check_usual_payer();

-- ------------------------------------------------------------------------------
-- 2. Janelas do casamento da importação
-- ------------------------------------------------------------------------------
create or replace function public.import_matching_valid(p_params jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_params) = 'object'
    and not exists (
      select 1 from jsonb_each(p_params) e
      where e.key not in (
          'date_window_days', 'other_method_window_days', 'amount_differs_days',
          'amount_drift_percent', 'min_similarity_percent', 'invoice_window_days')
        or jsonb_typeof(e.value) <> 'number'
        or (e.value #>> '{}') !~ '^[0-9]+(\.0+)?$'
        or (e.key in ('date_window_days', 'other_method_window_days', 'amount_differs_days')
            and (e.value #>> '{}')::numeric > 10)
        or (e.key in ('amount_drift_percent', 'min_similarity_percent')
            and (e.value #>> '{}')::numeric > 100)
        or (e.key = 'invoice_window_days' and (e.value #>> '{}')::numeric not between 1 and 120)
    )
    and coalesce((p_params->>'other_method_window_days')::numeric, 2)
      <= coalesce((p_params->>'date_window_days')::numeric, 3)
    and coalesce((p_params->>'amount_differs_days')::numeric, 1)
      <= coalesce((p_params->>'date_window_days')::numeric, 3);
$$;

alter table public.houses
  add column if not exists import_matching jsonb not null default '{}'::jsonb
    check (public.import_matching_valid(import_matching));

comment on column public.houses.import_matching is
  'Janelas de dias e valor do casamento de linhas do extrato com despesas; chave ausente vale o padrão (0100).';

-- ------------------------------------------------------------------------------
-- 3. Destino padrão das linhas novas importadas
-- ------------------------------------------------------------------------------
create or replace function public.import_defaults_valid(p_defaults jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_defaults) = 'object'
    and not exists (
      select 1 from jsonb_each(p_defaults) e
      where e.key not in ('category_id', 'split_mode', 'payment_method_id')
        or jsonb_typeof(e.value) <> 'string'
        or (e.key = 'split_mode' and e.value #>> '{}' not in ('category', 'equal', 'payer'))
        or (e.key in ('category_id', 'payment_method_id')
            and e.value #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    );
$$;

alter table public.houses
  add column if not exists import_defaults jsonb not null default '{}'::jsonb
    check (public.import_defaults_valid(import_defaults));

comment on column public.houses.import_defaults is
  'Categoria, divisão e cartão/conta padrão da importação de extrato; chave ausente vale o comportamento de sempre (0100).';

-- ------------------------------------------------------------------------------
-- 4. update_house_settings: aceita import_matching e import_defaults (resto como na 0099)
-- ------------------------------------------------------------------------------
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
  if p_settings ? 'closing_defaults' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os padrões do fechamento.';
  end if;
  if p_settings ? 'closing_defaults'
      and not public.closing_defaults_valid(p_settings->'closing_defaults') then
    raise exception 'Padrões do fechamento inválidos.';
  end if;
  if p_settings ? 'new_member_split_policy' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam a divisão para quem entra na casa.';
  end if;
  if p_settings ? 'new_member_split_policy'
      and coalesce(p_settings->>'new_member_split_policy', '') not in ('equal', 'keep_current', 'ask') then
    raise exception 'Política de divisão para novo morador inválida.';
  end if;

  if p_settings ? 'folego_params' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os parâmetros do Fôlego.';
  end if;
  if p_settings ? 'folego_params' and not public.folego_params_valid(p_settings->'folego_params') then
    raise exception 'Parâmetros do Fôlego inválidos.';
  end if;

  if p_settings ? 'budget_alert_stages' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam os estágios do alerta de orçamento.';
  end if;
  if p_settings ? 'budget_alert_stages'
      and not public.budget_alert_stages_valid(p_settings->'budget_alert_stages') then
    raise exception 'Estágios do alerta de orçamento inválidos.';
  end if;

  if p_settings ? 'import_matching' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam as janelas de casamento da importação.';
  end if;
  if p_settings ? 'import_matching' and not public.import_matching_valid(p_settings->'import_matching') then
    raise exception 'Janelas de casamento da importação inválidas.';
  end if;

  if p_settings ? 'import_defaults' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam o destino padrão da importação.';
  end if;
  if p_settings ? 'import_defaults' and not public.import_defaults_valid(p_settings->'import_defaults') then
    raise exception 'Destino padrão da importação inválido.';
  end if;

  update public.houses set
    opening_balance_rule = case when p_settings ? 'opening_balance_rule'
      then nullif(p_settings->>'opening_balance_rule', '') else opening_balance_rule end,
    opening_inflow_rules = coalesce(p_settings->'opening_inflow_rules', opening_inflow_rules),
    closing_defaults = coalesce(p_settings->'closing_defaults', closing_defaults),
    new_member_split_policy = coalesce(p_settings->>'new_member_split_policy', new_member_split_policy),
    folego_params = coalesce(p_settings->'folego_params', folego_params),
    budget_alert_stages = coalesce(p_settings->'budget_alert_stages', budget_alert_stages),
    import_matching = coalesce(p_settings->'import_matching', import_matching),
    import_defaults = coalesce(p_settings->'import_defaults', import_defaults),
    planner_history_cycles = coalesce((p_settings->>'planner_history_cycles')::smallint, planner_history_cycles),
    planner_mode = coalesce(p_settings->>'planner_mode', planner_mode),
    planner_adjust_percent = coalesce((p_settings->>'planner_adjust_percent')::smallint, planner_adjust_percent),
    planner_category_overrides = coalesce(p_settings->'planner_category_overrides', planner_category_overrides)
  where id = p_house_id
  returning * into v_row;

  return jsonb_build_object(
    'opening_balance_rule', v_row.opening_balance_rule,
    'opening_inflow_rules', v_row.opening_inflow_rules,
    'closing_defaults', v_row.closing_defaults,
    'new_member_split_policy', v_row.new_member_split_policy,
    'folego_params', v_row.folego_params,
    'budget_alert_stages', v_row.budget_alert_stages,
    'import_matching', v_row.import_matching,
    'import_defaults', v_row.import_defaults,
    'planner_history_cycles', v_row.planner_history_cycles,
    'planner_mode', v_row.planner_mode,
    'planner_adjust_percent', v_row.planner_adjust_percent,
    'planner_category_overrides', v_row.planner_category_overrides
  );
end;
$$;

revoke execute on function public.update_house_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_house_settings(uuid, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
