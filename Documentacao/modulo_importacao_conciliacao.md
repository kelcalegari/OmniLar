Documentação Funcional: Módulo de Importação e Conciliação (Fatura de Cartão e Extrato)

1. Visão Geral e Propósito
   Este módulo importa faturas de cartão e extratos bancários e os concilia com o que já foi lançado no app. Em vez de digitar linha por linha, o usuário envia o arquivo, o app propõe categoria, dono e rateio, detecta duplicidades e cria os lançamentos. Também resolve o caso do cartão de uso misto (casa e pessoal), com uma tela de "Rachar a Fatura" que gera, em um passo, Gastos da Casa e Empréstimos P2P.

2. Conceitos Essenciais
   2.1. Fonte de Importação
   Um cartão ou conta cadastrado em Ajustes (método de pagamento com data de fechamento e vencimento).
   2.2. Arquivo
   Formatos aceitos: OFX, CSV, PDF e imagem (foto/print). Arquivos estruturados (OFX/CSV) são preferidos, e PDF e imagem usam leitura inteligente.
   2.3. Linha Importada
   Cada transação do arquivo (data, descrição, valor, parcela, tipo). Fica em estado de Staging até a confirmação.
   2.4. Conciliação
   Processo de casar cada linha importada com um lançamento existente, ou criar um novo.
   2.5. Regra Aprendida
   Associação "estabelecimento → categoria / dono / rateio" criada a partir de correções do usuário.
   2.6. Rachar a Fatura
   Distribuição das linhas de uma fatura entre Casa, pessoas e dívidas P2P.

3. Regras de Negócio Fundamentais
   RN01: Staging Antes de Gravar
   Linhas importadas ficam numa área de revisão. Nada afeta o Caixa da Casa ou os empréstimos até o usuário confirmar a importação.
   RN02: Identificação da Fonte
   O usuário escolhe o cartão ou a conta. O app valida se o arquivo parece pertencer a ele (por final do cartão ou conta, quando disponível) e avisa se não parecer.
   RN03: Ciclo e Competência
   A data da compra e a data de fechamento da fatura definem em qual ciclo financeiro a despesa pesa. Parcelas futuras de compras parceladas são criadas nos ciclos corretos.
   RN04: Valor Real da Fatura
   Ao importar a fatura, o total real substitui a estimativa nos compromissos do ciclo. O Termômetro de Fôlego passa a usar o valor exato.
   RN05: Detecção de Duplicidade
   O sistema compara cada linha com lançamentos existentes (manuais, da Lista de Compras e de capturas) por valor, data próxima e descrição similar. Linhas com correspondência provável são sugeridas como Vincular. O usuário confirma ou diz "são diferentes".
   RN06: Importação Repetida
   Importar o mesmo arquivo (ou um período já importado) não duplica lançamentos. O app identifica as linhas por uma assinatura (data, valor, descrição, ordem) e ignora as já conciliadas.
   RN07: Classificação Sugerida
   Cada linha recebe sugestão de categoria, dono (Casa, pessoa) e rateio, com base nas regras aprendidas e no histórico. A sugestão tem nível de confiança.
   RN08: Correção em Lote e Aprendizado
   Ao corrigir uma linha, o app oferece "Aplicar a todas as linhas deste estabelecimento" e salva a regra. Regras podem ser vistas e editadas em Ajustes.
   RN09: Rachar a Fatura
   Em um cartão de uso misto, cada linha é atribuída a Casa, a um membro ou a um devedor.
* Linhas da Casa viram Gasto da Casa (com rateio) e consomem o Caixa até o vencimento da fatura.
* Linhas atribuídas a outro membro viram Empréstimo P2P, com o dono do cartão como credor.
* Linhas pessoais do dono do cartão não geram nada no app, apenas ficam no histórico da importação.
  RN10: Estornos e Créditos
  Estornos e créditos são tratados como lançamentos negativos e vinculados à compra original, quando identificada.
  RN11: Pagamento da Fatura
  O pagamento da fatura em si (saída da conta) não é uma despesa nova. Ele é reconhecido e vinculado ao compromisso do cartão, para não contar duas vezes.
  RN12: Extrato Bancário e Reconhecimento de Movimentos
  Entradas e saídas do extrato são comparadas com aportes e parcelas P2P esperados. O app sugere vínculos ("Pix de R$ 200 do Cris, parece o aporte do ciclo"), e o usuário confirma.
  RN13: Desfazer Importação
  Uma importação confirmada pode ser desfeita por completo, e os lançamentos dela são revertidos (exclusão lógica). O histórico da importação permanece.
  RN14: Privacidade
  Os arquivos importados contêm dados sensíveis. O app mascara informações desnecessárias antes de qualquer processamento externo e permite descartar o arquivo original após a conciliação.

