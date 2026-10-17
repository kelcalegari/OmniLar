-- ==============================================================================
-- 0085: Termos, consentimento da IA e "Baixar meus dados" (decisão 13 de
--       plano_proximas_frentes.md)
-- Descrição:
--   - profiles ganha terms_version e terms_accepted_at (versão dos Termos e da
--     Política aceita e quando) e ai_consent_at (consentimento para a leitura
--     por IA; null = não deu ou retirou).
--   - accept_terms(p_version) e set_ai_consent(p_given): só para a própria conta.
--   - export_my_data(): devolve, em JSON, os dados da própria conta e o que ela
--     lançou ou de que participa nas casas (direito de acesso e portabilidade,
--     LGPD art. 18).
-- ==============================================================================

alter table public.profiles
  add column if not exists terms_version text,
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists ai_consent_at timestamptz;

create or replace function public.accept_terms(p_version text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Faça login para aceitar os termos.';
  end if;
  if nullif(btrim(coalesce(p_version, '')), '') is null then
    raise exception 'Versão dos termos não informada.';
  end if;
  update public.profiles
     set terms_version = p_version, terms_accepted_at = now(), updated_at = now()
   where id = auth.uid();
end;
$$;

create or replace function public.set_ai_consent(p_given boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Faça login para mudar o consentimento.';
  end if;
  update public.profiles
     set ai_consent_at = case when p_given then now() else null end, updated_at = now()
   where id = auth.uid();
end;
$$;

create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_houses uuid[];
begin
  if v_user is null then
    raise exception 'Faça login para baixar os seus dados.';
  end if;

  select coalesce(array_agg(house_id), '{}') into v_houses
  from public.house_members where user_id = v_user;

  return jsonb_build_object(
    'gerado_em', now(),
    'perfil', (select to_jsonb(p) from public.profiles p where p.id = v_user),
    'conta', (select to_jsonb(s) - 'approved_by' from public.account_status s where s.user_id = v_user),
    'casas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'casa', jsonb_build_object('id', h.id, 'nome', h.name, 'criada_em', h.created_at),
                  'papel', m.role, 'entrou_em', m.joined_at, 'saiu_em', m.left_at)), '[]'::jsonb)
              from public.house_members m join public.houses h on h.id = m.house_id
              where m.user_id = v_user),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(e) order by e.date), '[]'::jsonb)
                 from public.house_expenses e
                 where e.house_id = any(v_houses)
                   and (e.created_by = v_user or e.paid_by_id = v_user
                        or exists (select 1 from public.split_rules r where r.expense_id = e.id and r.member_id = v_user))),
    'divisoes', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
                 from public.split_rules r where r.member_id = v_user),
    'aportes', (select coalesce(jsonb_agg(to_jsonb(c) order by c.cycle_start_date), '[]'::jsonb)
                from public.contributions c where c.member_id = v_user or c.created_by = v_user),
    'emprestimos', (select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object(
                        'parcelas', (select coalesce(jsonb_agg(to_jsonb(i) order by i.installment_number), '[]'::jsonb)
                                     from public.p2p_installments i where i.loan_id = l.id))
                      order by l.created_at), '[]'::jsonb)
                    from public.p2p_loans l
                    where l.lender_id = v_user or l.borrower_id = v_user or l.created_by = v_user),
    'transferencias_do_fechamento', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                                     from public.settlement_transfers t
                                     where t.from_member_id = v_user or t.to_member_id = v_user),
    'movimentos_de_caixinha', (select coalesce(jsonb_agg(to_jsonb(st)), '[]'::jsonb)
                               from public.savings_transactions st where st.member_id = v_user),
    'tarefas', (select coalesce(jsonb_agg(to_jsonb(tk)), '[]'::jsonb)
                from public.tasks tk where tk.created_by = v_user or tk.assigned_to = v_user),
    'itens_de_compra', (select coalesce(jsonb_agg(to_jsonb(si)), '[]'::jsonb)
                        from public.shopping_items si where si.created_by = v_user),
    'eventos', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                from public.events ev
                where ev.created_by = v_user
                   or exists (select 1 from public.event_participants ep where ep.event_id = ev.id and ep.user_id = v_user)),
    'notificacoes', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at), '[]'::jsonb)
                     from public.notifications n where n.user_id = v_user),
    'preferencias_de_notificacao', (select coalesce(jsonb_agg(to_jsonb(np)), '[]'::jsonb)
                                    from public.notification_preferences np where np.user_id = v_user),
    'configuracoes_de_notificacao', (select to_jsonb(ns) from public.notification_settings ns where ns.user_id = v_user),
    'aparelhos_com_notificacao', (select count(*) from public.device_tokens d where d.user_id = v_user),
    'leituras_por_ia', (select count(*) from public.ai_usage a where a.member_id = v_user)
  );
end;
$$;

revoke execute on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated, service_role;
revoke execute on function public.set_ai_consent(boolean) from public, anon;
grant execute on function public.set_ai_consent(boolean) to authenticated, service_role;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated, service_role;
