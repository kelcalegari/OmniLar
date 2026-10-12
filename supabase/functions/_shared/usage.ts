import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.8';

export interface AiUsageRecord {
  houseId: string;
  memberId: string;
  feature: 'capture' | 'import' | 'assistant';
  model: string;
  tokensIn?: number;
  tokensOut?: number;
  status: 'success' | 'rate_limited' | 'error';
}

/**
 * Limite diário padrão por casa no plano gratuito do sistema (quando não há chave BYOK).
 */
export const DEFAULT_DAILY_QUOTA_PER_HOUSE = 50;

/**
 * Verifica se a casa ou membro atingiu a cota diária de requisições de IA gratuita.
 * Se o usuário informou sua própria chave de API (BYOK), a cota é ilimitada.
 */
export async function checkAiDailyQuota(
  supabaseClient: ReturnType<typeof createClient>,
  houseId: string,
  memberId: string,
  hasCustomKey: boolean,
  quotaLimit = DEFAULT_DAILY_QUOTA_PER_HOUSE,
): Promise<{ allowed: boolean; currentCount: number; limit: number }> {
  // Usuário com chave própria não consome cota do app
  if (hasCustomKey) {
    return { allowed: true, currentCount: 0, limit: Infinity };
  }

  const startOfDay = new Date();
  startOfDay.setHours(0, 0, 0, 0);

  const { count, error } = await supabaseClient
    .from('ai_usage')
    .select('id', { count: 'exact', head: true })
    .eq('house_id', houseId)
    .gte('created_at', startOfDay.toISOString());

  if (error) {
    console.warn('Erro ao verificar ai_usage:', error.message);
    // Em caso de falha de consulta na cota, não bloqueia o usuário (fallback gracioso)
    return { allowed: true, currentCount: 0, limit: quotaLimit };
  }

  const currentCount = count || 0;
  return {
    allowed: currentCount < quotaLimit,
    currentCount,
    limit: quotaLimit,
  };
}

/**
 * Registra o consumo de IA na tabela public.ai_usage para auditoria e controle de limites.
 */
export async function recordAiUsage(
  supabaseClient: ReturnType<typeof createClient>,
  record: AiUsageRecord,
): Promise<void> {
  try {
    await supabaseClient.from('ai_usage').insert({
      house_id: record.houseId,
      member_id: record.memberId,
      feature: record.feature,
      model: record.model,
      tokens_in: record.tokensIn || 0,
      tokens_out: record.tokensOut || 0,
      status: record.status,
    });
  } catch (err) {
    console.warn('Falha silenciosa ao registrar ai_usage:', err);
  }
}
