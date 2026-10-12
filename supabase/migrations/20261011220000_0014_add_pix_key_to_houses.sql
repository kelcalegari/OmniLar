-- ==============================================================================
-- Migration: 0014_add_pix_key_to_houses.sql
-- Module: Núcleo / Casas & Fechamento Financeiro (Caixa da Casa / Super Pix)
-- Description:
--   1. Adiciona as colunas de Chave Pix na tabela public.houses
--      - pix_key: Chave Pix oficial do Caixa da Casa
--      - pix_key_type: Tipo da chave (cpf, cnpj, email, phone, random, other)
--      - pix_key_holder_name: Nome do favorecido / titular da conta da casa
--      - pix_key_bank: Nome da instituição financeira / banco da conta da casa
--   2. Permite que membros da casa visualizem e administradores editem a chave
-- ==============================================================================

alter table public.houses
  add column if not exists pix_key text,
  add column if not exists pix_key_type text check (pix_key_type in ('cpf', 'cnpj', 'email', 'phone', 'random', 'other')),
  add column if not exists pix_key_holder_name text,
  add column if not exists pix_key_bank text;

comment on column public.houses.pix_key is 'Chave Pix oficial da residência para aportes e fechamentos do Caixa da Casa';
comment on column public.houses.pix_key_type is 'Tipo da chave Pix da casa: cpf, cnpj, email, phone, random ou other';
comment on column public.houses.pix_key_holder_name is 'Nome do titular da conta bancária da casa para conferência no Pix';
comment on column public.houses.pix_key_bank is 'Nome do banco ou instituição financeira da conta conjunta/caixa da casa';
