/**
 * Provedor agnóstico de IA com implementação para o Google AI Studio (Gemini Flash).
 * A chave GEMINI_API_KEY reside nos segredos de ambiente da Edge Function,
 * com suporte nativo ao modelo BYOK (Bring Your Own Key) configurado pelo usuário.
 */

export interface StructuredAiResponse<T> {
  data: T;
  rawText: string;
  tokensUsed?: number;
}

export interface ChatMessagePart {
  role: 'user' | 'model';
  text: string;
}

/**
 * 'minute' = limite por minuto (passa esperando); 'day' = cota diária (esperar não adianta);
 * 'server' = Gemini sobrecarregado ou fora do ar; 'invalid' = pedido ou resposta inválida.
 */
export type AiErrorScope = 'minute' | 'day' | 'server' | 'invalid';

export class GeminiQuotaExhaustedError extends Error {
  public readonly isCustomKey: boolean;
  public readonly status: number;
  public readonly scope: AiErrorScope;
  public readonly retryAfterS?: number;

  constructor(
    message: string,
    isCustomKey: boolean,
    status = 429,
    scope: AiErrorScope = 'minute',
    retryAfterS?: number,
  ) {
    super(message);
    this.name = 'GeminiQuotaExhaustedError';
    this.isCustomKey = isCustomKey;
    this.status = status;
    this.scope = scope;
    this.retryAfterS = retryAfterS;
  }
}

/** Gemini sobrecarregado (500/503/504) ou sem rede, mesmo depois das tentativas automáticas. */
export class GeminiBusyError extends Error {
  public readonly status: number;
  public readonly scope: AiErrorScope = 'server';
  public readonly retryAfterS: number;

  constructor(message: string, status = 503, retryAfterS = 20) {
    super(message);
    this.name = 'GeminiBusyError';
    this.status = status;
    this.retryAfterS = retryAfterS;
  }
}

/** Espera máxima absorvida dentro da própria função antes de devolver o erro ao app. */
const MAX_INLINE_WAIT_S = 10;
const MAX_ATTEMPTS = 3;
const TRANSIENT_STATUS = new Set([500, 502, 503, 504]);

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Atraso de 1s, 2s... com variação aleatória, para não repetir no mesmo instante. */
function backoffMs(attempt: number): number {
  return 1000 * 2 ** attempt + Math.floor(Math.random() * 500);
}

/** Lê o escopo e a espera sugerida de um 429 do Gemini (QuotaFailure e RetryInfo). */
export function classifyQuotaError(
  status: number,
  errorBody: string,
  retryAfterHeader?: string | null,
): { scope: AiErrorScope; retryAfterS?: number } {
  let retryAfterS: number | undefined;
  const header = Number(retryAfterHeader);
  if (retryAfterHeader && Number.isFinite(header) && header >= 0) retryAfterS = Math.ceil(header);

  let quotaIds = '';
  try {
    const details = JSON.parse(errorBody)?.error?.details;
    if (Array.isArray(details)) {
      for (const d of details) {
        const type = String(d?.['@type'] ?? '');
        if (type.endsWith('RetryInfo') && typeof d.retryDelay === 'string') {
          const seconds = parseFloat(d.retryDelay);
          if (Number.isFinite(seconds)) retryAfterS = Math.ceil(seconds);
        }
        if (type.endsWith('QuotaFailure') && Array.isArray(d.violations)) {
          quotaIds += d.violations.map((v: any) => `${v?.quotaId ?? ''} ${v?.quotaMetric ?? ''}`).join(' ');
        }
      }
    }
  } catch (_) {
    // Corpo que não é JSON: segue só com o texto
  }

  const text = `${quotaIds} ${errorBody}`.toLowerCase();
  if (text.includes('perday') || text.includes('per day') || text.includes('daily')) {
    return { scope: 'day' };
  }
  // Sem sinal de cota diária: tratamos como limite por minuto, com espera padrão se o Google não disse
  return { scope: 'minute', retryAfterS: retryAfterS ?? 30 };
}

export interface AiProvider {
  generateStructuredJson<T>(
    prompt: string,
    imageBase64?: string,
    mimeType?: string,
  ): Promise<StructuredAiResponse<T>>;

  generateChatJson<T>(params: {
    systemInstruction?: string;
    contents: ChatMessagePart[];
    temperature?: number;
  }): Promise<StructuredAiResponse<T>>;
}

export class GeminiProvider implements AiProvider {
  private readonly apiKey: string;
  private readonly model: string;

