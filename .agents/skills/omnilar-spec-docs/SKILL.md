---
name: omnilar-spec-docs
description: >-
  Use when the user asks to create, edit, review or cross-check the Omni Lar
  product documentation in novoSite (modules, master doc, technical doc), or
  before implementing a module so the agent reads the right spec first.
---

# Omni Lar: Especificação e Documentação

Projeto novo do zero (app de finanças e organização da casa). Todas as specs ficam em `novoSite/`. Nada do app antigo "omni" (pasta `lib/`) deve ser reaproveitado.

## Mapa dos documentos
| Arquivo | Conteúdo |
|---|---|
| `Documentacao\/README_documento_mestre.md` | Visão, mapa dos módulos, navegação, regras transversais, roadmap, identidade |
| `Documentacao/arquitetura_tecnica.md` | Auth, Supabase (banco, RLS, storage, realtime, functions), IA (Gemini), Flutter, testes, CI, LGPD |
| `Documentacao/modulo_despesas_de_casa.md` | Caixa da Casa, ciclo, rateio |
| `Documentacao/modulo_emprestimo.md` | Empréstimos P2P |
| `Documentacao/integracao_modulo_financeiro.md` | Motor de Compensação, Super Pix, Hub de Liquidação |
| `Documentacao/modulo_importacao_conciliacao.md` | Fatura e extrato |
| `Documentacao/modulo_calendario.md`, `modulo_lista_de_tarefas.md`, `modulo_lista_de_compras.md` | Organização |
| `Documentacao/modulo_captura_inteligente.md`, `modulo_assistente_ia.md` | Inteligência |

## Procedimento
1. Antes de implementar ou alterar um módulo, leia o arquivo do módulo **e** as seções relevantes de `arquitetura_tecnica.md` e das regras transversais do mestre.
2. Preserve a estrutura dos módulos: 1 Visão Geral, 2 Conceitos, 3 Regras de Negócio (RNxx), 4 Funcionalidades, 5 UX, 6 Modelo de Dados, 7 Casos de Teste, 8 Fora do Escopo, seções de ganchos (Captura/IA).
3. Regras de negócio são numeradas `RN01...` por módulo. Ao criar uma regra nova, use o próximo número livre e adicione um caso de teste correspondente na seção de casos de teste.
4. Ao mudar um conceito que atravessa módulos (aba, Smart FAB, status derivado, integração), atualize **todos** os arquivos afetados e a tabela de interseções do mestre.
5. Se a decisão for técnica, registre em `arquitetura_tecnica.md` (seção 15 para decisões em aberto) e referencie a partir do mestre.
6. Idioma: português do Brasil. Não apague comentários ou conteúdo não relacionado à mudança.

## Verificação de consistência (rodar ao final)
- Número de abas = 5 (Casa, Pessoal, Agenda, Relatórios, Ajustes). O item 3.1 de `integracao_modulo_financeiro.md` está desatualizado, vale a seção 6 do mesmo arquivo.
- Seções numeradas sem duplicidade (conferir seções acrescentadas no fim dos arquivos).
- Valores sempre em centavos, status derivados, IA com confirmação humana.
- Menções ao app Omni antigo devem ser tratadas como obsoletas (importador, formato CSV do Omni).
- Links relativos entre os `.md` funcionam.
