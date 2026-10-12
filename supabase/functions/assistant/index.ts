import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { GeminiProvider, ChatMessagePart } from '../_shared/ai_provider.ts';
import { maskSensitiveData } from '../_shared/mask.ts';
import { checkAiDailyQuota, recordAiUsage } from '../_shared/usage.ts';
import { HttpError, requireHouseMember } from '../_shared/auth.ts';

interface AssistantActionProposalPayload {
  id: string;
  title: string;
  description: string;
  toolName: string;
  arguments: Record<string, unknown>;
  isHighRisk?: boolean;
}

interface AssistantResponsePayload {
  textResponse: string;
  actions: AssistantActionProposalPayload[];
  suggestions: string[];
}

const SYSTEM_PROMPT = `
Você é o Assistente Inteligente do Omni Lar, um aplicativo de gestão financeira, divisão de despesas e convivência para repúblicas, famílias e casais.

DIRETRIZES E REGRAS INEGOCIÁVEIS:
1. IDIOMA E TOM: Responda sempre em português do Brasil (pt-BR), de forma concisa, educada e empática.
2. CÓDIGO PRIMEIRO, IA DETERMINÍSTICA: Você NÃO inventa nem calcula valores finais complexos.
3. VALORES MONETÁRIOS: Todos os valores numéricos em dinheiro DEVEM estar em CENTAVOS (inteiros). Exemplo: R$ 50,00 -> 5000; R$ 120,50 -> 12050; R$ 10,00 -> 1000.
4. NADA É GRAVADO SEM CONFIRMAÇÃO (RN01):
   - Quando o usuário pedir para lançar despesa, adicionar item na lista, criar evento ou tarefa, você DEVE gerar uma proposta no array 'actions'.
   - O aplicativo apresentará um Cartão de Confirmação na tela. O usuário precisará clicar em "Confirmar" antes de qualquer alteração real no banco.
5. FERRAMENTAS SUPORTADAS NO ARRAY 'actions':
   - 'finance.addExpense': Lança despesa da casa.
     Argumentos: { "title": string, "cents": number, "paidByMemberId": string, "paymentMethodId"?: string, "paymentMethodName"?: string, "categoryHint"?: string }
   - 'finance.addContribution': Registra aporte no Caixa da Casa (Fundo Comum).
     Argumentos: { "cents": number, "memberId": string, "paymentMethodId"?: string, "paymentMethodName"?: string }
   - 'shopping.addItem': Adiciona item na lista de compras.
     Argumentos: { "name": string, "quantity": number, "unit": string }
   - 'shopping.toggleBought': Marca item como comprado na lista de compras.
     Argumentos: { "itemName": string }
   - 'calendar.addEvent': Cria evento/compromisso na agenda da casa.
     Argumentos: { "title": string, "dateIso": string, "description"?: string }
   - 'tasks.addTask': Cria tarefa da casa.
     Argumentos: { "title": string, "assignedToMemberId"?: string, "dueDateIso"?: string }
6. SIMULAÇÕES E PLANEJAMENTO (RN02 / Seção 4.5):
   - Se o usuário perguntar se cabe no orçamento ou se pode comprar algo (ex: "Dá para comprar uma TV de 2.000 sem estourar o ciclo?"), compare o valor com o Fôlego Livre do contexto.
   - Responda de forma analítica e clara (verde se couber, alerta se faltar), sem gerar nenhuma ação no array 'actions' ([]).
7. REGRA CRÍTICA PARA LANÇAMENTO DE DESPESAS (RN06 - TRATAMENTO DE AMBIGUIDADE / MEIO DE PAGAMENTO):
   - Ao lançar/cadastrar uma despesa da casa ('finance.addExpense'), o MEIO DE PAGAMENTO É OBRIGATÓRIO.
   - SE O USUÁRIO NÃO INFORMOU O MEIO DE PAGAMENTO (exemplo: "cadastrar maçã por 10 reais", "lançar 50 de padaria", "gastei 80 no mercado"):
     * NÃO gere a ação 'finance.addExpense' ainda! O array 'actions' DEVE vir VAZIO ([]).
     * No campo 'textResponse', pergunte educadamente qual meio de pagamento foi utilizado, mencionando o item e o valor em reais (exemplo: "Entendido! Para cadastrar a despesa de Maçã no valor de R$ 10,00, qual meio de pagamento você utilizou?").
     * No array 'suggestions', sugira como opções rápidas os meios de pagamento cadastrados na casa informados no contexto (ex: "Nubank Carlos", "VR Marina", "Conta Conjunta", "Pix").
   - SE O USUÁRIO INFORMOU O MEIO DE PAGAMENTO (na mensagem inicial como "cadastrar maçã por 10 reais no Nubank", OU em resposta à pergunta anterior sobre o meio de pagamento conforme o histórico):
     * Identifique o meio de pagamento correspondente da lista do contexto.
     * Preencha os argumentos "paymentMethodId" (id correspondente) e "paymentMethodName" (nome legível).
     * Inclua o meio de pagamento na descrição da proposta (ex: "Maçã: R$ 10,00 • Meio de Pagamento: Nubank Carlos").
     * Gere a proposta em 'actions' com status de proposta para o Cartão de Confirmação.
7. AÇÕES DE RISCO (RN07):
   - Para perdão de dívidas, renegociação de empréstimo ou exclusões, marque 'isHighRisk: true'.
8. FORMATO DE SAÍDA:
   Retorne EXCLUSIVAMENTE um objeto JSON válido no formato:
   {
     "textResponse": "Texto amigável explicando o resultado ou a proposta preparada",
     "actions": [
       {
         "id": "act_1",
         "title": "Título legível para o cartão",
         "description": "Descrição detalhada dos dados propostos",
         "toolName": "finance.addExpense",
         "arguments": { ... },
         "isHighRisk": false
       }
     ],
     "suggestions": [
       "Sugestão de pergunta rápida 1",
       "Sugestão 2"
     ]
   }
`;

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const {
      message,
      conversationId,
      houseId: requestedHouseId,
      userApiKey,
      userModel,
      contextSummary,
      history = [],
    } = body;

    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: 'Nenhuma mensagem enviada para o assistente.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Identidade e casa vêm do JWT e do banco, nunca do corpo da requisição
    const { userId: memberId, houseId, supabaseClient } = await requireHouseMember(
      req,
      requestedHouseId,
    );

    // 1. Chave customizada (BYOK) via corpo ou cabeçalho HTTP
    const headerKey = req.headers.get('x-user-gemini-key') || undefined;
    const headerModel = req.headers.get('x-user-gemini-model') || undefined;
    const effectiveApiKey = userApiKey || headerKey;
    const effectiveModel = userModel || headerModel;
    const hasCustomKey = Boolean(effectiveApiKey && effectiveApiKey.trim().length > 0);

    // 2. Verificação de cota diária (plano gratuito do sistema)
    const quotaCheck = await checkAiDailyQuota(
      supabaseClient,
      houseId,
      memberId,
      hasCustomKey,
    );

    if (!quotaCheck.allowed) {
      await recordAiUsage(supabaseClient, {
        houseId,
        memberId,
        feature: 'assistant',
        model: effectiveModel || 'system-quota',
        status: 'rate_limited',
      });

      return new Response(
        JSON.stringify({
          error:
            'A cota diária gratuita do assistente para esta casa foi atingida. ' +
            'Adicione sua chave gratuita do Google AI Studio em Ajustes > Assistente IA para continuar utilizando sem limites.',
          rateLimited: true,
          currentCount: quotaCheck.currentCount,
          limit: quotaCheck.limit,
        }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 3. Inicializa provedor de IA com a hierarquia: Chave do Usuário -> Chave Supabase Secrets
    const provider = new GeminiProvider(effectiveApiKey, effectiveModel);

    // 4. Mascaramento de dados sensíveis na mensagem do usuário
    const sanitizedMessage = maskSensitiveData(message);

    // 5. Montagem do prompt com contexto da casa
    let systemInstruction = SYSTEM_PROMPT;
    if (contextSummary && typeof contextSummary === 'string') {
      systemInstruction += `\n\nCONTEXTO ATUAL DA CASA FORNECIDO PELO APP:\n${maskSensitiveData(contextSummary)}`;
    }

    const contents: ChatMessagePart[] = [];
    if (Array.isArray(history)) {
      for (const item of history.slice(-6)) {
        if (item.role === 'user' || item.role === 'model') {
          contents.push({
            role: item.role,
            text: maskSensitiveData(item.text || item.content || ''),
          });
        }
      }
    }

    contents.push({
      role: 'user',
      text: sanitizedMessage,
    });

    // 6. Chamada estruturada ao Gemini
    const aiResponse = await provider.generateChatJson<AssistantResponsePayload>({
      systemInstruction,
      contents,
      temperature: 0.2,
    });

    const parsedData = aiResponse.data;

    // Normaliza IDs das ações se vierem nulas ou vazias
    if (parsedData.actions && Array.isArray(parsedData.actions)) {
      parsedData.actions = parsedData.actions.map((act, index) => ({
        ...act,
        id: act.id || `act_${Date.now()}_${index}`,
      }));
    }

    // 7. Registro de uso
    await recordAiUsage(supabaseClient, {
      houseId,
      memberId,
      feature: 'assistant',
      model: provider.effectiveModel,
      tokensIn: 0,
      tokensOut: aiResponse.tokensUsed || 0,
      status: 'success',
    });

    return new Response(
      JSON.stringify({
        success: true,
        interpretation: parsedData,
        usingCustomKey: provider.usingCustomKey,
        model: provider.effectiveModel,
        conversationId,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error: any) {
    if (error instanceof HttpError) {
      return new Response(
        JSON.stringify({ success: false, error: error.message }),
        { status: error.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const isQuota =
      error?.name === 'GeminiQuotaExhaustedError' ||
      error?.message?.includes('RESOURCE_EXHAUSTED') ||
      error?.message?.includes('cota') ||
      error?.message?.includes('quota');

    return new Response(
      JSON.stringify({
        success: false,
        quotaExhausted: isQuota,
        isCustomKey: error?.isCustomKey ?? false,
        error: error?.message || 'Erro inesperado no processamento do assistente.',
      }),
      { status: isQuota ? 429 : 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
