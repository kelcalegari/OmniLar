# Omni Lar — pendências para a próxima sessão

Atualizado em 12/10/2026. Este arquivo resume onde o trabalho parou, o que falta e como trabalhar no projeto. Ele substitui, para fins de continuidade, o `o_que_falta_fazer.md`, que está desatualizado e marca como concluído o que não está.

## Estado atual

- **Código:** `main` local e `origin/main` sincronizadas. A branch `fix/ui-fechamento-e-fila-offline` tem commits ainda não levados para a `main`. Eles dependem das migrations 0027, 0028 e 0029, todas já no banco.
- **Banco (Supabase `rygxmpwzofgieodvhpcy`):** migrations 0001 a 0029 aplicadas. Só as 0022 a 0027 constam no histórico de migrations do Supabase; as 0001 a 0021, a 0028 e a 0029 foram aplicadas à mão pelo SQL Editor (o conector recusou a aplicação da 0028 pelo assistente).
- **Edge Functions:** `capture-read` versão 8 e `assistant` versão 4, ambas com `verify_jwt=true` e exigindo usuário logado que more na casa.
- **Qualidade:** `flutter analyze` com 0 erros (4 warnings antigos de import não usado) e 264 testes passando. Os testes rodam só contra os datasources mock.
- **Dados de teste no banco:** uma casa ("Nossa Casa") com 3 moradores (kelvynn, dono; Cristiano e Joao, membros), rateio 23,33 / 43,34 / 33,33, e 3 empréstimos ativos. Existe uma segunda casa órfã, sem moradores.

## O que foi feito nesta sessão

1. **Segurança (migration 0022):** entrada em casa só por convite válido de uso único (RPC `join_house_with_invite`); convites não listáveis; perdão e renegociação de empréstimo por RPC com checagem de papel; confirmação de transferência só por RPC; Edge Functions autenticadas e com cota.
2. **Rateio e fechamento (0023):** percentuais normalizados; fechamento do ciclo atômico pela RPC `confirm_cycle_settlement`; só admin fecha ou reabre.
3. **Correções de dados:** IDs não-uuid, rateio gravado ao criar despesa, Pix inventado removido, fuso horário (0024).
4. **Itens 14, 15 e 16 da análise:** recorrência de eventos no Supabase, contas atrasadas e competência de cartão, fila offline (4 ações).
5. **Regra de ciclo único e data da baixa (0025):** cada despesa conta em um ciclo só; `paid_at` define o ciclo de uma conta que estava pendente.
6. **Fatura de cartão:** registrar e desfazer o dia do pagamento; bloqueio quando o ciclo está fechado.
7. **Reabrir ciclo (0026):** fechar de novo cobra só a diferença; rateio congelado no fechamento.
8. **Telas:** rateio padrão para 3+ moradores; escolha de como cobrir o excedente do balde no fechamento.

## Pendente: testes manuais no app

Nada disto foi exercitado com usuário logado; só passou por teste automatizado (mock) e por testes de banco com rollback.

- Fechar um ciclo como dono, tentar fechar como membro comum, reabrir, lançar uma despesa esquecida e fechar de novo (o Super Pix deve mostrar só a diferença).
- Fechar um ciclo com conta pendente e com gasto acima do balde (modelo de aportes fixos).
- Criar despesa com rateio personalizado (ex.: 70/30) e de responsável único; reabrir e conferir.
- Registrar e desfazer o pagamento de uma fatura de cartão; tentar com o ciclo fechado.
- Evento recorrente: criar, editar e excluir nos três escopos.
- Conta pendente atrasada sendo arrastada para o ciclo seguinte.
- Horários: evento com hora marcada e tarefa concluída batendo com o relógio.
- Fila offline com o aparelho realmente sem rede (o aviso de "Sem conexão" deve substituir o de sucesso).
- Fechamento visto por membro comum: aviso no lugar do botão de fechar, sem botão de reabrir.
- Caixinha: depositar, resgatar e tentar resgatar acima do saldo (agora dá erro em vez de zerar).
- Excluir "todas" de uma despesa recorrente quando existe outra com o mesmo nome (a outra deve ficar).
- Assistente e leitura de documento com usuário logado (nunca testados com sessão real).

