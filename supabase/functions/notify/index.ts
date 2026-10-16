// Função notify: envia pelo FCM (API HTTP v1) as notificações pendentes.
//
// É chamada pelo banco (pg_net, migration 0066) sempre que nasce uma
// notificação com push pendente, sem corpo útil: ela mesma busca o que está
// pendente. Por isso não recebe dados de quem chama e roda sem JWT; o pior que
// uma chamada de fora consegue é antecipar um envio que já ia sair.
//
// Secrets: FCM_SERVICE_ACCOUNT (JSON da conta de serviço do Firebase) e,
// opcional, FCM_PROJECT_ID (senão vem do JSON). SUPABASE_URL e
// SUPABASE_SERVICE_ROLE_KEY são do próprio Supabase.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.8';

const BATCH = 200;
// Com 3 ou mais avisos de uma vez para a mesma pessoa, vai um resumo só
const SUMMARY_FROM = 3;

interface Pending {
  id: string;
  house_id: string | null;
  user_id: string;
  type: string;
  category: string;
  title: string;
  body: string;
  deeplink: string | null;
  group_key: string | null;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

serve(async () => {
  const rawAccount = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!rawAccount) return json({ error: 'FCM_SERVICE_ACCOUNT não configurado.' }, 500);
  let account: ServiceAccount;
  try {
    account = JSON.parse(rawAccount);
  } catch {
    return json({ error: 'FCM_SERVICE_ACCOUNT não é um JSON válido.' }, 500);
  }
  const projectId = Deno.env.get('FCM_PROJECT_ID') || account.project_id;

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

  // Reserva as pendentes (uma chamada simultânea não pega as mesmas)
  const { data: claimed, error: claimError } = await db.rpc('claim_pending_notifications', { p_limit: BATCH });
  if (claimError) return json({ error: claimError.message }, 500);
  const pending = (claimed ?? []) as Pending[];
  if (pending.length === 0) return json({ sent: 0 });

  const userIds = [...new Set(pending.map((p) => p.user_id))];
  const houseIds = [...new Set(pending.map((p) => p.house_id).filter((h): h is string => !!h))];

  const [tokensRes, settingsRes, prefsRes, housesRes] = await Promise.all([
    db.from('device_tokens').select('id, user_id, token').in('user_id', userIds),
    db.from('notification_settings').select('user_id, quiet_hours_start, quiet_hours_end, hide_amounts').in('user_id', userIds),
    db.from('notification_preferences').select('user_id, house_id, category, push').in('user_id', userIds).eq('push', false),
    houseIds.length
      ? db.from('houses').select('id, timezone').in('id', houseIds)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const tokensByUser = groupBy(tokensRes.data ?? [], (t: { user_id: string }) => t.user_id);
  const settingsByUser = new Map((settingsRes.data ?? []).map((s: { user_id: string }) => [s.user_id, s]));
  const pushOff = new Set((prefsRes.data ?? []).map((p: { user_id: string; house_id: string; category: string }) =>
    `${p.user_id}|${p.house_id}|${p.category}`));
  const timezoneByHouse = new Map((housesRes.data ?? []).map((h: { id: string; timezone: string | null }) =>
    [h.id, h.timezone || 'America/Sao_Paulo']));

  let accessToken: string;
  try {
    accessToken = await googleAccessToken(account);
  } catch (e) {
    // Conta de serviço errada: devolve as reservadas como falha em vez de prendê-las
    await db.from('notifications').update({ push_status: 'failed' }).in('id', pending.map((p) => p.id));
    return json({ error: String(e) }, 500);
  }
  const results = { sent: [] as string[], skipped: [] as string[], failed: [] as string[], deferred: [] as Array<{ id: string; until: string }> };
  const deadTokens = new Set<string>();

  for (const [userId, items] of groupBy(pending, (p) => p.user_id)) {
    const tokens = tokensByUser.get(userId) ?? [];
    const settings = settingsByUser.get(userId) as
      | { quiet_hours_start: string | null; quiet_hours_end: string | null; hide_amounts: boolean }
      | undefined;

    const wanted = items.filter((n) => !(n.house_id && pushOff.has(`${userId}|${n.house_id}|${n.category}`)));
    results.skipped.push(...items.filter((n) => !wanted.includes(n)).map((n) => n.id));
    if (wanted.length === 0) continue;
    if (tokens.length === 0) {
      results.skipped.push(...wanted.map((n) => n.id));
      continue;
    }

    // Horário silencioso: fica pendente até o fim dele
    const timezone = timezoneByHouse.get(wanted[0].house_id ?? '') ?? 'America/Sao_Paulo';
    const quietUntil = quietHoursEnd(settings?.quiet_hours_start, settings?.quiet_hours_end, timezone);
    if (quietUntil) {
      results.deferred.push(...wanted.map((n) => ({ id: n.id, until: quietUntil })));
      continue;
    }

    const hide = settings?.hide_amounts === true;
    const messages = wanted.length >= SUMMARY_FROM
      ? [{
          title: 'Omni Lar',
          body: `Você tem ${wanted.length} avisos novos`,
          deeplink: '/notificacoes',
          tag: 'resumo',
          ids: wanted.map((n) => n.id),
        }]
      : wanted.map((n) => ({
          title: maybeHide(n.title, hide),
          body: maybeHide(n.body, hide),
          deeplink: n.deeplink ?? '/notificacoes',
          tag: n.group_key ?? n.id,
          ids: [n.id],
        }));

    for (const message of messages) {
      let delivered = false;
      for (const t of tokens) {
        const outcome = await sendToToken(projectId, accessToken, t.token, message);
        if (outcome === 'ok') delivered = true;
        if (outcome === 'dead') deadTokens.add(t.id);
      }
      (delivered ? results.sent : results.failed).push(...message.ids);
    }
  }

  const now = new Date().toISOString();
  await Promise.all([
    results.sent.length && db.from('notifications').update({ push_status: 'sent', pushed_at: now }).in('id', results.sent),
    results.skipped.length && db.from('notifications').update({ push_status: 'skipped' }).in('id', results.skipped),
    results.failed.length && db.from('notifications').update({ push_status: 'failed' }).in('id', results.failed),
    deadTokens.size && db.from('device_tokens').delete().in('id', [...deadTokens]),
    ...Array.from(groupBy(results.deferred, (d) => d.until)).map(([until, list]) =>
      db.from('notifications').update({ push_status: 'pending', push_after: until }).in('id', list.map((d) => d.id))),
  ]);

  return json({
    sent: results.sent.length,
    skipped: results.skipped.length,
    failed: results.failed.length,
    deferred: results.deferred.length,
    removed_tokens: deadTokens.size,
  });
});

function groupBy<T>(items: T[], key: (item: T) => string): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const item of items) {
    const k = key(item);
    map.set(k, [...(map.get(k) ?? []), item]);
  }
  return map;
}

