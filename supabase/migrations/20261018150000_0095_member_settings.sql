-- ==============================================================================
-- 0095: Ajustes de cada morador na casa
-- Descrição:
--   1. member_settings: uma linha por morador e casa, com um jsonb genérico
--      (próximas funções guardam aqui, por exemplo, os avisos de cada um).
--   2. Por enquanto, os padrões de lançamento de despesa:
--      - launch_payer: quem paga a despesa nova (me = eu, house = Caixa da casa);
--      - launch_payment_method_id: forma de pagamento fixa (sem ela, a última usada);
--      - launch_category_id: categoria fixa (sem ela, a mais usada).
--      A última forma e a categoria mais usada saem das despesas que o app já
--      carrega (ciclo aberto e os da média), sem gravar nada a cada lançamento.
--      Chaves que esta migration não conhece passam sem conferência.
--      Forma ou categoria apagada depois é ignorada pelo app (não há chave
--      estrangeira dentro do jsonb).
--   3. RLS: cada um lê e grava só a própria linha, e só nas casas de que faz parte.
-- ==============================================================================

create or replace function public.member_settings_valid(p_settings jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_settings) = 'object'
    and not exists (
      select 1 from jsonb_each(p_settings) e
      where (e.key = 'launch_payer'
             and (jsonb_typeof(e.value) <> 'string' or e.value #>> '{}' not in ('me', 'house')))
        or (e.key in ('launch_payment_method_id', 'launch_category_id')
            and (jsonb_typeof(e.value) <> 'string'
                 or e.value #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
    );
$$;

create table if not exists public.member_settings (
  house_id uuid not null references public.houses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb
    check (public.member_settings_valid(settings)),
  updated_at timestamptz not null default now(),
  primary key (house_id, user_id)
);

drop trigger if exists trg_member_settings_updated_at on public.member_settings;
create trigger trg_member_settings_updated_at
  before update on public.member_settings
  for each row execute function public.touch_updated_at();

alter table public.member_settings enable row level security;

-- Só a própria linha, e só em casa de que o morador faz parte
drop policy if exists "member_settings_select_own" on public.member_settings;
create policy "member_settings_select_own" on public.member_settings
  for select using (user_id = auth.uid() and public.is_house_member(house_id));

drop policy if exists "member_settings_insert_own" on public.member_settings;
create policy "member_settings_insert_own" on public.member_settings
  for insert with check (user_id = auth.uid() and public.is_house_member(house_id));

drop policy if exists "member_settings_update_own" on public.member_settings;
create policy "member_settings_update_own" on public.member_settings
  for update using (user_id = auth.uid() and public.is_house_member(house_id))
  with check (user_id = auth.uid() and public.is_house_member(house_id));

drop policy if exists "member_settings_delete_own" on public.member_settings;
create policy "member_settings_delete_own" on public.member_settings
  for delete using (user_id = auth.uid() and public.is_house_member(house_id));

grant select, insert, update, delete on public.member_settings to authenticated;
