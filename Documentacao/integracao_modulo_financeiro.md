> **Especificação original (06/10/2026).** Escrita antes do código. O que foi feito pode ser diferente: em caso de dúvida vale o código. O estado atual está em [plano_diretor_unificado.md](plano_diretor_unificado.md) e [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md).

Documentação Funcional: Integração Global do App (Ecossistema Financeiro)

1. Visão Geral da Arquitetura de Negócios
   O aplicativo consolida duas realidades financeiras em uma única plataforma:
* O Coletivo (Caixa da Casa): Onde vocês somam forças para manter o padrão de vida.
* O Individual (P2P): Onde vocês mantêm a individualidade para gastos pessoais, emprestando o cartão ou dinheiro um para o outro.
  A integração entre esses módulos é garantida por um Motor de Compensação Global, que cruza as obrigações do Caixa da Casa com as dívidas interpessoais, gerando um único fechamento financeiro simples e sem atritos.

2. Regras de Negócio de Integração (Interseções)
   RN-INT-01: A "Casa" como Terceira Entidade
   Logicamente, a "Casa" tem uma conta virtual.
* Se o Kelvynn paga a conta de luz com o dinheiro do próprio bolso (não com o dinheiro do aporte), a "Casa" passa a dever para o Kelvynn.
* Se o Cris pega R$ 100 do envelope do supermercado para comprar algo pessoal, o Cris passa a dever para a "Casa" (gera um Empréstimo P2P onde o credor é a Casa).
  RN-INT-02: O Fechamento Unificado (O "Super Pix")
  Esta é a regra de ouro da integração. Vocês não farão um Pix para acertar a casa e outro Pix para acertar os empréstimos pessoais. No último dia do Ciclo Financeiro, o sistema cruza tudo:
* Matemática: [Saldo de Aportes da Casa] + [Reembolsos por despesas cruzadas] + [Dívidas P2P do mês] = Saldo Líquido.
* Exemplo Prático:
    * Kelvynn deve R$ 500 de Aporte para a Casa.
    * Kelvynn deve R$ 100 para o Cris (Empréstimo P2P de um jogo).
    * A Casa deve R$ 200 para o Kelvynn (Ele pagou a luz do próprio bolso).
    * Resultado do Motor: O sistema subtrai os R$ 200 do aporte, soma os R$ 100 do jogo, e avisa: "Kelvynn, faça um único Pix de R$ 400 para a conta do Cris". Fim. Tudo liquidado.
      RN-INT-03: Abatimento de Dívidas com Sobra do Caixa
      Se no final do Ciclo Financeiro a "Casa" teve lucro (sobrou dinheiro no Fundo de Reserva) e a família decidir "sacar" esse dinheiro em vez de guardar, o sistema verifica se há Empréstimos P2P pendentes.
* Ação do Sistema: Antes de devolver R$ 100 de sobra para o Kelvynn, o app avisa: "Você tem uma dívida P2P com o Cris de R$ 80. Deseja usar sua parte da sobra da casa para abater essa dívida?"

3. Experiência do Usuário (UX) e Navegação Global
   Para que o app não pareça ter duas "personalidades" diferentes, a navegação precisa ser unificada e intuitiva.
   3.1. A Estrutura do App (Bottom Navigation Bar)
   O aplicativo terá 5 abas principais no rodapé:
* 🏠 A Casa: O Dashboard do Ciclo Financeiro (Timeline, Fôlego do mês, Lembretes de contas a vencer, cards de Compras e Tarefas).
* 🤝 Pessoal (P2P): O Dashboard de empréstimos diretos entre vocês (O que eu devo / O que me devem, Dívidas Perdoadas, Solicitações de Renegociação).
* 📅 Agenda: Calendário de eventos e tarefas com data (compromissos da casa e RSVP de participantes).
* 📊 Relatórios: Analytics unificado. Visão de categorias da casa e histórico de pagamentos gerais.
* ⚙️ Ajustes: Configurações de Regras de Rateio, Cadastro de Cartões, VR, Definição do dia de início do Ciclo, regras aprendidas e preferências do assistente.
  3.2. O "Smart FAB" (Floating Action Button Universal)
  Haverá apenas um botão grande de + (Adicionar) no centro do aplicativo. Ao clicar nele, o sistema abre um menu inteligente de contexto agrupado:
