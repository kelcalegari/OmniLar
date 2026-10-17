# Omni Lar

Aplicativo para quem mora junto organizar o dinheiro e a rotina da casa num só lugar: Caixa da Casa, rateio, fechamento do ciclo com um único Pix, empréstimos entre moradores, caixinhas, agenda, tarefas, lista de compras, importação de fatura e leitura de nota e boleto.

Feito em Flutter, com Supabase (Postgres, Auth, Realtime, Edge Functions) e Firebase (Hosting e push). Roda no Android e na web (https://omnilar.web.app, instalável no iPhone).

## Documentação

Tudo está em [`Documentacao/`](Documentacao/). Comece por:

- [plano_diretor_unificado.md](Documentacao/plano_diretor_unificado.md): o que funciona, o que falta e onde está o detalhe de cada coisa.
- [pendencias_proxima_sessao.md](Documentacao/pendencias_proxima_sessao.md): estado técnico atual, como trabalhar no projeto e testes pendentes.
- [README_documento_mestre.md](Documentacao/README_documento_mestre.md): visão do produto.

## Comandos

```bash
flutter analyze
flutter test
bash scripts/publicar_web.sh
flutter build apk --release
```

`publicar_web.sh` roda análise, testes, build e deploy no Firebase Hosting (precisa do Firebase CLI logado na conta dona do projeto). Os testes automatizados rodam contra o modo demo, sem Supabase.
