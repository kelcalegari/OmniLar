import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/services/installment_loan_groups.dart';

void main() {
  P2PLoan parcel(int number, {String plan = 'plan_ml', bool paid = false, int count = 12}) {
    final due = DateTime(2026, 11 + number, 10);
    return P2PLoan(
      id: '${plan}_$number',
      title: 'mercadolivre*mercadolivre ($number/$count) — Kelvynn',
      totalAmount: const Money(12542),
      lenderMemberId: P2PLoan.houseLenderId,
      borrowerMemberId: 'me',
      installmentsCount: 1,
      createdAt: DateTime(2026, 10, 30),
      firstDueDate: due,
      status: paid ? LoanStatus.paid : LoanStatus.active,
      installments: [
        P2PInstallment(
          id: 'i_${plan}_$number',
          loanId: '${plan}_$number',
          number: 1,
          totalCount: 1,
          amount: const Money(12542),
          paidAmount: paid ? const Money(12542) : const Money.zero(),
          dueDate: due,
        ),
      ],
      houseFunding: HouseLoanFunding.cycle,
      fundedOn: due,
      installmentPlanIds: [plan],
    );
  }

  final other = P2PLoan(
    id: 'avulso',
    title: 'Empréstimo da Marina',
    totalAmount: const Money(5000),
    lenderMemberId: 'marina',
    borrowerMemberId: 'me',
    installmentsCount: 2,
    createdAt: DateTime(2026, 10, 1),
    firstDueDate: DateTime(2026, 11, 10),
  );

  test('junta as parcelas da mesma compra num card só, na ordem das parcelas', () {
    final loans = [parcel(6), other, parcel(12), parcel(11)];
    final entries = groupInstallmentLoans(loans);

    expect(entries, hasLength(2));
    final group = entries.first as InstallmentLoanGroup;
    expect(group.title, 'mercadolivre*mercadolivre — Kelvynn');
    expect(group.purchaseInstallments, 12);
    expect(group.loans.map(InstallmentLoanGroup.numberOf), [6, 11, 12]);
    expect(group.remainingAmount.cents, 3 * 12542);
    expect((entries[1] as SingleLoanEntry).loan.id, 'avulso');
  });

  test('conta as parcelas já pagas que estão fora da lista', () {
    final paid = [for (var n = 1; n <= 5; n++) parcel(n, paid: true)];
    final open = [for (var n = 6; n <= 12; n++) parcel(n)];
    final group = groupInstallmentLoans(open, all: [...paid, ...open]).single as InstallmentLoanGroup;

    expect(group.loans, hasLength(7));
    expect(group.siblings, hasLength(12));
    expect(group.paidCount, 5);
    expect(group.totalAmount.cents, 12 * 12542);
    expect(group.progressPercentage, closeTo(5 / 12, 0.0001));
    expect(group.nextOpen?.id, 'plan_ml_6');
  });

  test('compras diferentes ficam em cards diferentes', () {
    final entries = groupInstallmentLoans([parcel(1), parcel(2), parcel(1, plan: 'outra'), parcel(2, plan: 'outra')]);
    expect(entries.whereType<InstallmentLoanGroup>().map((g) => g.planId), ['plan_ml', 'outra']);
  });

  test('uma parcela sozinha, sem irmãs, continua um card normal', () {
    final entries = groupInstallmentLoans([parcel(3)]);
    expect(entries.single, isA<SingleLoanEntry>());
  });

  test('empréstimo da fatura importada (sem "n/N" no título) não é agrupado', () {
    final invoice = parcel(1).copyWith(title: 'Nubank (venc. 10/11) — Kelvynn');
    final invoice2 = parcel(2).copyWith(title: 'Nubank (venc. 10/12) — Kelvynn');
    expect(groupInstallmentLoans([invoice, invoice2]).whereType<SingleLoanEntry>(), hasLength(2));
  });
}
