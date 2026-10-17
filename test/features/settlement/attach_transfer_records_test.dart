import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/settlement/data/datasources/supabase_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';

SuperPixTransfer _transfer(String id, String from, String to, int cents) => SuperPixTransfer(
      id: id,
      fromMemberId: from,
      fromMemberName: from,
      toMemberId: to,
      toMemberName: to,
      amount: Money(cents),
      description: 'Compensação do Ciclo',
    );

void main() {
  test('Liga cada transferência do retrato à linha gravada, das mais novas para as mais antigas', () {
    final transfers = [
      _transfer('calc_1', 'ana', 'bia', 42000),
      _transfer('calc_2', 'caio', 'bia', 1000),
      _transfer('calc_3', 'caixa', 'ana', 500),
    ];
    final rows = [
      {
        'id': 'row_old',
        'from_member_id': 'ana',
        'to_member_id': 'bia',
        'amount_cents': 42000,
        'created_at': '2026-10-01T10:00:00Z',
        'pix_sent_at': '2026-10-02T10:00:00Z',
      },
      {
        'id': 'row_new',
        'from_member_id': 'ana',
        'to_member_id': 'bia',
        'amount_cents': 42000,
        'created_at': '2026-10-10T10:00:00Z',
        'pix_sent_at': null,
      },
      {
        'id': 'row_caio',
        'from_member_id': 'caio',
        'to_member_id': 'bia',
        'amount_cents': 1000,
        'created_at': '2026-10-10T10:00:00Z',
        'pix_sent_at': '2026-10-11T12:00:00Z',
      },
    ];

    final result = attachTransferRecords(transfers, rows);

    expect(result[0].recordId, 'row_new');
    expect(result[0].pixSentAt, isNull);
    expect(result[1].recordId, 'row_caio');
    expect(result[1].pixSentAt, isNotNull);
    // Transferência do Caixa não tem linha: fica sem marca
    expect(result[2].recordId, isNull);
  });
}
