-- ==============================================================================
-- 0077: Regras de acesso leem o usuário uma vez por consulta
-- Descrição:
--   O relatório de alertas do Supabase apontou 54 regras de acesso que chamam
--   auth.uid() direto, o que o Postgres reavalia a cada linha. Com
--   (select auth.uid()) o valor é calculado uma vez por consulta. A regra em si
--   não muda: o texto abaixo foi gerado de pg_policies trocando só auth.uid()
--   (e o auth.role() de houses_insert_authenticated). Só as partes que têm
--   auth.uid() são reescritas; a outra parte da regra fica como está.
-- ==============================================================================

alter policy account_status_select_own on public.account_status
  using ((user_id = (select auth.uid())));

alter policy ai_usage_insert_house_member on public.ai_usage
  with check ((is_house_member(house_id) AND (member_id = (select auth.uid()))));

alter policy assistant_actions_owner_only on public.assistant_actions
  using ((EXISTS ( SELECT 1
   FROM assistant_conversations c
  WHERE ((c.id = assistant_actions.conversation_id) AND (c.member_id = (select auth.uid()))))));

alter policy assistant_conversations_owner_only on public.assistant_conversations
  using ((member_id = (select auth.uid())));

alter policy assistant_messages_owner_only on public.assistant_messages
  using ((EXISTS ( SELECT 1
   FROM assistant_conversations c
  WHERE ((c.id = assistant_messages.conversation_id) AND (c.member_id = (select auth.uid()))))));

alter policy assistant_preferences_owner_only on public.assistant_preferences
  using ((member_id = (select auth.uid())));

alter policy attachments_insert_member on public.attachments
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy captures_insert_house_member on public.captures
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy categories_insert_member on public.categories
  with check ((is_house_member(house_id) OR (EXISTS ( SELECT 1
   FROM houses h
  WHERE ((h.id = categories.house_id) AND (h.created_by = (select auth.uid())))))));

alter policy categories_update_admin_or_owner on public.categories
  using ((is_house_admin(house_id) OR (created_by = (select auth.uid()))))
  with check ((is_house_admin(house_id) OR (created_by = (select auth.uid()))));

alter policy contributions_insert_member on public.contributions
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy device_tokens_own on public.device_tokens
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));

alter policy event_participants_delete_creator_or_self on public.event_participants
  using (((user_id = (select auth.uid())) OR is_event_creator(event_id, (select auth.uid()))));

alter policy event_participants_insert_member on public.event_participants
  with check (((user_id = (select auth.uid())) OR ((house_id IS NOT NULL) AND is_house_member(house_id))));

alter policy event_participants_select_member on public.event_participants
  using (((user_id = (select auth.uid())) OR ((house_id IS NOT NULL) AND is_house_member(house_id))));

alter policy event_participants_update_self_or_creator on public.event_participants
  using (((user_id = (select auth.uid())) OR is_event_creator(event_id, (select auth.uid()))))
  with check (((user_id = (select auth.uid())) OR is_event_creator(event_id, (select auth.uid()))));

alter policy events_delete_creator_or_admin on public.events
  using ((is_house_member(house_id) AND ((created_by = (select auth.uid())) OR is_house_admin(house_id))));

alter policy events_insert_member on public.events
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy events_select_visibility on public.events
  using ((is_house_member(house_id) AND ((visibility = 'house'::text) OR (created_by = (select auth.uid())) OR ((visibility = 'restricted'::text) AND is_event_participant(id, (select auth.uid()))))));

alter policy events_update_creator_or_admin on public.events
  using ((is_house_member(house_id) AND ((created_by = (select auth.uid())) OR is_house_admin(house_id))));

alter policy house_expenses_insert_member on public.house_expenses
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy house_invites_insert_admin on public.house_invites
  with check ((is_house_admin(house_id) AND (created_by = (select auth.uid()))));

alter policy house_members_delete_admin_or_self on public.house_members
  using ((is_house_admin(house_id) OR (user_id = (select auth.uid()))));

alter policy house_members_insert_owner_or_admin on public.house_members
  with check ((is_house_admin(house_id) OR ((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM houses h
  WHERE ((h.id = house_members.house_id) AND (h.created_by = (select auth.uid()))))))));

alter policy house_members_select_member on public.house_members
  using ((is_house_member(house_id) OR (user_id = (select auth.uid()))));

alter policy houses_insert_authenticated on public.houses
  with check ((((select auth.role()) = 'authenticated'::text) AND ((created_by = (select auth.uid())) OR (created_by IS NULL))));

alter policy houses_select_member on public.houses
  using ((is_house_member(id) OR (created_by = (select auth.uid()))));