/** "Esconder valores nas notificações": troca os valores em reais por •••. */
function maybeHide(text: string, hide: boolean): string {
  return hide ? text.replace(/R\$\s?[\d.]+,\d{2}/g, 'R$ •••') : text;
}

/** Se agora está no horário silencioso, devolve quando ele acaba (ISO, UTC). */
function quietHoursEnd(start: string | null | undefined, end: string | null | undefined, timezone: string): string | null {
  if (!start || !end || start === end) return null;
  const now = new Date();
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: timezone, hour12: false, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit',
    }).formatToParts(now).map((p) => [p.type, p.value]),
  );
  const minutesNow = (Number(parts.hour) % 24) * 60 + Number(parts.minute);
  const toMinutes = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
  const s = toMinutes(start);
  const e = toMinutes(end);
  const inside = s < e ? minutesNow >= s && minutesNow < e : minutesNow >= s || minutesNow < e;
  if (!inside) return null;
  const wait = (e - minutesNow + 24 * 60) % (24 * 60);
  return new Date(now.getTime() + wait * 60_000).toISOString();
}

type SendOutcome = 'ok' | 'dead' | 'error';

async function sendToToken(
  projectId: string,
  accessToken: string,
  token: string,
  m: { title: string; body: string; deeplink: string; tag: string },
): Promise<SendOutcome> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token,
        // Sempre visível: o iPhone cancela a inscrição de push silencioso
        notification: { title: m.title, body: m.body },
        data: { deeplink: m.deeplink },
        android: { priority: 'high', notification: { tag: m.tag } },
        webpush: { notification: { tag: m.tag, icon: '/icons/Icon-192.png' } },
      },
    }),
  });
  if (res.ok) return 'ok';
  const body = await res.text();
  // Token que não vale mais (app removido, site tirado da Tela de Início, saiu da conta)
  if (res.status === 404 || body.includes('UNREGISTERED') || body.includes('registration-token-not-registered')) {
    return 'dead';
  }
  console.error('FCM recusou o envio', res.status, body.slice(0, 300));
  return 'error';
}

/** Token OAuth do Google a partir da conta de serviço (JWT assinado com RS256). */
async function googleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encode = (obj: unknown) => base64Url(new TextEncoder().encode(JSON.stringify(obj)));
  const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;

  const pem = account.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${base64Url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`Google OAuth recusou a conta de serviço: ${res.status}`);
  return (await res.json()).access_token as string;
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
