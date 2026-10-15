import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/presentation/pages/smart_scanner_page.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('nota lida pode ser lançada a pagar, com vencimento', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    cubit.goToCurrentCycle();
    await cubit.loadCycleData();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day, 12);
    final proposal = CaptureProposal(
      id: 'prop_nota_teste',
      documentType: DocumentType.nfce,
      title: 'Nota a pagar teste',
      totalAmount: const Money(4321),
      date: day,
      capturedAt: day,
    );

    await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
      value: cubit,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: SingleChildScrollView(child: SmartScannerPage(initialProposal: proposal)),
                  ),
                )),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Nota nasce como já paga, com a forma de pagamento à vista
    expect(find.textContaining('Compra em'), findsOneWidget);
    expect(find.text('Forma de Pagamento'), findsOneWidget);

    await tester.tap(find.text('A pagar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vence em'), findsOneWidget);
    expect(find.text('Forma de Pagamento'), findsNothing);

    final confirm = find.text('Confirmar Lançamento');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final saved = cubit.state.expenses.where((e) => e.title == 'Nota a pagar teste').single;
    expect(saved.status, ExpenseStatus.pending);
    expect(saved.dueDate, day);
  });
}
