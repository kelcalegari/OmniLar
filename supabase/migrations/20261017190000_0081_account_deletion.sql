-- ==============================================================================
-- 0081: Exclusão de conta (LGPD) — frente 3 de plano_proximas_frentes.md
-- Descrição:
--   O usuário exclui a própria conta em Ajustes › Conta e segurança. A Edge
--   Function delete-account confere a senha e chama delete_my_account_data;
--   depois apaga o usuário do Auth (quando não sobrou nada dele em casa
--   nenhuma) ou o deixa sem e-mail, sem senha e bloqueado.
--
--   Por que nem sempre apagar o usuário do Auth: split_rules e contributions
--   apagam em cascata junto com o usuário (sumiria a parte dele no histórico
--   dos outros moradores), e despesas, empréstimos e transferências impedem a
--   exclusão. Então, quando ele divide ou dividiu casa com alguém, os dados
--   pessoais saem e o histórico fica no nome "Ex-morador" (decisão 3.6).
--
--   Casa por casa (decisões 3.3 e 3.4):
--   - único morador: a casa é apagada (todas as tabelas da casa vão junto);
--   - dono com outros moradores: a propriedade passa ao administrador mais
--     antigo (ou ao morador mais antigo) e a pessoa sai da casa;
--   - morador comum: sai da casa.
--   Dívidas em aberto não impedem (decisão 3.5): a tela mostra a lista antes.
--
--   Apagar uma casa esbarrava em duas travas: a auditoria (fn_audit_record)
--   tentava registrar a exclusão das despesas numa casa que já estava sumindo,
--   e prevent_ledger_mutation proíbe apagar pagamentos e movimentos de
--   caixinha. As duas passam a deixar a exclusão seguir quando a marca
--   omnilar.deleting_house está ligada, o que só delete_my_account_data faz,
--   e só dentro da própria transação.
-- ==============================================================================

-- 0. Travas que deixam a casa ser apagada pela exclusão de conta
create or replace function public.prevent_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' and current_setting('omnilar.deleting_house', true) = 'on' then
    return OLD;
  end if;
  raise exception 'Operação não permitida: registros do ledger financeiro são imutáveis.';
end;
$$;

create or replace function public.fn_audit_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house_id uuid;
  v_actor_id uuid;
  v_entity_id uuid;
  v_action text;
  v_diff jsonb;
  v_old_data jsonb;
  v_new_data jsonb;
begin
  -- Casa sendo apagada pela exclusão de conta: o histórico dela vai junto
  if TG_OP = 'DELETE' and current_setting('omnilar.deleting_house', true) = 'on' then
    return OLD;
  end if;

  if TG_OP = 'INSERT' then
    v_new_data := to_jsonb(NEW);
    v_house_id := (v_new_data->>'house_id')::uuid;
    v_actor_id := coalesce(auth.uid(), (v_new_data->>'created_by')::uuid, (v_new_data->>'paid_by_id')::uuid);
    v_entity_id := (v_new_data->>'id')::uuid;
    v_action := 'create';
    v_diff := jsonb_build_object('new', v_new_data);

  elsif TG_OP = 'DELETE' then
    v_old_data := to_jsonb(OLD);
    v_house_id := (v_old_data->>'house_id')::uuid;
    v_actor_id := coalesce(auth.uid(), (v_old_data->>'created_by')::uuid);
    v_entity_id := (v_old_data->>'id')::uuid;
    v_action := 'delete';
    v_diff := jsonb_build_object('old', v_old_data);

  elsif TG_OP = 'UPDATE' then
    v_old_data := to_jsonb(OLD);
    v_new_data := to_jsonb(NEW);
    v_house_id := coalesce((v_new_data->>'house_id')::uuid, (v_old_data->>'house_id')::uuid);
    v_actor_id := coalesce(auth.uid(), (v_new_data->>'updated_by')::uuid, (v_new_data->>'created_by')::uuid);
    v_entity_id := (v_new_data->>'id')::uuid;

    -- Detecta se é Soft Delete ou Restore
    if (v_new_data->>'deleted_at') is not null and (v_old_data->>'deleted_at') is null then
      v_action := 'soft_delete';
    elsif (v_old_data->>'deleted_at') is not null and (v_new_data->>'deleted_at') is null then
      v_action := 'restore';
    else
      v_action := 'update';
    end if;

    v_diff := jsonb_build_object(
      'old', v_old_data,
      'new', v_new_data
    );
  end if;

  -- Se não conseguiu house_id diretamente, tenta obter de tabelas pai para parcelas/itens
  if v_house_id is null and TG_TABLE_NAME = 'p2p_installments' then
    select house_id into v_house_id from public.p2p_loans where id = (coalesce(v_new_data, v_old_data)->>'loan_id')::uuid;
  end if;

  -- Grava na tabela audit_log
  if v_entity_id is not null then
    insert into public.audit_log (
      house_id,
      actor_id,
      entity_type,
      entity_id,
      action,
      diff,
      created_at
    ) values (
      v_house_id,
      v_actor_id,
      TG_TABLE_NAME,
      v_entity_id,
      v_action,
      v_diff,
      now()
    );
  end if;

  return coalesce(NEW, OLD);
end;
$$;

revoke execute on function public.prevent_ledger_mutation() from public, anon, authenticated;
revoke execute on function public.fn_audit_record() from public, anon, authenticated;

-- 1. Situação "excluída" da conta
alter table public.account_status drop constraint if exists account_status_status_check;
alter table public.account_status
  add constraint account_status_status_check
  check (status in ('pending', 'active', 'rejected', 'suspended', 'deleted'));

