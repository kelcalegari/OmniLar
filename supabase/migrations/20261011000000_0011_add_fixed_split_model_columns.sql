-- ==============================================================================
-- Migration: 20261011000000_0011_add_fixed_split_model_columns.sql
-- Description: Adiciona default_fixed_amount_cents em house_members e
--              default_split_model em houses para persistência do rateio nominal (Balde Comum).
-- ==============================================================================

-- 1. COLUNA default_fixed_amount_cents EM house_members
alter table public.house_members 
  add column if not exists default_fixed_amount_cents bigint default 0
  check (default_fixed_amount_cents is null or default_fixed_amount_cents >= 0);

-- 2. COLUNA default_split_model EM houses
alter table public.houses 
  add column if not exists default_split_model text default 'percentage'
  check (default_split_model in ('percentage', 'fixed', 'category'));

-- 3. RECARREGA O SCHEMA CACHE DO POSTGREST IMEDIATAMENTE
NOTIFY pgrst, 'reload schema';
