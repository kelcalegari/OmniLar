Documentação Funcional: Módulo Assistente IA

1. Visão Geral e Propósito
   O Assistente IA é um agente conversacional (texto e voz) que conhece a casa: Caixa, empréstimos, calendário, compras e tarefas. Ele responde perguntas, executa ações por linguagem natural e avisa proativamente sobre o que importa. Princípio central: a IA interpreta e sugere, o motor determinístico do app calcula e grava, e toda ação que altera dados exige confirmação do usuário.

2. Conceitos Essenciais
   2.1. Consulta
   Pergunta que só lê dados ("quanto sobrou no Caixa?").
   2.2. Ação
   Pedido que altera dados ("adiciona leite na lista"). Sempre passa por um cartão de confirmação.
   2.3. Cartão de Confirmação
   Resumo do que será feito, com Confirmar, Editar e Cancelar. Nada é gravado antes de Confirmar.
   2.4. Proativo
   Mensagens que o assistente envia sem ser perguntado (resumos, alertas, sugestões).
   2.5. Contexto da Casa
   Dados que o assistente pode consultar, limitados às permissões do usuário que está falando com ele.
   2.6. Ferramentas (Tools)
   Funções do app que o assistente chama (consultar saldo, criar item, criar evento). O assistente nunca acessa o banco diretamente, só pelas ferramentas.

3. Regras de Negócio Fundamentais
   RN01: Confirmação Obrigatória
   Toda ação que cria, altera, exclui ou liquida algo exige confirmação explícita no Cartão de Confirmação. Consultas não exigem.
   RN02: Cálculo Determinístico
   Valores financeiros (saldo, dívida, rateio, liquidação) vêm sempre do motor de cálculo do app. O assistente apresenta o resultado e a origem, e não calcula por conta própria.
   RN03: Respeito a Permissões e Visibilidade
   O assistente só vê o que o usuário logado pode ver. Eventos Privados, tarefas privadas e dívidas de outros não aparecem para terceiros. Perguntas sobre dados inacessíveis recebem uma resposta de que não há permissão.
   RN04: Ações em Nome de Outros
   O assistente pode registrar ações que envolvem outras pessoas (marcar alguém num evento, atribuir tarefa), mas o efeito segue as regras do módulo (aceite, RSVP, pedido de troca). Ele nunca confirma pelo outro.
   RN05: Transparência
   Cada resposta numérica indica a origem ("com base no ciclo de 05/10 a 04/11") e permite abrir a tela correspondente.
   RN06: Ambiguidade
   Se o pedido for ambíguo (duas pessoas com o mesmo nome, valor sem categoria), o assistente pergunta em vez de assumir.
   RN07: Ações de Risco
   Ações como renegociar, perdoar dívida, liquidar o ciclo e excluir exigem confirmação reforçada (segundo toque ou biometria) e nunca são feitas em lote pelo assistente.
   RN08: Nível de Autonomia
   Na versão atual o assistente nunca grava sozinho. Não há limite de valor para lançamento automático. A autonomia só pode mudar em versão futura, com configuração explícita da casa.
   RN09: Histórico das Ações
   As ações propostas, confirmadas, editadas e canceladas ficam registradas (quem pediu, o que foi sugerido, o que foi gravado) para auditoria. O usuário pode ver e apagar o histórico de conversas.
   RN10: Proativo com Controle
   Mensagens proativas podem ser configuradas por tipo e frequência, ou desligadas. O assistente não envia notificações fora do horário configurado.
   RN11: Privacidade
   Dados enviados ao modelo são minimizados e mascarados (sem CPF, números de cartão e conta). O processamento ocorre no servidor, conforme a política do app. O usuário pode desativar o assistente a qualquer momento.
   RN12: Limites e Erros
   Se o assistente não souber responder, ele diz isso e oferece a tela manual correspondente. Falhas de serviço não bloqueiam o uso normal do app.
   RN13: Idioma e Tom
   Responde em português do Brasil, com tom claro e neutro. Em cobranças e mensagens a outras pessoas, usa um tom educado, nunca acusatório.

4. Descrição de Funcionalidades (Features)
   4.1. Consultas
* Financeiro: saldo livre, comprometido, o que vence até uma data, quanto cada um deve, por que uma conta subiu.
* Compras: o que falta na lista, quando um item costuma acabar, quanto foi gasto no mercado no mês.
* Calendário e Tarefas: compromissos da semana, quem não respondeu, tarefas atrasadas, divisão de esforço.
  4.2. Ações por Linguagem Natural
* "Adiciona leite e ovos na lista de mercado."
* "Marca como comprado o pão e o café."
* "Lança R$ 80 de gasolina, categoria Carro."
* "Marca jantar sábado às 20h e chama o Cris como necessário."
* "Cria tarefa para o Kelvynn: levar o lixo, toda terça."
* "Renegocia o empréstimo do jogo em 4x."
  4.3. Proativo
