-- ==============================================================================
-- 0101: Nome do Caixa, unidades de compra, padrões das listas e CSV da casa
-- Descrição:
--   O que era fixo no código ou guardado só no aparelho passa a ser da casa.
--   Sem escolha vale o comportamento de sempre, então nada muda até alguém
--   ajustar nos Ajustes.
--
--   1. houses.csv_mappings (jsonb): como ler o CSV de cada cartão ou conta,
--      por id da forma de pagamento: { "<payment_method_id>": { delimiter,
--      hasHeader, roles[] } }. Antes cada aparelho guardava o seu; o app usa o
--      do aparelho como reserva e envia ao salvar. Quem grava: qualquer
--      morador, por save_csv_mapping (quem importa o extrato).
--   2. houses.cash_label (text ou nulo): nome do Caixa mostrado no calendário
--      de pagamentos e nos próximos ciclos. Nulo vale o nome de sempre
--      ("Caixa da Casa"). Quem muda: administradores, por update_house_settings.
--   3. houses.shopping_units (jsonb): unidades de compra da casa, em ordem; a
--      primeira é a que um item novo usa. Padrão: un, kg, g, l, ml, pct, cx, dz.
--      De 1 a 20 unidades, de 1 a 8 caracteres, sem repetir. Quem muda:
--      administradores, por update_house_settings.
--   4. shopping_lists.default_category_id e default_split_mode: categoria e
--      divisão da despesa criada ao fechar a compra daquela lista. Nulo vale o
--      de sempre (categoria de mercado; divisão da categoria ou da casa).
--      default_split_mode: 'category', 'equal' (partes iguais) ou 'payer' (só
--      quem paga); categoria com dono segue 100% do dono em qualquer modo.
--      Quem muda: quem edita listas (qualquer morador, policy da 0003). A
--      categoria precisa ser da mesma casa da lista.
--   5. update_house_settings parte da versão da 0100 e aceita cash_label e
--      shopping_units, mantendo todos os campos anteriores.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Mapeamento de colunas do CSV, da casa
-- ------------------------------------------------------------------------------
create or replace function public.csv_mappings_valid(p_mappings jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_mappings) = 'object'
    and not exists (
      select 1 from jsonb_each(p_mappings) e
      where e.key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or jsonb_typeof(e.value) <> 'object'
        or jsonb_typeof(e.value->'delimiter') is distinct from 'string'
        or jsonb_typeof(e.value->'roles') is distinct from 'array'
        or jsonb_array_length(e.value->'roles') > 100
    );
$$;

alter table public.houses
  add column if not exists csv_mappings jsonb not null default '{}'::jsonb
    check (public.csv_mappings_valid(csv_mappings));

comment on column public.houses.csv_mappings is
  'Como ler o CSV de cada cartão ou conta, por id da forma de pagamento; compartilhado pela casa (0101).';

