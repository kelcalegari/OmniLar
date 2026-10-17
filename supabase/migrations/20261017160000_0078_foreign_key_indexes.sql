-- ==============================================================================
-- 0078: Índices nas chaves estrangeiras mais consultadas
-- Descrição:
--   O relatório de alertas do Supabase apontou 66 chaves estrangeiras sem
--   índice. Entram só as que o app filtra ou junta com frequência e as que
--   pesam ao excluir a linha de origem (categoria, forma de pagamento, despesa,
--   empréstimo, caixinha, lista, rotina e morador). As de auditoria e as de
--   "quem criou" ficam de fora.
-- ==============================================================================

create index if not exists idx_house_expenses_category_id on public.house_expenses (category_id);
create index if not exists idx_house_expenses_payment_method_id on public.house_expenses (payment_method_id);
create index if not exists idx_house_expenses_paid_by_id on public.house_expenses (paid_by_id);
create index if not exists idx_p2p_loans_borrower_id on public.p2p_loans (borrower_id);
create index if not exists idx_p2p_loans_repay_to_vault_id on public.p2p_loans (repay_to_vault_id);
create index if not exists idx_notifications_house_id on public.notifications (house_id);
create index if not exists idx_event_participants_house_id on public.event_participants (house_id);
create index if not exists idx_notification_preferences_house_id on public.notification_preferences (house_id);
create index if not exists idx_shopping_trips_list_id on public.shopping_trips (list_id);
create index if not exists idx_shopping_trips_expense_id on public.shopping_trips (expense_id);
create index if not exists idx_tasks_expense_id on public.tasks (expense_id);
create index if not exists idx_tasks_routine_id on public.tasks (routine_id);
create index if not exists idx_import_lines_expense_id on public.import_lines (expense_id);
create index if not exists idx_import_lines_loan_id on public.import_lines (loan_id);
create index if not exists idx_shopping_items_category_id on public.shopping_items (category_id);
create index if not exists idx_payment_methods_owner_member_id on public.payment_methods (owner_member_id);
create index if not exists idx_categories_owner_member_id on public.categories (owner_member_id);
create index if not exists idx_settlement_transfers_from_member_id on public.settlement_transfers (from_member_id);
create index if not exists idx_settlement_transfers_to_member_id on public.settlement_transfers (to_member_id);
create index if not exists idx_savings_transactions_member_id on public.savings_transactions (member_id);
create index if not exists idx_payments_payment_method_id on public.payments (payment_method_id);
