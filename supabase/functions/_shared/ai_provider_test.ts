import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { classifyQuotaError } from './ai_provider.ts';

const body = (quotaId: string, retryDelay?: string) =>
  JSON.stringify({
    error: {
      code: 429,
      status: 'RESOURCE_EXHAUSTED',
      details: [
        { '@type': 'type.googleapis.com/google.rpc.QuotaFailure', violations: [{ quotaId }] },
        ...(retryDelay ? [{ '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay }] : []),
      ],
    },
  });

Deno.test('429 por minuto usa o retryDelay do Google', () => {
  const r = classifyQuotaError(429, body('GenerateRequestsPerMinutePerProjectPerModel-FreeTier', '34.2s'));
  assertEquals(r, { scope: 'minute', retryAfterS: 35 });
});

Deno.test('429 por dia não devolve espera', () => {
  const r = classifyQuotaError(429, body('GenerateRequestsPerDayPerProjectPerModel-FreeTier', '34s'));
  assertEquals(r, { scope: 'day' });
});

Deno.test('429 sem detalhes vira minuto com espera padrão', () => {
  assertEquals(classifyQuotaError(429, 'Too Many Requests'), { scope: 'minute', retryAfterS: 30 });
});

Deno.test('cabeçalho Retry-After vale quando não há RetryInfo', () => {
  assertEquals(classifyQuotaError(429, '{}', '12'), { scope: 'minute', retryAfterS: 12 });
});
