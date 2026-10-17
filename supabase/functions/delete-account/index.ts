import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.8';
import { corsHeaders } from '../_shared/cors.ts';

/**
 * Exclui a conta de quem está logado (LGPD, migration 0081).
 *
 * Corpo: { password, confirm: "EXCLUIR" }. A senha é conferida de novo aqui.
 * Os dados saem por delete_my_account_data (casas, propriedade, perfil); depois
 * o usuário é apagado do Auth quando não sobrou casa nenhuma que dependa dele,
 * ou fica sem e-mail, sem senha e bloqueado (o histórico dos outros moradores
 * continua apontando para ele, com o nome "Ex-morador").
 */

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json(405, { error: 'Método não permitido.' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

  try {
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) {
      return json(401, { error: 'Faça login para excluir a conta.' });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    const user = userData?.user;
    if (userError || !user) {
      return json(401, { error: 'Sessão inválida ou expirada. Faça login novamente.' });
    }

    const body = await req.json().catch(() => ({}));
    if (body?.confirm !== 'EXCLUIR') {
      return json(400, { error: 'Digite EXCLUIR para confirmar.' });
    }
    if (typeof body?.password !== 'string' || body.password.length === 0) {
      return json(400, { error: 'Digite sua senha.' });
    }
    if (!user.email) {
      return json(400, { error: 'Esta conta não tem e-mail e senha. Fale com o suporte para excluí-la.' });
    }

    // A senha confere? (cliente à parte, sem guardar a sessão aberta)
    const checker = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: passwordError } = await checker.auth.signInWithPassword({
      email: user.email,
      password: body.password,
    });
    if (passwordError) {
      return json(403, { error: 'Senha incorreta.' });
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: result, error: dataError } = await admin.rpc('delete_my_account_data', {
      p_user_id: user.id,
    });
    if (dataError) {
      console.error('delete_my_account_data', user.id, dataError);
      return json(500, { error: 'Não foi possível excluir a conta agora. Nada foi apagado; tente de novo.' });
    }

    let removed = false;
    if (result?.can_delete_auth_user === true) {
      const { error } = await admin.auth.admin.deleteUser(user.id);
      if (error) {
        console.error('deleteUser', user.id, error);
      } else {
        removed = true;
      }
    }

    if (!removed) {
      const { error } = await admin.auth.admin.updateUserById(user.id, {
        email: `excluida-${user.id}@omnilar.invalid`,
        email_confirm: true,
        password: `${crypto.randomUUID()}${crypto.randomUUID()}`,
        ban_duration: '876000h',
        user_metadata: {},
      });
      if (error) {
        console.error('updateUserById', user.id, error);
        return json(500, {
          error: 'Seus dados foram apagados, mas o acesso não pôde ser bloqueado. Fale com o suporte.',
        });
      }
    }

    return json(200, {
      ok: true,
      deleted_houses: result?.deleted_houses ?? 0,
      left_houses: result?.left_houses ?? 0,
    });
  } catch (error) {
    console.error('delete-account', error);
    return json(500, { error: 'Não foi possível excluir a conta agora. Tente de novo.' });
  }
});
