import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { GeminiProvider, GeminiQuotaExhaustedError } from '../_shared/ai_provider.ts';
import { maskSensitiveData } from '../_shared/mask.ts';
import { checkAiDailyQuota, recordAiUsage } from '../_shared/usage.ts';
import { HttpError, requireHouseMember } from '../_shared/auth.ts';
import {
  type NfceAnalysis,
  allowedUrl,
  asksForCaptcha,
  decodeBody,
  frameUrl,
  pageText,
  parseStandardLayout,
  sefazError,
} from './page.ts';

/**
 * Consulta a NFC-e pelo link do QR Code: baixa a página pública da Sefaz do
 * estado e devolve loja, data, total e itens no mesmo formato do capture-read.
 * O layout padrão da Sefaz é lido sem IA; outro layout vai para a IA como texto.
 *
 * Falha devolve `reason` (unavailable, captcha, not_found, invalid_qr, quota)
 * com uma mensagem simples; o detalhe técnico fica só no log da função.
 */

const FETCH_TIMEOUT_MS = 15_000;
const MAX_PAGE_BYTES = 3_000_000;
const MAX_REDIRECTS = 5;
const MAX_AI_TEXT_CHARS = 60_000;

type FailureReason = 'unavailable' | 'captcha' | 'not_found' | 'invalid_qr' | 'quota';

const MESSAGES: Record<FailureReason, string> = {
  unavailable: 'A Sefaz não respondeu agora.',
  captcha: 'A Sefaz deste estado não libera a consulta automática.',
  not_found: 'A nota ainda não aparece na Sefaz; pode levar alguns minutos depois da compra.',
  invalid_qr: 'Esse QR não parece ser de uma nota fiscal.',
  quota: 'A cota diária gratuita de leitura de documentos desta casa foi atingida. ' +
    'Adicione sua chave gratuita do Google AI Studio em Ajustes > Assistente IA para continuar.',
};

const STATUS: Record<FailureReason, number> = {
  unavailable: 502,
  captcha: 422,
  not_found: 404,
  invalid_qr: 400,
  quota: 429,
};

/** Consulta que não deu certo: o motivo vai para o app, o detalhe para o log. */
class LookupFailure extends Error {
  constructor(public readonly reason: FailureReason, public readonly detail: string) {
    super(MESSAGES[reason]);
  }
}

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
      throw new LookupFailure('unavailable', controller.signal.aborted
        ? `timeout em ${url.host}`
        : `falha de rede em ${url.host}: ${(e as Error).message}`);
    } finally {
      clearTimeout(timer);
    }

    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get('location') || '';
      const next = allowedUrl(location, url);
      await res.body?.cancel();
      if (!next) throw new LookupFailure('unavailable', `redirecionou para fora do governo: ${location}`);
      url = next;
      continue;
    }
    if (!res.ok) {
      await res.body?.cancel();
      throw new LookupFailure('unavailable', `HTTP ${res.status} em ${url.host}`);
    }

    const buffer = new Uint8Array(await res.arrayBuffer());
    if (buffer.length > MAX_PAGE_BYTES) throw new LookupFailure('unavailable', `página de ${buffer.length} bytes`);
    return { html: decodeBody(buffer, res.headers.get('content-type')), url };
  }
  throw new LookupFailure('unavailable', 'redirecionamentos demais');
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
      throw new LookupFailure('invalid_qr', `endereço fora da Sefaz: ${String(rawUrl).slice(0, 120)}`);
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

    if (asksForCaptcha(page.html) || /SecurityVerify/i.test(page.url.pathname)) {
      throw new LookupFailure('captcha', `verificação de pessoa em ${page.url.host}`);
    }

    const refusal = sefazError(page.html);
    if (refusal) {
      const notFound = /n[aã]o (?:foi )?(?:encontrad|localizad)/i.test(refusal);
      throw new LookupFailure(notFound ? 'not_found' : 'invalid_qr', `${page.url.host}: ${refusal}`);
    }

    // Layout desconhecido: a IA lê o texto da página
    const text = maskSensitiveData(pageText(page.html)).slice(0, MAX_AI_TEXT_CHARS);
    if (text.length < 80) {
      throw new LookupFailure('unavailable', `página vazia em ${page.url.host}`);
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
      throw new LookupFailure('quota', `cota da casa ${houseId}`);
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
      throw new LookupFailure('not_found', `IA não achou a nota na página de ${page.url.host}`);
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
    if (error instanceof LookupFailure) {
      console.warn(`nfce-read ${error.reason}: ${error.detail}`);
      return json({ success: false, reason: error.reason, error: error.message }, STATUS[error.reason]);
    }
    if (error instanceof GeminiQuotaExhaustedError) {
      return json({ success: false, reason: 'quota', error: error.message }, 429);
    }
    if (error instanceof HttpError) {
      return json({ success: false, error: error.message }, error.status);
    }
    console.error('nfce-read erro inesperado:', error);
    return json({ success: false, reason: 'unavailable', error: MESSAGES.unavailable }, 500);
  }
});
