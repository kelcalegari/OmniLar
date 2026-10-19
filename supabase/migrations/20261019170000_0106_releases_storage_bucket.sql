-- 0106_releases_storage_bucket.sql
-- Configura o bucket 'releases' no Supabase Storage e permite download público
-- e upload/atualização automática do APK de release via script de terminal.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'releases',
  'releases',
  true,
  100000000, -- 100 MB (nosso APK tem ~35 MB)
  array['application/vnd.android.package-archive', 'application/octet-stream']
)
on conflict (id) do update set
  public = true,
  file_size_limit = 100000000;

-- 1. Buckets públicos NÃO precisam de policy de SELECT no storage.objects.
-- O Supabase CDN já serve os arquivos via /object/public/ diretamente.
-- Remover essa policy elimina o warning "Clients can list all files in this bucket".
drop policy if exists "Public read releases" on storage.objects;
drop policy if exists "Public Access Releases" on storage.objects;

-- 2. Permite envio de novas releases pelo script (apenas para o APK do OmniLar)
drop policy if exists "Upload releases" on storage.objects;
create policy "Upload releases" on storage.objects
  for insert with check (bucket_id = 'releases' and name = 'OmniLar-arm64-release.apk');

-- 3. Permite substituir (upsert) o APK com novas versões
drop policy if exists "Update releases" on storage.objects;
create policy "Update releases" on storage.objects
  for update using (bucket_id = 'releases' and name = 'OmniLar-arm64-release.apk')
  with check (bucket_id = 'releases' and name = 'OmniLar-arm64-release.apk');
