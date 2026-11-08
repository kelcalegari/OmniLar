import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/presentation/pages/smart_scanner_page.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
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

  testWidgets('nota lida pode ser paga com dois meios, valor digitado à mão', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    cubit.goToCurrentCycle();
    await cubit.loadCycleData();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day, 12);
    final proposal = CaptureProposal(
      id: 'prop_nota_dividida_teste',
      documentType: DocumentType.nfce,
      title: 'Nota dividida teste',
      totalAmount: const Money(15000),
      date: day,
      capturedAt: day,
    );

    await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
      value: cubit,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SmartScannerPage(initialProposal: proposal)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('scan_payment_split_switch'));
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final methodField = find.byKey(const Key('scan_payment_split_method_0'));
    await tester.ensureVisible(methodField);
    await tester.tap(methodField);
    await tester.pumpAndSettle();
    final otherName = cubit.state.paymentMethods.last.name;
    await tester.tap(find.text(otherName).last);
    await tester.pumpAndSettle();

    final amount = find.descendant(
      of: find.byKey(const Key('scan_payment_split_amount_0')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amount, '5000');
    await tester.pumpAndSettle();
    expect(find.textContaining('No meio principal: R\$\u00a0100,00'), findsOneWidget);

    final confirm = find.text('Confirmar Lançamento');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final saved = cubit.state.expenses.where((e) => e.title == 'Nota dividida teste').toList();
    expect(saved.map((e) => e.amount.cents).toList()..sort(), [5000, 10000]);
    expect(saved.map((e) => e.paymentGroupId).toSet(), hasLength(1));
    expect(saved.first.paymentGroupId, isNotNull);
  });

  testWidgets('boleto de condomínio com demonstrativo grava os itens como da casa', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    cubit.goToCurrentCycle();
    await cubit.loadCycleData();
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 12).add(const Duration(days: 3));
    final proposal = CaptureProposal(
      id: 'prop_condominio_teste',
      documentType: DocumentType.boleto,
      title: 'Condomínio teste com itens',
      totalAmount: const Money(123457),
      date: due,
      dueDate: due,
      capturedAt: now,
      items: const [
        InvoiceItemDraft(id: 'i1', name: 'Taxa ordinária', unitPrice: Money(100000), totalPrice: Money(100000)),
        InvoiceItemDraft(id: 'i2', name: 'Água', unitPrice: Money(13457), totalPrice: Money(13457)),
        InvoiceItemDraft(id: 'i3', name: 'Fundo de reserva', unitPrice: Money(10000), totalPrice: Money(10000)),
      ],
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

    final confirm = find.text('Confirmar Lançamento');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final saved = cubit.state.expenses.where((e) => e.title == 'Condomínio teste com itens').single;
    expect(saved.items.map((i) => i.title), ['Taxa ordinária', 'Água', 'Fundo de reserva']);
    expect(saved.items.every((i) => i.responsibleMemberId == null), isTrue);
  });

  testWidgets('boleto de luz pode entrar como conta recorrente, no dia do vencimento', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    cubit.goToCurrentCycle();
    await cubit.loadCycleData();
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 12).add(const Duration(days: 5));
    final proposal = CaptureProposal(
      id: 'prop_luz_recorrente_teste',
      documentType: DocumentType.boleto,
      title: 'Luz recorrente teste',
      totalAmount: const Money(18734),
      date: due,
      dueDate: due,
      capturedAt: now,
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

    final toggle = find.byKey(const Key('scan_mark_recurring'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('vencendo no dia ${due.day}'), findsOneWidget);
    expect(find.text('Valor variável'), findsOneWidget);

    final confirm = find.text('Confirmar Lançamento');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    // O vencimento pode cair no ciclo seguinte: lê o ciclo dele
    final ofDueCycle = await sl<FinanceRepository>().getExpensesForCycle(cubit.cycleSchedule.cycleFor(due));
    final saved = ofDueCycle.where((e) => e.title == 'Luz recorrente teste').single;
    expect(saved.isRecurring, isTrue);
    expect(saved.isVariable, isTrue);
    expect(saved.dueDay, due.day);
    expect(saved.status, ExpenseStatus.pending);
  });

  testWidgets('boleto sem marcar continua como conta avulsa', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    cubit.goToCurrentCycle();
    await cubit.loadCycleData();
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 12).add(const Duration(days: 6));
    final proposal = CaptureProposal(
      id: 'prop_boleto_avulso_teste',
      documentType: DocumentType.boleto,
      title: 'Boleto avulso teste',
      totalAmount: const Money(9911),
      date: due,
      dueDate: due,
      capturedAt: now,
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

    final confirm = find.text('Confirmar Lançamento');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    // O vencimento pode cair no ciclo seguinte: lê o ciclo dele
    final ofDueCycle = await sl<FinanceRepository>().getExpensesForCycle(cubit.cycleSchedule.cycleFor(due));
    final saved = ofDueCycle.where((e) => e.title == 'Boleto avulso teste').single;
    expect(saved.isRecurring, isFalse);
    expect(saved.dueDay, isNull);
  });
}
