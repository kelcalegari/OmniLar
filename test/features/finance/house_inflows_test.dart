import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_inflow.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/opening_inflows.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';
import 'package:omni_lar/features/finance/presentation/widgets/house_inflows_card.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

/// Entrada de fora (0096): dinheiro no Caixa que não é aporte de morador.
void main() {
  const engine = GlobalClearingEngine();
  final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 7);

  HouseExpense expense(int cents) => HouseExpense(
        id: 'e1',
        title: 'Conta',
        amount: Money(cents),
        date: DateTime(2026, 10, 12),
        categoryId: 'c',
        paidByMemberId: 'ana',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage(null),
      );

  group('Motor do fechamento', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
      HouseMember(id: 'bia', name: 'Bia', defaultSplitPercent: 50),
    ];

    // Despesa de R$ 1.000 e entrada de fora de R$ 200
    SettlementSummary close(OpeningInflowRules rules, {OpeningBalanceRule? legacy}) => engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [expense(100000)],
          contributions: const [],
          loans: const [],
          openingBalance: const Money(20000),
          openingBalanceRule: legacy,
          openingInflows: const OpeningInflows(thirdParty: Money(20000)),
          openingInflowRules: rules,
        );

    int due(SettlementSummary s, String id) =>
        s.memberBalances.firstWhere((b) => b.memberId == id).contributionDue.cents;

    test('Regra abater os aportes: reduz a parte de cada um e aparece na memória de cálculo', () {
      final s = close(const OpeningInflowRules(thirdParty: OpeningBalanceRule.reduceQuotas));
      expect(due(s, 'ana'), 40000);
      expect(due(s, 'bia'), 40000);
      expect(s.thirdPartyInflows.cents, 20000);
      final audit = s.auditTrails['ana']!.expenseShares.where((e) => e.expenseId == 'opening_balance');
      expect(audit.single.expenseTitle, 'Entrada de fora abatida');
    });

    test('Regra guardar (keep): ninguém é abatido', () {
      final s = close(const OpeningInflowRules(thirdParty: OpeningBalanceRule.keep));
      expect(due(s, 'ana'), 50000);
      expect(due(s, 'bia'), 50000);
    });

    test('Sem escolha própria segue a regra da sobra', () {
      final s = close(const OpeningInflowRules(rolledSurplus: OpeningBalanceRule.reduceQuotas));
      expect(due(s, 'ana'), 40000);
      final keep = close(const OpeningInflowRules(rolledSurplus: OpeningBalanceRule.keep));
      expect(due(keep, 'ana'), 50000);
    });

    test('Sem regra por tipo, a entrada segue a regra única e não conta duas vezes', () {
      final s = close(const OpeningInflowRules(), legacy: OpeningBalanceRule.reduceQuotas);
      expect(due(s, 'ana'), 40000);
      expect(due(s, 'bia'), 40000);
      final audit = s.auditTrails['ana']!.expenseShares.where((e) => e.expenseId == 'opening_balance');
      expect(audit.single.expenseTitle, 'Entrada de fora abatida');
    });
  });

  group('Fonte de dados e cubit', () {
    late MockFinanceDataSource ds;
    late FinanceCubit cubit;

    setUp(() async {
      ds = MockFinanceDataSource();
      cubit = FinanceCubit(FinanceRepositoryImpl(ds));
      await cubit.loadCycleData();
    });

    tearDown(() => cubit.close());

    HouseInflow inflow(int cents, DateTime day, {String id = 'novo'}) => HouseInflow(
          id: id,
          amount: Money(cents),
          receivedOn: day,
          description: 'Pix do João',
          source: HouseInflowSource.thirdPartyPix,
        );

    DateTime inCycle(FinancialCycle c) => c.startDate.add(const Duration(days: 1));

    test('A entrada vai para o Caixa do ciclo do dia e para OpeningInflows.thirdParty', () async {
      final current = cubit.state.currentCycle;
      final before = (await ds.getOpeningBalance(current)).cents;

      expect(await cubit.addHouseInflow(inflow(8000, inCycle(current))), isTrue);

      expect(cubit.state.houseInflows.single.amount.cents, 8000);
      expect(cubit.state.houseInflowsTotal.cents, 8000);
      expect((await ds.getOpeningInflows(current)).thirdParty.cents, 8000);
      expect((await ds.getOpeningBalance(current)).cents, before + 8000);
      expect(cubit.state.summary!.openingInflows!.thirdParty.cents, 8000);
      // Outro ciclo não recebe
      final other = FinancialCycle.fromDate(
        date: current.startDate.subtract(const Duration(days: 10)),
        cycleStartDay: current.startDate.day,
      );
      expect((await ds.getOpeningInflows(other)).thirdParty.cents, 0);
      expect(await ds.getHouseInflowsForCycle(other), isEmpty);
    });

    test('Corrigir e excluir', () async {
      final current = cubit.state.currentCycle;
      await cubit.addHouseInflow(inflow(8000, inCycle(current)));
      final saved = cubit.state.houseInflows.single;

      expect(await cubit.updateHouseInflow(saved.copyWith(amount: const Money(9500), source: HouseInflowSource.refund)),
          isTrue);
      expect(cubit.state.houseInflows.single.amount.cents, 9500);
      expect(cubit.state.houseInflows.single.source, HouseInflowSource.refund);

      expect(await cubit.deleteHouseInflow(saved.id), isTrue);
      expect(cubit.state.houseInflows, isEmpty);
    });

    test('Valor zero, sem descrição ou em ciclo fechado são recusados', () async {
      final current = cubit.state.currentCycle;
      expect(await cubit.addHouseInflow(inflow(0, inCycle(current))), isFalse);
      expect(
        await cubit.addHouseInflow(HouseInflow(
          id: 'x',
          amount: const Money(100),
          receivedOn: inCycle(current),
          description: '  ',
        )),
        isFalse,
      );
      await cubit.addHouseInflow(inflow(8000, inCycle(current)));
      ds.isDateInClosedCycle = (_) async => true;
      expect(await cubit.addHouseInflow(inflow(100, inCycle(current), id: 'y')), isFalse);
      expect(await cubit.deleteHouseInflow(cubit.state.houseInflows.single.id), isFalse);
      expect(cubit.state.houseInflows.length, 1);
    });

    test('Só quem lançou ou um administrador mexe na entrada', () {
      final i = HouseInflow(
        id: 'a',
        amount: Money(100),
        receivedOn: _day,
        description: 'x',
        createdBy: 'ana',
      );
      expect(i.canEdit(memberId: 'ana'), isTrue);
      expect(i.canEdit(memberId: 'bia'), isFalse);
      expect(i.canEdit(memberId: 'bia', isAdmin: true), isTrue);
    });
  });

  group('HouseInflowsCard', () {
    late MockFinanceDataSource ds;
    late FinanceCubit cubit;

    setUp(() async {
      ds = MockFinanceDataSource();
      cubit = FinanceCubit(FinanceRepositoryImpl(ds));
      await cubit.loadCycleData();
    });

    tearDown(() => cubit.close());

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: BlocBuilder<FinanceCubit, FinanceState>(
                  builder: (context, state) => SingleChildScrollView(
                    child: HouseInflowsCard(state: state, cubit: cubit, currentMemberId: 'member_carlos'),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('Lança uma entrada de fora pelo formulário e ela aparece na lista', (tester) async {
      await pump(tester);
      expect(find.text('Entradas de fora'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_house_inflow')));
      await tester.pumpAndSettle();
      // Sem valor, o formulário não fecha
      await tester.enterText(find.byKey(const Key('house_inflow_description')), 'Pix do João');
      await tester.tap(find.byKey(const Key('house_inflow_save')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o valor.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.tap(find.byKey(const Key('house_inflow_source_refund')));
      await tester.tap(find.byKey(const Key('house_inflow_save')));
      await tester.pumpAndSettle();

      expect(cubit.state.houseInflows.length, 1);
      expect(cubit.state.houseInflows.single.description, 'Pix do João');
      expect(cubit.state.houseInflows.single.source, HouseInflowSource.refund);
      expect(cubit.state.houseInflows.single.createdBy, 'member_carlos');
      expect(find.textContaining('Pix do João'), findsOneWidget);
    });

    testWidgets('Lança um repasse para fatura de cartão pelo formulário unificado', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('add_house_inflow')));
      await tester.pumpAndSettle();

      // Troca para o modo "Fatura de cartão"
      await tester.tap(find.text('Fatura de cartão'));
      await tester.pumpAndSettle();

      // Sem valor, não fecha
      await tester.tap(find.byKey(const Key('house_inflow_save')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o valor.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.enterText(find.byKey(const Key('receipt_payer')), 'Ana');
      await tester.tap(find.byKey(const Key('house_inflow_save')));
      await tester.pumpAndSettle();

      expect(cubit.state.heldThirdPartyReceipts.length, 1);
      final receipt = cubit.state.heldThirdPartyReceipts.single;
      expect(receipt.payerName, 'Ana');
      expect(receipt.amount.cents, 5000);
    });
  });
}

final _day = DateTime(2026, 10, 12);
