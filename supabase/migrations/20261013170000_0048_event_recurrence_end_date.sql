-- ==============================================================================
-- 0048: Data final da repetição de um evento
-- Descrição:
--   O evento recorrente passa a aceitar "repetir até": a série vai até essa
--   data (no máximo 200 ocorrências). A data fica gravada em cada ocorrência da
--   série, para a tela mostrar até quando ela vai. Sem data final continua
--   valendo o horizonte padrão de cada frequência.
-- ==============================================================================

alter table public.events
  add column if not exists recurrence_end_date date;

-- Igual à da 0045, gravando também a data final e limitando o tamanho da série.
create or replace function public.create_calendar_event(p_plan jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_event jsonb := p_plan->'event';
  v_house uuid := (p_plan->'event'->>'house_id')::uuid;
  v_frequency text := coalesce(p_plan->'event'->>'recurrence_frequency', 'none');
  v_first uuid;
  v_ids uuid[];
  v_id uuid;
  v_occurrence jsonb;
  v_end_date date := case
    when coalesce(p_plan->'event'->>'recurrence_frequency', 'none') = 'none' then null
    else (p_plan->'event'->>'recurrence_end_date')::date
  end;
begin
  if jsonb_array_length(coalesce(p_plan->'occurrences', '[]'::jsonb)) > 200 then
    raise exception 'Uma série pode ter no máximo 200 ocorrências. Escolha uma data final mais próxima.';
  end if;

  insert into public.events (
    id, house_id, title, description, location, start_time, end_time,
    is_all_day, visibility, created_by, recurrence_frequency, recurrence_end_date
  ) values (
    coalesce((v_event->>'id')::uuid, gen_random_uuid()),
    v_house,
    v_event->>'title',
    v_event->>'description',
    v_event->>'location',
    (v_event->>'start_time')::timestamptz,
    (v_event->>'end_time')::timestamptz,
    coalesce((v_event->>'is_all_day')::boolean, false),
    coalesce(v_event->>'visibility', 'house'),
    auth.uid(),
    v_frequency,
    v_end_date
  )
  returning id into v_first;
  v_ids := array[v_first];

  if v_frequency <> 'none' then
    update public.events set recurring_series_id = v_first where id = v_first;

    for v_occurrence in
      select * from jsonb_array_elements(coalesce(p_plan->'occurrences', '[]'::jsonb))
    loop
      insert into public.events (
        house_id, title, description, location, start_time, end_time,
        is_all_day, visibility, created_by, recurrence_frequency, recurring_series_id,
        recurrence_end_date
      ) values (
        v_house,
        v_event->>'title',
        v_event->>'description',
        v_event->>'location',
        (v_occurrence->>'start_time')::timestamptz,
        (v_occurrence->>'end_time')::timestamptz,
        coalesce((v_event->>'is_all_day')::boolean, false),
        coalesce(v_event->>'visibility', 'house'),
        auth.uid(),
        v_frequency,
        v_first,
        v_end_date
      )
      returning id into v_id;
      v_ids := v_ids || v_id;
    end loop;
  end if;

  insert into public.event_participants (
    event_id, user_id, house_id, is_essential, rsvp_status, responded_at
  )
  select
    e.id,
    (p->>'user_id')::uuid,
    v_house,
    coalesce((p->>'is_essential')::boolean, false),
    coalesce(p->>'rsvp_status', 'pending'),
    (p->>'responded_at')::timestamptz
  from unnest(v_ids) as e(id)
  cross join jsonb_array_elements(coalesce(p_plan->'participants', '[]'::jsonb)) as p;

  return v_first;
end;
$$;

revoke execute on function public.create_calendar_event(jsonb) from public, anon;
grant execute on function public.create_calendar_event(jsonb) to authenticated;
