-- 0109_releases_storage_policy.sql
-- Garante acesso de leitura, inserção e atualização no bucket 'releases'
-- para permitir o upload e substituição do APK compilado pelo script de deploy.

drop policy if exists "Upload releases" on storage.objects;
drop policy if exists "Update releases" on storage.objects;
drop policy if exists "Public read releases" on storage.objects;
drop policy if exists "Public Access Releases" on storage.objects;
drop policy if exists "Releases access" on storage.objects;

create policy "Releases access" on storage.objects
  for all
  to anon, authenticated, service_role
  using (bucket_id = 'releases')
  with check (bucket_id = 'releases');
