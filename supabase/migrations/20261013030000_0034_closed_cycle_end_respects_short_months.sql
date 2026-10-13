-- ==============================================================================
-- 0034: Fim do ciclo fechado em casas com dia de início 29, 30 ou 31
-- Descrição:
--   Quando o mês não tem o dia de início configurado, o ciclo começa no último
--   dia do mês (ex.: dia 31 → 28/02) e vai até a véspera do início seguinte
--   (30/03). "Início + 1 mês" terminava em 27/03 e deixava os últimos dias do
--   ciclo fechado destravados.
--   O dia configurado na casa só é consultado quando o ciclo começou no último
--   dia de um mês; nos demais casos o próprio dia do início basta.
-- ==============================================================================

-- Primeiro dia do ciclo seguinte ao que começa em p_cycle_start
create or replace function public.next_cycle_start(p_cycle_start date, p_cycle_start_day integer)
returns date
language sql
immutable
set search_path = public
as $$
  select case
    when p_cycle_start = (date_trunc('month', p_cycle_start) + interval '1 month - 1 day')::date
    then least(
      (date_trunc('month', p_cycle_start) + interval '1 month')::date
        + (greatest(coalesce(p_cycle_start_day, 1), extract(day from p_cycle_start)::integer) - 1),
      (date_trunc('month', p_cycle_start) + interval '2 months - 1 day')::date
    )
    else (p_cycle_start + interval '1 month')::date
  end;
$$;

revoke execute on function public.next_cycle_start(date, integer) from public, anon, authenticated;

-- A data cai em um ciclo com fechamento confirmado?
create or replace function public.is_date_in_closed_cycle(p_house_id uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.settlements s
    join public.houses h on h.id = s.house_id
    where s.house_id = p_house_id
      and s.status in ('confirmed', 'completed')
      and p_date >= s.cycle_start_date
      and p_date < public.next_cycle_start(s.cycle_start_date, h.cycle_start_day)
  );
$$;