* **Financeiro:** 🛒 Gasto da Casa, 💸 Empréstimo / Fiado, 📥 Registrar Aporte, 📄 Importar Fatura/Extrato.
* **Casa:** 📅 Evento, ✅ Tarefa, 🛍️ Item de Compras.
* **Inteligente:** 📷 Escanear, ✨ Assistente.
  3.3. O "Hub de Liquidação" (A Tela de Fechamento)
  Quando o Ciclo "vira" (ex: chegou o dia 04 e o salário cai no dia 05), o aplicativo exibe um Card em destaque na tela inicial: "Resumo do Ciclo Encerrado".
  Ao clicar, a UX apresenta um recibo claro e detalhado:
* Passo 1 (Resumo da Casa): Mostra se a casa fechou no azul ou no vermelho.
* Passo 2 (Resumo P2P): Mostra as parcelas interpessoais que venceram neste mês.
* Passo 3 (O Veredito): O botão de ação final com a instrução exata: "Kelvynn, transfira R$ 400 para o Cris".
* Ao confirmar, o sistema liquida automaticamente todas as faturas e parcelas envolvidas daquele mês, carimbando-as como "Pagas".

4. Fluxos de Interseção (Casos de Uso na Prática)
   Para garantir que a documentação cobre a vida real, veja como os dois módulos operam juntos nos cenários mais confusos:
   Cenário A: O Cartão Pessoal usado para a Casa e para Uso Próprio
* A Situação: O Cris vai ao mercado. Compra R$ 200 de mantimentos para a Casa, mas aproveita e passa R$ 50 de uma camisa para o Kelvynn na mesma nota do cartão dele.
* Como o App resolve:
    * O Cris abre o app, clica no + e escolhe "Gasto da Casa" (R$ 200, Categoria Mercado).
    * Em seguida, clica no + e escolhe "Empréstimo" (R$ 50, Devedor: Kelvynn, Anexa a foto da notinha).
    * Resultado: O Caixa da Casa entende que precisa cobrir os R$ 200 do Cris até o vencimento do cartão dele. E o módulo P2P adiciona R$ 50 na aba "O que me devem" do Cris. Tudo organizado.
      Cenário B: Antecipando Aportes (Pagando conta com dinheiro que não é da casa)
* A Situação: A conta de luz venceu, mas o Fundo da Casa ainda está zerado (o aporte ainda não foi feito). O Kelvynn paga a luz de R$ 150 com o dinheiro da conta corrente pessoal dele para não gerar multa.
* Como o App resolve:
    * O Kelvynn lança a Despesa da Casa (Luz - R$ 150), mas marca que o método de pagamento foi "Conta Pessoal - Kelvynn".
    * O Motor de Compensação transforma esse ato de heroísmo em um Aporte Antecipado. Quando chegar o dia do Kelvynn depositar a parte dele no Caixa da Casa, o sistema vai cobrar R$ 150 a menos dele.

5. Próximos Passos (Para a fase técnica)
   Com essa integração funcional definida, quando você for passar para a arquitetura técnica (Flutter + Supabase), você terá clareza para modelar:
* Uma tabela central de transações (transactions) que usa Polimorfismo (pode apontar tanto para uma house_expense quanto para um p2p_loan).
* O padrão BLoC / Provider gerenciando o estado do GlobalClearingEngine (o motor matemático que junta as duas realidades).
* O GoRouter lidando com deeplinks de notificações (ex: O Cris aperta na notificação de "Renegociação de Dívida" e o router abre a aba P2P diretamente).

6. Mapa dos Módulos e Princípios de IA
   6.1. Mapa dos Módulos
* Financeiro: Despesas da Casa, Empréstimos P2P, Integração (Motor de Compensação), Importação e Conciliação.
* Organização: Calendário, Lista de Tarefas, Lista de Compras.
* Inteligência: Captura Inteligente e Assistente IA.
   6.2. Interseções Novas
* Lista de Compras para Casa: o fechamento da compra gera o Gasto da Casa (itens pessoais geram Empréstimo P2P).
* Importação para Casa e P2P: a fatura importada fixa o valor real do ciclo e o "Rachar a Fatura" cria Gastos da Casa e Empréstimos.
* Captura para qualquer módulo: a proposta nasce de uma foto e só grava após confirmação.
* Assistente para todos: consulta e propõe ações em qualquer módulo, sempre com confirmação e respeitando permissões.
* Tarefa e Calendário: o mesmo registro, com duas visões.
   6.3. Princípios Transversais de IA
* Dinheiro nunca é gravado sem revisão humana.
* Cálculos financeiros são sempre feitos pelo motor determinístico, nunca pela IA.
* Dados sensíveis são mascarados antes do processamento no servidor.
* O app continua funcionando por completo sem IA (fallback manual).