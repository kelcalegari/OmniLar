Documentação Funcional: Módulo de Lista de Tarefas (Tarefas Domésticas)

1. Visão Geral e Propósito
   Este módulo organiza as responsabilidades da casa: quem faz o quê, até quando e com que frequência. Substitui o "achei que você ia fazer" por tarefas com responsável, prazo e conclusão visível para todos. Ele cobre tarefas avulsas (trocar lâmpada) e rotinas recorrentes (tirar o lixo, lavar o banheiro), com rodízio automático entre os membros.

   Relação com o Calendário: o módulo de Calendário permite transformar um evento em tarefa. A Lista de Tarefas é a visão focada em afazeres (com checklist, rodízio e rotinas). Tarefas com data aparecem na Agenda, e tarefas criadas no Calendário aparecem aqui, sem duplicação (o mesmo registro, duas visões).

2. Conceitos Essenciais
   2.1. Tarefa
   Título, descrição, responsável, prazo (opcional), prioridade, categoria e checklist de subitens.
   2.2. Estados
   A fazer, Em andamento, Concluída e Atrasada (derivado: prazo vencido e não concluída).
   2.3. Rotina (Tarefa Recorrente)
   Modelo que gera tarefas automaticamente (diária, semanal, mensal ou personalizada), com responsável fixo ou em rodízio.
   2.4. Rodízio
   Distribuição automática da rotina entre os membros, para dividir o trabalho de forma justa.
   2.5. Pontos e Equilíbrio (Opcional)
   Cada tarefa tem um peso (esforço). O app mostra a divisão do esforço entre os membros no ciclo.

3. Regras de Negócio Fundamentais
   RN01: Responsável Único
   Uma tarefa tem um responsável por vez. Tarefas sem responsável ficam no "Quadro Aberto", e qualquer membro pode assumi-las.
   RN02: Atribuição e Aceite
   Quando alguém atribui uma tarefa a outra pessoa, o destinatário recebe a notificação e pode Aceitar ou Pedir Troca. Quem criou decide se aprova a troca.
   RN03: Conclusão
   O responsável e o criador podem concluir a tarefa. O app registra quem concluiu e quando. Concluir uma tarefa com checklist exige confirmação se houver subitens pendentes.
   RN04: Atraso
   Tarefa com prazo vencido e não concluída fica Atrasada, e o responsável é lembrado. O prazo pode ser reagendado e o histórico guarda o número de reagendamentos.
   RN05: Rotinas e Geração
   Cada rotina gera a próxima tarefa quando a anterior é concluída ou quando o prazo vence, o que acontecer primeiro. Não acumula tarefas repetidas: se a anterior continuar aberta, ela fica Atrasada e a próxima não é criada em duplicidade.
   RN06: Rodízio Justo
   No rodízio, a próxima tarefa vai para quem tem menor carga no ciclo (considerando o peso). Membros em Ausência (viagem, doença) são ignorados e voltam ao rodízio ao retornar.
   RN07: Troca e Cobertura
   Um membro pode pedir que outro cubra uma tarefa específica sem alterar o rodízio. A cobertura conta para o equilíbrio de quem fez.
   RN08: Tarefas Privadas
   Tarefas pessoais ficam visíveis só ao criador, sem entrar no equilíbrio da casa.
   RN09: Histórico
   Tarefas concluídas ficam no histórico, não são apagadas. Excluir uma tarefa é permitido apenas ao criador, e a exclusão é lógica.
   RN10: Tarefas com Custo
   Se uma tarefa exige gasto (ex.: "comprar lâmpada"), ao concluir o app oferece registrar um Gasto da Casa, ou adicionar o item na Lista de Compras.

4. Descrição de Funcionalidades (Features)
* Quadro de Tarefas: visões "Minhas", "Da Casa", "Quadro Aberto" e "Concluídas".
* Checklist: subitens dentro da tarefa, com progresso.
* Rotinas e Rodízio: criação de rotinas com frequência e quem participa.
* Peso e Equilíbrio: gráfico simples de esforço por membro no ciclo.
* Prioridade e Etiquetas: Alta, Média e Baixa, e categorias (Limpeza, Manutenção, Pets, Burocracia).
* Comentários: conversa curta dentro da tarefa e anexos de foto (ex.: foto do vazamento).
* Lembretes: por prazo e por pessoa (mesmo mecanismo do Calendário).
* Reagendamento: alterar o prazo com um toque.
* Ausência: marcar período em que a pessoa não entra no rodízio.

5. Experiência do Usuário (UX) e Navegação
   5.1. Localização
   Acessível por A Casa (card "Tarefas") e pela aba Agenda (filtro "Tarefas"). O Smart FAB ganha ✅ Tarefa.
   5.2. Tela Principal
* Topo: "Hoje" com as tarefas de hoje e as atrasadas em destaque.
* Abas: Minhas, Da Casa, Quadro Aberto.
* Toque no círculo da tarefa conclui, com animação discreta e desfazer por alguns segundos.
  5.3. Criação Rápida
* Passo 1: título.
* Passo 2: quem faz (avatares tocáveis, ou "Quadro Aberto").
* Passo 3 (opcional): prazo, prioridade, checklist, rotina e peso.
  5.4. Equilíbrio da Casa
  Um card compara o esforço de cada membro no ciclo ("Cris 55% / Kelvynn 45%"), sem tom de cobrança.
  5.5. Feedback Positivo (Nudges)
* "Tudo em dia! Nenhuma tarefa atrasada. 🎉"
* "Kelvynn assumiu 'Trocar a lâmpada do corredor'."
* "O ciclo fechou com as tarefas bem divididas. 👏"

6. Modelo de Dados Sugerido
```
tasks(id, creator_id, assignee_id, title, description, due_at, priority, category,
      weight, status[todo|doing|done], is_private, routine_id, event_id,
      done_by, done_at, reschedule_count, deleted_at)
task_checklist_items(id, task_id, text, done)
task_routines(id, title, recurrence_rule, assignment[fixed|rotation], fixed_assignee_id,
              weight, active)
task_routine_members(routine_id, member_id, position)
member_absences(id, member_id, starts_on, ends_on)
task_comments(id, task_id, author_id, text, photo_url, created_at)
```
O campo `event_id` liga a tarefa ao registro do Calendário (mesmo item, duas visões). O status Atrasada é derivado de `due_at` e `status`.

7. Casos de Teste Derivados
* Tarefa sem responsável aparece no Quadro Aberto e pode ser assumida (RN01).
* Atribuir a outra pessoa gera notificação, com aceite ou pedido de troca (RN02).
* Tarefa vencida e aberta vira Atrasada (RN04).
* Rotina não cria duplicata enquanto a anterior está aberta (RN05).
* Rodízio pula quem está ausente e prioriza menor carga (RN06).
* Tarefa privada não aparece para outros nem entra no equilíbrio (RN08).
* Concluir tarefa com custo oferece Gasto da Casa ou item na Lista de Compras (RN10).
* Tarefa criada no Calendário aparece aqui sem duplicar (integração).


8. Ganchos de Captura Inteligente e IA
* Captura (📷): foto de um problema (vazamento, lâmpada queimada) cria a tarefa com a imagem anexada e título e categoria sugeridos.
* Assistente: "Cria tarefa para o Kelvynn: levar o lixo, toda terça", "Quem está com mais tarefas?". Atribuições seguem a RN02 (aceite ou pedido de troca).
* Proativo: resumo semanal com tarefas atrasadas, sugestão de rodízio e aviso de desequilíbrio no ciclo.
