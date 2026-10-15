-- ==============================================================================
-- 0060: Interruptor "gasto variável" na categoria
-- Descrição:
--   O Planejamento de Aportes estima pela média os gastos variáveis do ciclo.
--   Até aqui o app adivinhava quais categorias são variáveis pelo nome
--   (mercado, feira, luz, energia, água, gás). Agora cada categoria pode dizer
--   isso no próprio cadastro.
--   A coluna aceita nulo: categoria que nunca teve o interruptor mexido continua
--   sendo adivinhada pelo nome, então as casas que já existem e as categorias
--   padrão de uma casa nova não mudam de comportamento.
--   Quem pode alterar segue a regra de categories_update_admin_or_owner.
-- ==============================================================================

alter table public.categories
  add column if not exists is_variable_spend boolean;

comment on column public.categories.is_variable_spend is
  'Gasto variável no Planejamento de Aportes (estimado pela média). Nulo: o app decide pelo nome da categoria.';
