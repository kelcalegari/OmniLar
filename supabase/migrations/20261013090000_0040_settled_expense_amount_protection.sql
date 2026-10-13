-- ==============================================================================
-- 0040: Despesa já acertada não muda de valor nem de quem pagou
-- Descrição:
--   Com o ciclo reaberto, excluir uma despesa que já entrou em um fechamento
--   era recusado (0029), mas alterar o valor dela continuava possível e não
--   gerava acerto: o reembolso e o rateio já tinham sido feitos com o valor
--   antigo. Agora valor, pagador e "pago do próprio bolso" de uma despesa já
--   acertada não mudam; a correção é um lançamento de ajuste, como na exclusão.
--   Título, categoria, observações e datas continuam editáveis.
-- ==============================================================================

create or replace function public.protect_settled_expense()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- As funções do banco aplicam a regra por conta própria, e exclusões em
  -- cascata (ex: a casa inteira) não passam por aqui
  if current_user not in ('authenticated', 'anon') or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if old.settled_at is not null then
    if tg_op = 'DELETE' then
      raise exception 'Esta despesa já entrou em um fechamento de ciclo e não pode ser excluída. Lance um ajuste para corrigir o valor.';
    elsif new.deleted_at is not null and old.deleted_at is null then
      raise exception 'Esta despesa já entrou em um fechamento de ciclo e não pode ser excluída. Lance um ajuste para corrigir o valor.';
    elsif new.amount_cents is distinct from old.amount_cents
       or new.paid_by_id is distinct from old.paid_by_id
       or new.paid_out_of_pocket is distinct from old.paid_out_of_pocket then
      raise exception 'Esta despesa já entrou em um fechamento de ciclo: o valor e quem pagou não podem ser alterados. Lance um ajuste para corrigir a diferença.';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
