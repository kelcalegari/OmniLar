import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../entities/cycle_preview.dart';
import '../entities/payment_due_entry.dart';

/// Relatório do ciclo em CSV para planilha (Excel, Google Sheets): ponto e
/// vírgula como separador, vírgula decimal e BOM UTF-8 para os acentos.
class CycleReportCsv {
  const CycleReportCsv();

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _money(Money m) =>
      (m.cents / 100.0).toStringAsFixed(2).replaceAll('.', ',');

  /// Texto entre aspas, com as aspas internas dobradas.
  static String _text(String value) => '"${value.replaceAll('"', '""')}"';

  /// Nome do arquivo: o início do ciclo, para ordenar por data.
  static String fileNameFor(FinancialCycle cycle) {
    final s = cycle.startDate;
    return 'omnilar_ciclo_${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}.csv';
  }

  String build({
    required FinancialCycle cycle,
    required List<HouseExpense> expenses,
    required List<ExpenseCategory> categories,
    required List<HouseMember> members,
    CyclePreview? preview,
    PaymentCalendar? calendar,
  }) {
    final b = StringBuffer();
    b.write('﻿');
    b.writeln('RELATÓRIO DO CICLO — OMNI LAR');
    b.writeln('Período;${_date(cycle.startDate)} até ${_date(cycle.endDate)}');
    b.writeln('');

    final categoryNames = {for (final c in categories) c.id: c.name};
    final memberNames = {for (final m in members) m.id: m.name};

    b.writeln('DESPESAS');
    b.writeln('Data;Descrição;Categoria;Valor (R\$);Quem pagou;Status;Tipo');
    for (final e in expenses) {
      final payer = e.isPending
          ? 'Em aberto'
          : (e.paidOutOfPocket
                ? (memberNames[e.paidByMemberId] ?? 'Membro')
                : 'Caixa da Casa');
      final kind = e.isRecurring
          ? (e.isVariable ? 'Recorrente variável' : 'Recorrente fixa')
          : 'Avulsa';
      b.writeln(
        [
          _date(e.date),
          _text(e.title),
          _text(categoryNames[e.categoryId] ?? 'Geral'),
          _money(e.amount),
          _text(payer),
          e.isPending ? 'Pendente' : 'Paga',
          kind,
        ].join(';'),
      );
    }

    // Totais das próprias linhas acima, para o arquivo fechar com ele mesmo
    final paid = expenses
        .where((e) => !e.isPending)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    final pending = expenses
        .where((e) => e.isPending)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    b.writeln('');
    b.writeln('RESUMO');
    b.writeln('Total pago (R\$);${_money(Money(paid))}');
    b.writeln('Total pendente (R\$);${_money(Money(pending))}');
    b.writeln('Total do ciclo (R\$);${_money(Money(paid + pending))}');

    if (preview != null && preview.members.isNotEmpty) {
      b.writeln('');
      b.writeln(
        preview.isSettled
            ? 'FECHAMENTO${preview.settledAt != null ? ' (fechado em ${_date(preview.settledAt!)})' : ''}'
            : 'PRÉVIA DO FECHAMENTO (o mesmo cálculo do Hub de Liquidação, sem as escolhas feitas lá)',
      );
      b.writeln(
        'Morador;Aporte do ciclo;Já aportado;Pagou do bolso;Sobra devolvida;Parcelas a pagar;Parcelas a receber;Saldo (positivo recebe, negativo paga)',
      );
      for (final m in preview.members) {
        b.writeln(
          [
            _text(m.memberName),
            _money(m.contributionDue),
            _money(m.contributionPaid),
            _money(m.outOfPocket),
            _money(m.contributionRefund),
            _money(m.p2pToPay),
            _money(m.p2pToReceive),
            _money(m.net),
          ].join(';'),
        );
      }
      final transfers = {
        for (final m in preview.members) ...{
          for (final t in m.transfersOut) t.id: t,
        },
        for (final m in preview.members) ...{
          for (final t in m.transfersIn) t.id: t,
        },
      }.values;
      if (transfers.isNotEmpty) {
        b.writeln('');
        b.writeln('Transferências do fechamento');
        b.writeln('De;Para;Valor (R\$)');
        for (final t in transfers) {
          b.writeln(
            [
              _text(t.fromMemberName),
              _text(t.toMemberName),
              _money(t.amount),
            ].join(';'),
          );
        }
      }
    }

    if (calendar != null && calendar.entries.isNotEmpty) {
      b.writeln('');
      b.writeln('PRÓXIMOS PAGAMENTOS');
      b.writeln(
        'Data;Descrição;Quem paga;Para quem;Valor (R\$);Situação;Código',
      );
      for (final e in calendar.entries) {
        final status = [
          if (e.isOverdue) 'Atrasado',
          if (e.kind == PaymentDueKind.installment) 'Fora do fechamento',
          if (e.reimbursedAtClosing) 'Volta no fechamento',
          if (e.date == null) 'Sem prazo',
        ].join(', ');
        b.writeln(
          [
            e.date == null ? '' : _date(e.date!),
            _text(e.title),
            _text(e.payerName),
            _text(e.receiverName ?? ''),
            _money(e.amount),
            _text(status),
            _text(e.barcode ?? ''),
          ].join(';'),
        );
      }
    }
    return b.toString();
  }
}
