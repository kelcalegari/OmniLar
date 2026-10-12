-- ==============================================================================
-- Migration: 0013_add_pix_key_to_profiles.sql
-- Module: Núcleo / Perfis & Fechamento Financeiro (Super Pix)
-- Description:
--   1. Adiciona a coluna pix_key e pix_key_type na tabela public.profiles
--   2. Permite que cada usuário cadastre sua Chave Pix real para liquidações do Super Pix
-- ==============================================================================

alter table public.profiles
  add column if not exists pix_key text,
  add column if not exists pix_key_type text check (pix_key_type in ('cpf', 'email', 'phone', 'random', 'other'));

comment on column public.profiles.pix_key is 'Chave Pix cadastrada pelo usuário para receber transferências de acerto e do Super Pix';
comment on column public.profiles.pix_key_type is 'Tipo da chave Pix: cpf, email, phone, random ou other';
