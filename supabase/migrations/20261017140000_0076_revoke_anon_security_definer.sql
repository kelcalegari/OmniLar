-- ==============================================================================
-- 0076: Funções security definer fora do alcance de quem não está logado
-- Descrição:
--   O relatório de alertas do Supabase apontou 19 funções security definer que
--   o papel anon (sem login) podia chamar pela API.
--   1) As 12 funções de gatilho: ninguém as chama direto (o Postgres só confere
--      a permissão ao criar o gatilho), então ficam sem execute para public,
--      anon e authenticated. Os gatilhos continuam disparando.
--   2) As 7 funções usadas pelo app e pelas regras de acesso: saem de public e
--      anon e continuam com authenticated e service_role.
-- ==============================================================================

revoke execute on function public.apply_category_owner_to_open_expenses() from public, anon, authenticated;
revoke execute on function public.fn_audit_record() from public, anon, authenticated;
revoke execute on function public.guard_house_creation_account() from public, anon, authenticated;
revoke execute on function public.guard_house_member_account() from public, anon, authenticated;
revoke execute on function public.guard_project_plan_limit() from public, anon, authenticated;
revoke execute on function public.guard_savings_vault_delete() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.notify_vault_goal_reached() from public, anon, authenticated;
revoke execute on function public.prevent_ledger_mutation() from public, anon, authenticated;
revoke execute on function public.route_house_loan_payment_to_vault() from public, anon, authenticated;
revoke execute on function public.set_event_participant_house_id() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

revoke execute on function public.create_house_with_owner(text, integer, text) from public, anon;
grant execute on function public.create_house_with_owner(text, integer, text) to authenticated, service_role;
revoke execute on function public.delete_house_expense(uuid, text) from public, anon;
grant execute on function public.delete_house_expense(uuid, text) to authenticated, service_role;
revoke execute on function public.is_event_creator(uuid, uuid) from public, anon;
grant execute on function public.is_event_creator(uuid, uuid) to authenticated, service_role;
revoke execute on function public.is_event_house_member(uuid, uuid) from public, anon;
grant execute on function public.is_event_house_member(uuid, uuid) to authenticated, service_role;
revoke execute on function public.is_event_participant(uuid, uuid) from public, anon;
grant execute on function public.is_event_participant(uuid, uuid) to authenticated, service_role;
revoke execute on function public.is_house_admin(uuid) from public, anon;
grant execute on function public.is_house_admin(uuid) to authenticated, service_role;
revoke execute on function public.is_house_member(uuid) from public, anon;
grant execute on function public.is_house_member(uuid) to authenticated, service_role;
