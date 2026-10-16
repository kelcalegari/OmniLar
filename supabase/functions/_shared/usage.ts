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
 * Limite diário usado só se o banco não responder o limite do plano da casa.
 */
export const DEFAULT_DAILY_QUOTA_PER_HOUSE = 10;

/**
 * Limite diário de leituras de IA do plano da casa (migration 0069). Nulo = sem limite.
 */
export async function houseAiDailyLimit(
  supabaseClient: ReturnType<typeof createClient>,
  houseId: string,
): Promise<number | null> {
  const { data, error } = await supabaseClient.rpc('house_ai_daily_limit', { p_house_id: houseId });
  if (error) {
    console.warn('Erro ao ler o limite do plano:', error.message);
    return DEFAULT_DAILY_QUOTA_PER_HOUSE;
  }
  return typeof data === 'number' ? data : null;
}

/**
 * Verifica se a casa atingiu a cota diária de leituras de IA do plano dela.
 * Se o usuário informou sua própria chave de API (BYOK), a cota é ilimitada.
 */
export async function checkAiDailyQuota(
  supabaseClient: ReturnType<typeof createClient>,
  houseId: string,
  memberId: string,
  hasCustomKey: boolean,
  quotaLimit?: number | null,
): Promise<{ allowed: boolean; currentCount: number; limit: number }> {
  // Usuário com chave própria não consome cota do app
  if (hasCustomKey) {
    return { allowed: true, currentCount: 0, limit: Infinity };
  }

  // Sem limite informado, vale o do plano da casa (Free ou Premium)
  const limit = quotaLimit === undefined ? await houseAiDailyLimit(supabaseClient, houseId) : quotaLimit;
  if (limit === null) {
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
    // Sem conseguir contar o uso, não libera a chave do sistema
    return { allowed: false, currentCount: 0, limit };
  }

  const currentCount = count || 0;
  return {
    allowed: currentCount < limit,
    currentCount,
    limit,
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