* Resumo semanal da casa: contas a vencer, tarefas atrasadas, eventos sem resposta e fôlego do ciclo.
* Alertas: aporte pendente perto do vencimento, conta variável acima da média, possível cobrança duplicada.
* Sugestões: reposição de itens, importar a fatura que vence, rodízio de tarefa.
* Mensagem de cobrança pronta a partir do "Veredito" do Hub de Liquidação, em tom educado, para enviar com um toque.
  4.4. Apoio à Captura e à Importação
* Explica a leitura ("li este valor com baixa confiança, confira").
* Ajuda a classificar linhas de fatura e propõe regras aprendidas.
* Responde dúvidas sobre divergências ("por que a soma não bate?").
  4.5. Planejamento
* Simulações: "Dá para comprar X sem estourar o ciclo?", exibindo o cálculo feito pelo motor, não pela IA.
* Previsão de contas variáveis para o Termômetro de Fôlego.
  4.6. Voz
* Comandos por voz com transcrição na tela antes de executar.

5. Experiência do Usuário (UX) e Navegação
   5.1. Pontos de Acesso
* Smart FAB: opção ✨ Assistente.
* Barra de busca/pergunta no topo da aba A Casa.
* Atalhos contextuais ("Perguntar sobre esta conta") nas telas de Casa, Pessoal, Agenda e Compras.
  5.2. Tela de Conversa
* Chat simples, com sugestões de perguntas ("O que vence esta semana?").
* Respostas com cartões visuais (mini-gráfico, lista de itens, evento) e link para a tela completa.
  5.3. Cartão de Confirmação
* Resumo claro: "Vou adicionar: leite (2), ovos (1 dúzia) em Lista de Mercado."
* Botões Confirmar, Editar e Cancelar. Ações de risco pedem segundo toque.
  5.4. Preferências
* Em Ajustes: ligar ou desligar o assistente, tipos de alerta proativo, horários, voz e histórico.
  5.5. Feedback Positivo (Nudges)
* "Pronto! Adicionei 2 itens na sua lista. ✅"
* "Esta semana tudo em dia: nenhuma conta atrasada e todos confirmaram o jantar. 🎉"

6. Modelo de Dados Sugerido
```
assistant_conversations(id, member_id, started_at)
assistant_messages(id, conversation_id, role[user|assistant|tool], content, created_at)
assistant_actions(id, conversation_id, tool_name, arguments_json, status[proposed|confirmed|edited|cancelled|failed],
                  result_ref_type, result_ref_id, confirmed_at)
assistant_preferences(member_id, enabled, proactive_types_json, quiet_hours, voice_enabled)
```
As ferramentas expostas ao assistente seguem as mesmas regras de permissão (RLS) do app. As chamadas passam por uma camada de validação antes de executar.

7. Casos de Teste Derivados
* Ação sem confirmação não grava nada (RN01).
* Pergunta de saldo retorna o valor do motor, com origem (RN02/RN05).
* Usuário não vê evento Privado de outro membro (RN03).
* Marcar o Cris em evento gera convite, sem aceite automático (RN04).
* Pedido ambíguo gera pergunta de esclarecimento (RN06).
* Perdoar dívida exige confirmação reforçada (RN07).
* Histórico mostra proposta, edição e confirmação (RN09).
* Desligar o assistente remove acessos e alertas (RN10/RN11).
* Falha do serviço de IA não impede lançamentos manuais (RN12).

8. Fora do Escopo (Versão Atual)
* Lançamentos automáticos sem confirmação.
* Conselhos de investimento ou recomendações financeiras personalizadas.
* Conversa com terceiros em nome do usuário (envio de mensagens externas sem toque do usuário).


9. Provedor de IA e Economia de Chamadas
   O assistente usa a Gemini API (Google AI Studio), começando no plano gratuito (detalhes na seção 17 de [arquitetura_tecnica.md](arquitetura_tecnica.md)).
* Atalhos sem IA: perguntas frequentes ("O que vence esta semana?", "Quanto sobrou no Caixa?", "O que falta na lista?") aparecem como botões que chamam funções do app diretamente, sem consumir a IA.
* A IA entra quando o pedido exige interpretação de linguagem natural (criar item, evento ou tarefa por frase, perguntas abertas). Ela usa *function calling* para chamar as ferramentas do app, e as ferramentas executam com as permissões do usuário.
* Limite de uso por usuário e por Casa por dia. Ao atingir o limite ou em caso de erro, o assistente informa e indica a tela manual (RN12).
* Proativo (resumos e alertas): gerado por regras e consultas do banco, com a IA apenas para redigir o texto, de preferência uma vez por período e em lote.
* Dados enviados ao modelo são mínimos e mascarados (RN11). Sem CPF, número de cartão ou conta.
* Plano gratuito: o conteúdo enviado pode ser usado pelo Google para melhoria dos produtos. Em desenvolvimento, use apenas dados seus ou fictícios. Antes de convidar outros usuários, migre para o plano pago e atualize o texto de consentimento.
