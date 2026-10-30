import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/services/installment_loan_groups.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/widgets/installment_group_card.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<P2PCubit>()) {
      await initServiceLocator();
    }
  });

  P2PLoan parcel(int number) {
    final due = DateTime(2026, 11 + number, 10);
    return P2PLoan(
      id: 'ml_$number',
      title: 'mercadolivre ($number/3) — Kelvynn',
      totalAmount: const Money(12542),
      lenderMemberId: P2PLoan.houseLenderId,
      borrowerMemberId: 'me',
      installmentsCount: 1,
      createdAt: DateTime(2026, 10, 30),
      firstDueDate: due,
      installments: [
        P2PInstallment(
          id: 'i_$number',
          loanId: 'ml_$number',
          number: 1,
          totalCount: 1,
          amount: const Money(12542),
          dueDate: due,
        ),
      ],
      installmentPlanIds: const ['plan_ml'],
    );
  }

  testWidgets('mostra a compra num card só e abre a lista das parcelas', (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final group = groupInstallmentLoans([parcel(1), parcel(2), parcel(3)]).single as InstallmentLoanGroup;
    await tester.pumpWidget(
      BlocProvider.value(
        value: sl<P2PCubit>(),
        child: MaterialApp(
          home: Scaffold(body: InstallmentGroupCard(group: group, isDebtor: true)),
        ),
      ),
    );

    expect(find.text('mercadolivre — Kelvynn'), findsOneWidget);
    expect(find.text('Compra parcelada em 3×'), findsOneWidget);
    expect(find.textContaining('0/3 parcelas pagas'), findsOneWidget);

    await tester.tap(find.text('mercadolivre — Kelvynn'));
    await tester.pumpAndSettle();

    expect(find.text('Parcela 1/3'), findsOneWidget);
    expect(find.text('Parcela 2/3'), findsOneWidget);
    expect(find.text('Parcela 3/3'), findsOneWidget);
  });
}
