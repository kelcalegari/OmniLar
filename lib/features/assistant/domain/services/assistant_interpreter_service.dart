import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/p2p/domain/repositories/p2p_repository.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/shopping/domain/repositories/shopping_repository.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_item.dart';
import 'package:omni_lar/features/calendar/domain/repositories/calendar_repository.dart';
import '../entities/assistant_message.dart';

class NaturalLanguageInterpretation {
  final String textResponse;
  final List<AssistantActionProposal> actions;
  final List<String> suggestions;

  const NaturalLanguageInterpretation({
    required this.textResponse,
    this.actions = const [],
    this.suggestions = const [],
  });
}

class AssistantInterpreterService {
  final FinanceRepository financeRepository;
  final P2PRepository p2pRepository;
  final ShoppingRepository shoppingRepository;
  final CalendarRepository calendarRepository;

  AssistantInterpreterService({
    required this.financeRepository,
    required this.p2pRepository,
    required this.shoppingRepository,
    required this.calendarRepository,
  });

  /// Processa a mensagem em linguagem natural.
  /// Implementa o princípio "Código primeiro, IA determinística":
  /// Responde perguntas da casa com dados reais e propõe ações que exigem confirmação humana (RN01, RN02).
  Future<NaturalLanguageInterpretation> interpretMessage(String query, {FinancialCycle? currentCycle}) async {
    final lower = query.toLowerCase().trim();
    final cycle = currentCycle ?? FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);

    // 1. Consultas Financeiras (RN02, RN05)
    if (lower.contains('saldo') || lower.contains('fôlego') || lower.contains('quanto sobrou') || lower.contains('caixa')) {
      final summary = await financeRepository.getCycleSummary(cycle);
      final freeMoney = summary.folego;
      final spentMoney = summary.totalExpensesPaid;

      String statusText = 'confortável e saudável';
      if (summary.status == FolegoStatus.warning) {
        statusText = 'em alerta (menos de 15% de margem)';
      } else if (summary.status == FolegoStatus.danger) {
        statusText = 'no limite / negativo';
      }

      return NaturalLanguageInterpretation(
        textResponse: 'Com base no ciclo atual (${summary.cycle.label}), o Caixa da casa gastou '
            '${spentMoney.format()}. O saldo livre (fôlego) é de ${freeMoney.format()}.\n'
            'O fôlego financeiro está $statusText.',
        suggestions: [
          'O que vence esta semana?',
          'Quem deve para quem?',
          'Adicionar despesa de supermercado',
        ],
      );
    }

    // 2. Consulta de Empréstimos e Dívidas P2P
    if (lower.contains('deve') || lower.contains('dívida') || lower.contains('emprestimo') || lower.contains('empréstimo') || lower.contains('p2p')) {
      final loans = await p2pRepository.getLoans();
      int toReceiveCents = 0;
      int toPayCents = 0;

      for (final loan in loans) {
        if (loan.status == LoanStatus.active) {
          if (loan.lenderMemberId == 'member_carlos') {
            toReceiveCents += loan.remainingAmount.cents;
          } else if (loan.borrowerMemberId == 'member_carlos') {
            toPayCents += loan.remainingAmount.cents;
          }
        }
      }

      final toReceive = Money(toReceiveCents);
      final toPay = Money(toPayCents);
      final net = toReceive - toPay;

      return NaturalLanguageInterpretation(
        textResponse: 'Resumo de acertos pessoais:\n'
            '• A receber de outros: ${toReceive.format()}\n'
            '• A pagar para outros: ${toPay.format()}\n'
            'Saldo P2P líquido: ${net.format()}.',
        suggestions: [
          'Ver fechamento da casa',
          'Lembrar marina do pagamento',
          'Como funciona a compensação?',
        ],
      );
    }

    // 3. Ação: Adicionar Item na Lista de Compras (RN01 - Ação antes de consulta)
    if (lower.startsWith('adiciona ') || lower.startsWith('adicionar ') || lower.startsWith('compra ') || lower.startsWith('comprar ')) {
      String itemText = lower
          .replaceAll('adicionar ', '')
          .replaceAll('adiciona ', '')
          .replaceAll('comprar ', '')
          .replaceAll('compra ', '')
          .replaceAll(' na lista', '')
          .replaceAll(' de compras', '')
          .replaceAll(' de mercado', '')
          .trim();

      if (itemText.isNotEmpty) {
        final action = AssistantActionProposal(
          id: 'act_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Adicionar à Lista de Compras',
          description: 'Adicionar "$itemText" na lista da casa',
          toolName: 'shopping.addItem',
          arguments: {
            'name': itemText[0].toUpperCase() + itemText.substring(1),
            'quantity': 1.0,
            'unit': 'un',
          },
          status: AssistantActionStatus.proposed,
        );

        return NaturalLanguageInterpretation(
          textResponse: 'Preparei o cartão para incluir este item. Por favor, confirme abaixo para gravar na lista da casa:',
          actions: [action],
          suggestions: [
            'Adicionar mais um item',
            'O que já temos na lista?',
          ],
        );
      }
    }

