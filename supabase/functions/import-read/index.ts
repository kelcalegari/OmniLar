import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { GeminiProvider } from '../_shared/ai_provider.ts';
import { maskSensitiveData } from '../_shared/mask.ts';
import { checkAiDailyQuota, recordAiUsage } from '../_shared/usage.ts';
import { HttpError, requireHouseMember } from '../_shared/auth.ts';

// ~7,5 MB de arquivo em base64
const MAX_FILE_BASE64_CHARS = 10_000_000;
const MAX_LINES_TO_CLASSIFY = 300;

const LINE_TYPES = ['purchase', 'refund', 'payment', 'income'] as const;
type LineType = (typeof LINE_TYPES)[number];

export interface StatementLine {
  date: string;
  description: string;
  amount_cents: number;
  type: LineType;
  installment_number: number | null;
  installments_total: number | null;
}

export interface StatementReading {
  lines: StatementLine[];
  due_date: string | null;
  total_cents: number | null;
  card_last_digits: string | null;
  period_start: string | null;
  period_end: string | null;
  /** Compras menos estornos das linhas lidas, para conferir com o total impresso. */
  lines_sum_cents: number;
}

export interface LineClassification {
  id: string;
  title: string | null;
  category_id: string | null;
}

const READ_PROMPT = (sourceType: string) => `
Você lê ${sourceType === 'bank_statement' ? 'extratos de conta bancária' : 'faturas de cartão de crédito'} brasileiros para o Omni Lar, um app de finanças de casas compartilhadas.
Extraia TODOS os lançamentos do documento, na ordem em que aparecem, sem resumir, agrupar nem inventar linhas.

REGRAS:
1. "amount_cents" é sempre um inteiro POSITIVO em centavos (R$ 150,50 vira 15050). O sentido do lançamento vai em "type".
2. "type":
   - "purchase": compra no cartão ou saída da conta (débito, Pix enviado, boleto pago, tarifa, juros, IOF, anuidade).
   - "refund": estorno ou crédito de uma compra.
   - "payment": pagamento da fatura (na fatura: "pagamento recebido"; no extrato: saída que paga a fatura de um cartão).
   - "income": entrada na conta (Pix recebido, salário, transferência recebida).
3. "date" é a data do lançamento no formato YYYY-MM-DD. Se o documento mostrar só dia e mês, use o ano do período do documento. NUNCA use anos de rodapé, copyright ou avisos legais (ex: "© 2020"). Se o ano não for explícito na fatura, use o ano corrente (${new Date().getFullYear()}).
4. "description" é o texto do lançamento exatamente como aparece, sem a data e sem o valor.
5. Compra parcelada ("03/10", "Parcela 3 de 10"): preencha "installment_number" e "installments_total"; senão, null.
6. NÃO inclua linhas de saldo, subtotal, total, limite, encargos projetados nem lançamentos futuros.
7. Do cabeçalho: "due_date" (vencimento da fatura - nunca use ano de copyright do rodapé), "total_cents" (total da fatura ou, no extrato, null), "card_last_digits" (4 últimos dígitos do cartão), "period_start" e "period_end". O que não estiver no documento fica null.
8. Nunca copie CPF, número completo de cartão ou de conta para a resposta.

Retorne EXCLUSIVAMENTE um objeto JSON:
{
  "lines": [
    { "date": string, "description": string, "amount_cents": number, "type": "purchase" | "refund" | "payment" | "income", "installment_number": number | null, "installments_total": number | null }
  ],
  "due_date": string | null,
  "total_cents": number | null,
  "card_last_digits": string | null,
  "period_start": string | null,
  "period_end": string | null
}
`;

