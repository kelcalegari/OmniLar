-- 0108_fix_receipt_storage_permissions.sql
-- 1. Garante permissão de execução nas funções de verificação para 'anon' e 'authenticated'
-- para não quebrar uploads anônimos/públicos em outros buckets (como o APK no bucket 'releases').
grant execute on function public.is_house_member(uuid) to anon, authenticated, service_role;

-- 2. Atualiza a função house_plan para considerar administradores como Premium automaticamente
create or replace function public.house_plan(p_house_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when bool_or(
      public.account_plan(m.user_id) = 'premium'
      or exists (select 1 from public.platform_admins a where a.user_id = m.user_id)
    ) then 'premium'
    else 'free'
  end
  from public.house_members m
  where m.house_id = p_house_id and m.role = 'owner' and m.left_at is null;
$$;

grant execute on function public.house_plan(uuid) to anon, authenticated, service_role;

-- 3. Recria as políticas do bucket 'receipts' com 'TO authenticated' explícito
drop policy if exists "Members read house receipts" on storage.objects;
create policy "Members read house receipts" on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'receipts'
    and public.is_house_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "Premium members upload house receipts" on storage.objects;
create policy "Premium members upload house receipts" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'receipts'
    and public.is_house_member((storage.foldername(name))[1]::uuid)
    and public.house_plan((storage.foldername(name))[1]::uuid) = 'premium'
  );

drop policy if exists "Members delete house receipts" on storage.objects;
create policy "Members delete house receipts" on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'receipts'
    and public.is_house_member((storage.foldername(name))[1]::uuid)
  );
