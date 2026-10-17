# Plano: primeiro acesso, cadastro, confirmação de e-mail, troca de e-mail/senha e login com Google

Escrito em 16/10/2026, a partir do código da branch `fix/web-mobile-ajustes` e de uma consulta só de leitura ao Supabase `rygxmpwzofgieodvhpcy`.

**Situação em 17/10/2026:** as fases 1 a 3 estão na `main` e a migration 0071 está aplicada; a fase 4 (Google) está no código, escondida até a publicação. A seção 1 descreve o ponto de partida, antes dessas fases. Continuam pendentes: o teste com conta real de cada fase e, para produção, o SMTP próprio (decisão 2).

## 1. Como estava antes das fases (16/10/2026)

**Telas e fluxo**
- Uma única tela, `lib/features/auth/presentation/pages/login_page.dart`, com as abas "Entrar" e "Criar Conta" (nome, e-mail, senha de no mínimo 6 caracteres) e o botão de demonstração.
- Depois de entrar: sem casa → `/onboarding/house`; conta em análise (migration 0068) → `/conta/em-analise`; com casa → `/casa`. Na web, sem login só se acessa `/landing` e `/login` (`lib/core/router/app_router.dart:89`).
- O Supabase usa o fluxo PKCE (`lib/core/network/supabase_config.dart:43`).

**Cadastro** (`supabase_auth_datasource.dart:147`)
- `signUp` sem `emailRedirectTo`.
- Logo depois faz um `upsert` em `profiles` pelo app. Isso é redundante: o gatilho `handle_new_user` (0068) já cria o perfil e o status da conta.
- Se o Supabase não devolve sessão (é o que acontece quando a confirmação de e-mail está ligada), o app tenta `signInWithPassword` e **engole o erro**. Depois o cubit emite `authenticatedNoHouse` mesmo sem sessão, e o usuário cai no onboarding sem estar logado: criar a casa falharia. Com a confirmação ligada, o `upsert` sem sessão também quebra antes disso, e aparece "Erro ao cadastrar" mesmo com a conta já criada.

**Confirmação de e-mail**
- No Supabase hospedado, os 3 usuários existentes estão confirmados e nenhum recebeu e-mail de confirmação (`confirmation_sent_at` vazio). Na prática a confirmação está **desligada**. A configuração em si só aparece no Dashboard (Authentication → Providers → Email). No `supabase/config.toml` local, `enable_confirmations = false`.
- O app não tem tela de "confira seu e-mail", reenvio, nem tratamento do erro "Email not confirmed".

**Esqueci minha senha / alterar senha**
- Não existe. Não há `resetPasswordForEmail` nem tela de nova senha. Em Configurações também não há troca de senha.

**Alterar e-mail** (`supabase_auth_datasource.dart:271`, `settings_page.dart:321`)
- Fica junto do "Editar perfil": `updateUser(email: ...)` sem `emailRedirectTo`, com um aviso genérico ("pode ser necessário confirmar").
- O app não mostra que existe um e-mail esperando confirmação (`user.newEmail`).
- Depois da confirmação, `profiles.email` fica com o e-mail antigo: o gatilho só roda no INSERT de `auth.users`, e os outros membros veem `profiles.email`.

**Links que voltam para o app**
- O Android (`AndroidManifest.xml`) e o iOS (`Info.plist`) não declaram nenhum esquema ou deep link. Um link de confirmação ou de redefinição aberto no celular cai no `site_url` (o site), não no app.

**Google**
- Não implementado. O único provedor em `auth.identities` é `email`. Não há pacote `google_sign_in`.

**Outros**
- As mensagens de erro do Supabase aparecem em inglês ("Invalid login credentials").
- A validação de e-mail só confere se tem `@`.
- O SMTP padrão do Supabase tem limite baixo de envio e só serve para testes. Sem um SMTP próprio, confirmação e redefinição não funcionam de verdade em produção.

## 2. Decisões do dono (antes de começar)

