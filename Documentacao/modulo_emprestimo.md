> **Especificação original (06/10/2026).** Escrita antes do código. O que foi feito pode ser diferente: em caso de dúvida vale o código. O estado atual está em [plano_diretor_unificado.md](plano_diretor_unificado.md) e [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md).

Documentação Funcional: Módulo de Empréstimos (P2P Familiar)
1. Visão Geral e Propósito
   Este módulo gerencia exclusivamente as dívidas diretas entre os membros da família (ex: dinheiro vivo emprestado, Pix, ou compras pessoais feitas no cartão de crédito de outro membro). O objetivo é garantir que esses valores sejam cobrados de forma justa, permitindo flexibilidade de pagamento, renegociações amigáveis e total transparência sobre a origem da dívida, sem comprometer o histórico financeiro da casa.
2. Regras de Negócio Fundamentais
   RN01: Cobrança por Competência (O Tempo da Dívida)
   O sistema só exige o pagamento de parcelas que vencem no mês atual. Parcelas futuras ou empréstimos "Sem Prazo" ficam registrados no painel do usuário, mas não bloqueiam nem deixam o saldo do mês atual negativo.
   RN02: Pagamento Parcial e Saldo Rolado
   Pagamentos menores que o valor da fatura ou da parcela são permitidos. O sistema não empurra o saldo restante para frente de forma "cega"; a parcela original ou o mês original continuam existindo com o status de "Parcialmente Pago" até serem 100% liquidados.
   RN03: Perdão de Dívida (Anistia)
   Um credor (quem emprestou) tem autoridade para perdoar o saldo devedor restante a qualquer momento. A dívida perdoada não é apagada do sistema (para não quebrar a matemática e o histórico), mas seu status muda para Perdoado, e o devedor deixa de ser cobrado.
   RN04: Renegociação de Parcelas (Refinanciamento)
   Dívidas ativas podem ser reestruturadas. Se o devedor não conseguir pagar, o sistema permite pegar o saldo devedor restante e gerar um novo plano de parcelas. As parcelas antigas pendentes são invalidadas e substituídas pelas novas. Toda renegociação exige o aceite explícito do credor.
   RN05: Transparência Documental (Anexos)
   Para evitar a dúvida de "da onde saiu esse valor quebrado?", empréstimos originados de compras a terceiros (ex: uso do cartão) suportam a anexação da nota fiscal original ou fatura como prova documental inalterável atrelada ao contrato do empréstimo.
3. Descrição de Funcionalidades (Features)
* Calculadora e Edição de Parcelas:
    * Geração automática de parcelas baseada no valor total e quantidade de meses. Permite edição manual de dias de vencimento e valores de parcelas individuais antes da confirmação.
* Abatimentos e Antecipações:
    * Permite adiantar o pagamento de parcelas de meses futuros ou fazer pagamentos avulsos de qualquer valor para empréstimos "Sem Prazo".
* Anexo de Comprovantes (Upload):
    * Durante a criação da dívida, o credor pode anexar fotos (nota fiscal da loja) ou prints (tela da Amazon, comprovante de Pix).
* Solicitação de Renegociação:
    * O devedor pode abrir a dívida e enviar uma proposta: "Desejo redividir os R$ 800 restantes em 4x de R$ 200". O credor recebe o pedido para Aprovar ou Recusar.
* Ação de Perdão de Dívida:
    * Um botão exclusivo na visão do credor que encerra o contrato imediatamente, isentando o devedor de qualquer pagamento futuro relacionado àquele empréstimo.
4. Experiência do Usuário (UX) e Navegação
   4.1. Dashboard de Empréstimos
* Abas Semânticas: "O que eu devo" (Vermelho) e "O que me devem" (Verde).
* Barra de Progresso: Cada empréstimo exibe visualmente quanto já foi pago (ex: Card do Celular - 4/10 parcelas - 40% Pago).
* Transparência a um toque: Ao clicar na dívida, o usuário vê a lista de parcelas e um botão claro "Ver Comprovante" (caso o credor tenha anexado a nota fiscal).
  4.2. Fluxo de Interações Familiares
* Notificação de Aceite de Dívida: Ninguém é pego de surpresa. Se o pai diz que o filho deve R$ 50, o filho recebe um alerta para "Aceitar" a dívida no app.
* UX do Perdão de Dívida: Ao ser perdoado, o devedor recebe uma notificação comemorativa e empática (ex: "Atenção! Seu pai acaba de perdoar os R$ 300 restantes do seu empréstimo! 🎉"). No painel, o card ganha uma etiqueta verde de "Perdoado".
* UX da Renegociação: Interface em formato de "proposta". O devedor vê uma prévia de como ficarão as novas parcelas antes de enviar o pedido. O credor recebe a notificação detalhando o que muda: "João quer mudar de 2x de R$ 400 para 4x de R$ 200. Aprovar?".


5. Ganchos de Captura Inteligente, Importação e IA
* Captura (📷): foto da nota, print da Amazon ou comprovante de Pix sugere valor, data e loja ao criar o empréstimo, e anexa a imagem como prova (RN05).
* Comprovante de Pix de um devedor sugere a baixa da parcela correspondente, com confirmação do credor.
* Importação: no "Rachar a Fatura", linhas atribuídas a outro membro viram Empréstimos P2P, com o dono do cartão como credor. O extrato bancário sugere o vínculo de entradas a parcelas esperadas.
* Importador do Omni: converte o `repasses_db.json` do app antigo em empréstimos, parcelas e pagamentos.
* Assistente: "Quanto o Kelvynn deve ao Cris?", "Renegocia o empréstimo do jogo em 4x" (ação de risco com confirmação reforçada) e mensagem de cobrança educada, pronta para enviar.