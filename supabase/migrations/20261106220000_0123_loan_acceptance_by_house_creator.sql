-- ==============================================================================
-- 0123: Só quem criou a casa decide se o empréstimo pede aceite
-- Descrição:
--   A 0116 criou `houses.loan_acceptance` (por origem, se o empréstimo lançado
--   por outra pessoa espera o aceite do devedor) e a 0120 levou a chave
--   `house` para o empréstimo do Caixa. Quem podia mudar era qualquer um com
--   `editar_configuracoes`. Agora a configuração é de quem criou a casa
--   (`houses.created_by`, o mesmo dono que arquiva a casa na 0114) e vale para
--   todos os moradores: desligada, o empréstimo já nasce aceito, sem esperar
--   o devedor.
--
--   A regra fica num gatilho da tabela, então vale para a
--   `update_house_settings` e para qualquer update direto pelo app. Sem
--   usuário (service_role, migrações) passa, como nas outras guardas.
--   Quando o dono sai, a `leave_house` já passa `created_by` para o herdeiro,
--   que herda também esta configuração.
-- ==============================================================================

create or replace function public.guard_house_loan_acceptance()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.loan_acceptance is distinct from old.loan_acceptance
     and auth.uid() is not null
     and auth.uid() is distinct from old.created_by then
    raise exception 'Só quem criou a casa muda quando o empréstimo pede aceite.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_houses_guard_loan_acceptance on public.houses;
create trigger trg_houses_guard_loan_acceptance
  before update of loan_acceptance on public.houses
  for each row execute function public.guard_house_loan_acceptance();

comment on column public.houses.loan_acceptance is
  'Por origem (manual, import, house), se o empréstimo lançado por outra pessoa espera o aceite do devedor; chave ausente = true (0116). Só quem criou a casa muda (0123).';
