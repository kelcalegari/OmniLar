import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/assistant/domain/entities/assistant_message.dart';
import 'package:omni_lar/features/assistant/domain/services/assistant_interpreter_service.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';
import 'package:omni_lar/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/repositories/p2p_repository.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_item.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_list.dart';
import 'package:omni_lar/features/shopping/domain/repositories/shopping_repository.dart';

class MockFinanceRepository extends Mock implements FinanceRepository {}
class MockP2PRepository extends Mock implements P2PRepository {}
class MockShoppingRepository extends Mock implements ShoppingRepository {}
class MockCalendarRepository extends Mock implements CalendarRepository {}

class FakeFinancialCycle extends Fake implements FinancialCycle {}
class FakeCalendarEvent extends Fake implements CalendarEvent {}
class FakeTaskItem extends Fake implements TaskItem {}
class FakeShoppingItem extends Fake implements ShoppingItem {}
class FakeContribution extends Fake implements Contribution {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFinancialCycle());
    registerFallbackValue(FakeCalendarEvent());
    registerFallbackValue(FakeTaskItem());
    registerFallbackValue(FakeShoppingItem());
    registerFallbackValue(FakeContribution());
  });

  late MockFinanceRepository mockFinance;
  late MockP2PRepository mockP2P;
  late MockShoppingRepository mockShopping;
  late MockCalendarRepository mockCalendar;
  late AssistantInterpreterService service;

  setUp(() {
    mockFinance = MockFinanceRepository();
    mockP2P = MockP2PRepository();
    mockShopping = MockShoppingRepository();
    mockCalendar = MockCalendarRepository();

    service = AssistantInterpreterService(
      financeRepository: mockFinance,
      p2pRepository: mockP2P,
      shoppingRepository: mockShopping,
      calendarRepository: mockCalendar,
    );
  });

  group('AssistantInterpreterService (Fase 7 - IA Determinística & Confirmação Humana)', () {
    test('Consulta financeira retorna dados determinísticos do motor de cálculo (RN02, RN05)', () async {
      final testCycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 10), cycleStartDay: 5);

      when(() => mockFinance.getCycleSummary(any())).thenAnswer(
        (_) async => FinancialCycleSummary(
          cycle: testCycle,
          totalContributions: const Money(500000), // R$ 5.000,00
          totalExpensesPaid: const Money(150000), // R$ 1.500,00
          committedFutureExpenses: const Money(0),
          folego: const Money(350000), // R$ 3.500,00
          memberContributions: const {'member_carlos': Money(500000)},
          memberExpensesPaid: const {'member_carlos': Money(150000)},
        ),
      );

      final result = await service.interpretMessage('Quanto sobrou no caixa da casa?');

      expect(result.textResponse, contains('1.500,00'));
      expect(result.textResponse, contains('3.500,00'));
      expect(result.textResponse, contains('confortável'));
      expect(result.actions, isEmpty); // Consultas não criam propostas de ação
    });

    test('Consulta de empréstimos retorna valores do motor P2P', () async {
      final loan = P2PLoan(
        id: 'loan_1',
        title: 'Camisa',
        totalAmount: const Money(25000), // R$ 250,00
        lenderMemberId: 'member_carlos',
        borrowerMemberId: 'member_marina',
        installmentsCount: 1,
        createdAt: DateTime.now(),
        firstDueDate: DateTime.now(),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'loan_1_inst_1',
            loanId: 'loan_1',
            number: 1,
            totalCount: 1,
            amount: const Money(25000),
            dueDate: DateTime.now(),
          ),
        ],
      );

      when(() => mockP2P.getLoans()).thenAnswer((_) async => [loan]);

      final result = await service.interpretMessage('Quem deve para quem?');

      expect(result.textResponse, contains('250,00'));
      expect(result.actions, isEmpty);
    });

    test('Consulta de empréstimos com activeMemberId dinâmico (ex: Marina)', () async {
      final loan = P2PLoan(
        id: 'loan_1',
        title: 'Camisa',
        totalAmount: const Money(25000),
        lenderMemberId: 'member_carlos',
        borrowerMemberId: 'member_marina',
        installmentsCount: 1,
        createdAt: DateTime.now(),
        firstDueDate: DateTime.now(),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'loan_1_inst_1',
            loanId: 'loan_1',
            number: 1,
            totalCount: 1,
            amount: const Money(25000),
            dueDate: DateTime.now(),
          ),
        ],
      );

      when(() => mockP2P.getLoans()).thenAnswer((_) async => [loan]);

      final result = await service.interpretMessage('Quem deve para quem?', activeMemberId: 'member_marina');

      expect(result.textResponse, contains('A pagar para outros: ${const Money(25000).format()}'));
      expect(result.textResponse, contains('Saldo P2P líquido: ${(-const Money(25000)).format()}'));
    });

    test('Pedido de adicionar compras gera proposta que exige confirmação (RN01)', () async {
      final result = await service.interpretMessage('Adicionar leite e ovos na lista');

      expect(result.actions.length, 1);
      final action = result.actions.first;
      expect(action.toolName, 'shopping.addItem');
      expect(action.status, AssistantActionStatus.proposed); // Não grava diretamente
      expect(action.arguments['name'], 'Leite e ovos');
    });

    test('Lançamento de despesa via linguagem natural com meio de pagamento cria proposta sem gravar direto (RN01, RN02)', () async {
      when(() => mockFinance.getPaymentMethods()).thenAnswer((_) async => [
        const PaymentMethod(id: 'pm_card_carlos', name: 'Nubank Carlos', type: PaymentMethodType.card),
      ]);

      final result = await service.interpretMessage('Gastei 85 na padaria no Nubank');

      expect(result.actions.length, 1);
      final action = result.actions.first;
      expect(action.toolName, 'finance.addExpense');
      expect(action.arguments['cents'], 8500); // 85 reais em centavos
      expect(action.arguments['paymentMethodName'], contains('Nubank'));
      expect(action.status, AssistantActionStatus.proposed);
    });

    test('Lançamento de despesa sem meio de pagamento pergunta qual meio foi utilizado (RN06)', () async {
      when(() => mockFinance.getPaymentMethods()).thenAnswer((_) async => [
        const PaymentMethod(id: 'pm_card_carlos', name: 'Nubank Carlos', type: PaymentMethodType.card),
        const PaymentMethod(id: 'pm_vr_marina', name: 'VR Marina', type: PaymentMethodType.vr),
      ]);

      final result = await service.interpretMessage('cadastrar maca por 10 reais');

      expect(result.actions, isEmpty); // Não cria ação ainda
      expect(result.textResponse.toLowerCase(), contains('qual meio de pagamento'));
      expect(result.suggestions, contains('Nubank Carlos'));
      expect(result.suggestions, contains('VR Marina'));
    });

    test('Resposta informando meio de pagamento resolve a pendência e gera a proposta (RN01, RN06)', () async {
      when(() => mockFinance.getPaymentMethods()).thenAnswer((_) async => [
        const PaymentMethod(id: 'pm_card_carlos', name: 'Nubank Carlos', type: PaymentMethodType.card),
        const PaymentMethod(id: 'pm_vr_marina', name: 'VR Marina', type: PaymentMethodType.vr),
      ]);

      final history = [
        AssistantMessage(
          id: 'msg_1',
          role: AssistantRole.user,
          content: 'cadastrar maca por 10 reais',
          createdAt: DateTime.now(),
        ),
        AssistantMessage(
          id: 'msg_2',
          role: AssistantRole.assistant,
          content: 'Entendido! Para cadastrar a despesa de "Maca" (R\$ 10,00), qual meio de pagamento você utilizou?',
          createdAt: DateTime.now(),
        ),
      ];

      final result = await service.interpretMessage('Nubank Carlos', history: history);

      expect(result.actions.length, 1);
      final action = result.actions.first;
      expect(action.toolName, 'finance.addExpense');
      expect(action.arguments['title'], 'Maca');
      expect(action.arguments['cents'], 1000);
      expect(action.arguments['paymentMethodId'], 'pm_card_carlos');
      expect(action.arguments['paymentMethodName'], 'Nubank Carlos');
      expect(action.status, AssistantActionStatus.proposed);
    });

    test('Lançamento direto com meio de pagamento cria proposta de imediato', () async {
      when(() => mockFinance.getPaymentMethods()).thenAnswer((_) async => [
        const PaymentMethod(id: 'pm_card_carlos', name: 'Nubank Carlos', type: PaymentMethodType.card),
      ]);

      final result = await service.interpretMessage('cadastrar maca por 10 reais no pix');

      expect(result.actions.length, 1);
      final action = result.actions.first;
      expect(action.arguments['cents'], 1000);
      expect(action.arguments['paymentMethodName'], 'Pix');
    });

    test('Execução de proposta confirmada para calendar.addEvent chama CalendarRepository', () async {
      when(() => mockCalendar.addEvent(any())).thenAnswer((_) async {});

      const proposal = AssistantActionProposal(
        id: 'act_cal_1',
        title: 'Jantar de Confraternização',
        description: 'Jantar sábado',
        toolName: 'calendar.addEvent',
        arguments: {
          'title': 'Jantar de Confraternização',
          'dateIso': '2026-10-18T20:00:00.000Z',
          'description': 'Comemorar o fechamento',
        },
      );

      await service.executeAction(proposal, activeMemberId: 'member_carlos');

      verify(() => mockCalendar.addEvent(any(that: isA<CalendarEvent>()))).called(1);
    });

    test('Execução de proposta confirmada para tasks.addTask chama CalendarRepository', () async {
      when(() => mockCalendar.addTask(any())).thenAnswer((_) async {});

      const proposal = AssistantActionProposal(
        id: 'act_tsk_1',
        title: 'Comprar detergente',
        description: 'Tarefa da casa',
        toolName: 'tasks.addTask',
        arguments: {
          'title': 'Comprar detergente',
          'assignedToMemberId': 'member_marina',
        },
      );

      await service.executeAction(proposal, activeMemberId: 'member_carlos');

      verify(() => mockCalendar.addTask(any(that: isA<TaskItem>()))).called(1);
    });

    test('Execução de proposta confirmada para shopping.toggleBought marca item como comprado', () async {
      when(() => mockShopping.getLists()).thenAnswer(
        (_) async => [const ShoppingList(id: 'list_1', name: 'Geral', isDefault: true)],
      );
      when(() => mockShopping.getItems('list_1')).thenAnswer(
        (_) async => [
          const ShoppingItem(
            id: 'item_pao',
            listId: 'list_1',
            name: 'Pão de forma',
            quantity: 1,
            unit: 'un',
            category: 'Padaria',
            isBought: false,
          ),
        ],
      );
      when(() => mockShopping.toggleItemBought('item_pao')).thenAnswer((_) async {});

      const proposal = AssistantActionProposal(
        id: 'act_shop_toggle',
        title: 'Marcar Pão como Comprado',
        description: 'Marca pão na lista',
        toolName: 'shopping.toggleBought',
        arguments: {
          'itemName': 'pão',
        },
      );

      await service.executeAction(proposal);

      verify(() => mockShopping.toggleItemBought('item_pao')).called(1);
    });

    test('Simulação de compra responde positivamente quando há fôlego livre suficiente (RN02, Seção 4.5)', () async {
      final testCycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 10), cycleStartDay: 5);
      when(() => mockFinance.getCycleSummary(any())).thenAnswer(
        (_) async => FinancialCycleSummary(
          cycle: testCycle,
          totalContributions: const Money(500000),
          totalExpensesPaid: const Money(150000),
          committedFutureExpenses: const Money(0),
          folego: const Money(350000), // R$ 3.500,00 livres
          memberContributions: const {},
          memberExpensesPaid: const {},
        ),
      );

      final result = await service.interpretMessage('Dá para comprar uma TV de 1500 reais?');

      expect(result.actions, isEmpty); // Simulações não criam ações
      expect(result.textResponse, contains('Sim, cabe no ciclo atual!'));
      expect(result.textResponse, contains('3.500,00'));
      expect(result.textResponse, contains('2.000,00')); // Restante projetado
    });

    test('Simulação de compra alerta quando o valor estoura o fôlego livre (RN02, Seção 4.5)', () async {
      final testCycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 10), cycleStartDay: 5);
      when(() => mockFinance.getCycleSummary(any())).thenAnswer(
        (_) async => FinancialCycleSummary(
          cycle: testCycle,
          totalContributions: const Money(500000),
          totalExpensesPaid: const Money(400000),
          committedFutureExpenses: const Money(50000),
          folego: const Money(50000), // R$ 500,00 livres
          memberContributions: const {},
          memberExpensesPaid: const {},
        ),
      );

      final result = await service.interpretMessage('Dá para comprar uma geladeira de 3000 reais?');

      expect(result.actions, isEmpty);
      expect(result.textResponse, contains('Atenção: essa compra pode estourar o ciclo atual!'));
      expect(result.textResponse, contains('500,00'));
      expect(result.textResponse, contains('2.500,00')); // Déficit
    });

    test('Lançamento de aporte no caixa gera proposta de ação (finance.addContribution)', () async {
      when(() => mockFinance.getPaymentMethods()).thenAnswer((_) async => [
        const PaymentMethod(id: 'pm_pix', name: 'Pix', type: PaymentMethodType.pix),
      ]);

      final result = await service.interpretMessage('Aporte de 500 reais via Pix');

      expect(result.actions.length, 1);
      final action = result.actions.first;
      expect(action.toolName, 'finance.addContribution');
      expect(action.arguments['cents'], 50000);
      expect(action.arguments['paymentMethodName'], 'Pix');
      expect(action.status, AssistantActionStatus.proposed);
    });

    test('Execução de proposta confirmada para finance.addContribution chama FinanceRepository', () async {
      when(() => mockFinance.addContribution(any())).thenAnswer((_) async {});

      const proposal = AssistantActionProposal(
        id: 'act_contrib_1',
        title: 'Registrar Aporte no Caixa',
        description: 'Aporte de R\$ 500,00',
        toolName: 'finance.addContribution',
        arguments: {
          'cents': 50000,
          'memberId': 'member_carlos',
          'paymentMethodId': 'pm_pix',
        },
      );

      await service.executeAction(proposal, activeMemberId: 'member_carlos');

      verify(() => mockFinance.addContribution(any(that: isA<Contribution>()))).called(1);
    });
  });
}
