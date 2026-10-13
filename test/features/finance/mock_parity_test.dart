import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/recurring_series.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';

void main() {
  group('Modo demo se comporta como o banco', () {
    test('resgate acima do saldo da caixinha é recusado e não mexe no saldo', () async {
      final dataSource = MockFinanceDataSource();
      final vault = (await dataSource.getSavingsVaults()).first;

      await expectLater(
        dataSource.withdrawFromVault(
          vaultId: vault.id,
          memberId: 'member_carlos',
          amount: Money(vault.currentBalance.cents + 1),
          description: 'acima do saldo',
        ),
        throwsA(isA<ServerFailure>()),
      );

      final after = (await dataSource.getSavingsVaults()).firstWhere((v) => v.id == vault.id);
      expect(after.currentBalance, vault.currentBalance);
    });

    test('empréstimo criado sem parcelas ganha as parcelas e não aparece quitado', () async {
      final dataSource = MockP2PDataSource();
      await dataSource.createLoan(
        P2PLoan(
          id: 'loan_sem_parcelas',
          title: 'Fatura dividida',
          totalAmount: const Money(30000),
          lenderMemberId: 'member_carlos',
          borrowerMemberId: 'member_marina',
          installmentsCount: 3,
          createdAt: DateTime(2026, 10, 13),
          firstDueDate: DateTime(2026, 11, 10),
        ),
      );

      final loan = (await dataSource.getLoans()).firstWhere((l) => l.id == 'loan_sem_parcelas');
      expect(loan.installments.length, 3);
      expect(
        loan.installments.fold<int>(0, (acc, i) => acc + i.amount.cents),
        30000,
      );
    });
  });

  group('Parcela atrasada', () {
    P2PInstallment installment(DateTime due) => P2PInstallment(
          id: 'i1',
          loanId: 'l1',
          number: 1,
          totalCount: 1,
          amount: const Money(10000),
          dueDate: due,
        );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    test('no dia do vencimento ainda está em dia; no dia seguinte, atrasada', () {
      expect(installment(today).status, InstallmentStatus.pending);
      expect(installment(today.subtract(const Duration(days: 1))).status, InstallmentStatus.overdue);
      expect(installment(today.add(const Duration(days: 1))).status, InstallmentStatus.pending);
    });
  });

  group('Séries recorrentes', () {
    HouseExpense occurrence(String id, DateTime due, {String? seriesId, int cents = 10000}) =>
        HouseExpense(
          id: id,
          title: 'Internet',
          amount: Money(cents),
          date: due,
          dueDate: due,
          categoryId: 'c',
          paymentMethodId: 'pm',
          paidByMemberId: 'm1',
          splitRule: const SplitRule.percentage({'m1': 100.0}),
          isRecurring: true,
          recurringSeriesId: seriesId,
        );

    test('uma linha por série ativa, com a ocorrência mais recente', () {
      final rows = [
        occurrence('s1', DateTime(2026, 10, 20)),
        occurrence('s1-nov', DateTime(2026, 11, 20), seriesId: 's1', cents: 12000),
        occurrence('s2-old', DateTime(2026, 9, 5), seriesId: 's2'),
      ];

      final series = latestOccurrencePerSeries(rows, activeSeriesIds: {'s1'});

      expect(series.length, 1);
      expect(series.single.id, 's1-nov');
      expect(series.single.amount.cents, 12000);
    });
  });
}
