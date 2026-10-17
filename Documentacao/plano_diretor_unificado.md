# Omni Lar — onde estamos e o que falta

Reescrito em 17/10/2026. É o painel de cima do projeto: o que já funciona, o que falta e onde está o detalhe de cada coisa. A visão do produto está em [README_documento_mestre.md](README_documento_mestre.md); o estado técnico do dia a dia, as decisões do dono e os testes manuais pendentes estão em [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md), que é o ponto de partida de cada sessão.

## 1. Situação geral (17/10/2026)

| Item | Situação |
|---|---|
| Código | `main` no GitHub (`kelcalegari/OmniLar`), com tudo das branches de decisões, notificações, login, painel administrativo e pendências |
| Qualidade | `flutter analyze` sem erros nem warnings; 610 testes automatizados passando (só contra o modo demo, nenhum contra o Supabase); CI no GitHub Actions (`.github/workflows/ci.yml`) |
| Banco | Supabase `rygxmpwzofgieodvhpcy`, migrations 0001 a 0075 aplicadas |
| Edge Functions | `capture-read`, `assistant`, `import-read`, `nfce-read` (com login) e `notify` (chamada pelo banco) |
| Site | https://omnilar.web.app (Firebase Hosting, projeto `omnilar-ef002`), publicado em 17/10/2026 |
| Android | APK de release gerado à mão (`flutter build apk --release`), ainda assinado com a chave de debug |
| iPhone | Sem App Store: o app é usado como site instalado na Tela de Início (PWA) |
| Uso | Uma casa ("Nossa Casa"), duas contas; o dono testa com sessão real |

## 2. O que já funciona

**Dinheiro da casa**
- Caixa da Casa por ciclo, com dia de início configurável (inclusive 29 a 31 e troca a partir do próximo ciclo), três modelos de rateio (porcentagem, aportes fixos e por categoria) e categoria com dono.
- Despesas compostas (sub-itens com responsável), contas recorrentes geradas no banco, contas a pagar com boleto (código guardado e copiado), compra no cartão dentro da fatura, pagamento da fatura pelo titular ou pelo Caixa.
- Fechamento do ciclo atômico (Super Pix, memória de cálculo, retrato do fechamento, reabrir), sobra do Caixa, pagamento parcial e acordos com o Lar.
- Empréstimos entre moradores (parcelas, pagamento parcial, perdão, renegociação, exclusão controlada) e caixinhas (meta com prazo, histórico, transferência, depósito e resgate ligados ao ciclo).
- Importação de fatura e extrato (OFX, CSV, PDF e foto por IA), com conciliação, regras aprendidas, estorno, divisão de linha e desfazer.
- Relatórios com prévia do fechamento, calendário de pagamentos, próximos ciclos, saldo do Caixa por dia e exportação em CSV e PDF.
- Projetos compartilhados (viagens, reformas) com rateio próprio entre participantes.

**Rotina**
- Agenda (eventos, participantes necessários, respostas, séries com "repetir até"), tarefas e lista de compras compartilhadas, tudo em tempo real.
- Fila offline para os lançamentos simples, marcar e excluir itens e tarefas.

**Captura e IA**
- Escâner de nota (QR da NFC-e consultado na Sefaz; SC vai direto para a foto), boleto (código de barras e linha digitável conferidos) e foto lida por IA (Gemini), sempre com revisão antes de gravar.
- Assistente com propostas que só gravam depois de confirmadas.

**Contas e administração**
- Cadastro com confirmação por código, "Esqueci minha senha", troca de e-mail e senha; login com Google pronto e escondido até a publicação.
- Aprovação de contas novas, planos Free e Premium e painel administrativo (`/admin`).
- Notificações: sino com tempo real, gatilhos na hora, lembretes agendados (`pg_cron`) e push pelo FCM (Android, navegador e iPhone instalado). O envio do push ainda não foi visto chegar num aparelho.

## 3. O que falta

### 3.1. Agora (depende do dono)
- Testes manuais com sessão real dos itens de 15, 16 e 17/10 (lista em `pendencias_proxima_sessao.md`).
- Confirmar que um push chega no celular.

### 3.2. Antes de abrir para outras casas
- **Levar o cálculo do fechamento para o banco:** adiado por decisão do dono; plano em [fechamento_no_banco.md](fechamento_no_banco.md).
- **Alertas do Supabase:** revogar `anon` nas funções de gatilho, otimizar as regras de acesso (`(select auth.uid())`), índices nas chaves estrangeiras e proteção contra senha vazada (detalhe em `pendencias_proxima_sessao.md`).
- **IA no plano pago:** no plano gratuito o Google pode usar o conteúdo enviado (seção 17 de [arquitetura_tecnica.md](arquitetura_tecnica.md)).
- **SMTP próprio** para os e-mails de confirmação e senha (o padrão do Supabase tem limite baixo) — ver [plano_autenticacao.md](plano_autenticacao.md).
- **Exclusão de conta (LGPD):** Edge Function `delete-account` (decisão 10 de [plano_painel_admin.md](plano_painel_admin.md)).

### 3.3. Publicação
- Chave de assinatura própria do Android e pacote `.aab` para a Google Play.
- Login com Google (configuração no Google Cloud e no Supabase, Fase 4 de `plano_autenticacao.md`).
- Termos de uso e política de privacidade; domínio próprio (trocar o endereço obriga a reinstalar o site no iPhone e reativar as notificações).

### 3.4. Evolução (sem data)
- Notificações: aceite de empréstimo pelo devedor, gatilhos informativos restantes, preferências nos Ajustes, resumo semanal e alertas do Assistente ([plano_notificacoes.md](plano_notificacoes.md), seção 0).
- Cópia local para abrir sem internet (hoje a fila offline só cobre a conexão que cai no meio do uso).
- Web/desktop: área de soltura de arquivos na importação, modo grade dos lançamentos e atalho `Ctrl + F`.
- Leitura de boleto de condomínio com os itens (água, gás, fundo de reserva) já separados.
- "Criar senha" para quem entrou só pelo Google.

## 4. Documentos

| Documento | Para quê |
|---|---|
| [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md) | Estado técnico atual, como trabalhar no projeto, decisões do dono, testes manuais pendentes e lista das migrations |
| [README_documento_mestre.md](README_documento_mestre.md) | Visão do produto, glossário, módulos e regras transversais |
| [arquitetura_tecnica.md](arquitetura_tecnica.md) | Arquitetura (proposta original e, na seção 0, como ficou) e regras da IA |
| [plano_notificacoes.md](plano_notificacoes.md) | Notificações: andamento, catálogo e decisões |
| [plano_painel_admin.md](plano_painel_admin.md) | Aprovação de contas, planos e painel |
| [plano_autenticacao.md](plano_autenticacao.md) | Cadastro, senha, e-mail e Google |
| [plano_importacao_conciliacao.md](plano_importacao_conciliacao.md) | Importação de fatura e extrato |
| [plano_relatorios_previa_ciclo.md](plano_relatorios_previa_ciclo.md) | Relatórios, prévia e exportação |
| [fechamento_no_banco.md](fechamento_no_banco.md) | Trabalho adiado: cálculo do fechamento no banco |
| `modulo_*.md` e [integracao_modulo_financeiro.md](integracao_modulo_financeiro.md) | Especificação original de cada módulo (06/10/2026); pode divergir do que foi feito, e em caso de dúvida vale o código |
