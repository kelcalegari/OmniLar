-- ==============================================================================
-- Migration: 0111_delete_shared_project_rpc.sql
-- Module: Projetos Compartilhados (Viagens, Compras, Reformas)
-- Description: RPC segura delete_shared_project para exclusão lógica (soft-delete)
--              de projetos compartilhados sem violar RLS PostgREST (erro 42501).
-- ==============================================================================

create or replace function public.delete_shared_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.shared_projects%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Usuário precisa estar autenticado.';
  end if;

  select * into v_project
  from public.shared_projects
  where id = p_project_id and deleted_at is null;

  if not found then
    return;
  end if;

  if not public.is_house_member(v_project.house_id) then
    raise exception 'Apenas membros da casa podem excluir um projeto.';
  end if;

  if v_project.created_by <> auth.uid() and not public.is_house_admin(v_project.house_id) then
    raise exception 'Apenas o criador do projeto ou um administrador podem excluí-lo.';
  end if;

  -- Realiza soft-delete atualizando deleted_at
  update public.shared_projects
  set deleted_at = now()
  where id = p_project_id;
end;
$$;

revoke execute on function public.delete_shared_project(uuid) from public, anon;
grant execute on function public.delete_shared_project(uuid) to authenticated, service_role;
