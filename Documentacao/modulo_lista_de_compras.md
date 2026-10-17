> **Especificação original (06/10/2026).** Escrita antes do código. O que foi feito pode ser diferente: em caso de dúvida vale o código. O estado atual está em [plano_diretor_unificado.md](plano_diretor_unificado.md) e [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md).

Documentação Funcional: Módulo de Lista de Compras (Compartilhada)

1. Visão Geral e Propósito
   Este módulo mantém listas de compras compartilhadas entre os membros da casa, atualizadas em tempo real. Qualquer um adiciona itens, quem vai ao mercado marca o que pegou, e ao final a compra pode virar um Gasto da Casa com poucos toques. O módulo conversa com o Caixa da Casa para que o valor gasto seja lançado na categoria e na regra de rateio corretas.

2. Conceitos Essenciais
   2.1. Lista
   Conjunto de itens com um nome e um tipo (Mercado, Farmácia, Casa/Limpeza, Feira, Personalizada). A casa pode ter várias listas ativas ao mesmo tempo.
   2.2. Item
   Nome, quantidade, unidade, categoria/corredor, observação, foto opcional e quem pediu.
   2.3. Estados do Item
   Pendente, Comprado e Indisponível (não achou no mercado, fica para a próxima).
   2.4. Compra (Sessão de Compras)
   Momento em que alguém está no mercado. A pessoa "assume" a lista, os demais veem o progresso e a lista é encerrada com o valor total.
   2.5. Itens Frequentes (Despensa)
   Histórico de itens comprados. O sistema aprende o que se repete e sugere "está acabando?" para reposição.

3. Regras de Negócio Fundamentais
   RN01: Lista Compartilhada em Tempo Real
   Todos os membros veem e editam as listas da casa. Alterações aparecem para os outros sem recarregar a tela.
   RN02: Autoria do Pedido
   Cada item guarda quem o adicionou. Um item pode ser marcado como Pessoal (ex.: "meu shampoo") e, nesse caso, o custo não entra no rateio da casa (veja RN06).
   RN03: Item Duplicado
   Ao digitar um item que já está pendente na lista, o app avisa e oferece somar a quantidade, em vez de criar uma duplicata.
   RN04: Modo Compra
   Quem inicia a compra vira o Comprador da lista. Os itens marcados como Comprado ficam riscados e os outros membros recebem o aviso "Cris está no mercado" e podem adicionar itens de última hora, que aparecem destacados.
   RN05: Encerramento da Compra
   Ao finalizar, os itens não comprados voltam para a próxima compra, sem se perder. O Comprador pode informar o Valor Total e a Forma de Pagamento (cartão, VR, Pix, dinheiro).
   RN06: Integração com o Caixa da Casa
   Ao informar o valor total, o app oferece lançar como Gasto da Casa já preenchido (categoria Mercado, forma de pagamento escolhida e rateio padrão da casa). Itens marcados como Pessoais são separados e geram um Empréstimo P2P para quem os pediu. A divisão proporcional do valor entre os itens da casa e os pessoais é calculada pelo valor informado por item. Quando o valor por item não é informado, o app pede apenas o subtotal dos itens pessoais.
   RN07: Pagamento com VR/VA
   Se a forma de pagamento escolhida for VR/VA, a regra de categoria alimentícia do Caixa se aplica ao lançamento.
   RN08: Itens Recorrentes
   Itens podem ser marcados como recorrentes (ex.: leite a cada 7 dias). Eles voltam sozinhos para a lista quando o intervalo vence.
   RN09: Histórico Imutável
   Compras encerradas ficam consultáveis, com itens, valor total, comprador e data. Itens comprados não são apagados.
    RN10: Marcação Simples como Comprado
    O Modo Compra é opcional. Qualquer membro pode marcar um ou vários itens como Comprado diretamente na lista, sem iniciar uma compra e sem informar valor ou forma de pagamento.
* O app registra quem marcou e quando (`bought_by`, `bought_at`), mas não cria Compra nem Gasto da Casa.
* Itens marcados assim alimentam a despensa e a recorrência (RN08), sem preço. O preço estimado permanece o último informado.
* Para lançar o gasto depois, basta selecionar itens já comprados e usar "Registrar gasto" (RN06), que cria a compra retroativamente.
* Ao encerrar uma compra em andamento, a opção "Só marcar como comprado" fecha a sessão sem valor (RN05).
* Marcação por engano pode ser desfeita (o item volta para Pendente).

