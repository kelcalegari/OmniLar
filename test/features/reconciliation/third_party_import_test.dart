import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/reconciliation/data/supabase_import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_extras.dart';

const _members = [
  HouseMember(id: '33333333-3333-4333-8333-333333333333', name: 'Kelvynn', defaultSplitPercent: 60),
  HouseMember(id: '44444444-4444-4444-8444-444444444444', name: 'Cristiano', defaultSplitPercent: 40),
];

// Cartão do Cristiano, que comprou as marmitas
const _card = PaymentMethod(
  id: '22222222-2222-4222-8222-222222222222',
  name: 'Nubank Cristiano',
  type: PaymentMethodType.card,
  ownerMemberId: '44444444-4444-4444-8444-444444444444',
  closingDay: 28,
  dueDay: 10,
);

const _houseAccount = PaymentMethod(id: 'pm_casa', name: 'Conta da Casa', type: PaymentMethodType.account);
const _memberAccount = PaymentMethod(
  id: 'pm_conta_kel',
  name: 'Conta Kelvynn',
  type: PaymentMethodType.account,
  ownerMemberId: '33333333-3333-4333-8333-333333333333',
);

final _vaults = [
  SavingsVault(id: 'vault_repasses', name: 'Repasses', targetAmount: const Money.zero(), createdAt: DateTime(2026, 10)),
  SavingsVault(id: 'vault_reserva', name: 'Reserva', targetAmount: const Money.zero(), createdAt: DateTime(2026, 10)),
];

ImportedStatementLine _line(String id, String description, int cents, {StatementLineKind kind = StatementLineKind.purchase}) =>
    ImportedStatementLine(
      id: id,
      date: DateTime(2026, 10, 17),
      description: description,
      amount: Money(cents),
      kind: kind,
      destination: kind == StatementLineKind.purchase ? LineDestination.house : LineDestination.ignored,
    );

void main() {
  const schedule = CycleSchedule(1);

  group('Fatura com parte paga por terceiros', () {
    // R$ 192 de marmitas: R$ 32 do Cristiano e R$ 160 de quem não mora na casa
    ImportSession marmitas() {
      final session = ImportSession.start(
        source: _card,
        fileName: 'fatura.csv',
        lines: [_line('marmitas', 'MARMITARIA DA ESQUINA', 19200)],
        payerMemberId: _card.ownerMemberId!,
      ).withInvoiceDueDate(DateTime(2026, 11, 10)).splitLine('marmitas', const Money(3200));
      final parts = session.lines;
      return session
          .withLine(parts[0].copyWith(destination: LineDestination.cardOwnerPersonal))
          .withLine(parts[1].copyWith(destination: LineDestination.thirdParty));
    }

    test('A parte de terceiros não vira despesa nem empréstimo e fica no histórico', () {
      final session = marmitas();
      final plan = session.buildPlan(members: _members, categories: const [], schedule: schedule);

      expect(plan.newExpenses, isEmpty);
      expect(plan.loans, isEmpty);
      expect(session.blockers, isEmpty);
      final records = plan.lineRecords.where((r) => r.line.destination == LineDestination.thirdParty);
      expect(records.single.outcome, LineOutcome.ignored);
      expect(records.single.line.amount.cents, 16000);
    });

    test('Os totais mostram a parte paga por terceiros à parte', () {
      final totals = marmitas().totals;

      expect(totals.file.cents, 19200);
      expect(totals.personal.cents, 3200);
      expect(totals.thirdParty.cents, 16000);
      expect(totals.house.cents, 0);
    });

    test('"Pago por terceiros" não vira regra para a próxima fatura', () {
      final session = ImportSession.start(
        source: _card,
        fileName: 'fatura.csv',
        lines: [_line('marmitas', 'MARMITARIA DA ESQUINA', 16000)],
        payerMemberId: _card.ownerMemberId!,
      );
      final marked = session.withLine(session.lines.single.copyWith(destination: LineDestination.thirdParty));

      expect(marked.rulesToLearn(), isEmpty);
    });

    test('No banco, a linha vai como third_party', () {
      final session = marmitas();
      final plan = session.buildPlan(members: _members, categories: const [], schedule: schedule);
      final payload = importPayload(
        session,
        plan,
        houseId: '11111111-1111-4111-8111-111111111111',
        currentUserId: _members[0].id,
      );

      final destinations = [for (final row in payload['lines'] as List) (row as Map)['split_destination']];
      expect(destinations, containsAll(['personal', 'third_party']));
    });
  });

  group('Pix de terceiros no extrato da conta', () {
    final lines = [_line('pix', 'PIX RECEBIDO JOAO DA SILVA', 16000, kind: StatementLineKind.income)];

    Map<String, List<ExtraAction>> options(PaymentMethod source) => StatementExtras.optionsFor(
          lines: lines,
          source: source,
          payerMemberId: _members[0].id,
          members: _members,
          cards: const [_card],
          openInvoices: const [],
          history: const [],
          loans: const [],
          vaults: _vaults,
        );

    test('Na conta da Casa, a entrada pode ser guardada como repasse em cada caixinha', () {
      final repasses = options(_houseAccount)['pix']!
          .where((o) => o.type == ExtraActionType.thirdPartyReceipt)
          .toList();

      expect(repasses.map((o) => o.vaultId), ['vault_repasses', 'vault_reserva']);
      expect(repasses.first.label, 'Repasse de terceiros (guardar em Repasses)');
      expect(repasses.any((o) => o.suggested), isFalse, reason: 'o app não adivinha que é de terceiros');
    });

    test('Na conta de um morador, não há repasse para a Casa', () {
      final found = options(_memberAccount)['pix'] ?? const <ExtraAction>[];

      expect(found.any((o) => o.type == ExtraActionType.thirdPartyReceipt), isFalse);
    });
  });
}