4. Descrição de Funcionalidades (Features)
* Importar Arquivo: OFX, CSV, PDF ou imagem, com seleção do cartão ou conta.
* Tela de Conciliação: lista de linhas com status (Nova, Vinculada, Duplicada provável, Ignorada).
* Sugestão de Classificação: categoria, dono e rateio propostos por linha.
* Correção em Lote: aplicar uma decisão a várias linhas semelhantes.
* Rachar a Fatura: atribuição visual de linhas entre Casa e pessoas, com totais por pessoa.
* Resumo da Importação: total da fatura, quanto é da Casa, quanto é de cada pessoa e quanto virou dívida.
* Regras Aprendidas: tela para consultar, editar e remover regras.
* Histórico de Importações: arquivos importados, período, status e opção de desfazer.
* Exportação: CSV com subtotal por fatura, no formato já usado pelo Omni (BOM UTF-8 para Excel).
* Importador do Omni: converte o `repasses_db.json` do app antigo em empréstimos, parcelas e pagamentos.

5. Experiência do Usuário (UX) e Navegação
   5.1. Pontos de Entrada
* Ajustes, em Cartões e Contas, no botão "Importar fatura/extrato".
* Smart FAB, no atalho 📥 Importar.
* A Casa, no card do cartão que está para vencer ("Importar fatura de Nubank?").
  5.2. Fluxo
* Passo 1: escolher o cartão/conta e o arquivo.
* Passo 2: o app lê o arquivo e mostra o resumo (período, total, número de linhas).
* Passo 3: revisar as linhas (duplicadas, sugestões de classificação).
* Passo 4 (cartão misto): Rachar a Fatura.
* Passo 5: conferir o resumo final e confirmar.
  5.3. Tela de Revisão
* Linhas agrupadas por data, com chips de categoria e dono.
* Cores: verde (vinculada), amarelo (baixa confiança), cinza (ignorada).
* Barra de verificação: "Soma das linhas bate com o total da fatura ✔".
  5.4. Rachar a Fatura
* Linhas arrastáveis ou com seleção rápida para Casa, Kelvynn ou Cris.
* Rodapé fixo com totais: "Casa R$ 1.240 | Kelvynn R$ 310 | Cris R$ 95".
  5.5. Feedback Positivo (Nudges)
* "Fatura importada! 42 linhas, 6 já estavam lançadas. 🎉"
* "Aprendi que Posto Ipiranga é do Cris. Vou aplicar nas próximas faturas."
* "O valor real da fatura é R$ 180 menor que o previsto. Seu fôlego do ciclo aumentou."

6. Modelo de Dados Sugerido
```
import_batches(id, member_id, payment_method_id, file_url, file_hash, format,
               period_start, period_end, total_cents, status[staging|confirmed|undone], created_at)
import_lines(id, batch_id, line_signature, date, description, amount_cents, installment_info,
             type[purchase|refund|payment|fee], suggested_category, suggested_owner, confidence,
             decision[new|linked|ignored], linked_target_type, linked_target_id)
import_rules(id, match_pattern, category_id, owner_member_id, split_rule, times_applied, active)
```
Os lançamentos confirmados apontam para `import_batches` e `import_lines` para permitir rastreio e desfazer (RN13).

7. Casos de Teste Derivados
* Linhas importadas não afetam o Caixa antes de confirmar (RN01).
* Importar o mesmo arquivo duas vezes não duplica lançamentos (RN06).
* Linha igual a um gasto manual sugere vínculo (RN05).
* Compra parcelada cria parcelas nos ciclos corretos (RN03).
* Total real da fatura substitui a estimativa e atualiza o Fôlego (RN04).
* Corrigir um estabelecimento cria regra e aplica às linhas semelhantes (RN08).
* Rachar a fatura: linhas da Casa viram Gasto, linhas de outro membro viram Empréstimo P2P (RN09).
* Pagamento da fatura na conta não conta como nova despesa (RN11).
* Desfazer importação reverte todos os lançamentos (RN13).
* Pix de entrada do extrato sugere vínculo a aporte ou parcela P2P (RN12).

8. Fora do Escopo (Versão Atual)
* Conexão automática com bancos (Open Finance). Pode ser uma evolução futura, usando o mesmo fluxo de staging.
* Importação de investimentos.
