import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';

void main() {
  group('Settlement Confirmation Flow', () {
    late MockFinanceDataSource financeDataSource;
    late MockP2PDataSource p2pDataSource;
    late MockSettlementDataSource settlementDataSource;
    late FinancialCycle cycle;

    setUp(() async {
      financeDataSource = MockFinanceDataSource();
      p2pDataSource = MockP2PDataSource();
      settlementDataSource = MockSettlementDataSource(
        financeDataSource: financeDataSource,
        p2pDataSource: p2pDataSource,
      );

      final now = DateTime.now();
      cycle = FinancialCycle.fromDate(date: now, cycleStartDay: 5);
    });

    test(
      'Confirmação da liquidação injeta aportes compensatórios e zera o déficit do fôlego',
      () async {
        // Cria um déficit no ciclo adicionando um compromisso que supera os aportes atuais
        await financeDataSource.addExpense(
          HouseExpense(
            id: 'exp_deficit_teste',
            title: 'Reforma Estrutural e Pintura',
            amount: const Money(150000), // R$ 1.500,00
            date: cycle.startDate.add(const Duration(days: 2)),
            dueDate: cycle.startDate.add(const Duration(days: 2)),
            categoryId: 'cat_moradia',
            paidByMemberId: 'member_carlos',
            paymentMethodId: 'pm_caixa',
            splitRule: const SplitRule.percentage({
              'member_carlos': 60.0,
              'member_marina': 40.0,
            }),
            status: ExpenseStatus.pending,
          ),
        );

        // 1. Verifica estado antes do fechamento
        final summaryBefore = await financeDataSource.getCycleSummary(cycle);
        expect(
          summaryBefore.folego.isNegative,
          isTrue,
          reason: 'Fôlego antes do fechamento deve estar deficitário/negativo',
        );

        // 2. Apura o fechamento do ciclo
        final settlement = await settlementDataSource.getSettlementSummary(
          cycle,
        );
        expect(settlement.status, SettlementStatus.readyToSettle);
        expect(settlement.transfers, isNotEmpty);

        // 3. Executa a liquidação atômica do ciclo
        await settlementDataSource.confirmSettlement(settlement);

        // 4. Verifica se o veredito foi arquivado com sucesso como liquidado
        final updatedSettlement = await settlementDataSource
            .getSettlementSummary(cycle);
        expect(updatedSettlement.status, SettlementStatus.settled);

        // 5. Verifica se o Fôlego do ciclo foi recalculado e agora está equilibrado (não negativo)
        final summaryAfter = await financeDataSource.getCycleSummary(cycle);
        expect(
          summaryAfter.folego.cents,
          greaterThanOrEqualTo(0),
          reason:
              'Aportes compensatórios devem ter coberto o déficit das despesas do ciclo',
        );
        expect(
          summaryAfter.committedFutureExpenses.cents,
          equals(0),
          reason:
              'Todas as despesas a vencer do ciclo foram quitadas na liquidação',
        );
      },
    );
  });
}
