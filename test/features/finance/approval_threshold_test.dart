import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';

void main() {
  group('Limite de aprovação da casa', () {
    test('sem limite nada pede aprovação (comportamento atual)', () {
      const s = HouseSettings();
      expect(s.approvalThresholdCents, isNull);
      expect(s.requiresApproval(100000000), isFalse);
      expect(HouseSettings.fromJson({}).approvalThresholdCents, isNull);
      expect(HouseSettings.fromJson({'approval_threshold_cents': 0}).approvalThresholdCents, isNull);
    });

    test('só passa do limite quem é maior que ele', () {
      final s = HouseSettings.fromJson({'approval_threshold_cents': 50000});
      expect(s.requiresApproval(50000), isFalse);
      expect(s.requiresApproval(50001), isTrue);
      expect(s.copyWith(clearApprovalThreshold: true).approvalThresholdCents, isNull);
      expect(HouseSettings.columns, contains('approval_threshold_cents'));
      expect(HouseSettings.columnsBefore0104, isNot(contains('approval_threshold_cents')));
    });
  });

  group('Empréstimo aguardando aprovação', () {
    P2PLoan loan({bool waiting = false}) => P2PLoan(
          id: 'l1',
          title: 'Reforma',
          totalAmount: const Money(90000),
          lenderMemberId: 'a',
          borrowerMemberId: 'b',
          installmentsCount: 1,
          createdAt: DateTime(2026, 10, 1),
          firstDueDate: DateTime(2026, 10, 20),
          awaitingApproval: waiting,
        );

    test('fica fora do fechamento até a aprovação', () {
      expect(loan().entersCycleSettlement, isTrue);
      expect(loan(waiting: true).entersCycleSettlement, isFalse);
      expect(loan(waiting: true).copyWith(awaitingApproval: false).entersCycleSettlement, isTrue);
    });

    test('mock: aprovar libera e recusar cancela', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(loan(waiting: true));
      await ds.decideLoanApproval('l1', approve: true);
      expect((await ds.getLoans()).firstWhere((l) => l.id == 'l1').awaitingApproval, isFalse);
      await ds.deleteLoan('l1');

      await ds.createLoan(loan(waiting: true));
      await ds.decideLoanApproval('l1', approve: false);
      expect((await ds.getLoans()).where((l) => l.id == 'l1'), isEmpty);
    });
  });

  group('Migration 0104 (aprovação)', () {
    final sql = File('supabase/migrations/20261018240000_0104_card_cycle_approval_tasks.sql').readAsStringSync();

    test('coluna, gatilho no modelo da 0082 e RPC com a permissão', () {
      expect(sql, contains('add column if not exists approval_threshold_cents bigint'));
      expect(sql, contains('awaiting_approval boolean not null default false'));
      expect(sql, contains("current_user = 'authenticated'"));
      expect(sql, contains('create or replace trigger trg_guard_p2p_loan_approval'));
      expect(sql, contains("public.has_house_permission(v_loan.house_id, 'editar_configuracoes')"));
    });

    test('update_house_settings mantém todos os campos da 0103, inclusive permissions', () {
      final base = File('supabase/migrations/20261018230000_0103_house_permissions.sql').readAsStringSync();
      final returned = RegExp(r"'(\w+)', v_row\.\w+").allMatches(base).map((m) => m.group(1)!).toSet();
      expect(returned, contains('permissions'));
      for (final key in returned) {
        expect(sql, contains("'$key', v_row."), reason: key);
      }
      expect(sql, contains("'approval_threshold_cents', v_row.approval_threshold_cents"));
      expect(sql, contains("permissions = coalesce(p_settings->'permissions', permissions)"));
    });
  });
}