-- 2. O que vai acontecer, para a tela mostrar antes de confirmar
create or replace function public.account_deletion_preview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_houses jsonb := '[]'::jsonb;
  v_loans jsonb;
  h record;
  v_others integer;
  v_heir uuid;
begin
  if v_user is null then
    raise exception 'Faça login para excluir a conta.';
  end if;

  for h in
    select m.house_id, m.role, x.name
    from public.house_members m
    join public.houses x on x.id = m.house_id
    where m.user_id = v_user and m.left_at is null
    order by m.joined_at
  loop
    select count(*) into v_others
    from public.house_members where house_id = h.house_id and left_at is null and user_id <> v_user;

    v_heir := null;
    if v_others > 0 and h.role = 'owner' then
      v_heir := public.account_deletion_heir(h.house_id, v_user);
    end if;

    v_houses := v_houses || jsonb_build_object(
      'house_id', h.house_id,
      'name', h.name,
      'action', case when v_others = 0 then 'delete_house'
                     when h.role = 'owner' then 'transfer'
                     else 'leave' end,
      'new_owner_name', case when v_heir is null then null else public.notification_first_name(v_heir) end
    );
  end loop;

  -- Empréstimos com saldo em aberto em que a pessoa deve ou tem a receber
  select coalesce(jsonb_agg(jsonb_build_object(
           'title', l.title,
           'open_cents', o.open_cents,
           'side', case when l.borrower_id = v_user then 'borrower' else 'lender' end,
           'other_name', case when l.borrower_id = v_user
                              then case when l.lender_is_house then 'Caixa da Casa'
                                        else public.notification_first_name(l.lender_id) end
                              else public.notification_first_name(l.borrower_id) end
         ) order by l.created_at), '[]'::jsonb)
    into v_loans
  from public.p2p_loans l
  join lateral (
    select sum(i.amount_cents - i.paid_cents) as open_cents
    from public.p2p_installments i
    where i.loan_id = l.id and i.status in ('pending', 'partial')
  ) o on o.open_cents > 0
  where l.status = 'active' and (l.borrower_id = v_user or l.lender_id = v_user);

  return jsonb_build_object('houses', v_houses, 'open_loans', v_loans);
end;
$$;

-- Quem herda a casa: administrador mais antigo; sem administrador, o morador mais antigo
create or replace function public.account_deletion_heir(p_house_id uuid, p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select user_id from public.house_members
  where house_id = p_house_id and left_at is null and user_id <> p_user_id
  order by (role = 'admin') desc, joined_at, user_id
  limit 1;
$$;

-- 3. Exclusão dos dados (só a Edge Function, com a chave de serviço)
create or replace function public.delete_my_account_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  v_others integer;
  v_heir uuid;
  v_deleted_houses integer := 0;
  v_left_houses integer := 0;
begin
  if p_user_id is null then
    raise exception 'Usuário não informado.';
  end if;

  for h in
    select m.house_id, m.role from public.house_members m
    where m.user_id = p_user_id and m.left_at is null
  loop
    select count(*) into v_others
    from public.house_members where house_id = h.house_id and left_at is null and user_id <> p_user_id;

    if v_others = 0 then
      perform set_config('omnilar.deleting_house', 'on', true);
      delete from public.houses where id = h.house_id;
      perform set_config('omnilar.deleting_house', 'off', true);
      v_deleted_houses := v_deleted_houses + 1;
      continue;
    end if;

    if h.role = 'owner' then
      v_heir := public.account_deletion_heir(h.house_id, p_user_id);
      update public.house_members set role = 'owner'
      where house_id = h.house_id and user_id = v_heir;
      update public.houses set created_by = v_heir
      where id = h.house_id and created_by = p_user_id;
    end if;

    update public.house_members set left_at = now(), role = 'member'
    where house_id = h.house_id and user_id = p_user_id and left_at is null;
    v_left_houses := v_left_houses + 1;
  end loop;

  -- Dados pessoais e do aparelho
  update public.profiles
     set full_name = 'Ex-morador', phone = null, avatar_url = null,
         pix_key = null, pix_key_type = null, updated_at = now()
   where id = p_user_id;
  delete from public.device_tokens where user_id = p_user_id;
  delete from public.notification_preferences where user_id = p_user_id;
  delete from public.notification_settings where user_id = p_user_id;
  delete from public.notifications where user_id = p_user_id;
  delete from public.assistant_conversations where member_id = p_user_id;
  delete from public.assistant_preferences where member_id = p_user_id;
  delete from public.platform_admins where user_id = p_user_id;

  insert into public.account_status (user_id, status, status_reason, updated_at)
  values (p_user_id, 'deleted', 'Conta excluída pelo próprio usuário', now())
  on conflict (user_id) do update
    set status = 'deleted', status_reason = excluded.status_reason, updated_at = now();

  return jsonb_build_object(
    'deleted_houses', v_deleted_houses,
    'left_houses', v_left_houses,
    -- Sem nenhuma casa em que more ou tenha morado, nada de outros depende dele
    'can_delete_auth_user', not exists (select 1 from public.house_members where user_id = p_user_id)
  );
end;
$$;

revoke execute on function public.account_deletion_preview() from public, anon;
grant execute on function public.account_deletion_preview() to authenticated, service_role;
revoke execute on function public.account_deletion_heir(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.delete_my_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_my_account_data(uuid) to service_role;
