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

export class GeminiQuotaExhaustedError extends Error {
  public readonly isCustomKey: boolean;
  public readonly status: number;

  constructor(message: string, isCustomKey: boolean, status = 429) {
    super(message);
    this.name = 'GeminiQuotaExhaustedError';
    this.isCustomKey = isCustomKey;
    this.status = status;
  }
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
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      // Detecção de cota/tokens esgotados no Google AI Studio (RESOURCE_EXHAUSTED / 429)
      if (
        response.status === 429 ||
        errorBody.includes('RESOURCE_EXHAUSTED') ||
        errorBody.toLowerCase().includes('quota')
      ) {
        const msg = this.usingCustomKey
          ? 'Os tokens ou o limite de requisições por minuto da sua chave pessoal do Google AI Studio foram esgotados (RESOURCE_EXHAUSTED). Aguarde 1 minuto ou confira sua cota no AI Studio.'
          : 'A cota diária gratuita do app foi esgotada temporariamente. Você pode cadastrar sua chave gratuita do Google AI Studio em Ajustes.';
        throw new GeminiQuotaExhaustedError(msg, this.usingCustomKey, response.status);
      }

      throw new Error(`Erro na API do Gemini (${response.status}): ${errorBody}`);
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
