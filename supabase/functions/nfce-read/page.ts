/** Leitura da página de consulta da NFC-e (sem dependências do Deno). */

export interface NfceItem {
  title: string;
  quantity: number;
  unit_cents: number;
  amount_cents: number;
  is_common_expense: boolean;
}

export interface NfceAnalysis {
  found: boolean;
  title: string;
  total_cents: number;
  discount_cents?: number;
  issue_date?: string | null;
  merchant_name?: string | null;
  merchant_cnpj?: string | null;
  is_itemized: boolean;
  items: NfceItem[];
  raw_notes?: string | null;
}

/** Só páginas de governo: a função não serve para buscar outros sites. */
export function allowedUrl(raw: string, base?: URL): URL | null {
  let url: URL;
  try {
    url = base ? new URL(raw, base) : new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (url.username || url.password) return null;
  if (url.port && url.port !== '80' && url.port !== '443') return null;
  const host = url.hostname.toLowerCase();
  if (!host.endsWith('.gov.br')) return null;
  return url;
}

export function decodeBody(bytes: Uint8Array, contentType: string | null): string {
  const headerCharset = /charset=([\w-]+)/i.exec(contentType || '')?.[1];
  const head = new TextDecoder('latin1').decode(bytes.slice(0, 4096));
  const metaCharset = /<meta[^>]+charset=["']?([\w-]+)/i.exec(head)?.[1];
  const charset = (headerCharset || metaCharset || 'utf-8').toLowerCase();
  try {
    return new TextDecoder(charset === 'iso-8859-1' ? 'windows-1252' : charset).decode(bytes);
  } catch {
    return new TextDecoder('utf-8').decode(bytes);
  }
}

const ENTITIES: Record<string, string> = {
  nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'",
  ccedil: 'ç', Ccedil: 'Ç', atilde: 'ã', Atilde: 'Ã', otilde: 'õ', Otilde: 'Õ',
  aacute: 'á', Aacute: 'Á', eacute: 'é', Eacute: 'É', iacute: 'í', Iacute: 'Í',
  oacute: 'ó', Oacute: 'Ó', uacute: 'ú', Uacute: 'Ú', acirc: 'â', Acirc: 'Â',
  ecirc: 'ê', Ecirc: 'Ê', ocirc: 'ô', Ocirc: 'Ô', agrave: 'à', Agrave: 'À',
};

export function decodeEntities(text: string): string {
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&([a-z]+);/gi, (m, name) => ENTITIES[name] ?? m);
}

export function cleanText(html: string): string {
  return decodeEntities(html.replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
}

export function pageText(html: string): string {
  const body = html
    .replace(/<(script|style|noscript|head)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<(br|\/p|\/div|\/tr|\/li|\/h\d)[^>]*>/gi, '\n')
    .replace(/<\/t[dh]>/gi, ' | ');
  return decodeEntities(body.replace(/<[^>]*>/g, ' '))
    .split('\n')
    .map((l) => l.replace(/[ \t]+/g, ' ').trim())
    .filter((l) => l.length > 0 && l !== '|')
    .join('\n');
}

/** "1.234,56" ou "1234.56" em centavos. */
export function toCents(raw: string | undefined | null): number {
  if (!raw) return 0;
  const m = /-?[\d.]+(?:,\d+)?|-?\d+(?:\.\d+)?/.exec(raw.replace(/\s/g, ''));
  if (!m) return 0;
  const s = m[0];
  const value = s.includes(',') ? Number(s.replace(/\./g, '').replace(',', '.')) : Number(s);
  return Number.isFinite(value) ? Math.round(value * 100) : 0;
}

export function toQuantity(raw: string | undefined | null): number {
  if (!raw) return 1;
  const s = raw.replace(/[^\d.,]/g, '');
  const value = s.includes(',') ? Number(s.replace(/\./g, '').replace(',', '.')) : Number(s);
  return Number.isFinite(value) && value > 0 ? value : 1;
}

export function spanByClass(html: string, cls: string): string | null {
  const re = new RegExp(`<(span|div|label)[^>]*class=["'][^"']*\\b${cls}\\b[^"']*["'][^>]*>([\\s\\S]*?)<\\/\\1>`, 'i');
  const m = re.exec(html);
  return m ? cleanText(m[2]) : null;
}

export function issueDateOf(text: string): string | null {
  const m = /Emiss[aã]o:?\s*(\d{2})\/(\d{2})\/(\d{4})/i.exec(text) ||
    /(\d{2})\/(\d{2})\/(\d{4})\s+\d{2}:\d{2}/.exec(text);
  return m ? `${m[3]}-${m[2]}-${m[1]}` : null;
}

/**
 * Layout padrão da consulta por QR (o mesmo em boa parte dos estados): itens
 * com txtTit / Rqtd / RvlUnit / valor e o total em totalNumb.
 */
export function parseStandardLayout(html: string): NfceAnalysis | null {
  if (!/class=["'][^"']*\bRqtd\b/i.test(html)) return null;

  const items: NfceItem[] = [];
  const rows = html.split(/<tr[^>]*id=["']Item/i).slice(1);
  for (const row of rows) {
    const chunk = row.split(/<\/tr>/i)[0];
    const title = spanByClass(chunk, 'txtTit');
    const amount = toCents(spanByClass(chunk, 'valor'));
    if (!title || amount <= 0) continue;
    const quantity = toQuantity(spanByClass(chunk, 'Rqtd')?.replace(/Qtde\.?:?/i, ''));
    const unit = toCents(spanByClass(chunk, 'RvlUnit')?.replace(/Vl\.?\s*Unit\.?:?/i, ''));
    items.push({
      title,
      quantity,
      unit_cents: unit > 0 ? unit : Math.round(amount / quantity),
      amount_cents: amount,
      is_common_expense: true,
    });
  }
  if (items.length === 0) return null;

  // "Valor a pagar" é o último totalNumb antes da forma de pagamento
  let total = 0;
  let discount = 0;
  const totals = /<div[^>]*id=["']totalNota["'][^>]*>([\s\S]*?)<div[^>]*id=["']infos/i.exec(html)?.[1] ?? html;
  for (const line of totals.split(/<div[^>]*id=["']linhaTotal/i).slice(1)) {
    const label = cleanText(/<label[^>]*>([\s\S]*?)<\/label>/i.exec(line)?.[1] ?? '').toLowerCase();
    const value = toCents(spanByClass(line, 'totalNumb'));
    if (label.includes('valor a pagar')) total = value;
    else if (label.includes('desconto')) discount = value;
    else if (!total && label.includes('valor total')) total = value;
  }
  const itemsSum = items.reduce((s, it) => s + it.amount_cents, 0);
  if (total <= 0) total = itemsSum - discount;

  const text = cleanText(html);
  const merchant = spanByClass(html, 'txtTopo');
  const cnpj = /CNPJ:?\s*([\d./-]{14,18})/i.exec(text)?.[1] ?? null;

  return {
    found: true,
    title: merchant || 'Nota Fiscal (NFC-e)',
    total_cents: total,
    discount_cents: discount,
    issue_date: issueDateOf(text),
    merchant_name: merchant,
    merchant_cnpj: cnpj,
    is_itemized: true,
    items,
  };
}

/**
 * Recusa da própria Sefaz (QR inválido, nota não encontrada, "205 - ..."),
 * para avisar sem gastar IA. O código numérico só vale em página curta, onde
 * não há endereço com número para confundir.
 */
export function sefazError(html: string): string | null {
  const known = /(QR[ -]?Code inv[aá]lido[^<'"\n]{0,200}|NFC-?e n[aã]o (?:foi )?(?:encontrad|localizad)[^<'"\n]{0,200}|Nota n[aã]o (?:foi )?(?:encontrad|localizad)[^<'"\n]{0,200})/i
    .exec(html);
  const tidy = (m: string) => cleanText(m).replace(/\s*Erro\(s\):?\s*$/i, '').replace(/[\s|.:;-]+$/, '');
  if (known) return tidy(known[1]);
  const text = pageText(html);
  if (text.length < 400) {
    const coded = /\b\d{3} - [^\n]{10,200}/.exec(text);
    if (coded) return tidy(coded[0]);
  }
  return null;
}

/** Página só com moldura: segue o primeiro frame do governo. */
export function frameUrl(html: string, base: URL): URL | null {
  const src = /<i?frame[^>]+src=["']([^"']+)["']/i.exec(html)?.[1];
  return src ? allowedUrl(decodeEntities(src), base) : null;
}
