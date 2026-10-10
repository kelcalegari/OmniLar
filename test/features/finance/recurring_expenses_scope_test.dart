import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/enums/recurrence.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';

void main() {
  group('MockFinanceDataSource - Despesas Recorrentes & Escopos de Edição/Exclusão', () {
    late MockFinanceDataSource dataSource;

    setUp(() {
      dataSource = MockFinanceDataSource();
    });

    test('updateExpense com scope thisInstanceOnly altera apenas a cobrança pontual', () async {
      final baseDate = DateTime(2026, 10, 10);
      const seriesId = 'series_internet_fiber';

      final expCurrent = HouseExpense(
        id: 'exp_net_out',
        title: 'Internet Fibra Óptica',
        amount: const Money(12000), // R$ 120,00
        date: baseDate,
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      final expNext = HouseExpense(
        id: 'exp_net_nov',
        title: 'Internet Fibra Óptica',
        amount: const Money(12000),
        date: baseDate.add(const Duration(days: 30)),
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      await dataSource.addExpense(expCurrent);
      await dataSource.addExpense(expNext);

      // Altera apenas o mês de Outubro para R$ 150,00 (ex: taxa pontual de visita técnica)
      final modifiedCurrent = expCurrent.copyWith(amount: const Money(15000));
      await dataSource.updateExpense(modifiedCurrent, scope: RecurrenceScope.thisInstanceOnly);

      final allRecurring = await dataSource.getRecurringExpenses();
      final outExpense = allRecurring.firstWhere((e) => e.id == 'exp_net_out');
      final novExpense = allRecurring.firstWhere((e) => e.id == 'exp_net_nov');

      expect(outExpense.amount, equals(const Money(15000)));
      expect(novExpense.amount, equals(const Money(12000))); // manteve valor original!
    });

    test('updateExpense com scope thisAndFuture altera do mês atual em diante', () async {
      final baseDate = DateTime(2026, 10, 5);
      const seriesId = 'series_aluguel';

      final exp1 = HouseExpense(
        id: 'aluguel_out',
        title: 'Aluguel do Apartamento',
        amount: const Money(250000), // R$ 2.500,00
        date: baseDate,
        categoryId: 'cat_moradia',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      final exp2 = HouseExpense(
        id: 'aluguel_nov',
        title: 'Aluguel do Apartamento',
        amount: const Money(250000),
        date: baseDate.add(const Duration(days: 30)),
        categoryId: 'cat_moradia',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      await dataSource.addExpense(exp1);
      await dataSource.addExpense(exp2);

      // Reajuste anual: a partir de Outubro sobe para R$ 2.700,00
      final reajuste = exp1.copyWith(amount: const Money(270000));
      await dataSource.updateExpense(reajuste, scope: RecurrenceScope.thisAndFuture);

      final allRecurring = await dataSource.getRecurringExpenses();
      final out = allRecurring.firstWhere((e) => e.id == 'aluguel_out');
      final nov = allRecurring.firstWhere((e) => e.id == 'aluguel_nov');

      expect(out.amount, equals(const Money(270000)));
      expect(nov.amount, equals(const Money(270000)));
    });

    test('deleteExpense com scope thisAndFuture cancela a assinatura futura e mantém histórico', () async {
      final baseDate = DateTime(2026, 10, 1);
      const seriesId = 'series_stream_cancel';

      final expPast = HouseExpense(
        id: 'stream_set',
        title: 'Assinatura Streaming',
        amount: const Money(4500),
        date: baseDate.subtract(const Duration(days: 30)),
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_marina',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      final expCurrent = HouseExpense(
        id: 'stream_out',
        title: 'Assinatura Streaming',
        amount: const Money(4500),
        date: baseDate,
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_marina',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      await dataSource.addExpense(expPast);
      await dataSource.addExpense(expCurrent);

      // Cancela a partir de outubro
      await dataSource.deleteExpense('stream_out', scope: RecurrenceScope.thisAndFuture);

      final recurringActive = await dataSource.getRecurringExpenses();
      expect(recurringActive.any((e) => e.id == 'stream_out'), isFalse);
    });

    test('deleteExpense com scope allInstances remove completamente toda a série', () async {
      const seriesId = 'series_total_remove';
      final exp = HouseExpense(
        id: 'test_delete_all_exp',
        title: 'Serviço Cancelado Integral',
        amount: const Money(8000),
        date: DateTime.now(),
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        isRecurring: true,
        recurringSeriesId: seriesId,
      );

      await dataSource.addExpense(exp);
      await dataSource.deleteExpense('test_delete_all_exp', scope: RecurrenceScope.allInstances);

      final recurringActive = await dataSource.getRecurringExpenses();
      expect(recurringActive.any((e) => e.title == 'Serviço Cancelado Integral'), isFalse);
    });
  });
}
