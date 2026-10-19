# Plano: Anexo de Comprovantes e Ciclo de Vida (Modelo A)

Escrito em 19/10/2026. Define a arquitetura, o modelo de dados, os fluxos no app e a política de retenção para o anexo real de documentos e comprovantes fiscais no Omni Lar, adotando o **Modelo A (Retenção por Ciclo Financeiro)**.

---

## 1. Visão Geral e Motivação

No modelo financeiro do Omni Lar, as despesas da casa e compras compartilhadas são apuradas mensalmente por **Ciclos Financeiros**, culminando no **Fechamento do Ciclo (Super Pix)**.

Durante o ciclo em aberto, é comum que moradores queiram conferir a nota fiscal ou comprovante de pagamento (*"De onde veio esse valor de R$ 192,00 no mercado?"*). Porém, após o ciclo ser fechado, conferido e quitado por todos os membros, guardar fotos pesadas de notas térmicas de mercado e comprovantes de anos anteriores:
1. **Gera custo desnecessário de nuvem** (estourando quotas do Supabase Storage).
2. **Cria passivo de privacidade (LGPD)** ao armazenar dados fiscais e bancários indefinidamente.
3. **Não agrega valor contábil**, pois a verdade contábil (valores em centavos, rateios, datas e categorias) já está imutável no banco de dados e nos fechamentos arquivados.

Por isso, o Omni Lar adota o **Modelo A**: o comprovante físico tem vida útil atrelada ao ciclo financeiro, servindo para conferência e auditoria enquanto as contas estão sendo apuradas e quitadas.

---

## 2. Planos (Free vs. Premium) e Postura de UX Suave

### 2.1. Alocação do Recurso
* **Plano Free:** Não armazena arquivos físicos no Storage (custo zero de nuvem para o projeto). O Scanner com IA **continua funcionando 100% no Free**, lendo a foto na memória e preenchendo todos os itens e valores da conta sem interrupções. O arquivo apenas não fica guardado na nuvem.
* **Plano Premium:** Permite anexar arquivos físicos e guardá-los no Supabase Storage durante o ciclo de vida do **Modelo A** (ciclo ativo + 30 dias após o fechamento).

### 2.2. Diretriz de UX: Não-Incisivo e Respeitoso (Sem Paywall Agressivo)
O Omni Lar preza por uma convivência tranquila e uma interface limpa. **É proibido ser agressivo, empurrar vendas ou exibir popups bloqueantes** do tipo *"Quer anexar? Assine já!"*.
* **No Formulário de Despesa (Free):** A seção de comprovante exibe apenas uma identificação visual calma e discreta: `Comprovante / Cupom ⭐`.
  * Se o usuário clicar, um modal informativo simples e educado esclarece:
    > *"O arquivamento de fotos de notas na nuvem é uma comodidade do Omni Lar Premium. O lançamento da despesa funciona normalmente no seu plano atual."*
  * O usuário tem um botão neutro *"Entendi"* para continuar sem nenhum atrito.
* **No Scanner de IA (Free):** Nenhum aviso ou bloqueio. O escâner lê a nota fiscal, preenche a despesa perfeitamente e fecha com sucesso. Não interrompe o fluxo de lançamento com propaganda.

---

## 3. Política de Retenção — Modelo A (Casas Premium)

| Fase da Despesa | Situação do Anexo | Acesso no App |
|---|---|---|
| **Ciclo em Aberto** (ativo) | Guardado no Supabase Storage (`receipts`) | Visualização completa e download por qualquer morador da casa |
| **Ciclo Fechado** (até 30 dias após quitação) | Mantido no Storage para eventuais contestações ou conferência final | Visualização completa e download |
| **Após 30 dias da Quitação do Ciclo** | **Expurgo Automático:** o arquivo físico é deletado do Storage; a despesa mantém todos os dados numéricos e textuais intactos | Card na timeline mostra *"Comprovante arquivado após quitação do ciclo"* |

### Vantagens do Modelo A:
* **Custo previsível e baixo:** Apenas ~60 a 90 dias de fotos ativas simultaneamente por casa Premium. Dificilmente uma casa ultrapassa 150 MB de armazenamento.
* **Privacidade por Design (LGPD):** Elimina dados pessoais e fiscais assim que a finalidade (conferência entre moradores) é cumprida.
* **Integridade Contábil:** O fechamento e as despesas continuam com valor, itens discriminados, pagador e categorias preservados para sempre.

---

## 4. Arquitetura e Supabase Storage

### 4.1. Bucket no Supabase
* **Nome do Bucket:** `receipts` (ou `attachments`).
* **Visibilidade:** Privado (não público).
* **Estrutura de Pastas:**
  ```text
  receipts/{house_id}/expenses/{expense_id}_{timestamp}.{ext}
  ```
