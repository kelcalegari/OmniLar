-- ==============================================================================
-- 0045: Criar evento da agenda em uma transação
-- Descrição:
--   Criar um evento gravava em chamadas separadas o evento, a marcação da
--   série, as ocorrências seguintes e os participantes. Uma falha no meio
--   deixava, por exemplo, uma série sem participantes ou só com a primeira
--   ocorrência. Agora é uma função só: ou grava tudo, ou nada.
--   Roda com as permissões de quem chama (security invoker): as regras de
--   acesso das tabelas continuam valendo como antes.
-- ==============================================================================

-- p_plan: {"event": {...}, "occurrences": [{"start_time","end_time"}],
--          "participants": [{"user_id","is_essential","rsvp_status","responded_at"}]}
-- Devolve o id do evento (da primeira ocorrência, quando é uma série).
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
begin
  insert into public.events (
    id, house_id, title, description, location, start_time, end_time,
    is_all_day, visibility, created_by, recurrence_frequency
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
    v_frequency
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
        is_all_day, visibility, created_by, recurrence_frequency, recurring_series_id
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
        v_first
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