  constructor(userApiKey?: string, userModel?: string) {
    // 1. Prioridade: Chave e modelo customizados pelo usuário (BYOK - Bring Your Own Key)
    // 2. Fallback: Chave e modelo padrão do sistema configurados nos segredos do Supabase
    this.apiKey = userApiKey?.trim() || Deno.env.get('GEMINI_API_KEY') || '';
    this.model = userModel?.trim() || Deno.env.get('AI_MODEL_CHAT') || Deno.env.get('AI_MODEL_VISION') || 'gemini-1.5-flash';

    if (!this.apiKey) {
      throw new Error(
        'Nenhuma chave de IA configurada. ' +
        'Adicione sua chave gratuita do Google AI Studio em Ajustes > Assistente IA no app ou assine o plano Pro.',
      );
    }
  }

  get usingCustomKey(): boolean {
    return Boolean(this.apiKey && this.apiKey !== Deno.env.get('GEMINI_API_KEY'));
  }

  get effectiveModel(): string {
    return this.model;
  }

  async generateStructuredJson<T>(
    prompt: string,
    imageBase64?: string,
    mimeType = 'image/jpeg',
  ): Promise<StructuredAiResponse<T>> {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;

    const parts: any[] = [{ text: prompt }];

    if (imageBase64) {
      parts.push({
        inlineData: {
          mimeType,
          data: imageBase64,
        },
      });
    }

    const payload = {
      contents: [
        {
          role: 'user',
          parts,
        },
      ],
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: 0.1, // Alta determinística para extração financeira
      },
    };

    return this._executePost<T>(url, payload);
  }

  async generateChatJson<T>(params: {
    systemInstruction?: string;
    contents: ChatMessagePart[];
    temperature?: number;
  }): Promise<StructuredAiResponse<T>> {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;

    const payload: any = {
      contents: params.contents.map((c) => ({
        role: c.role,
        parts: [{ text: c.text }],
      })),
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: params.temperature ?? 0.2,
      },
    };

    if (params.systemInstruction) {
      payload.systemInstruction = {
        parts: [{ text: params.systemInstruction }],
      };
    }

    return this._executePost<T>(url, payload);
  }

  private async _executePost<T>(url: string, payload: any): Promise<StructuredAiResponse<T>> {
    const body = JSON.stringify(payload);
    let response: Response | undefined;

    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const isLast = attempt === MAX_ATTEMPTS - 1;
      try {
        response = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body,
        });
      } catch (_) {
        // Falha de rede: tenta de novo e, esgotadas as tentativas, avisa que o serviço está ocupado
        if (isLast) throw new GeminiBusyError('A leitura por IA não respondeu agora.', 503);
        await sleep(backoffMs(attempt));
        continue;
      }

      if (response.ok) break;

      const errorBody = await response.text();
      // Detecção de cota/tokens esgotados no Google AI Studio (RESOURCE_EXHAUSTED / 429)
      if (
        response.status === 429 ||
        errorBody.includes('RESOURCE_EXHAUSTED') ||
        errorBody.toLowerCase().includes('quota')
      ) {
        const { scope, retryAfterS } = classifyQuotaError(
          response.status,
          errorBody,
          response.headers.get('retry-after'),
        );
        // Espera curta de limite por minuto é absorvida aqui, sem o app perceber
        if (scope === 'minute' && !isLast && retryAfterS !== undefined && retryAfterS <= MAX_INLINE_WAIT_S) {
          await sleep(retryAfterS * 1000 + Math.floor(Math.random() * 500));
          continue;
        }
        const msg = scope === 'day'
          ? (this.usingCustomKey
            ? 'A cota diária da sua chave pessoal do Google AI Studio foi esgotada. Confira sua cota no AI Studio.'
            : 'A cota diária gratuita do app foi esgotada temporariamente. Você pode cadastrar sua chave gratuita do Google AI Studio em Ajustes.')
          : (this.usingCustomKey
            ? 'O limite de requisições por minuto da sua chave pessoal do Google AI Studio foi atingido. Aguarde um instante.'
            : 'A leitura por IA está com muitos pedidos neste minuto. Aguarde um instante.');
        throw new GeminiQuotaExhaustedError(msg, this.usingCustomKey, response.status, scope, retryAfterS);
      }

      if (TRANSIENT_STATUS.has(response.status)) {
        if (isLast) throw new GeminiBusyError('A leitura por IA está sobrecarregada agora.', response.status);
        await sleep(backoffMs(attempt));
        continue;
      }

      throw new Error(`Erro na API do Gemini (${response.status}): ${errorBody}`);
    }

    if (!response || !response.ok) {
      throw new GeminiBusyError('A leitura por IA não respondeu agora.', 503);
    }

    const json = await response.json();
    const candidate = json.candidates?.[0];
    const textContent = candidate?.content?.parts?.[0]?.text;

    if (!textContent) {
      throw new Error('Nenhuma resposta gerada pelo modelo.');
    }

    try {
      const parsedData = JSON.parse(textContent) as T;
      return {
        data: parsedData,
        rawText: textContent,
        tokensUsed: json.usageMetadata?.totalTokenCount,
      };
    } catch (e) {
      throw new Error(`Falha ao deserializar JSON gerado pelo modelo: ${textContent}`);
    }
  }
}