create or replace function public.save_csv_mapping(
  p_house_id uuid,
  p_payment_method_id uuid,
  p_mapping jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mappings jsonb;
begin
  if auth.uid() is null or not public.is_house_member(p_house_id) then
    raise exception 'Você não faz parte desta casa.';
  end if;
  if not exists (
    select 1 from public.payment_methods pm
    where pm.id = p_payment_method_id and pm.house_id = p_house_id
  ) then
    raise exception 'Cartão ou conta não encontrado nesta casa.';
  end if;

  -- Nulo remove o mapeamento daquela forma de pagamento
  update public.houses set
    csv_mappings = case
      when p_mapping is null or jsonb_typeof(p_mapping) = 'null'
        then csv_mappings - p_payment_method_id::text
      else csv_mappings || jsonb_build_object(p_payment_method_id::text, p_mapping)
    end
  where id = p_house_id
  returning csv_mappings into v_mappings;

  return v_mappings;
end;
$$;

revoke execute on function public.save_csv_mapping(uuid, uuid, jsonb) from public, anon;
grant execute on function public.save_csv_mapping(uuid, uuid, jsonb) to authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 2. Nome do Caixa
-- ------------------------------------------------------------------------------
create or replace function public.cash_label_valid(p_label jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_label is null
    or jsonb_typeof(p_label) = 'null'
    or (jsonb_typeof(p_label) = 'string'
        and char_length(btrim(p_label #>> '{}')) <= 30);
$$;

alter table public.houses
  add column if not exists cash_label text
    check (cash_label is null or char_length(btrim(cash_label)) between 1 and 30);

comment on column public.houses.cash_label is
  'Nome do Caixa nas telas; nulo vale "Caixa da Casa" (0101).';

-- ------------------------------------------------------------------------------
-- 3. Unidades de compra
-- ------------------------------------------------------------------------------
create or replace function public.shopping_units_valid(p_units jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_units) = 'array'
    and jsonb_array_length(p_units) between 1 and 20
    and not exists (
      select 1 from jsonb_array_elements(p_units) e
      where jsonb_typeof(e) <> 'string'
        or char_length(e #>> '{}') not between 1 and 8
        or (e #>> '{}') <> btrim(e #>> '{}')
    )
    and (select count(distinct lower(e #>> '{}')) from jsonb_array_elements(p_units) e)
      = jsonb_array_length(p_units);
$$;

alter table public.houses
  add column if not exists shopping_units jsonb not null
    default '["un","kg","g","l","ml","pct","cx","dz"]'::jsonb
    check (public.shopping_units_valid(shopping_units));

comment on column public.houses.shopping_units is
  'Unidades de compra da casa; a primeira é a de um item novo (0101).';

-- ------------------------------------------------------------------------------
-- 4. Categoria e divisão padrão de cada lista de compras
-- ------------------------------------------------------------------------------
alter table public.shopping_lists
  add column if not exists default_category_id uuid references public.categories(id) on delete set null,
  add column if not exists default_split_mode text
    check (default_split_mode is null or default_split_mode in ('category', 'equal', 'payer'));

comment on column public.shopping_lists.default_category_id is
  'Categoria da despesa criada ao fechar a compra desta lista; nulo vale a de mercado (0101).';
comment on column public.shopping_lists.default_split_mode is
  'Divisão da despesa criada ao fechar a compra: category (padrão), equal ou payer (0101).';

create or replace function public.shopping_lists_check_default_category()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.default_category_id is not null
     and (tg_op = 'INSERT' or new.default_category_id is distinct from old.default_category_id)
     and not exists (
       select 1 from public.categories c
       where c.id = new.default_category_id and c.house_id = new.house_id
     ) then
    raise exception 'A categoria padrão precisa ser desta casa.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_shopping_lists_check_default_category
  before insert or update of default_category_id on public.shopping_lists
  for each row execute function public.shopping_lists_check_default_category();

-- ------------------------------------------------------------------------------
-- 5. update_house_settings: aceita cash_label e shopping_units (resto como na 0100)
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

  if p_settings ? 'cash_label' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam o nome do Caixa.';
  end if;
  if p_settings ? 'cash_label' and not public.cash_label_valid(p_settings->'cash_label') then
    raise exception 'Nome do Caixa inválido.';
  end if;

  if p_settings ? 'shopping_units' and not public.is_house_admin(p_house_id) then
    raise exception 'Só administradores mudam as unidades de compra.';
  end if;
  if p_settings ? 'shopping_units' and not public.shopping_units_valid(p_settings->'shopping_units') then
    raise exception 'Unidades de compra inválidas.';
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
    cash_label = case when p_settings ? 'cash_label'
      then nullif(btrim(p_settings->>'cash_label'), '') else cash_label end,
    shopping_units = coalesce(p_settings->'shopping_units', shopping_units),
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
    'cash_label', v_row.cash_label,
    'shopping_units', v_row.shopping_units,
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
