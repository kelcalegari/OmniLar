-- ==============================================================================
-- 0046: Dono da forma de pagamento em duas colunas, sempre iguais
-- Descrição:
--   payment_methods tem duas colunas para o dono (owner_id, a original, e
--   owner_member_id, a que o app lê). A migration 0017 previa um gatilho para
--   mantê-las iguais, mas ele não existe no banco (a 0017 foi aplicada à mão).
--   Uma forma de pagamento ("Nubank") está com o dono só em owner_id.
--   Aqui: iguala o que já está gravado e cria o gatilho. Quando as duas
--   chegam diferentes, vale a que mudou.
-- ==============================================================================

update public.payment_methods
set owner_member_id = owner_id
where owner_member_id is null and owner_id is not null;

update public.payment_methods
set owner_id = owner_member_id
where owner_id is null and owner_member_id is not null;

create or replace function public.sync_payment_methods_owner()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.owner_member_id := coalesce(new.owner_member_id, new.owner_id);
    new.owner_id := new.owner_member_id;
  elsif new.owner_member_id is distinct from old.owner_member_id then
    new.owner_id := new.owner_member_id;
  elsif new.owner_id is distinct from old.owner_id then
    new.owner_member_id := new.owner_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_payment_methods_owner on public.payment_methods;
create trigger trg_sync_payment_methods_owner
  before insert or update on public.payment_methods
  for each row execute function public.sync_payment_methods_owner();