## Pendente: decisões do dono do projeto

- O devedor ainda pode excluir o empréstimo inteiro (política da migration 0018).
- As opções de sobra "rolar para o próximo ciclo" e "estornar aos membros" estão desabilitadas na tela de fechamento ("Ainda não disponível") e a escolha de crédito do morador foi removida: falta decidir se serão implementadas.

## Pendente: limites conhecidos

- **Reabrir ciclo:** com a migration 0029, excluir despesa já acertada passa a ser recusado (a correção é um lançamento de ajuste), mas alterar o valor de uma despesa já acertada continua possível e não gera acerto; trocar a divisão do excedente do balde no segundo fechamento redistribui o excedente inteiro; parcelas P2P e acordos do primeiro fechamento não são desfeitos.
- **Fatura de cartão:** com a migration 0028 o bloqueio de ciclo fechado passa a ser feito no banco, pelas funções `pay_card_invoice` e `undo_card_invoice_payment`; gravar `paid_at` direto na tabela de despesas continua possível para qualquer morador; só funciona para cartão com fechamento e vencimento cadastrados.
- **Dia de início do ciclo:** o painel financeiro e o fechamento passaram a usar o dia configurado na casa (9), no lugar do 5 fixo. Falta conferir no app. O assistente (`assistant_interpreter_service.dart`) ainda usa 5 quando não recebe o ciclo atual.
- **Fila offline:** não há cache local (sem rede as listas não carregam); a tela ainda mostra "adicionada com sucesso" por um instante antes do aviso de "Sem conexão", porque várias telas não esperam a gravação terminar (vale também para erro do servidor); empréstimos, pagamento de parcela e marcar item como comprado ficam de fora.
- **Recorrência de eventos:** horizonte fixo (14 diárias, 8 semanais, 4 quinzenais, 6 mensais, 2 anuais) e a data final da repetição não é gravada.
- **Fechamento:** com a migration 0029 o banco confere o plano (despesas da casa, rateio congelado somando o valor da despesa, transferências, acordos e totais de caixinha), mas o cálculo do rateio continua sendo do app do admin (decisão do dono).
- **Itens médios da análise ainda abertos:** caixinha pode ser criada pelo cliente já com saldo inicial; a sobrecarga antiga `delete_house_expense(uuid)` continua no banco; categorias e formas de pagamento padrão duplicadas; `category_id` de compras nunca gravado; participantes removidos de evento não são apagados; "testar chave" de IA usa `dart:io` (não deve funcionar na web); colunas duplicadas no schema.
- **Documentação:** `o_que_falta_fazer.md` precisa ser reescrito.

## Como trabalhar neste projeto

- **Fluxo de git:** criar uma branch a partir da `main`, commitar nela e, quando o dono pedir, fazer merge fast-forward na `main` e push. Commit e push só a pedido.
- **Banco:** qualquer alteração no Supabase é confirmada com o dono antes de aplicar. Migrations ficam em `supabase/migrations/` e são aplicadas pelo conector do Supabase.
- **Validação de SQL:** rodar a migration e os testes dentro de um bloco `DO` que termina em `RAISE EXCEPTION` com os resultados, o que desfaz tudo (rollback). Para simular um usuário: `set_config('request.jwt.claims', ...)` com o `sub` do usuário e `set local role authenticated`.
- **Contas e login:** o assistente não cria contas nem faz login no Supabase hospedado. Fluxos que exigem sessão real são testados pelo dono no app; depois dá para conferir no banco e nos logs.
- **Depois de mudar código que depende de migration:** reiniciar por completo as instâncias abertas do app. A migration 0024 (fuso) só pode rodar uma vez.
- **Não há Deno nem Supabase CLI na máquina.** As Edge Functions são publicadas pelo conector, enviando o conteúdo dos arquivos.
