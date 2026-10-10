# 🧳 Omni Lar: Módulo de Projetos e Viagens Compartilhadas

## 1. Visão Geral
O módulo de **Projetos e Viagens Compartilhadas** atende despesas colaborativas e eventos extraordinários do lar ou de grupos fechados (ex.: viagens de férias, compra conjunta de bens ou imóveis, reformas da casa, festas e investimentos coletivos).

**Princípio Fundamental de Isolamento:** Os custos de um projeto pertencem exclusivamente àquele projeto e aos seus participantes. **Não pesam no Caixa da Casa, no Fôlego Financeiro nem no Fechamento Geral do ciclo da Casa.** A apuração e liquidação ocorrem por meio de um balanço e transferências dedicadas via Super Pix do próprio projeto.

---

## 2. Conceitos
- **Projeto Compartilhado (`SharedProject`):** Uma iniciativa delimitada no tempo e/ou orçamento (Viagem, Reforma, Evento, Aquisição, Genérico).
- **Participante do Projeto (`ProjectParticipant`):** Membro cadastrado da casa ou convidado externo que integra o projeto. Pode ter um percentual padrão individual (`defaultSplitPercent`).
- **Orçamento Previsto (`targetBudget`):** Meta de gastos estipulada para alertar o consumo e evitar estouro.
- **Isolamento de Despesas:** `HouseExpense` com `projectId != null` é uma despesa de projeto. Não é debitada do caixa comum da casa.
- **Super Pix do Projeto:** Algoritmo de transferências mínimas calculado exclusivamente entre os participantes do projeto para zerar os saldos devedores e credores.

---

## 3. Regras de Negócio (RN)

### RN01 — Isolamento Orçamentário da Casa
Despesas vinculadas a um projeto (`projectId != null`) **não entram** no cálculo de:
1. Despesas do Ciclo da Casa (`getExpensesForCycle`).
2. Fôlego Financeiro da Casa (`folego = aportes - compromissos`).
3. Fechamento Geral da Casa (`GlobalClearingEngine.computeSettlement`).
Elas são acessadas e totalizadas via `getExpensesForProject(projectId)`.

### RN02 — Participantes Internos e Externos
Um participante de projeto pode ser:
- Um membro registrado da casa (`userId != null`).
- Um convidado externo sem login (ex.: amigo que viajou junto, empreiteiro de obra com `userId == null` e `externalName` preenchido).

### RN03 — Despesas Trans-Ciclo
Projetos como viagens e reformas podem atravessar múltiplos meses/ciclos. O balanço e a liquidação do projeto consideram **todas as despesas registradas para o projeto**, independentemente da data de competência ou ciclo mensal.

### RN04 — Regras de Rateio de Projeto
O rateio de despesas do projeto pode ser:
1. **Percentual Explícito na Despesa:** definido em `SplitRule.percentages` (suportando IDs de participante ou `userId`).
2. **Percentual Padrão dos Participantes:** quando a despesa for percentual sem valores explícitos, aplica o `defaultSplitPercent` de cada participante.
3. **Divisão Igualitária:** fallback quando nenhum percentual foi estipulado, dividindo em centavos e distribuindo o resto sem perda.
4. **Sub-itens / Despesas Compostas:** se a despesa tiver itens específicos (`HouseExpenseItem`), cada item é apurado individualmente com sua regra ou responsável exclusivo.

### RN05 — Compensação Mínima (Super Pix do Projeto)
O motor `ProjectSettlementService` calcula o saldo líquido de cada participante (`totalPaid - totalShareDue`) e aplica o algoritmo de emparelhamento ótimo guloso (*greedy minimum transfers*) para gerar o menor número de Pix necessários para quitar o projeto.

---

## 4. Funcionalidades
- **Hub de Projetos (`ProjectsHubPage`):** Lista de projetos ativos e concluídos com progresso de orçamento e badge de status.
- **Criação de Projetos:** Definição de título, tipo, orçamento teto e participantes.
- **Vínculo em Nova Despesa (`AddExpensePage`):** Dropdown dinâmico para atrelar qualquer despesa (simples, recorrente ou composta) a um projeto ativo.
- **Balanço e Acerto de Contas:** Visualização em tempo real de quem pagou, quem deve e lista de transferências Super Pix recomendadas.

---

## 5. UX e Telas
- **Acesso:** Atalho na Home ("Viagens e Projetos") e rota direta `/projetos` (`/casa/projetos`).
- **Cards com Termômetro:** Ícone contextual por tipo de projeto (viagem: avião, reforma: casa/ferramentas, etc.).
- **Balanço Colorido:** Credores em verde esmeralda com sinal `+` e devedores com sinal `-`.

---

## 6. Modelo de Dados

### Tabela `shared_projects`
- `id`: UUID (PK)
- `house_id`: UUID (FK houses)
- `title`: TEXT
- `type`: TEXT (`trip`, `asset_purchase`, `investment`, `event`, `generic`)
- `target_budget_cents`: BIGINT (centavos)
- `status`: TEXT (`planning`, `active`, `settled`, `archived`)
- `start_date`, `end_date`: DATE
- `created_by`: UUID (FK auth.users)

### Tabela `project_participants`
- `id`: UUID (PK)
- `project_id`: UUID (FK shared_projects)
- `user_id`: UUID (FK auth.users, opcional)
- `external_name`: TEXT (opcional)
- `default_split_percent`: NUMERIC(5,2)

---

## 7. Casos de Teste Obrigatórios
- [x] Rateio igualitário de despesas na viagem entre participantes internos e externos.
- [x] Despesa de projeto excluída das despesas do ciclo e do fechamento da casa (RN01).
- [x] Resolução de pagador por `userId` e `SplitRule` por `userId`.
- [x] Rateio respeitando `defaultSplitPercent` dos participantes.
- [x] Projeção de progresso de orçamento e detecção de estouro.
- [x] Renderização correta da lista no `ProjectsHubPage`.

---

## 8. Fora do Escopo
- Conversão de moedas estrangeiras em tempo real (versão atual armazena em BRL).
- Integração bancária direta de Pix de terceiros (o app gera a proposta de transferência e chave Pix; a execução é manual no banco).
