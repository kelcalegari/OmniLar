import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  test('Super Pix não inventa chave para quem não cadastrou Pix', () {
    final summary = const GlobalClearingEngine().computeSettlement(
      cycle: FinancialCycle.fromDate(
        date: DateTime(2026, 10, 12),
        cycleStartDay: 9,
      ),
      members: const [
        HouseMember(id: 'ana', name: 'Ana'),
        HouseMember(id: 'bia', name: 'Bia', pixKey: 'bia@exemplo.com'),
      ],
      expenses: [
        HouseExpense(
          id: 'e1',
          title: 'Mercado',
          amount: const Money(20000),
          date: DateTime(2026, 10, 12),
          categoryId: 'c',
          paidByMemberId: 'ana',
          paymentMethodId: 'pm',
          splitRule: const SplitRule.percentage(null),
          paidOutOfPocket: true,
        ),
        HouseExpense(
          id: 'e2',
          title: 'Farmácia',
          amount: const Money(4000),
          date: DateTime(2026, 10, 13),
          categoryId: 'c',
          paidByMemberId: 'bia',
          paymentMethodId: 'pm',
          splitRule: const SplitRule.singleResponsible('ana'),
          paidOutOfPocket: true,
        ),
      ],
      contributions: const [],
      loans: const [],
    );

    // Bia deve a Ana, que não tem chave Pix cadastrada
    final toAna = summary.transfers.where((t) => t.toMemberId == 'ana');
    expect(toAna, isNotEmpty);
    for (final transfer in toAna) {
      expect(transfer.pixKey, isNull);
    }
  });
}
