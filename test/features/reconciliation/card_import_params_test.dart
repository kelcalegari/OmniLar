import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/import_params.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/pending_payment.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_matcher.dart';

const _uuidA = '11111111-1111-4111-8111-111111111111';
const _uuidB = '22222222-2222-4222-8222-222222222222';

const _card = PaymentMethod(
  id: 'pm_nubank',
  name: 'Nubank',
  type: PaymentMethodType.card,
  ownerMemberId: 'kelvynn',
  closingDay: 28,
  dueDay: 10,
);

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

const _categories = [
  ExpenseCategory(id: 'cat_mercado', name: 'Mercado', icon: 'cart', colorHex: '#10B981'),
  ExpenseCategory(id: 'cat_lazer', name: 'Lazer', icon: 'fun', colorHex: '#F59E0B'),
  ExpenseCategory(id: 'cat_carro', name: 'Carro', icon: 'car', colorHex: '#000000', ownerMemberId: 'cristiano'),
];

ImportedStatementLine _line(String id, DateTime date, String description, int cents, {String? categoryId}) =>
    ImportedStatementLine(
      id: id,
      date: date,
      description: description,
      amount: Money(cents),
      categoryId: categoryId,
      signature: '$id#1',
    );

HouseExpense _expense(String id, String title, int cents, DateTime date) => HouseExpense(
      id: id,
      title: title,
      amount: Money(cents),
      date: date,
      categoryId: 'cat_mercado',
      paidByMemberId: 'kelvynn',
      paymentMethodId: 'pm_nubank',
      splitRule: const SplitRule.percentage({'kelvynn': 60, 'cristiano': 40}),
      status: ExpenseStatus.paid,
    );