alter policy import_batches_insert_house_member on public.import_batches
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy notification_preferences_own on public.notification_preferences
  using ((user_id = (select auth.uid())))
  with check (((user_id = (select auth.uid())) AND is_house_member(house_id)));

alter policy notification_settings_own on public.notification_settings
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));

alter policy notifications_select_own on public.notifications
  using ((user_id = (select auth.uid())));

alter policy notifications_update_own on public.notifications
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));

alter policy p2p_installments_delete_parties on public.p2p_installments
  using ((EXISTS ( SELECT 1
   FROM p2p_loans l
  WHERE ((l.id = p2p_installments.loan_id) AND is_house_member(l.house_id) AND ((l.lender_id = (select auth.uid())) OR (l.created_by = (select auth.uid())) OR is_house_admin(l.house_id))))));

alter policy p2p_loans_delete_parties on public.p2p_loans
  using ((is_house_member(house_id) AND (((lender_id = (select auth.uid())) AND (NOT COALESCE(lender_is_house, false))) OR is_house_admin(house_id)) AND (NOT (EXISTS ( SELECT 1
   FROM p2p_installments i
  WHERE ((i.loan_id = p2p_loans.id) AND (i.paid_cents > 0)))))));

alter policy p2p_loans_insert_member on public.p2p_loans
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy p2p_loans_update_parties on public.p2p_loans
  using (((lender_id = (select auth.uid())) OR (borrower_id = (select auth.uid())) OR (lender_is_house AND is_house_admin(house_id))))
  with check (((lender_id = (select auth.uid())) OR (borrower_id = (select auth.uid())) OR (lender_is_house AND is_house_admin(house_id))));

alter policy payment_methods_delete_owner_or_admin on public.payment_methods
  using ((is_house_admin(house_id) OR (owner_id = (select auth.uid())) OR (created_by = (select auth.uid()))));

alter policy payment_methods_insert_member on public.payment_methods
  with check ((is_house_member(house_id) OR (EXISTS ( SELECT 1
   FROM houses h
  WHERE ((h.id = payment_methods.house_id) AND (h.created_by = (select auth.uid())))))));

alter policy payment_methods_update_owner_or_admin on public.payment_methods
  using ((is_house_admin(house_id) OR (owner_id = (select auth.uid())) OR (created_by = (select auth.uid()))))
  with check ((is_house_admin(house_id) OR (owner_id = (select auth.uid())) OR (created_by = (select auth.uid()))));

alter policy payments_insert_member on public.payments
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy profiles_insert_own on public.profiles
  with check ((id = (select auth.uid())));

alter policy profiles_select_own_or_house_members on public.profiles
  using (((id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM (house_members hm1
     JOIN house_members hm2 ON ((hm1.house_id = hm2.house_id)))
  WHERE ((hm1.user_id = (select auth.uid())) AND (hm2.user_id = profiles.id) AND (hm1.left_at IS NULL) AND (hm2.left_at IS NULL))))));

alter policy profiles_update_own on public.profiles
  using ((id = (select auth.uid())))
  with check ((id = (select auth.uid())));

alter policy savings_transactions_insert_member on public.savings_transactions
  with check ((EXISTS ( SELECT 1
   FROM savings_vaults v
  WHERE ((v.id = savings_transactions.vault_id) AND is_house_member(v.house_id) AND (savings_transactions.member_id = (select auth.uid()))))));

alter policy shared_projects_delete_member on public.shared_projects
  using ((is_house_member(house_id) AND ((created_by = (select auth.uid())) OR is_house_admin(house_id))));

alter policy shared_projects_insert_member on public.shared_projects
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy shopping_items_insert_member on public.shopping_items
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy shopping_lists_insert_member on public.shopping_lists
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy shopping_trips_insert_member on public.shopping_trips
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy task_routines_insert_member on public.task_routines
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy tasks_delete_member on public.tasks
  using ((is_house_member(house_id) AND ((created_by = (select auth.uid())) OR is_house_admin(house_id))));

alter policy tasks_insert_member on public.tasks
  with check ((is_house_member(house_id) AND (created_by = (select auth.uid()))));

alter policy tasks_select_member on public.tasks
  using ((is_house_member(house_id) AND ((visibility = 'house'::text) OR (created_by = (select auth.uid())) OR (assigned_to = (select auth.uid())))));

alter policy tasks_update_member on public.tasks
  using ((is_house_member(house_id) AND ((visibility = 'house'::text) OR (created_by = (select auth.uid())) OR (assigned_to = (select auth.uid())))));