const CLASSIFY_PROMPT = `
Você organiza lançamentos de fatura e extrato para o Omni Lar, um app de finanças de casas compartilhadas no Brasil.
Para cada lançamento recebido, devolva:
- "title": o nome do estabelecimento como uma pessoa escreveria ("PAO DE ACUCAR LJ 1234 SAO PAULO BR" vira "Pão de Açúcar"), sem cidade, número de loja, parcela ou código do intermediador de pagamento.
- "category_id": o id da categoria da lista que melhor descreve o gasto, ou null se nenhuma servir ou se não der para saber. NUNCA invente um id fora da lista.

Não decida se o gasto é da casa ou pessoal: isso é escolha do usuário.

Retorne EXCLUSIVAMENTE um objeto JSON:
{ "items": [ { "id": string, "title": string | null, "category_id": string | null } ] }
`;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isoDateOrNull(value: unknown): string | null {
  return typeof value === 'string' && DATE_RE.test(value) && !Number.isNaN(Date.parse(value)) ? value : null;
}

function positiveIntOrNull(value: unknown): number | null {
  const n = typeof value === 'number' ? Math.round(value) : NaN;
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** Aceita só o que tem data, descrição e valor válidos: o resto é descartado. */
export function sanitizeReading(raw: any): StatementReading {
  const lines: StatementLine[] = [];
  for (const item of Array.isArray(raw?.lines) ? raw.lines : []) {
    const date = isoDateOrNull(item?.date);
    const amount = positiveIntOrNull(item?.amount_cents);
    const description = typeof item?.description === 'string' ? maskSensitiveData(item.description.trim()) : '';
    if (!date || !amount || !description) continue;

    const number = positiveIntOrNull(item?.installment_number);
    const total = positiveIntOrNull(item?.installments_total);
    const isInstallment = number !== null && total !== null && total >= 2 && number <= total;

    lines.push({
      date,
      description: description.slice(0, 200),
      amount_cents: amount,
      type: LINE_TYPES.includes(item?.type) ? item.type : 'purchase',
      installment_number: isInstallment ? number : null,
      installments_total: isInstallment ? total : null,
    });
  }

  const digits = typeof raw?.card_last_digits === 'string' ? raw.card_last_digits.replace(/\D/g, '') : '';
  return {
    lines,
    due_date: isoDateOrNull(raw?.due_date),
    total_cents: positiveIntOrNull(raw?.total_cents),
    card_last_digits: digits.length >= 4 ? digits.slice(-4) : null,
    period_start: isoDateOrNull(raw?.period_start),
    period_end: isoDateOrNull(raw?.period_end),
    lines_sum_cents: lines.reduce(
      (sum, line) =>
        line.type === 'purchase' ? sum + line.amount_cents : line.type === 'refund' ? sum - line.amount_cents : sum,
      0,
    ),
  };
}

/** Só devolve linhas que foram enviadas e categorias que existem na lista. */
export function sanitizeClassification(
  raw: any,
  sentIds: Set<string>,
  categoryIds: Set<string>,
): LineClassification[] {
  const result: LineClassification[] = [];
  const seen = new Set<string>();
  for (const item of Array.isArray(raw?.items) ? raw.items : []) {
    const id = typeof item?.id === 'string' ? item.id : '';
    if (!sentIds.has(id) || seen.has(id)) continue;
    seen.add(id);
    const title = typeof item?.title === 'string' ? item.title.trim().slice(0, 80) : '';
    const categoryId = typeof item?.category_id === 'string' ? item.category_id : '';
    result.push({
      id,
      title: title || null,
      category_id: categoryIds.has(categoryId) ? categoryId : null,
    });
  }
  return result;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { mode, userApiKey, userModel, houseId: requestedHouseId } = body;

    const { userId, houseId, supabaseClient } = await requireHouseMember(req, requestedHouseId);

    if (mode !== 'read' && mode !== 'classify') {
      return json({ success: false, error: 'Modo inválido.' }, 400);
    }

    // Chave ou modelo podem vir no corpo JSON ou nos cabeçalhos HTTP
    const effectiveApiKey = userApiKey || req.headers.get('x-user-gemini-key') || undefined;
    const effectiveModel = userModel || req.headers.get('x-user-gemini-model') || undefined;
    const hasCustomKey = Boolean(effectiveApiKey && effectiveApiKey.trim().length > 0);

    // Cota diária da casa (só quando usa a chave do sistema)
    const quotaCheck = await checkAiDailyQuota(supabaseClient, houseId, userId, hasCustomKey);
    if (!quotaCheck.allowed) {
      await recordAiUsage(supabaseClient, {
        houseId,
        memberId: userId,
        feature: 'import',
        model: effectiveModel || 'system-quota',
        status: 'rate_limited',
      });
      return json(
        {
          success: false,
          error:
            'A cota diária gratuita de IA desta casa foi atingida. ' +
            'Adicione sua chave gratuita do Google AI Studio em Ajustes > Assistente IA para continuar.',
          rateLimited: true,
        },
        429,
      );
    }

    const provider = new GeminiProvider(effectiveApiKey, effectiveModel);
    const recordSuccess = (tokens?: number) =>
      recordAiUsage(supabaseClient, {
        houseId,
        memberId: userId,
        feature: 'import',
        model: provider.effectiveModel,
        tokensIn: 0,
        tokensOut: tokens || 0,
        status: 'success',
      });

    if (mode === 'read') {
      const { fileBase64, mimeType, sourceType } = body;
      if (typeof fileBase64 !== 'string' || fileBase64.length === 0) {
        return json({ success: false, error: 'Nenhum arquivo enviado para leitura.' }, 400);
      }
      if (fileBase64.length > MAX_FILE_BASE64_CHARS) {
        return json({ success: false, error: 'Arquivo grande demais para leitura. Envie um arquivo menor.' }, 413);
      }

      const response = await provider.generateStructuredJson<unknown>(
        READ_PROMPT(sourceType === 'bank_statement' ? 'bank_statement' : 'credit_card'),
        fileBase64,
        typeof mimeType === 'string' && mimeType ? mimeType : 'application/pdf',
      );
      await recordSuccess(response.tokensUsed);

      const reading = sanitizeReading(response.data);
      if (reading.lines.length === 0) {
        return json(
          {
            success: false,
            error:
              'Não encontrei lançamentos neste arquivo. Se o PDF tem senha, baixe a fatura pelo app do banco ou use um arquivo OFX ou CSV.',
          },
          422,
        );
      }
      return json({ success: true, reading });
    }

    // mode === 'classify'
    const sentLines = (Array.isArray(body.lines) ? body.lines : [])
      .filter((l: any) => typeof l?.id === 'string' && typeof l?.description === 'string')
      .slice(0, MAX_LINES_TO_CLASSIFY)
      .map((l: any) => ({ id: l.id as string, description: maskSensitiveData(l.description as string).slice(0, 200) }));
    const categories = (Array.isArray(body.categories) ? body.categories : [])
      .filter((c: any) => typeof c?.id === 'string' && typeof c?.name === 'string')
      .map((c: any) => ({ id: c.id as string, name: (c.name as string).slice(0, 80) }));

    if (sentLines.length === 0) {
      return json({ success: true, items: [] });
    }

    const response = await provider.generateStructuredJson<unknown>(
      `${CLASSIFY_PROMPT}\n\nCATEGORIAS DA CASA:\n${JSON.stringify(categories)}\n\nLANÇAMENTOS:\n${JSON.stringify(sentLines)}`,
    );
    await recordSuccess(response.tokensUsed);

    const items = sanitizeClassification(
      response.data,
      new Set(sentLines.map((l: { id: string }) => l.id)),
      new Set(categories.map((c: { id: string }) => c.id)),
    );
    return json({ success: true, items });
  } catch (error: any) {
    if (error instanceof HttpError) {
      return json({ success: false, error: error.message }, error.status);
    }
    const status = typeof error?.status === 'number' ? error.status : 500;
    return json({ success: false, error: error?.message || 'Erro inesperado na leitura por IA.' }, status);
  }
});
