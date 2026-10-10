Documentação Funcional: Módulo de Calendário (Agenda Compartilhada)

1. Visão Geral e Propósito
   Este módulo permite que cada membro da casa crie eventos e marque as pessoas necessárias. O objetivo é alinhar compromissos do dia a dia (consultas, jantares, viagens, tarefas) com confirmação explícita de quem precisa participar, evitando o "ninguém avisou". Eventos também podem ser configurados como tarefas com responsável. O módulo é independente dos módulos financeiros nesta versão, mas reaproveita os mesmos membros, notificações e navegação.

2. Conceitos Essenciais
   2.1. Evento
   Compromisso com data/hora, criado por um membro (o Criador), com uma lista de participantes.
   2.2. Participante e Papel
   Cada pessoa marcada tem um papel no evento:
* Necessário: a presença é indispensável. Precisa responder.
* Opcional: é convidado, mas o evento não depende dele.
* Informado: apenas vê o evento. Não responde.
  2.3. Resposta (RSVP)
  Estados: Pendente, Aceito, Recusado e Talvez.
  2.4. Evento como Tarefa
  Um evento pode ser marcado como Tarefa, com um Responsável e estado de conclusão (A fazer / Concluída).
  2.5. Escopo de Pessoas
  Só podem ser marcados membros da casa. Contatos externos estão fora do escopo.

3. Regras de Negócio Fundamentais
   RN01: Status Derivado do Evento
   O status é calculado a partir das respostas dos participantes Necessários:
* Aguardando: existe ao menos um Necessário pendente.
* Confirmado: todos os Necessários aceitaram.
* Em Risco: ao menos um Necessário recusou ou respondeu Talvez.
* Cancelado: definido manualmente pelo Criador.
  Participantes Opcionais e Informados nunca alteram o status.
  RN02: Resposta Obrigatória dos Necessários
  Participantes Necessários recebem lembretes de resposta pendente até a data do evento. O Criador pode ver quem ainda não respondeu.
  RN03: Recusa de Participante Necessário
  Quando um Necessário recusa, o Criador é notificado e o evento passa a Em Risco. O sistema sugere duas ações: Remarcar ou Remover da lista de Necessários.
  RN04: Conflito de Agenda
  Ao marcar uma pessoa, o sistema verifica se ela já tem evento Confirmado ou Aceito no mesmo horário e exibe um aviso. O aviso não bloqueia a criação.
  RN05: Permissões de Edição
* Apenas o Criador edita, remarca ou cancela o evento.
* Participantes podem Propor Novo Horário. O Criador aprova ou recusa. Se aprovado, as respostas dos Necessários voltam para Pendente.
  RN06: Cancelamento sem Apagar
  Cancelar não remove o evento. Ele permanece no histórico com o status Cancelado e todos os marcados são notificados.
  RN07: Visibilidade
* Casa: todos os membros veem o evento.
* Restrito: só o Criador e os marcados veem.
* Privado: só o Criador vê (sem participantes).
  RN08: Recorrência
  Eventos podem repetir diariamente, semanalmente, mensalmente ou de forma personalizada. A edição pode ser aplicada Só neste evento ou Neste e nos próximos. Cada ocorrência tem suas próprias respostas de participantes.
  RN09: Lembretes
  Cada pessoa tem lembretes padrão (ex.: 1 dia e 1 hora antes) nas suas configurações, e pode sobrescrevê-los por evento. Evento de dia inteiro lembra às 09:00 do dia anterior por padrão.
  RN10: Tarefas com Responsável
* Uma tarefa tem exatamente um Responsável, que deve ser um dos participantes.
* O Responsável pode marcar a tarefa como Concluída. O Criador também pode.
* Tarefa vencida e não concluída fica com a etiqueta Atrasada e o Responsável é notificado.
* Tarefas recorrentes geram uma nova pendência a cada ocorrência.
  RN11: Sincronização Externa (Google/Apple)
  Eventos podem ser exportados e sincronizados com o calendário do dispositivo. A sincronização é de mão única (app para calendário externo) na primeira versão. Eventos Privados só são exportados para o próprio Criador, nunca para outros membros.

4. Descrição de Funcionalidades (Features)
* Criação de Evento: título, data/hora (ou dia inteiro), local, descrição, cor, visibilidade, recorrência, lembretes e participantes com papel.
* Convites e Respostas: cartão de convite com Aceitar, Recusar, Talvez e Propor outro horário.
* Painel de Respostas: o Criador vê quem aceitou, recusou ou ainda não respondeu.
* Proposta de Remarcação: sugestão de novo horário com preview, aprovada pelo Criador.
* Detecção de Conflitos: aviso de choque de horário por participante.
* Tarefas: eventos com Responsável, estado de conclusão e etiqueta de atraso.
* Filtros: por pessoa, por papel (Necessário para mim), por tipo (Evento/Tarefa) e por status.
* Exportação para Calendário Externo: envio de eventos para o calendário do dispositivo (Google/Apple), conforme RN11.
* Histórico: eventos passados e cancelados permanecem consultáveis.