1. **Código de 6 dígitos ou link no e-mail?** ⭐ Código. Funciona igual na web, no Android e no iOS, sem deep link, e o usuário não sai do app. O link exige configurar App Links/Universal Links e tratar o PKCE quando o link é aberto em outro aparelho ou navegador.
2. **SMTP próprio:** qual serviço (ex.: Resend, Brevo, Amazon SES) e qual remetente (ex.: `nao-responda@<domínio>`). Isso bloqueia as fases 1 a 3 em produção.
3. **Ligar a confirmação obrigatória para contas novas?** ⭐ Sim. As 3 contas atuais já estão confirmadas, então não são afetadas.
4. **Troca de senha logado:** ⭐ pedir a senha atual. Alternativa: código por e-mail (reautenticação do Supabase).
5. **Google no Android/iOS:** ⭐ login nativo (`google_sign_in` + `signInWithIdToken`), sem navegador e sem deep link. Alternativa: `signInWithOAuth` pelo navegador, que exige deep link.
6. **Senha mínima:** manter 6 ou subir para 8.
7. **Aprovação de conta (0068):** quem entra pelo Google também cai em "em análise"? ⭐ Sim, mesma regra (o gatilho já trata isso).

## 3. Fases

### Fase 0 — Configuração (dono, no Dashboard; sem código)
- Supabase → Authentication → SMTP: configurar o SMTP próprio.
- Providers → Email: ligar "Confirm email" e "Secure email change" (confirmação nos dois endereços).
- Email Templates (Confirm signup, Reset password, Change email address, Reauthentication): texto em português com o código `{{ .Token }}`, se a decisão 1 for o código.
- URL Configuration: `site_url` = `https://omnilar.web.app`; redirect URLs com `https://omnilar.web.app/**` (para o Google na web).
- (Adiado até a publicação, ver Fase 4) Google Cloud: tela de consentimento e clientes OAuth (Web; Android com o SHA-1 de debug e de release; iOS). Depois, Supabase → Providers → Google com o Client ID/Secret do cliente Web e os IDs de Android/iOS em "Authorized Client IDs".

### Fase 1 — Cadastro com confirmação de e-mail ✅ código pronto (branch `feat/auth-cadastro-confirmacao`, 16/10/2026)

**O que foi feito:** `AuthStatus.awaitingEmailConfirmation` + `pendingEmail`, a tela `ConfirmEmailPage` em `/login/confirmar-email` (código, reenviar após 60 s, "já confirmei pelo link", "e-mail errado"), o login de conta não confirmada reenvia o código e abre essa tela, os erros do Supabase saem em português (`auth_error_messages.dart`), mais confirmação da senha e e-mail validado no cadastro. O mock ganhou `requireEmailConfirmation` (código `123456`) e há 5 testes novos.

**Enquanto "Confirm email" estiver desligado no Supabase, nada muda para o usuário:** o cadastro continua entrando direto. Para ligar, nesta ordem: SMTP próprio → template "Confirm signup" com `{{ .Token }}` → ligar "Confirm email". Com o template padrão (só link), a tela continua funcionando pelo botão "Já confirmei pelo link".

**Ainda não testado com uma conta real:** o dono cria a conta no app depois de ligar a confirmação.

Itens originais da fase:
- `signUpWithEmailPassword`: tirar o `upsert` em `profiles` e a tentativa silenciosa de login. Quando vier sem sessão, devolver o resultado "aguardando confirmação" (novo estado `AuthStatus.awaitingEmailConfirmation`, com o e-mail) em vez de um usuário.
- Nova tela `ConfirmEmailPage` (`/login/confirmar-email`): campo do código, `verifyOTP(type: OtpType.signup)`, botão "Reenviar código" com espera de 60 s (`auth.resend`) e "Trocar e-mail" (volta ao cadastro).
- Login com e-mail não confirmado: reconhecer o erro `email_not_confirmed` e mandar para a mesma tela, já reenviando o código.
- Router: liberar as novas rotas de `/login/*` sem sessão (também na web).
- Mensagens de erro do Supabase traduzidas num único ponto (mapear `AuthException.code`).
- Validação de e-mail com regex simples e confirmação da senha no cadastro.

### Fase 2 — Esqueci minha senha ✅ código pronto (branch `feat/auth-recuperar-senha`, feita a partir da Fase 1, 16/10/2026)

