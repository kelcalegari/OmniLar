import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.8';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class HttpError extends Error {
  public readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
  }
}

export interface HouseMemberContext {
  userId: string;
  houseId: string;
  /** Cliente com o JWT do usuário: toda leitura/escrita passa pelo RLS. */
  supabaseClient: ReturnType<typeof createClient>;
}

/**
 * Exige um usuário autenticado que more na casa informada.
 * Identidade e casa vêm do JWT e do banco, nunca do corpo da requisição:
 * sem [requestedHouseId] válido, usa a primeira casa ativa do usuário.
 */
export async function requireHouseMember(
  req: Request,
  requestedHouseId?: unknown,
): Promise<HouseMemberContext> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';

  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) {
    throw new HttpError(401, 'Faça login para usar os recursos de IA.');
  }

  const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await supabaseClient.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) {
    throw new HttpError(401, 'Sessão inválida ou expirada. Faça login novamente.');
  }

  let query = supabaseClient
    .from('house_members')
    .select('house_id')
    .eq('user_id', user.id)
    .is('left_at', null);

  if (typeof requestedHouseId === 'string' && UUID_RE.test(requestedHouseId)) {
    query = query.eq('house_id', requestedHouseId);
  }

  const { data: memberships, error: memberError } = await query.limit(1);
  if (memberError || !memberships || memberships.length === 0) {
    throw new HttpError(403, 'Você não participa desta casa.');
  }

  return {
    userId: user.id,
    houseId: memberships[0].house_id as string,
    supabaseClient,
  };
}
