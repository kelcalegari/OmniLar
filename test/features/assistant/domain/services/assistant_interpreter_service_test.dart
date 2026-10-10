import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/assistant/domain/entities/assistant_message.dart';
import 'package:omni_lar/features/assistant/domain/services/assistant_interpreter_service.dart';
import 'package:omni_lar/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/repositories/p2p_repository.dart';
import 'package:omni_lar/features/shopping/domain/repositories/shopping_repository.dart';

class MockFinanceRepository extends Mock implements FinanceRepository {}
class MockP2PRepository extends Mock implements P2PRepository {}
class MockShoppingRepository extends Mock implements ShoppingRepository {}
class MockCalendarRepository extends Mock implements CalendarRepository {}

class FakeFinancialCycle extends Fake implements FinancialCycle {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFinancialCycle());
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

    test('Lançamento de despesa via linguagem natural cria proposta de rateio sem gravar direto (RN01, RN02)', () async {
      final result = await service.interpretMessage('Gastei 85 na padaria');

      expect(result.actions.length, 1);
      final action = result.actions.first;
      expect(action.toolName, 'finance.addExpense');
      expect(action.arguments['cents'], 8500); // 85 reais em centavos
      expect(action.status, AssistantActionStatus.proposed);
    });
  });
}
