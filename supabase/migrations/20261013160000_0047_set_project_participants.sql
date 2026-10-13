-- ==============================================================================
-- 0047: Trocar os participantes de um projeto compartilhado
-- Descrição:
--   O app passa a permitir editar quem participa de um projeto (moradores e
--   convidados de fora) e o percentual de cada um. A lista antiga sai e a nova
--   entra na mesma transação.
--   Roda com as permissões de quem chama (security invoker): vale a regra de
--   acesso de project_participants (qualquer morador da casa do projeto).
-- ==============================================================================

create or replace function public.set_project_participants(p_project_id uuid, p_participants jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer;
begin
  if jsonb_typeof(p_participants) <> 'array' or jsonb_array_length(p_participants) = 0 then
    raise exception 'O projeto precisa de ao menos um participante.';
  end if;

  if not exists (select 1 from public.shared_projects where id = p_project_id) then
    raise exception 'Projeto não encontrado.';
  end if;

  delete from public.project_participants where project_id = p_project_id;

  insert into public.project_participants (project_id, user_id, external_name, default_split_percent)
  select
    p_project_id,
    (item->>'user_id')::uuid,
    nullif(trim(item->>'external_name'), ''),
    (item->>'default_split_percent')::numeric
  from jsonb_array_elements(p_participants) as item;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.set_project_participants(uuid, jsonb) from public, anon;
grant execute on function public.set_project_participants(uuid, jsonb) to authenticated;
