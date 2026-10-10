---
name: omnilar-ai-pipeline
description: >-
  Use when implementing Omni Lar AI features with the Gemini API (Google AI
  Studio): Edge Functions for receipt/boleto/statement reading, classification,
  the assistant with function calling, usage limits, masking and fallbacks.
---

# Omni Lar: Pipeline de IA (Gemini API)

Referências: `novoSite/arquitetura_tecnica.md` seções 8 e 17, `modulo_captura_inteligente.md`, `modulo_importacao_conciliacao.md`, `modulo_assistente_ia.md`.

## Regras inegociáveis
1. **Código primeiro, IA depois:** QR Code da NFC-e, linha digitável de boleto, OFX e CSV são lidos por código. A IA só entra para foto/PDF sem estrutura e para linguagem natural.
2. **A IA propõe, a pessoa confirma.** Nada de dinheiro gravado sem a tela de revisão.
3. **A IA não calcula valores finais.** Saldos, rateios e liquidação vêm de funções SQL/motor.
4. **A chave da API fica só nos secrets das Edge Functions.** Nunca no app nem no repositório.
5. **Funciona sem IA:** todo fluxo tem alternativa manual; erro/limite/indisponibilidade cai nela.
6. **Plano gratuito:** o conteúdo enviado pode ser usado pelo Google. Em desenvolvimento use só dados seus ou fictícios. Antes de convidar outros usuários, migrar para o plano pago e atualizar o consentimento.

## Estrutura
```
supabase/functions/
  _shared/ai_provider.ts   # interface AiProvider + GeminiProvider
  _shared/mask.ts          # mascaramento (CPF, cartão, conta)
  _shared/usage.ts         # limite diário e registro em ai_usage
  capture-read/ import-classify/ assistant/
```
- Modelos em configuração: `AI_MODEL_VISION`, `AI_MODEL_CHAT`, `AI_MODEL_CLASSIFY` (família Flash; Flash-Lite para classificação). Conferir nomes e limites atuais no AI Studio antes de fixar.
- `AiProvider` isola o provedor para trocar modelo ou fornecedor sem mexer nas funções.

## Passo a passo de uma função de leitura
1. Validar JWT e entrada (schema). Exigir `idempotency_key`.
2. Checar consentimento do usuário e limite diário (`ai_usage`). Excedeu: responder 429 com mensagem para fallback manual.
3. Calcular `file_hash`; se já processado, devolver o resultado em cache.
4. Tentar caminho por código (QR/linha digitável/OFX/CSV). Só se falhar, seguir.
5. Mascarar dados sensíveis e remover EXIF.
6. Chamar o Gemini com **saída estruturada (JSON Schema)** e instrução de sistema em pt-BR.
7. Validar a resposta de novo no servidor. Fora do schema: tentar uma vez; depois falhar para o manual.
8. Gravar proposta (`captures`/`import_lines`) com **confiança por campo** e registrar uso (apenas metadados).
9. Retornar a proposta; a gravação real só ocorre na confirmação do app.

## Assistente
- Usa *function calling* com as ferramentas do app. Cada ferramenta executa com o **JWT do usuário** (a RLS vale).
- Ferramentas de escrita só devolvem uma **proposta** (`assistant_actions` em `proposed`); a escrita real ocorre após confirmação do app.
- Ações de risco (renegociar, perdoar, liquidar, excluir): confirmação reforçada, nunca em lote.
- Perguntas frequentes têm atalhos que chamam SQL direto, sem LLM.
- Não enviar CPF, número de cartão ou conta no contexto.

## Economia de chamadas
Cache por hash, classificação em lote numa chamada, regras aprendidas antes da IA, imagens comprimidas, `backoff` exponencial em erro 429.

## Testes
- Conjunto fixo de documentos **fictícios** com saída esperada; rodar a cada mudança de modelo ou prompt.
- Falhas: 429, fora do schema, timeout, imagem ilegível → fallback manual.
- Métricas: acerto por campo, taxa de baixa confiança, taxa de correção pelo usuário.
