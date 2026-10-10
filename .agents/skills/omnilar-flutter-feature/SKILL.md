---
name: omnilar-flutter-feature
description: >-
  Use when scaffolding or implementing a Flutter feature for Omni Lar
  (feature-first structure, domain/data/presentation layers, Cubit, GoRouter,
  Supabase repository, offline queue, tests). Not for generic Flutter questions.
---

# Omni Lar: Nova Feature Flutter

Referência: `novoSite/arquitetura_tecnica.md` seção 10 e 11.

## Estrutura (feature-first)
```
lib/features/<feature>/
  data/          # datasource Supabase, DTOs, repository_impl
  domain/        # entidades (Dart puro), repository (interface), use cases
  presentation/  # cubit/state, pages, widgets
```
- `domain` **não importa** Flutter nem Supabase.
- Erros viram `Failure` tipado (rede, permissão, validação, conflito), nunca exceção crua na UI.

## Passo a passo
1. Ler o módulo em `novoSite/modulo_*.md` (regras RNxx e casos de teste).
2. Criar entidades imutáveis (`freezed`) e a interface do repositório em `domain`.
3. Escrever os **testes do domínio primeiro** a partir dos casos de teste do módulo.
4. Implementar use cases e depois o repositório em `data` (Supabase). Mapear DTO para entidade.
5. Criar o Cubit com estado `initial/loading/success/failure` (freezed). Sem lógica de negócio no widget.
6. Registrar dependências (`get_it`) e a rota no GoRouter (`StatefulShellRoute` para as 5 abas).
7. Construir as telas com os estados de carregamento, vazio, erro e sem conexão.
8. Se houver escrita: gerar `client_id` (idempotência) e usar a fila offline para ações simples.
9. Rodar a verificação abaixo.

## Regras
- **Dinheiro:** usar o tipo `Money` (centavos `int`). Proibido `double` para valores.
- **Estado derivado:** não gravar status calculável (parcela vencida, tarefa atrasada); calcular a partir dos dados.
- **Cubits** consomem repositórios, não outros Cubits.
- **Realtime:** stream no repositório, convertida em estado; reconciliar por `updated_at` ao reconectar.
- **Ações de risco** (renegociar, perdoar, liquidar, excluir): exigir reautenticação (`local_auth` ou senha) e confirmação reforçada.
- **IA:** nunca gravar dinheiro direto de uma proposta; sempre passar pela tela de revisão e confirmação.
- **Textos:** pt-BR via `intl`; sem strings fixas nos widgets.
- **Acessibilidade:** não depender só de cor (vermelho/verde de P2P tem ícone e texto), alvos de toque adequados.

## Verificação
```
dart format --set-exit-if-changed .
flutter analyze
flutter test
dart run build_runner build --delete-conflicting-outputs   # se mudou freezed/json
```
Conferir: testes do domínio cobrem os casos de teste do módulo; nenhuma importação de `supabase_flutter` em `domain`.
