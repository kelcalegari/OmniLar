-- ==============================================================================
-- 0073: Editar uma série de eventos de uma vez
-- Descrição:
--   Editar "esta e as próximas" ou "todas" eram várias gravações seguidas do
--   app: uma queda no meio deixava a série pela metade. E as ocorrências
--   criadas ao estender o "repetir até" ficavam no nome de quem editou; como só
--   o criador ou um administrador edita um evento, quem criou a série deixava de
--   conseguir editar essas ocorrências, sem aviso.
--   Agora o app calcula o plano (horário de cada ocorrência, o que sai e o que
--   entra) e esta função grava tudo na mesma transação. As ocorrências novas
--   ficam no nome de quem criou a série. Pode editar quem criou a série ou um
--   administrador da casa (a mesma regra de events_update_creator_or_admin).
--
--   p_plan:
--     event_id            ocorrência que foi aberta para editar
--     fields              title, description, location, is_all_day, visibility
--     updates             [{id, start_time, end_time}] ocorrências que ficam
--     remove_ids          [id] ocorrências que passam da nova data final
--     add                 [{start_time, end_time}] ocorrências que faltam
--     end_date_changed    true quando o "repetir até" mudou
--     recurrence_end_date nova data final (nula = sem data final)
--     from_start          com "esta e as próximas": a data só muda daqui em diante
--     participants        [{user_id, is_essential, rsvp_status, responded_at}]
-- ==============================================================================

create or replace function public.update_event_series(p_plan jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid := (p_plan->>'event_id')::uuid;
  v_fields jsonb := coalesce(p_plan->'fields', '{}'::jsonb);
  v_house uuid;
  v_series uuid;
  v_frequency text;
  v_creator uuid;
  v_end date := (p_plan->>'recurrence_end_date')::date;
  v_from timestamptz := (p_plan->>'from_start')::timestamptz;
  v_ids uuid[] := '{}';
  v_id uuid;
  v_item jsonb;
  v_count integer;
begin
  select house_id, recurring_series_id into v_house, v_series
    from public.events where id = v_event_id;
  if v_series is null then
    raise exception 'Este evento não faz parte de uma série.';
  end if;

  -- Dono da série: quem criou a primeira ocorrência (se ela foi excluída, a mais antiga)
  select created_by, recurrence_frequency into v_creator, v_frequency
    from public.events
   where recurring_series_id = v_series
   order by (id = v_series) desc, start_time
   limit 1;

  if not public.is_house_member(v_house)
     or not (v_creator = auth.uid() or public.is_house_admin(v_house)) then
    raise exception 'Só quem criou a série ou um administrador da casa pode editá-la.';
  end if;

  -- Toda ocorrência citada precisa ser desta série
  select count(*) into v_count
    from (
      select (u->>'id')::uuid as id from jsonb_array_elements(coalesce(p_plan->'updates', '[]'::jsonb)) u
      union
      select r::uuid from jsonb_array_elements_text(coalesce(p_plan->'remove_ids', '[]'::jsonb)) r
    ) cited
   where not exists (
     select 1 from public.events e where e.id = cited.id and e.recurring_series_id = v_series
   );
  if v_count > 0 then
    raise exception 'A edição cita ocorrências que não são desta série.';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'updates', '[]'::jsonb)) loop
    update public.events set
      title = coalesce(v_fields->>'title', title),
      description = v_fields->>'description',
      location = v_fields->>'location',
      is_all_day = coalesce((v_fields->>'is_all_day')::boolean, is_all_day),
      visibility = coalesce(v_fields->>'visibility', visibility),
      start_time = (v_item->>'start_time')::timestamptz,
      end_time = (v_item->>'end_time')::timestamptz
    where id = (v_item->>'id')::uuid;
    v_ids := v_ids || (v_item->>'id')::uuid;
  end loop;

  delete from public.events
   where recurring_series_id = v_series
     and id in (select r::uuid from jsonb_array_elements_text(coalesce(p_plan->'remove_ids', '[]'::jsonb)) r);

  select count(*) into v_count from public.events where recurring_series_id = v_series;
  if v_count + jsonb_array_length(coalesce(p_plan->'add', '[]'::jsonb)) > 200 then
    raise exception 'Uma série pode ter no máximo 200 ocorrências. Escolha uma data final mais próxima.';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_plan->'add', '[]'::jsonb)) loop
    insert into public.events (
      house_id, title, description, location, start_time, end_time, is_all_day,
      visibility, created_by, recurrence_frequency, recurring_series_id, recurrence_end_date
    ) values (
      v_house,
      v_fields->>'title',
      v_fields->>'description',
      v_fields->>'location',
      (v_item->>'start_time')::timestamptz,
      (v_item->>'end_time')::timestamptz,
      coalesce((v_fields->>'is_all_day')::boolean, false),
      coalesce(v_fields->>'visibility', 'house'),
      v_creator,
      v_frequency,
      v_series,
      v_end
    )
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;

  if coalesce((p_plan->>'end_date_changed')::boolean, false) then
    update public.events set recurrence_end_date = v_end
     where recurring_series_id = v_series
       and (v_from is null or start_time >= v_from);
  end if;

  -- Participantes de cada ocorrência editada ou criada ficam iguais à lista
  delete from public.event_participants ep
   where ep.event_id = any(v_ids)
     and ep.user_id not in (
       select (p->>'user_id')::uuid from jsonb_array_elements(coalesce(p_plan->'participants', '[]'::jsonb)) p
     );

  insert into public.event_participants (event_id, user_id, house_id, is_essential, rsvp_status, responded_at)
  select e.id,
         (p->>'user_id')::uuid,
         v_house,
         coalesce((p->>'is_essential')::boolean, false),
         coalesce(p->>'rsvp_status', 'pending'),
         (p->>'responded_at')::timestamptz
    from unnest(v_ids) as e(id)
   cross join jsonb_array_elements(coalesce(p_plan->'participants', '[]'::jsonb)) as p
  on conflict (event_id, user_id) do update set
    is_essential = excluded.is_essential,
    rsvp_status = excluded.rsvp_status,
    responded_at = excluded.responded_at;

  return coalesce(array_length(v_ids, 1), 0);
end;
$$;

revoke execute on function public.update_event_series(jsonb) from public, anon;
grant execute on function public.update_event_series(jsonb) to authenticated;