4. Descrição de Funcionalidades (Features)
* Múltiplas Listas: criar, renomear e arquivar listas por tipo.
* Adição Rápida: digitar o nome com sugestões automáticas, e quantidade opcional por toque.
* Organização por Categoria: itens agrupados por corredor/categoria, para seguir o roteiro do mercado.
* Marcar como Comprado Direto: marcar itens como comprados na própria lista, sem Modo Compra, sem valor e sem lançamento financeiro (RN10). Aceita seleção múltipla.
* Modo Compra: tela com itens grandes para marcar com um toque, contador de progresso e indicação de quem está comprando.
* Itens Sugeridos: baseados no histórico ("Você costuma comprar café a cada 15 dias").
* Preço Estimado: valor de referência por item (último preço pago), com total estimado da lista.
* Finalização com Lançamento: botão "Registrar gasto" que abre o Gasto da Casa pré-preenchido (RN06).
* Compartilhar Lista: exportar a lista como texto para enviar por mensagem.
* Notificações: aviso quando alguém inicia ou conclui uma compra, e quando um item é adicionado durante a compra.

5. Experiência do Usuário (UX) e Navegação
   5.1. Localização
   O módulo fica acessível por A Casa (card "Compras") e pelo Smart FAB (🛒 Item de Compras, que adiciona direto à lista padrão).
   5.2. Tela da Lista
* Cabeçalho com nome da lista, total de itens e total estimado.
* Itens agrupados por categoria, com swipe para marcar Comprado ou Indisponível.
* Campo de adição sempre visível no rodapé.
  5.3. Tela de Modo Compra
* Botão "Estou no mercado" no topo.
* Barra de progresso (7 de 12 itens) e itens comprados indo para o fim da lista.
  5.4. Fechamento
* Passo 1: conferir itens não comprados (voltam para a próxima compra ou são removidos).
* Passo 2: informar valor total e forma de pagamento, ou tocar em "Só marcar como comprado" para encerrar sem valor (RN10).
* Passo 3: confirmar o lançamento no Caixa da Casa.
  5.5. Feedback Positivo (Nudges)
* "Lista concluída! Tudo comprado. 🛒"
* "Compra de R$ 312 lançada no Caixa da Casa, categoria Mercado."
* "O leite deve estar acabando. Adicionar à lista?"

6. Modelo de Dados Sugerido
```
shopping_lists(id, name, type, archived_at)
shopping_items(id, list_id, name, quantity, unit, category, note, photo_url,
               requested_by, is_personal, status[pending|bought|unavailable],
               estimated_price_cents, recurrence_days, bought_by, bought_at, trip_id[nullable])
shopping_trips(id, list_id, shopper_id, started_at, finished_at, total_cents,
               payment_method_id, house_expense_id)
pantry_history(id, item_name, last_price_cents, last_bought_at, avg_interval_days)
```
O campo `house_expense_id` liga a compra ao lançamento do Caixa da Casa. Itens pessoais com valor geram um `loan` P2P.

7. Casos de Teste Derivados
* Adicionar item já existente soma a quantidade (RN03).
* Item adicionado durante a compra aparece destacado para o Comprador (RN04).
* Itens não comprados voltam para a próxima compra (RN05).
* Finalizar compra gera Gasto da Casa com categoria Mercado e rateio padrão (RN06).
* Item pessoal gera Empréstimo P2P para quem pediu e não entra no rateio (RN02/RN06).
* Item recorrente reaparece após o intervalo definido (RN08).
* Marcar item como Comprado na lista não cria Compra nem Gasto da Casa (RN10).
* Marcação direta registra `bought_by` e `bought_at` e atualiza a despensa sem preço (RN10).
* Itens comprados sem valor podem ser lançados depois via "Registrar gasto" (RN10/RN06).
* Desfazer devolve o item para Pendente (RN10).


8. Ganchos de Captura Inteligente, Importação e IA
* Captura (📷): foto da nota (ou QR Code da NFC-e) no fechamento da compra marca os itens da lista como Comprados, preenche o valor total e o Gasto da Casa, e separa itens pessoais (RN07 e RN09 do módulo de Captura Inteligente).
* Foto de código de barras ou de produto adiciona o item à lista com nome normalizado.
* Foto da despensa ou geladeira sugere itens que parecem estar acabando (apenas sugestão).
* Importação: linhas de fatura com categoria Mercado são conciliadas com compras já lançadas, evitando duplicidade.
* IA: normalização de nomes de itens, previsão de reposição e preço estimado por histórico.
* Assistente: "Adiciona leite na lista", "Marca o pão como comprado", "Quanto gastei no mercado este mês?". Toda ação passa por confirmação.