* **Políticas RLS de Storage:**
  * **SELECT:** Apenas usuários autenticados que sejam membros ativos da casa (`public.is_house_member(house_id)`).
  * **INSERT:** Membros da casa, desde que a casa seja Premium (`public.house_plan(house_id) = 'premium'`), com limite de tamanho de 5 MB por arquivo e tipos MIME permitidos (`image/jpeg`, `image/png`, `image/webp`, `application/pdf`).
  * **DELETE:** O autor da despesa, administrador da casa ou a rotina de expurgo do sistema (`service_role`).

### 4.2. Modelo de Dados no Banco
Adição de colunas na tabela `public.house_expenses` (e na entidade Dart `HouseExpense`):

```sql
ALTER TABLE public.house_expenses
  ADD COLUMN IF NOT EXISTS attachment_path TEXT,
  ADD COLUMN IF NOT EXISTS attachment_name TEXT,
  ADD COLUMN IF NOT EXISTS attachment_content_type TEXT,
  ADD COLUMN IF NOT EXISTS attachment_size_bytes INTEGER,
  ADD COLUMN IF NOT EXISTS attachment_purged_at TIMESTAMPTZ;
```

---

## 5. Rotina Automática de Expurgo (Scheduler)

Uma função agendada (`purge-expired-receipts`) executada semanalmente via `pg_cron` no Supabase:

1. **Critério de Busca:**
   Localiza despesas com `attachment_path IS NOT NULL` cujo ciclo financeiro vinculado possua `settlement_status = 'settled'` com data de fechamento superior a 30 dias:
   ```sql
   SELECT id, house_id, attachment_path 
   FROM public.house_expenses e
   JOIN public.financial_cycles c ON c.id = e.cycle_id
   WHERE e.attachment_path IS NOT NULL
     AND c.status = 'closed'
     AND c.closed_at < (NOW() - INTERVAL '30 days');
   ```
2. **Remoção Física:** A Edge Function remove os arquivos do bucket através da API de Storage (`supabase.storage.from('receipts').remove([path])`).
3. **Atualização do Registro:** Atualiza a despesa:
   ```sql
   UPDATE public.house_expenses
   SET attachment_path = NULL,
       attachment_purged_at = NOW()
   WHERE id = e.id;
   ```

---

## 6. Experiência no App (Flutter)

### 6.1. No Formulário de Despesa (`AddExpensePage`)
* **Em Casas Premium:**
  * Botão ativo *"Anexar Comprovante / Nota"*.
  * Abre o seletor nativo (`FilePicker` ou câmera).
  * O app redimensiona imagens grandes para no máximo 1600px de largura com compressão JPEG 80% (reduzindo arquivos de 6 MB para ~300 KB antes do envio).
  * Exibe barra de progresso de upload com opção de remover ou trocar antes de salvar.
  * Legenda sutil: *"Disponível para conferência até 30 dias após o fechamento do ciclo."*
* **Em Casas Free:**
  * Indicador discreto `Comprovante / Cupom ⭐`.
  * Sem bloqueios nem popups invasivos.

### 6.2. No Scanner Inteligente (`SmartScannerPage`)
* Em casas Free: a IA lê a nota e extrai todos os itens e valores normalmente para a despesa. O fluxo termina normalmente.
* Em casas Premium: além da extração, inclui o toggle opcional:
  * `[x] Salvar documento como anexo da despesa`

### 6.3. Na Timeline e Detalhes da Despesa (`ExpenseTimelineItem`)
* **Se o comprovante existir (Casa Premium):**
  * Exibe miniatura ou ícone de PDF com nome do arquivo e tamanho.
  * Botão **"Ver Comprovante"**: abre modal com visualizador interativo (zoom, pan, rotação ou leitor de PDF).
  * Botão **"Baixar"**: faz o download do arquivo original para o aparelho (`FilePicker.saveFile`).
* **Se o comprovante tiver sido expurgado:**
  * Mostra etiqueta informativa discreta: *"Comprovante arquivado após o fechamento do ciclo de MM/AAAA."*

---

## 6. Etapas de Implementação

| Etapa | O que fazer | Dependência |
|---|---|---|
| **Fase 1: Storage & Banco** | Migration para criar colunas na `house_expenses` e criar o bucket `receipts` com políticas RLS por casa | — |
| **Fase 2: Upload no App** | Implementar `AttachmentService` (compressão de imagem + upload para o bucket) e ligar em `AddExpensePage` e `SmartScannerPage` | Fase 1 |
| **Fase 3: Visualização e Download** | Adicionar visualizador em modal (`InteractiveViewer`) e botão de download na tela de detalhes da despesa | Fase 2 |
| **Fase 4: Rotina de Expurgo** | Edge Function `purge-expired-receipts` e agendamento `pg_cron` no Supabase | Fase 1 |
| **Fase 5: Termos e LGPD** | Atualizar Termos de Uso e Política de Privacidade refletindo o prazo de retenção do Modelo A | — |