**O que foi feito:** link "Esqueci minha senha" na aba Entrar → `ResetPasswordPage` em `/login/recuperar-senha` (o e-mail vai por `extra`, nunca pela URL). Passo 1: e-mail → `resetPasswordForEmail`, com mensagem neutra. Passo 2: código + nova senha + confirmação → `verifyOTP(recovery)` e `updateUser(password)` numa só chamada. Enquanto a senha nova não é gravada, o datasource segura o aviso de sessão aberta, para o app não entrar antes da hora. Se a gravação falhar, a sessão é fechada e a tela pede um código novo; se a senha for igual à antiga, a pessoa só entra. Ao terminar, a pessoa já está logada. Há 3 testes de cubit e 1 de widget.

**Depende do template "Reset password" com `{{ .Token }}`.** O template padrão do Supabase manda só um link, que abre o site e ainda não é tratado pelo app. Sem o template novo, este fluxo não funciona.

**Ainda não testado com conta real.**

Itens originais da fase:
- Link "Esqueci minha senha" na aba Entrar → tela `/login/recuperar-senha`: e-mail → `resetPasswordForEmail` → código → `verifyOTP(type: OtpType.recovery)`, que abre uma sessão → nova senha → `updateUser(password:)`.
- Não revelar se o e-mail existe: mensagem neutra ("se houver conta, enviamos um código").

### Fase 3 — Conta em Configurações (e-mail e senha) ✅ código pronto (branch `feat/auth-conta-seguranca`, feita a partir da Fase 2, 16/10/2026)

**O que foi feito:**
- Grupo novo **Conta e segurança** nos Ajustes (`AccountSecurityPanel`), com o e-mail atual, a troca pendente (com "Digitar código") e as formas de entrar.
- **Alterar senha:** pede a senha atual, conferida com `signInWithPassword` sem recarregar perfil e casa, e grava a nova com `updateUser(password, currentPassword)`.
- **Alterar e-mail:** novo e-mail → código do novo endereço → se a troca segura estiver ligada, código do e-mail atual. O passo intermediário é reconhecido porque o Supabase não devolve sessão nele.
- O campo de e-mail saiu do "Editar perfil".
- Busca dos Ajustes: entradas "E-mail de acesso" e "Senha".
- Testes: 4 de cubit e 1 de widget.

**Migration 0071** (`20261016100000_0071_sync_profile_email.sql`): gatilho `on_auth_user_email_changed` copia `auth.users.email` para `profiles.email`, mais uma correção única dos perfis desalinhados (hoje: 0). Foi testada em bloco com rollback: o gatilho copia o e-mail, não dispara quando muda outra coluna, `anon` não executa a função e nada ficou gravado. Aplicada em 16/10/2026.

**Depende do template "Change email address" com `{{ .Token }}`.** Sem ele, a troca chega só por link.

**Ainda não testado com conta real.**

Itens originais da fase:
- Separar do "Editar perfil" uma seção **Conta e segurança**: e-mail atual, e-mail pendente (se houver) e métodos de acesso ligados (e-mail/senha, Google).
- **Alterar senha:** senha atual + nova + confirmação. Confere a atual com `signInWithPassword` e depois chama `updateUser(password:)`. Quem só tem Google ganha a opção "Criar senha".
- **Alterar e-mail:** tela própria → `updateUser(email:)` → códigos (no e-mail novo e, com a troca segura, também no antigo) → `verifyOTP(type: OtpType.emailChange)`. Mostrar "aguardando confirmação de <novo>" com reenviar/cancelar.
- **Migration 0071:** gatilho `AFTER UPDATE OF email ON auth.users` que copia o e-mail para `profiles.email`. Será validada com rollback antes de aplicar e só aplicada com o OK do dono.

### Fase 4 — Entrar com Google ⏸️ adiada até a publicação (código já na `main`, botão escondido)

**Decisão do dono (16/10/2026):** a configuração do Google (Google Cloud e Supabase) só será feita quando o app sair dos testes internos e ele decidir publicar. Até lá o botão continua escondido (`GOOGLE_SIGN_IN` desligado) e ninguém precisa mexer nisso. Os passos abaixo valem para esse momento.

