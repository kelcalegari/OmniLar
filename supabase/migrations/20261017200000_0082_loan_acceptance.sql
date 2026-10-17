-- ==============================================================================
-- 0082: Aceite do empréstimo pelo devedor (decisão 4.4 de plano_proximas_frentes.md)
-- Descrição:
--   Empréstimo lançado por outra pessoa que não o devedor nasce aguardando o
--   aceite dele (awaiting_acceptance). Lançado pelo próprio devedor, já nasce
--   aceito. Os que as funções do banco criam (fechamento do ciclo, fatura paga
--   pelo Caixa) rodam como dona das tabelas e também nascem aceitos.
--   - O fechamento do ciclo não cobra parcela de empréstimo não aceito: quem
--     monta o plano é o app, que deixa esse empréstimo de fora e avisa.
--   - Só o devedor aceita (accept_p2p_loan) ou recusa (decline_p2p_loan). Recusar
--     cancela o empréstimo (status cancelled), que fica no histórico.
--   - Pagar uma parcela vale como aceite.
--   - Os empréstimos que já existem contam como aceitos.
-- ==============================================================================

alter table public.p2p_loans
  add column if not exists awaiting_acceptance boolean not null default false,
  add column if not exists accepted_at timestamptz;

update public.p2p_loans set accepted_at = created_at where accepted_at is null and not awaiting_acceptance;

-- 1. Quem lança e quem aceita
-- Roda com as permissões de quem grava (sem security definer): current_user diz
-- se veio do app (authenticated) ou de uma função do banco (dona das tabelas).
create or replace function public.guard_p2p_loan_acceptance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_by_app boolean := current_user = 'authenticated';
begin
  if TG_OP = 'INSERT' then
    if v_by_app and v_user is not null and v_user is distinct from new.borrower_id then
      new.awaiting_acceptance := true;
      new.accepted_at := null;
    else
      new.awaiting_acceptance := false;
      new.accepted_at := coalesce(new.accepted_at, now());
    end if;
    return new;
  end if;

  -- Ninguém além do devedor tira o empréstimo da espera pelo app
  if old.awaiting_acceptance and not new.awaiting_acceptance
     and v_by_app and v_user is distinct from new.borrower_id then
    raise exception 'Só quem deve pode aceitar o empréstimo.';
  end if;
  -- Nem volta para a espera depois de aceito
  if not old.awaiting_acceptance and new.awaiting_acceptance and v_by_app then
    raise exception 'O empréstimo já foi aceito.';
  end if;
  if old.awaiting_acceptance and not new.awaiting_acceptance then
    new.accepted_at := coalesce(new.accepted_at, now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_p2p_loan_acceptance on public.p2p_loans;
create trigger trg_guard_p2p_loan_acceptance
  before insert or update of awaiting_acceptance, accepted_at on public.p2p_loans
  for each row execute function public.guard_p2p_loan_acceptance();

-- 2. Pagar uma parcela vale como aceite
create or replace function public.accept_p2p_loan_on_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.paid_cents > coalesce(old.paid_cents, 0) then
    update public.p2p_loans
       set awaiting_acceptance = false, accepted_at = now()
     where id = new.loan_id and awaiting_acceptance;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_accept_p2p_loan_on_payment on public.p2p_installments;
create trigger trg_accept_p2p_loan_on_payment
  after update of paid_cents on public.p2p_installments
  for each row execute function public.accept_p2p_loan_on_payment();

-- 3. Aceitar e recusar (só o devedor)
create or replace function public.accept_p2p_loan(p_loan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_user uuid := auth.uid();
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found or not public.is_house_member(v_loan.house_id) then
    raise exception 'Empréstimo não encontrado.';
  end if;
  if v_loan.borrower_id is distinct from v_user then
    raise exception 'Só quem deve pode aceitar o empréstimo.';
  end if;
  if not v_loan.awaiting_acceptance then
    return;
  end if;

  update public.p2p_loans set awaiting_acceptance = false, accepted_at = now() where id = p_loan_id;

  perform public.enqueue_notification(
    v_loan.house_id,
    case when v_loan.lender_is_house then public.notification_house_admin_ids(v_loan.house_id)
         else array[v_loan.lender_id] end,
    'loan_accepted', 'emprestimos',
    'Empréstimo aceito',
    public.notification_first_name(v_user) || ' aceitou o empréstimo ' || v_loan.title || ': '
      || public.notification_brl(v_loan.total_amount_cents),
    '/pessoal/emprestimo/' || p_loan_id, 'p2p_loan', p_loan_id,
    'loan_accepted:' || p_loan_id, false
  );
end;
$$;

create or replace function public.decline_p2p_loan(p_loan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.p2p_loans%rowtype;
  v_user uuid := auth.uid();
begin
  select * into v_loan from public.p2p_loans where id = p_loan_id for update;
  if not found or not public.is_house_member(v_loan.house_id) then
    raise exception 'Empréstimo não encontrado.';
  end if;
  if v_loan.borrower_id is distinct from v_user then
    raise exception 'Só quem deve pode recusar o empréstimo.';
  end if;
  if not v_loan.awaiting_acceptance then
    raise exception 'Este empréstimo já foi aceito; para desfazer, fale com quem lançou.';
  end if;

  update public.p2p_loans set status = 'cancelled', awaiting_acceptance = false, updated_at = now()
  where id = p_loan_id;

  perform public.enqueue_notification(
    v_loan.house_id,
    case when v_loan.lender_is_house then public.notification_house_admin_ids(v_loan.house_id)
         else array[coalesce(v_loan.created_by, v_loan.lender_id)] end,
    'loan_declined', 'emprestimos',
    'Empréstimo recusado',
    public.notification_first_name(v_user) || ' recusou o empréstimo ' || v_loan.title || ': '
      || public.notification_brl(v_loan.total_amount_cents),
    '/pessoal/emprestimo/' || p_loan_id, 'p2p_loan', p_loan_id,
    'loan_declined:' || p_loan_id, true
  );
end;
$$;

revoke execute on function public.accept_p2p_loan_on_payment() from public, anon, authenticated;
revoke execute on function public.accept_p2p_loan(uuid) from public, anon;
grant execute on function public.accept_p2p_loan(uuid) to authenticated, service_role;
revoke execute on function public.decline_p2p_loan(uuid) from public, anon;
grant execute on function public.decline_p2p_loan(uuid) to authenticated, service_role;