void main() {
  group('ImportMatching', () {
    test('sem nada gravado vale o que a importação sempre usou', () {
      for (final json in <Object?>[null, 'x', <String, dynamic>{}]) {
        expect(ImportMatching.fromJson(json), const ImportMatching());
      }
      const defaults = ImportMatching();
      expect(defaults.dateWindowDays, StatementMatcher.dateWindowDays);
      expect(defaults.otherMethodWindowDays, StatementMatcher.otherMethodWindowDays);
      expect([
        defaults.dateWindowDays,
        defaults.otherMethodWindowDays,
        defaults.amountDiffersDays,
        defaults.amountDriftPercent,
        defaults.minSimilarityPercent,
        defaults.invoiceWindowDays,
      ], [3, 2, 1, 25, 50, 45]);
      expect(HouseSettings.fromJson({}).importMatching, defaults);
    });

    test('lê e escreve o objeto inteiro; valor fora da faixa ou incoerente volta ao padrão', () {
      const custom = ImportMatching(dateWindowDays: 5, otherMethodWindowDays: 4, amountDriftPercent: 10);
      expect(ImportMatching.fromJson(custom.toJson()), custom);
      expect(HouseSettings.fromJson({'import_matching': custom.toJson()}).importMatching, custom);
      expect(ImportMatching.fromJson({'date_window_days': 99}), const ImportMatching());
      expect(ImportMatching.fromJson({'date_window_days': 1}), const ImportMatching());
      expect(ImportMatching.fromJson({'invoice_window_days': 0}), const ImportMatching());
      expect(ImportMatching.fromJson({'amount_drift_percent': 2.5}), const ImportMatching());
      expect(const ImportMatching(dateWindowDays: 1).isValid, isFalse);
      expect(const ImportMatching(minSimilarityPercent: 101).isValid, isFalse);
      expect(const ImportMatching().isValid, isTrue);
    });
  });

  group('Janelas do casamento', () {
    final lines = [_line('l', DateTime(2026, 10, 14), 'MERCADO', 10000)];
    final expenses = [_expense('e', 'Mercado', 10000, DateTime(2026, 10, 10))];

    Map<String, LineMatch> match(ImportMatching matching) => StatementMatcher.match(
          lines: lines,
          expenses: expenses,
          paymentMethodId: 'pm_nubank',
          matching: matching,
        );

    test('4 dias de diferença: fora do padrão, dentro de uma janela maior', () {
      expect(match(const ImportMatching()), isEmpty);
      final wider = match(const ImportMatching(dateWindowDays: 5));
      expect(wider['l']!.kind, LineMatchKind.alreadyLaunched);
    });

    test('janela menor recusa o que o padrão aceitava', () {
      final close = [_line('l', DateTime(2026, 10, 12), 'MERCADO', 10000)];
      final found = StatementMatcher.match(lines: close, expenses: expenses, paymentMethodId: 'pm_nubank');
      expect(found['l']!.kind, LineMatchKind.alreadyLaunched);
      final none = StatementMatcher.match(
        lines: close,
        expenses: expenses,
        paymentMethodId: 'pm_nubank',
        matching: const ImportMatching(dateWindowDays: 1, otherMethodWindowDays: 1),
      );
      expect(none, isEmpty);
    });

    test('valor diferente: a tolerância de valor é da casa', () {
      final tip = [_line('t', DateTime(2026, 10, 10), 'JANTAR SABOR', 11500)];
      final dinner = [_expense('d', 'Jantar Sabor', 10000, DateTime(2026, 10, 10))];
      Map<String, LineMatch> run(ImportMatching m) =>
          StatementMatcher.match(lines: tip, expenses: dinner, paymentMethodId: 'pm_nubank', matching: m);
      expect(run(const ImportMatching())['t']!.kind, LineMatchKind.amountDiffers);
      expect(run(const ImportMatching(amountDriftPercent: 5)), isEmpty);
      expect(run(const ImportMatching(minSimilarityPercent: 100))['t'], isNotNull);
    });

    test('a sessão carrega as janelas e busca ciclos pela janela da casa', () {
      const schedule = CycleSchedule(1);
      final base = ImportSession.start(
        source: _card,
        fileName: 'f.csv',
        lines: [_line('l', DateTime(2026, 11, 5), 'X', 100)],
        payerMemberId: 'kelvynn',
      );
      // Com 3 dias, 05/11 só toca o ciclo de novembro (mais o do vencimento);
      // com 10, a janela chega a outubro
      expect(base.cyclesToSearch(schedule).length, 2);
      final wide = base.withParams(matching: const ImportMatching(dateWindowDays: 10));
      expect(wide.matching.dateWindowDays, 10);
      expect(wide.cyclesToSearch(schedule).length, 3);
    });
  });

  group('Destino padrão das linhas novas', () {
    test('sem nada gravado vale o de sempre', () {
      expect(ImportDefaults.fromJson(null), const ImportDefaults());
      expect(ImportDefaults.fromJson({'category_id': 'nao-uuid', 'split_mode': 'x'}), const ImportDefaults());
      expect(const ImportDefaults().toJson(), isEmpty);
      expect(HouseSettings.fromJson({}).importDefaults.isEmpty, isTrue);
    });

    test('lê e escreve só o que foi escolhido', () {
      const defaults = ImportDefaults(categoryId: _uuidA, splitMode: ImportSplitMode.equal, paymentMethodId: _uuidB);
      expect(ImportDefaults.fromJson(defaults.toJson()), defaults);
      expect(defaults.toJson(), {'category_id': _uuidA, 'split_mode': 'equal', 'payment_method_id': _uuidB});
      expect(defaults.isValid, isTrue);
      expect(const ImportDefaults(categoryId: 'x').isValid, isFalse);
    });

    ImportSession session(ImportDefaults defaults) => ImportSession.start(
          source: _card,
          fileName: 'f.csv',
          lines: [_line('a', DateTime(2026, 10, 3), 'COMPRA QUALQUER', 5000)],
          payerMemberId: 'kelvynn',
          defaults: defaults,
        ).withInvoiceDueDate(DateTime(2026, 11, 10));

    ImportPlan plan(ImportSession s) => s.buildPlan(
          members: _members,
          categories: _categories,
          schedule: const CycleSchedule(1),
          now: DateTime(2026, 10, 17),
          newId: () => 'id',
        );

    test('categoria padrão: vale para a linha sem sugestão; escolha da linha vence', () {
      var s = session(const ImportDefaults(categoryId: 'cat_lazer'))
          .withSuggestedCategories(categories: _categories, history: const []);
      expect(s.lines.single.categoryId, 'cat_lazer');
      expect(plan(s).newExpenses.single.categoryId, 'cat_lazer');

      s = s.withLine(s.lines.single.copyWith(categoryId: 'cat_mercado'));
      expect(plan(s).newExpenses.single.categoryId, 'cat_mercado');
    });

    test('categoria padrão que não existe mais é ignorada', () {
      final s = session(const ImportDefaults(categoryId: 'sumiu'))
          .withSuggestedCategories(categories: _categories, history: const []);
      expect(s.lines.single.categoryId, isNull);
      expect(plan(s).newExpenses.single.categoryId, 'cat_mercado');
    });

    test('divisão: padrão da casa, partes iguais ou só quem paga; dono da categoria vence', () {
      expect(plan(session(const ImportDefaults())).newExpenses.single.splitRule.percentages,
          {'kelvynn': 60.0, 'cristiano': 40.0});
      expect(
          plan(session(const ImportDefaults(splitMode: ImportSplitMode.equal))).newExpenses.single.splitRule.percentages,
          {'kelvynn': 50.0, 'cristiano': 50.0});
      expect(
          plan(session(const ImportDefaults(splitMode: ImportSplitMode.payer))).newExpenses.single.splitRule,
          const SplitRule.singleResponsible('kelvynn'));

      final owned = session(const ImportDefaults(splitMode: ImportSplitMode.equal));
      final withOwner = owned.withLine(owned.lines.single.copyWith(categoryId: 'cat_carro'));
      expect(plan(withOwner).newExpenses.single.splitRule, const SplitRule.singleResponsible('cristiano'));
    });
  });

  group('Quem costuma pagar a fatura', () {
    const pixKelvynn = PaymentMethod(id: 'pm_pix_k', name: 'Pix K', type: PaymentMethodType.pix, ownerMemberId: 'kelvynn');
    const caixa = PaymentMethod(id: 'pm_caixa', name: 'Caixa', type: PaymentMethodType.account);

    test('o cartão guarda a sugestão e ela some ao limpar', () {
      final withPayer = _card.copyWith(usualInvoicePayerId: 'cristiano');
      expect(withPayer.usualInvoicePayerId, 'cristiano');
      expect(withPayer == _card, isFalse);
      expect(withPayer.copyWith(name: 'Outro').usualInvoicePayerId, 'cristiano');
      expect(withPayer.copyWith(clearUsualInvoicePayer: true).usualInvoicePayerId, isNull);
    });

    test('sem sugestão a ordem é a de sempre; com ela, os meios dele vão na frente', () {
      final base = invoicePaymentOptions(_card, [caixa, pixKelvynn]);
      expect(base.map((o) => o.key), ['pm_pix_k', 'pm_caixa']);
      expect(invoicePaymentOptions(_card, [caixa, pixKelvynn], usualPayerId: 'kelvynn').map((o) => o.key), base.map((o) => o.key));
      // Outro morador sem meio próprio: nada muda
      expect(invoicePaymentOptions(_card, [caixa, pixKelvynn], usualPayerId: 'cristiano').map((o) => o.key),
          base.map((o) => o.key));
    });

    test('cartão da casa pago por morador específico: só reordena o que ele tem', () {
      const houseCard = PaymentMethod(id: 'pm_h', name: 'Casa', type: PaymentMethodType.card, closingDay: 1, dueDay: 8);
      const pixCasa = PaymentMethod(id: 'pm_pix', name: 'Pix', type: PaymentMethodType.pix);
      final options = invoicePaymentOptions(houseCard, [caixa, pixCasa, pixKelvynn], usualPayerId: 'kelvynn');
      expect(options.map((o) => o.key), ['pm_caixa', 'pm_pix']);
    });

    test('o modo demo grava e limpa a sugestão', () async {
      final ds = MockFinanceDataSource();
      await ds.addPaymentMethod(_card.copyWith(id: 'pm_novo', usualInvoicePayerId: 'cristiano'));
      final saved = (await ds.getPaymentMethods()).firstWhere((p) => p.id == 'pm_novo');
      expect(saved.usualInvoicePayerId, 'cristiano');
      await ds.updatePaymentMethod(saved.copyWith(clearUsualInvoicePayer: true));
      expect((await ds.getPaymentMethods()).firstWhere((p) => p.id == 'pm_novo').usualInvoicePayerId, isNull);
    });
  });

  test('modo demo grava os parâmetros da casa', () async {
    final ds = MockFinanceDataSource();
    final saved = await ds.updateHouseSettings({
      'import_matching': const ImportMatching(dateWindowDays: 6).toJson(),
      'import_defaults': const ImportDefaults(splitMode: ImportSplitMode.payer).toJson(),
    });
    expect(saved.importMatching.dateWindowDays, 6);
    expect(saved.importDefaults.splitMode, ImportSplitMode.payer);
    expect((await ds.getHouseSettings()).importMatching.dateWindowDays, 6);
  });

  group('Migration 0100', () {
    final sql = File('supabase/migrations/20261018200000_0100_card_import_params.sql').readAsStringSync();

    test('segue o estilo: create or replace trigger, sem drop trigger', () {
      expect(sql, contains('create or replace trigger trg_payment_methods_check_usual_payer'));
      expect(sql.toLowerCase(), isNot(contains('drop trigger')));
    });

    test('colunas e validações', () {
      expect(sql, contains('usual_invoice_payer uuid references auth.users(id) on delete set null'));
      expect(sql, contains('import_matching_valid'));
      expect(sql, contains('import_defaults_valid'));
      expect(sql, contains("add column if not exists import_matching jsonb not null default '{}'::jsonb"));
      expect(sql, contains("add column if not exists import_defaults jsonb not null default '{}'::jsonb"));
    });

    test('update_house_settings mantém os campos anteriores e restringe os novos a administradores', () {
      for (final field in [
        'opening_balance_rule',
        'opening_inflow_rules',
        'closing_defaults',
        'new_member_split_policy',
        'folego_params',
        'budget_alert_stages',
        'planner_history_cycles',
        'planner_mode',
        'planner_adjust_percent',
        'planner_category_overrides',
      ]) {
        expect(sql, contains("'$field'"), reason: field);
      }
      expect(sql, contains("p_settings ? 'import_matching' and not public.is_house_admin(p_house_id)"));
      expect(sql, contains("p_settings ? 'import_defaults' and not public.is_house_admin(p_house_id)"));
    });
  });
}