5. Experiência do Usuário (UX) e Navegação
   5.1. Nova Aba "Agenda"
   A barra inferior passa a ter 5 abas: 🏠 A Casa, 🤝 Pessoal, 📅 Agenda, 📊 Relatórios, ⚙️ Ajustes. Isso atualiza a estrutura descrita no documento de integração (que tinha 4 abas).
   5.2. Visões da Agenda
* Mês: grade com pontos coloridos por pessoa.
* Semana: linha do tempo por hora.
* Próximos: lista cronológica com status de cada evento e destaque para o que exige a sua resposta.
  5.3. Smart FAB
  O botão + ganha duas novas opções: 📅 Evento e ✅ Tarefa, ao lado de Gasto da Casa, Empréstimo e Aporte. Na aba Agenda, o + abre direto a criação de evento.
  5.4. Criação Rápida (menos de 10 segundos)
* Passo 1: título e data/hora.
* Passo 2: "Quem precisa estar?" Avatares tocáveis: um toque marca como Necessário, dois toques como Opcional, três como Informado e quatro remove.
* Passo 3 (opcional): local, recorrência, lembretes, visibilidade e transformar em Tarefa (escolher Responsável).
  5.5. Cartão de Convite e Notificações
* Notificação com ações rápidas: Aceitar, Recusar, Propor horário.
* Deeplink do GoRouter abre o evento diretamente a partir da notificação.
  5.6. Feedback Positivo (Nudges)
* Todos confirmaram: "Tudo certo! Todos os necessários confirmaram para o jantar de sábado. 🎉"
* Pendência: "Falta só o Cris responder."
* Conflito: "Kelvynn já tem um compromisso às 19h. Deseja continuar?"
* Tarefa concluída: "Revisão do carro concluída por Cris. ✅"

6. Modelo de Dados Sugerido (Fase Técnica)
```
events(id, creator_id, title, description, location, starts_at, ends_at, all_day,
       color, visibility[house|restricted|private], status_manual[null|cancelled],
       recurrence_rule, is_task, task_assignee_id, task_done_at)
event_participants(event_id, member_id, role[required|optional|info],
                   rsvp[pending|accepted|declined|maybe], responded_at)
event_reminders(event_id, member_id, offset_minutes)
event_reschedule_proposals(id, event_id, proposer_id, new_starts_at, new_ends_at,
                           status[pending|approved|rejected], created_at)
```
* O status (RN01) é derivado de `event_participants`, assim como o status das parcelas nos módulos financeiros.
* RLS no Supabase aplica a visibilidade (RN07).
* O estado da Agenda é gerenciado por BLoC/Cubit e os deeplinks pelo GoRouter.

7. Casos de Teste Derivados
* Evento com 2 Necessários: aguardando até os dois aceitarem, depois Confirmado (RN01).
* Um Necessário recusa: evento Em Risco e criador notificado (RN03).
* Opcional recusa: o status não muda (RN01).
* Aprovar proposta de remarcação: os Necessários voltam para Pendente (RN05).
* Cancelar: o evento continua no histórico (RN06).
* Evento Privado: não aparece para outro membro nem na exportação dele (RN07/RN11).
* Tarefa recorrente: gera uma nova pendência por ocorrência (RN10).
* Marcar pessoa com horário ocupado: aviso sem bloqueio (RN04).

8. Fora do Escopo (Versão Atual)
* Contatos externos (convidados sem conta).
* Sincronização de mão dupla com Google/Apple.
* Integração com o financeiro (vencimentos, parcelas P2P, eventos com custo e fechamento do ciclo). Pode ser tratada como evolução futura, reaproveitando `source_ref` nos eventos.


9. Ganchos de Captura Inteligente e IA
* Captura (📷): foto de convite, panfleto ou receita médica cria um evento rascunho (título, data, local) para o usuário revisar.
* Assistente: "Marca jantar sábado às 20h e chama o Cris como necessário", "O que tenho esta semana?", "Quem ainda não respondeu?". Ações passam por confirmação e respeitam as regras de RSVP (o assistente não confirma pelo outro) e de visibilidade.
* Proativo: resumo semanal com eventos sem resposta e conflitos de agenda.