    // 4. Consulta de Compras
    if (lower.contains('lista') || lower.contains('compras') || lower.contains('o que falta') || lower.contains('mercado')) {
      final lists = await shoppingRepository.getLists();
      final targetListId = lists.isNotEmpty ? lists.first.id : 'list_default';
      final items = await shoppingRepository.getItems(targetListId);
      final pending = items.where((i) => !i.isBought).toList();

      if (pending.isEmpty) {
        return const NaturalLanguageInterpretation(
          textResponse: 'A lista de compras está em dia! Todos os itens já foram comprados.',
          suggestions: [
            'Adicionar leite e pão',
            'Quanto foi gasto no mercado?',
          ],
        );
      }

      final itemsList = pending.take(5).map((i) => '• ${i.name} (${i.quantity.toInt()} ${i.unit})').join('\n');
      final more = pending.length > 5 ? '\n... e mais ${pending.length - 5} itens.' : '';

      return NaturalLanguageInterpretation(
        textResponse: 'Atualmente temos ${pending.length} itens pendentes na lista de compras:\n$itemsList$more',
        suggestions: [
          'Adicionar ovos e queijo',
          'Marcar leite como comprado',
          'Ir para a tela de compras',
        ],
      );
    }

    // 5. Ação: Registrar Despesa por Linguagem Natural (RN01, RN02)
    final moneyMatch = RegExp(r'(?:r\$\s*|gastei\s*|lança\s*|lanca\s*|pagar\s*)?(\d+(?:[.,]\d{1,2})?)\s*(?:reais|no|na|de)?\s*(.*)', caseSensitive: false).firstMatch(query);
    if ((lower.contains('lança') || lower.contains('gastei') || lower.contains('paguei')) && moneyMatch != null) {
      final valueStr = moneyMatch.group(1) ?? '0';
      final cleanDesc = (moneyMatch.group(2) ?? 'Despesa').replaceAll('reais', '').replaceAll('de', '').trim();
      final parsedMoney = Money.parse(valueStr.replaceAll(',', '.'));

      if (parsedMoney.cents > 0) {
        final action = AssistantActionProposal(
          id: 'act_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Lançar Despesa da Casa',
          description: '${cleanDesc.isEmpty ? "Despesa" : cleanDesc}: ${parsedMoney.format()}',
          toolName: 'finance.addExpense',
          arguments: {
            'title': cleanDesc.isEmpty ? 'Despesa' : cleanDesc,
            'cents': parsedMoney.cents,
          },
          status: AssistantActionStatus.proposed,
        );

        return NaturalLanguageInterpretation(
          textResponse: 'Entendido. Criei uma proposta de lançamento determinístico com divisão da casa. '
              'Você confirma a gravação?',
          actions: [action],
          suggestions: [
            'Dividir apenas comigo',
            'Cancelar lançamento',
          ],
        );
      }
    }

    // 6. Consultas de Agenda e Tarefas
    if (lower.contains('compromisso') || lower.contains('evento') || lower.contains('agenda') || lower.contains('tarefa') || lower.contains('hoje')) {
      final events = await calendarRepository.getEvents();
      final tasks = await calendarRepository.getTasks();
      final overdueTasks = tasks.where((t) => t.isOverdue).length;

      return NaturalLanguageInterpretation(
        textResponse: 'Na agenda da casa temos ${events.length} compromissos agendados.\n'
            'Nas tarefas, há ${tasks.length} ativas, sendo $overdueTasks com prazo vencido.',
        suggestions: [
          'Ver tarefas atrasadas',
          'Criar novo compromisso',
          'Quem está responsável pela limpeza?',
        ],
      );
    }

    // 7. Resposta padrão inteligente com sugestões
    return const NaturalLanguageInterpretation(
      textResponse: 'Olá! Sou o assistente do Omni Lar. Conheço o caixa da casa, compromissos da agenda, '
          'itens de compras e empréstimos pessoais. Como posso te apoiar hoje?',
      suggestions: [
        'Quanto sobrou no Caixa?',
        'O que falta na lista de compras?',
        'Quem deve para quem?',
        'Adicionar leite na lista',
      ],
    );
  }

  /// Executa uma proposta previamente confirmada pelo usuário (RN01)
  Future<void> executeAction(AssistantActionProposal proposal) async {
    switch (proposal.toolName) {
      case 'shopping.addItem':
        final item = ShoppingItem(
          id: 'shop_${DateTime.now().millisecondsSinceEpoch}',
          listId: 'list_groceries',
          name: proposal.arguments['name'] as String? ?? 'Item',
          quantity: (proposal.arguments['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: proposal.arguments['unit'] as String? ?? 'un',
          category: 'Geral',
          isBought: false,
        );
        await shoppingRepository.addItem(item);
        break;

      case 'finance.addExpense':
        final expense = HouseExpense(
          id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
          title: proposal.arguments['title'] as String? ?? 'Despesa',
          amount: Money(proposal.arguments['cents'] as int? ?? 0),
          date: DateTime.now(),
          categoryId: 'cat_groceries',
          paidByMemberId: 'member_carlos',
          paymentMethodId: 'pm_card_carlos',
          splitRule: const SplitRule.percentage({'member_carlos': 50.0, 'member_marina': 50.0}),
        );
        await financeRepository.addExpense(expense);
        break;

      default:
        throw UnimplementedError('Ferramenta ${proposal.toolName} não suportada');
    }
  }
}