**O que foi feito:**
- Botão "Continuar com Google" na tela de login. Fica escondido até ser ligado (`GoogleAuthConfig`, em `lib/core/network/google_auth_config.dart`).
- **Web:** `signInWithOAuth` volta para `/login`; o Supabase troca o código pela sessão ao abrir a página.
- **Android/iOS:** `google_sign_in` 7 → `idToken` (e `accessToken`) → `signInWithIdToken`. Desistir na tela do Google só volta ao login.
- Sair também esquece a conta Google no celular.
- Os testes cobrem o botão escondido e a falha mostrada. O build da web com o botão ligado compila.
- A migration 0071 foi aplicada em 16/10/2026.

**Para ligar (dono):**
1. Google Cloud → APIs e serviços → Tela de consentimento OAuth (nome Omni Lar, e-mail de suporte, domínio `omnilar.web.app`).
2. Credenciais → criar cliente OAuth **Aplicativo da Web**. Origem: `https://omnilar.web.app`. URI de redirecionamento: `https://rygxmpwzofgieodvhpcy.supabase.co/auth/v1/callback`.
3. Criar cliente **Android**: pacote `br.com.omnilar.app` + SHA-1 de debug e de release (`keytool -list -v -keystore ...`).
4. (Se for publicar no iOS) criar cliente **iOS** e pôr o URL scheme invertido do ID iOS em `ios/Runner/Info.plist` (`CFBundleURLTypes`).
5. Supabase → Authentication → Providers → Google: ligar, colar o Client ID/Secret do cliente Web e, em "Authorized Client IDs", os IDs Web, Android e iOS. No iOS, ligar também "Skip nonce checks" (o token nativo do iOS vem com nonce).
6. Supabase → URL Configuration → Redirect URLs: `https://omnilar.web.app/**` e o endereço local de desenvolvimento.
7. Build: `--dart-define=GOOGLE_SIGN_IN=true` (web) e, no celular, também `--dart-define=GOOGLE_WEB_CLIENT_ID=...` e, no iOS, `--dart-define=GOOGLE_IOS_CLIENT_ID=...`. Os IDs não são segredo: depois de criados, podem virar o valor padrão no código, como a chave pública do Supabase.

**Fica para depois:** "Criar senha" para quem entrou só pelo Google (hoje o painel só explica que a conta não tem senha).

**Ainda não testado com conta real.**

Itens originais da fase:
- Botão "Continuar com Google" na tela de login e na landing da web.
- **Web:** `signInWithOAuth(OAuthProvider.google, redirectTo: <origem atual>)`. O PKCE troca o código na volta ao site; conferir que o router espera a sessão (splash) em vez de mandar para `/landing`.
- **Android/iOS:** pacote `google_sign_in` → `idToken`/`accessToken` → `auth.signInWithIdToken(provider: OAuthProvider.google, ...)`. iOS: `GIDClientID` e o URL scheme invertido no `Info.plist`.
- Nome e foto: o Google manda `full_name`/`name` e `avatar_url` nos metadados, que o gatilho já usa. Conferir o fallback para `name`.
- Mesmo e-mail já cadastrado com senha: o Supabase liga as identidades automaticamente quando o e-mail é verificado. Testar esse caso.
- Sair: chamar também `GoogleSignIn().signOut()` no celular, para poder trocar de conta.

### Fase 5 — Testes e acabamento
- `mock_auth_datasource.dart` e `auth_cubit_test.dart`: cobrir aguardando confirmação, código inválido/expirado, reenviar, recuperação de senha, troca de e-mail pendente e Google cancelado.
- Roteiro de teste manual para o dono: as contas reais são criadas por ele (combinado de não criar contas no Supabase hospedado).
- Atualizar `pendencias_proxima_sessao.md`.

## 4. Ordem e dependências

Fase 0 (SMTP e templates) → Fase 1 → Fase 2 → Fase 3 → Fase 5. A Fase 4 (Google) fica para a publicação.
A Fase 4 depende só da parte Google da Fase 0 e pode andar em paralelo com as Fases 2 e 3. Cada fase vira uma branch própria, com merge quando o dono pedir.
