import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { GeminiProvider } from '../_shared/ai_provider.ts';
import { maskSensitiveData } from '../_shared/mask.ts';

export interface DocumentItemProposal {
  title: string;
  amount_cents: number;
  category_hint?: string;
  is_common_expense: boolean; // true para despesas ordinárias do lar; false para obras/reserva (proprietário)
}

export interface DocumentAnalysisResult {
  title: string;
  total_cents: number;
  due_date?: string;
  issue_date?: string;
  barcode?: string;
  category_suggestion: string;
  confidence: number;
  is_itemized: boolean;
  items: DocumentItemProposal[];
  merchant_name?: string;
  merchant_cnpj?: string;
  raw_notes?: string;
}

const OCR_PROMPT = `
Você é o assistente contábil e auditor inteligente do Omni Lar, um aplicativo de gestão financeira para lares compartilhados e repúblicas.
Sua missão é extrair com precisão cirúrgica todas as informações da imagem enviada (recibo, cupom fiscal NFC-e, boleto bancário ou demonstrativo de condomínio).

REGRAS DE CONVERSÃO FINANCEIRA:
1. Todos os valores monetários DEVEM ser retornados em CENTAVOS (inteiros, ex: R$ 150,50 vira 15050; R$ 800,00 vira 80000).
2. Se o documento for um BOLETO DE CONDOMÍNIO com demonstrativo detalhado de cobrança:
   - Marque 'is_itemized' como true.
   - Desmembre cada linha do rateio no array 'items':
     * Taxa de Condomínio / Cota Ordinária -> 'is_common_expense': true
     * Consumo de Água / Esgoto -> 'is_common_expense': true
     * Consumo de Gás -> 'is_common_expense': true
     * Fundo de Reserva / Obras Estruturais / Manutenção Predial -> 'is_common_expense': false (deverá ser rateado com o proprietário do imóvel)
   - A soma de todos os 'amount_cents' dos sub-itens deve bater com o 'total_cents' do boleto.
3. Se for cupom de supermercado/farmácia com itens avulsos:
   - Marque 'is_itemized' como true apenas se os itens individuais estiverem legíveis.
4. Identifique o código de barras ou linha digitável numérica do boleto se presente.
5. Datas devem estar no formato ISO YYYY-MM-DD.

Retorne EXCLUSIVAMENTE um objeto JSON válido seguindo a estrutura:
{
  "title": string,
  "total_cents": number,
  "due_date": string | null,
  "issue_date": string | null,
  "barcode": string | null,
  "category_suggestion": string,
  "confidence": number,
  "is_itemized": boolean,
  "items": [
    {
      "title": string,
      "amount_cents": number,
      "category_hint": string,
      "is_common_expense": boolean
    }
  ],
  "merchant_name": string | null,
  "merchant_cnpj": string | null,
  "raw_notes": string | null
}
`;

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const {
      imageBase64,
      mimeType = 'image/jpeg',
      ocrRawText,
      userApiKey,
      userModel,
    } = body;

    if (!imageBase64 && !ocrRawText) {
      return new Response(
        JSON.stringify({ error: 'Nenhuma imagem ou texto de documento fornecido para processamento.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Chave ou modelo podem vir no corpo JSON ou nos cabeçalhos HTTP
    const headerKey = req.headers.get('x-user-gemini-key') || undefined;
    const headerModel = req.headers.get('x-user-gemini-model') || undefined;
    const effectiveApiKey = userApiKey || headerKey;
    const effectiveModel = userModel || headerModel;

    const provider = new GeminiProvider(effectiveApiKey, effectiveModel);

    let fullPrompt = OCR_PROMPT;
    if (ocrRawText) {
      const sanitizedText = maskSensitiveData(ocrRawText);
      fullPrompt += `\n\nTEXTO BRUTO PRÉ-EXTRAÍDO VIA OCR NATIVO DO DISPOSITIVO:\n${sanitizedText}`;
    }

    const response = await provider.generateStructuredJson<DocumentAnalysisResult>(
      fullPrompt,
      imageBase64,
      mimeType,
    );

    const result = response.data;

    // Validação de consistência de centavos: se itemized, verifica o balanço dos sub-itens
    if (result.is_itemized && result.items && result.items.length > 0) {
      const itemsSum = result.items.reduce((sum, it) => sum + (it.amount_cents || 0), 0);
      if (itemsSum !== result.total_cents) {
        result.raw_notes = (result.raw_notes ? result.raw_notes + '. ' : '') +
          `Aviso de conferência: soma dos sub-itens (${itemsSum}) difere do valor total (${result.total_cents}).`;
      }
    }

    return new Response(JSON.stringify({ success: true, analysis: result }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error: any) {
    return new Response(
      JSON.stringify({ success: false, error: error?.message || 'Erro inesperado no OCR/IA.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
