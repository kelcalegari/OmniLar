import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { GeminiProvider } from '../_shared/ai_provider.ts';
import { maskSensitiveData } from '../_shared/mask.ts';
import { checkAiDailyQuota, recordAiUsage } from '../_shared/usage.ts';
import { HttpError, requireHouseMember } from '../_shared/auth.ts';
import { type NfceAnalysis, allowedUrl, decodeBody, frameUrl, pageText, parseStandardLayout, sefazError } from './page.ts';

/**
 * Consulta a NFC-e pelo link do QR Code: baixa a página pública da Sefaz do
 * estado e devolve loja, data, total e itens no mesmo formato do capture-read.
 * O layout padrão da Sefaz é lido sem IA; outro layout vai para a IA como texto.
 */

const FETCH_TIMEOUT_MS = 15_000;
const MAX_PAGE_BYTES = 3_000_000;
const MAX_REDIRECTS = 5;
const MAX_AI_TEXT_CHARS = 60_000;

const AI_PROMPT = `
Você lê a página pública de consulta de uma NFC-e (cupom fiscal eletrônico) da Sefaz e extrai os dados dela.
Todos os valores em CENTAVOS inteiros (R$ 17,50 vira 1750). Datas no formato YYYY-MM-DD.
- total_cents é o "Valor a pagar" (já com descontos).
- Cada item: descrição, quantidade, valor unitário e valor total do item.
- Se a página disser que a nota não foi encontrada, ainda não foi processada ou houve erro, devolva found=false.

Retorne EXCLUSIVAMENTE um objeto JSON:
{
  "found": boolean,
  "total_cents": number,
  "discount_cents": number,
  "issue_date": string | null,
  "merchant_name": string | null,
  "merchant_cnpj": string | null,
  "items": [{ "title": string, "quantity": number, "unit_cents": number, "amount_cents": number }]
}

TEXTO DA PÁGINA:
`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Baixa a página seguindo redirecionamentos, todos dentro de .gov.br. */
async function fetchPage(start: URL): Promise<{ html: string; url: URL }> {
  let url = start;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    let res: Response;
    try {
      res = await fetch(url, {
        redirect: 'manual',
        signal: controller.signal,
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'pt-BR,pt;q=0.9',
        },
      });
    } catch (e) {
      throw new HttpError(502, controller.signal.aborted
        ? 'A Sefaz demorou demais para responder.'
        : `Não foi possível falar com a Sefaz: ${(e as Error).message}`);
    } finally {
      clearTimeout(timer);
    }

    if (res.status >= 300 && res.status < 400) {
      const next = allowedUrl(res.headers.get('location') || '', url);
      await res.body?.cancel();
      if (!next) throw new HttpError(502, 'A Sefaz redirecionou para um endereço fora do governo.');
      url = next;
      continue;
    }
    if (!res.ok) {
      await res.body?.cancel();
      throw new HttpError(502, `A Sefaz respondeu com erro (${res.status}).`);
    }

    const buffer = new Uint8Array(await res.arrayBuffer());
    if (buffer.length > MAX_PAGE_BYTES) throw new HttpError(502, 'A página da Sefaz veio grande demais.');
    return { html: decodeBody(buffer, res.headers.get('content-type')), url };
  }
  throw new HttpError(502, 'A Sefaz redirecionou vezes demais.');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { url: rawUrl, userApiKey, userModel, houseId: requestedHouseId } = body;

    const { userId, houseId, supabaseClient } = await requireHouseMember(req, requestedHouseId);

    const start = typeof rawUrl === 'string' ? allowedUrl(rawUrl.trim()) : null;
    if (!start) {
      return json({ success: false, error: 'O QR lido não é um link de consulta da Sefaz.' }, 400);
    }

    let page = await fetchPage(start);
    let parsed = parseStandardLayout(page.html);
    if (!parsed && pageText(page.html).length < 400) {
      const frame = frameUrl(page.html, page.url);
      if (frame) {
        page = await fetchPage(frame);
        parsed = parseStandardLayout(page.html);
      }
    }

    if (parsed) {
      return json({ success: true, source: 'sefaz', analysis: parsed });
    }

    const refusal = sefazError(page.html);
    if (refusal) {
      return json({ success: false, error: `A Sefaz recusou a consulta: ${refusal}.` }, 404);
    }

    // Layout desconhecido: a IA lê o texto da página
    const text = maskSensitiveData(pageText(page.html)).slice(0, MAX_AI_TEXT_CHARS);
    if (text.length < 80) {
      return json({ success: false, error: 'A página da Sefaz veio vazia. Tente fotografar o cupom.' }, 502);
    }

    const headerKey = req.headers.get('x-user-gemini-key') || undefined;
    const headerModel = req.headers.get('x-user-gemini-model') || undefined;
    const effectiveApiKey = userApiKey || headerKey;
    const effectiveModel = userModel || headerModel;
    const hasCustomKey = Boolean(effectiveApiKey && effectiveApiKey.trim().length > 0);

    const quotaCheck = await checkAiDailyQuota(supabaseClient, houseId, userId, hasCustomKey);
    if (!quotaCheck.allowed) {
      await recordAiUsage(supabaseClient, {
        houseId,
        memberId: userId,
        feature: 'capture',
        model: effectiveModel || 'system-quota',
        status: 'rate_limited',
      });
      return json({
        success: false,
        error: 'A cota diária gratuita de leitura de documentos desta casa foi atingida. ' +
          'Adicione sua chave gratuita do Google AI Studio em Ajustes > Assistente IA para continuar.',
        rateLimited: true,
      }, 429);
    }

    const provider = new GeminiProvider(effectiveApiKey, effectiveModel);
    const response = await provider.generateStructuredJson<NfceAnalysis>(AI_PROMPT + text);
    await recordAiUsage(supabaseClient, {
      houseId,
      memberId: userId,
      feature: 'capture',
      model: provider.effectiveModel,
      tokensOut: response.tokensUsed || 0,
      status: 'success',
    });

    const ai = response.data;
    if (!ai || ai.found === false) {
      return json({
        success: false,
        error: 'A Sefaz não mostrou esta nota (pode ainda não ter sido processada). Tente de novo em alguns minutos ou fotografe o cupom.',
      }, 404);
    }
    const items = (ai.items || [])
      .filter((it) => it && it.title && it.amount_cents > 0)
      .map((it) => ({ ...it, quantity: it.quantity > 0 ? it.quantity : 1, is_common_expense: true }));
    return json({
      success: true,
      source: 'ai',
      analysis: {
        ...ai,
        found: true,
        title: ai.merchant_name || 'Nota Fiscal (NFC-e)',
        is_itemized: items.length > 0,
        items,
      },
    });
  } catch (error: any) {
    if (error instanceof HttpError) {
      return json({ success: false, error: error.message }, error.status);
    }
    return json({ success: false, error: error?.message || 'Erro inesperado ao consultar a nota.' }, 500);
  }
});
