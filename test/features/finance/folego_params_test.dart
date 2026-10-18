import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/auth/domain/entities/house.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/folego_params.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/presentation/widgets/folego_gauge_card.dart';

FinancialCycleSummary summary({required int contributions, required int folego}) => FinancialCycleSummary(
      cycle: FinancialCycle(start: DateTime(2026, 10, 5), end: DateTime(2026, 11, 4)),
      totalContributions: Money(contributions),
      totalExpensesPaid: const Money.zero(),
      committedFutureExpenses: const Money.zero(),
      folego: Money(folego),
      memberContributions: const {},
      memberExpensesPaid: const {},
    );

void main() {
  group('FolegoParams', () {
    test('sem nada gravado valem os padrões de sempre', () {
      for (final json in <Object?>[null, <String, dynamic>{}, 'x']) {
        final p = FolegoParams.fromJson(json);
        expect(p, const FolegoParams());
        expect(p.warningPercent, 15);
        expect(p.commitmentWarningPercent, 65);
        expect(p.commitmentDangerPercent, 85);
        expect(p.comfortableDailyCents, 5000);
        expect(p.recurringHorizonMonths, 3);
        expect(p.transitionMinDays, 15);
      }
      expect(HouseSettings.fromJson({}).folegoParams, const FolegoParams());
    });

    test('lê o gravado, ignora o inválido e faz ida e volta', () {
      final p = FolegoParams.fromJson({
        'warning_percent': 25,
        'commitment_warning_percent': 50,
        'commitment_danger_percent': 70,
        'comfortable_daily_cents': 8000,
        'recurring_horizon_months': 6,
        'transition_min_days': 20,
      });
      expect(p.warningPercent, 25);
      expect(p.recurringHorizonMonths, 6);
      expect(FolegoParams.fromJson(p.toJson()), p);
      expect(HouseSettings.fromJson({'folego_params': p.toJson()}).folegoParams, p);

      // Fora da faixa ou incoerente: cai no padrão
      final bad = FolegoParams.fromJson({
        'warning_percent': 150,
        'commitment_warning_percent': 90,
        'commitment_danger_percent': 80,
        'recurring_horizon_months': 0,
        'transition_min_days': 3,
      });
      expect(bad, const FolegoParams());
      expect(const FolegoParams(commitmentWarningPercent: 90, commitmentDangerPercent: 80).isValid, isFalse);
      expect(const FolegoParams().isValid, isTrue);
    });
  });

  group('Status do Fôlego', () {
    test('o padrão mantém o corte em 15% dos aportes', () {
      expect(summary(contributions: 100000, folego: 14999).status, FolegoStatus.warning);
      expect(summary(contributions: 100000, folego: 15000).status, FolegoStatus.positive);
      expect(summary(contributions: 100000, folego: -1).status, FolegoStatus.danger);
    });

    test('a casa move o limite', () {
      final s = summary(contributions: 100000, folego: 20000);
      expect(s.statusWith(const FolegoParams()), FolegoStatus.positive);
      expect(s.statusWith(const FolegoParams(warningPercent: 30)), FolegoStatus.warning);
      expect(s.statusWith(const FolegoParams(warningPercent: 0)), FolegoStatus.positive);
    });
  });

  group('Cartão do Fôlego', () {
    Future<void> show(WidgetTester tester, FinancialCycleSummary s, FolegoParams params) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FolegoGaugeCard(
              summary: s,
              cycle: s.cycle,
              onPreviousCycle: () {},
              onNextCycle: () {},
              params: params,
            ),
          ),
        ),
      ));
    }

    testWidgets('o selo segue o limite da casa', (tester) async {
      final s = summary(contributions: 100000, folego: 20000);
      await show(tester, s, const FolegoParams());
      expect(find.text('Saudável'), findsOneWidget);
      await show(tester, s, const FolegoParams(warningPercent: 30));
      expect(find.text('Atenção'), findsOneWidget);
    });
  });

  group('Transição do ciclo', () {
    test('padrão único de 15 dias, igual ao de sempre', () {
      expect(CycleSchedule.defaultTransitionDays, 15);
      expect(const CycleSchedule(5).minTransitionDays, 15);
      expect(CycleSchedule.transitionDaysFromParams(null), 15);
      expect(CycleSchedule.transitionDaysFromParams({'transition_min_days': 99}), 15);
      expect(CycleSchedule.transitionDaysFromParams({'transition_min_days': 20}), 20);
    });

    test('a casa alonga o mínimo da transição', () {
      // Troca do dia 9 para o 5 em 09/11: com 15 dias o dia 5 de dezembro já vale;
      // com 30, só o dia 5 de janeiro.
      final change = CycleDayChange(from: DateTime(2026, 11, 9), day: 5, previousDay: 9);
      final padrao = CycleSchedule(5, [change]).cycleFor(DateTime(2026, 12, 10));
      final longa = CycleSchedule(5, [change], 30).cycleFor(DateTime(2026, 12, 10));
      expect(padrao.startDate, DateTime(2026, 12, 5));
      expect(longa.startDate, DateTime(2026, 11, 9));
      expect(longa.endDate.day, 4);
      expect(longa.endDate.month, 1);
    });

    test('a casa carrega o mínimo no calendário', () {
      const house = House(id: 'h', name: 'Casa', transitionMinDays: 25);
      expect(house.cycleSchedule.minTransitionDays, 25);
      expect(const House(id: 'h', name: 'Casa').cycleSchedule.minTransitionDays, 15);
    });
  });

  test('modo demo grava os parâmetros da casa', () async {
    final ds = MockFinanceDataSource();
    final saved = await ds.updateHouseSettings({
      'folego_params': const FolegoParams(warningPercent: 20).toJson(),
    });
    expect(saved.folegoParams.warningPercent, 20);
    expect((await ds.getHouseSettings()).folegoParams.warningPercent, 20);
  });
}
