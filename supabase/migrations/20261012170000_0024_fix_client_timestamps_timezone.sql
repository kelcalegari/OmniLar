-- ==============================================================================
-- 0024: Corrige horários gravados pelo app sem fuso horário
-- Descrição:
--   O app enviava o horário local sem offset e o banco o lia como UTC, então
--   "15:00 em Brasília" ficou gravado como 15:00 UTC (3 horas adiantado no
--   relógio real). A partir desta versão o app envia UTC e converte na leitura.
--   Esta migration reinterpreta, uma única vez, os valores já gravados pelo app
--   como horário local da casa. Colunas preenchidas pelo próprio banco (now())
--   não são tocadas.
-- ==============================================================================

-- Sem gatilhos de usuário: é correção de dados, não uma edição feita por alguém
alter table public.events disable trigger user;
alter table public.house_expenses disable trigger user;
alter table public.p2p_loans disable trigger user;
alter table public.p2p_installments disable trigger user;
alter table public.shopping_items disable trigger user;
alter table public.tasks disable trigger user;
alter table public.shared_projects disable trigger user;

-- Agenda
update public.events e
set start_time = (e.start_time at time zone 'UTC') at time zone h.timezone,
    end_time = (e.end_time at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = e.house_id;

update public.event_participants p
set responded_at = (p.responded_at at time zone 'UTC') at time zone h.timezone
from public.events e
join public.houses h on h.id = e.house_id
where e.id = p.event_id and p.responded_at is not null;

-- Despesas (data do lançamento)
update public.house_expenses x
set date = (x.date at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = x.house_id and x.date is not null;

-- Empréstimos: data de criação informada pelo app
update public.p2p_loans l
set created_at = (l.created_at at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = l.house_id;

-- Parcelas já pagas informadas no cadastro (as baixadas por RPC usam now() e têm alocação)
update public.p2p_installments i
set paid_at = (i.paid_at at time zone 'UTC') at time zone h.timezone
from public.p2p_loans l
join public.houses h on h.id = l.house_id
where l.id = i.loan_id
  and i.paid_at is not null
  and not exists (
    select 1 from public.payment_allocations a where a.installment_id = i.id
  );

-- Compras
update public.shopping_items s
set bought_at = (s.bought_at at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = s.house_id and s.bought_at is not null;

update public.shopping_trips t
set completed_at = (t.completed_at at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = t.house_id;

-- Tarefas
update public.tasks t
set completed_at = (t.completed_at at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = t.house_id and t.completed_at is not null;

-- Projetos excluídos
update public.shared_projects p
set deleted_at = (p.deleted_at at time zone 'UTC') at time zone h.timezone
from public.houses h
where h.id = p.house_id and p.deleted_at is not null;

alter table public.events enable trigger user;
alter table public.house_expenses enable trigger user;
alter table public.p2p_loans enable trigger user;
alter table public.p2p_installments enable trigger user;
alter table public.shopping_items enable trigger user;
alter table public.tasks enable trigger user;
alter table public.shared_projects enable trigger user;
