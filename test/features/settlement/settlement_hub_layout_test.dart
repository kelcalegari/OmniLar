import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/data/repositories/settlement_repository_impl.dart';
import 'package:omni_lar/features/settlement/presentation/cubit/settlement_cubit.dart';
import 'package:omni_lar/features/settlement/presentation/pages/settlement_hub_page.dart';
import 'package:omni_lar/features/settlement/presentation/widgets/settlement_audit_sheet.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  setUp(() async {
    await sl.reset();
    final finance = MockFinanceDataSource();
    final p2p = MockP2PDataSource();
    final repository = SettlementRepositoryImpl(
      MockSettlementDataSource(financeDataSource: finance, p2pDataSource: p2p),
    );
    sl.registerFactory<SettlementCubit>(() => SettlementCubit(repository));
  });

  tearDown(() => sl.reset());

  Future<void> pumpHub(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
    await tester.pumpWidget(
      MaterialApp(home: SettlementHubPage(initialCycle: cycle)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('No celular: o único acesso à auditoria é o botão, sem estourar a tela', (
    tester,
  ) async {
    await pumpHub(tester, const Size(360, 800));

    await tester.scrollUntilVisible(
      find.text('Auditar memória de cálculo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Auditar memória de cálculo'), findsOneWidget);
    expect(find.byTooltip('Auditar memória de cálculo'), findsNothing);
    expect(find.text('Auditar'), findsNothing);

    await tester.ensureVisible(find.text('Auditar memória de cálculo'));
    await tester.tap(find.text('Auditar memória de cálculo'));
    await tester.pumpAndSettle();
    expect(find.text('Auditoria do Cálculo'), findsOneWidget);
  });

  testWidgets('No desktop: a auditoria fica na tela e não há botão para o modal', (
    tester,
  ) async {
    await pumpHub(tester, const Size(1400, 900));

    expect(find.byType(SettlementAuditSheet), findsOneWidget);
    expect(find.text('Auditar memória de cálculo'), findsNothing);
  });
}
