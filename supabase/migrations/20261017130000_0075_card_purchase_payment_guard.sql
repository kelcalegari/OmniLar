-- ==============================================================================
-- 0075: Pagamento de compra no cartão só pela fatura
-- Descrição:
--   Compra no cartão nasce pendente (0054/0058) e é paga junto com a fatura,
--   pelas funções pay_card_invoice e undo_card_invoice_payment. Mas qualquer
--   morador ainda conseguia gravar status, paid_at ou paid_out_of_pocket direto
--   na tabela, tirando a compra da fatura.
--   1) Cartão precisa ter dia de fechamento e de vencimento (o app já pede; não
--      havia nenhum cartão sem eles no banco).
--   2) Numa compra no cartão (fora de projeto e não recorrente), mudar o
--      pagamento direto na tabela é recusado. As funções do banco rodam como
--      dona das tabelas (current_user diferente de authenticated) e continuam
--      podendo: pagar e desfazer a fatura, fechamento do ciclo etc.
--      Se a forma de pagamento acabou de virar cartão, a compra volta a ficar
--      pendente, como ao lançar (card_purchase_waits_for_invoice).
-- ==============================================================================

alter table public.payment_methods
  drop constraint if exists payment_methods_card_needs_days;
alter table public.payment_methods
  add constraint payment_methods_card_needs_days
  check (type <> 'card' or (closing_day is not null and due_day is not null));

create or replace function public.guard_card_purchase_payment()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Só a gravação direta do app (as funções do banco rodam como dona)
  if current_user <> 'authenticated' then
    return new;
  end if;

  if new.project_id is not null
     or coalesce(new.is_recurring, false)
     or new.payment_method_id is null
     or not exists (
       select 1 from public.payment_methods pm
       where pm.id = new.payment_method_id and pm.type = 'card'
     ) then
    return new;
  end if;

  if new.payment_method_id is distinct from old.payment_method_id then
    -- Passou a ser compra no cartão: espera a fatura
    new.status := 'pending';
    new.paid_at := null;
    new.paid_out_of_pocket := false;
    return new;
  end if;

  -- Quem pagou a fatura só muda com ela; numa compra ainda pendente a
  -- importação pode corrigir paid_out_of_pocket
  if new.status is distinct from old.status
     or new.paid_at is distinct from old.paid_at
     or (old.status = 'paid' and new.paid_out_of_pocket is distinct from old.paid_out_of_pocket) then
    raise exception 'Compra no cartão é paga junto com a fatura. Use "Pagar fatura" (ou desfaça o pagamento dela).';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_house_expenses_card_payment_guard on public.house_expenses;
create trigger trg_house_expenses_card_payment_guard
  before update on public.house_expenses
  for each row execute function public.guard_card_purchase_payment();
