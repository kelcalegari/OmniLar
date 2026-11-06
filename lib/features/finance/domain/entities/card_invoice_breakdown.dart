import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

/// Para onde foi uma compra da fatura importada.
enum InvoicePartKind {
  /// Virou (ou já era) despesa da Casa.
  house,

  /// Virou empréstimo para um morador.
  loan,

  /// Gasto pessoal do dono do cartão.
  personal,

  /// Pago por quem não mora na casa.
  thirdParty,

  /// Ignorada na revisão.
  ignored,

  /// Ficou de fora por cair em ciclo fechado.
  skipped,
}

/// Uma compra (ou estorno) de uma importação confirmada da fatura.
class InvoiceFileLine extends Equatable {
  final Money amount;

  /// Estorno ou crédito: abate do total.
  final bool isRefund;
  final InvoicePartKind kind;

  /// Devedor do empréstimo ou dono do gasto pessoal.
  final String? memberId;

  /// Identifica a linha entre importações da mesma fatura.
  final String? signature;

  /// Despesa da Casa que a linha criou ou casou.
  final String? expenseId;

  const InvoiceFileLine({
    required this.amount,
    required this.kind,
    this.isRefund = false,
    this.memberId,
    this.signature,
    this.expenseId,
  });

  @override
  List<Object?> get props => [amount, isRefund, kind, memberId, signature, expenseId];
}

/// Uma parte da fatura inteira: Casa, empréstimo de alguém, pessoal...
class InvoicePart extends Equatable {
  final InvoicePartKind? kind;

  /// Morador da parte (empréstimo ou pessoal).
  final String? memberId;
  final Money amount;
  final int count;

  /// Compras da Casa lançadas no app que não estão em nenhum arquivo.
  final bool outsideFile;

  /// Estornos e créditos da fatura (valor negativo).
  bool get isRefunds => kind == null && !outsideFile;

  const InvoicePart({
    required this.kind,
    required this.amount,
    required this.count,
    this.memberId,
    this.outsideFile = false,
  });

  @override
  List<Object?> get props => [kind, memberId, amount, count, outsideFile];
}

/// A fatura inteira de um cartão em um vencimento, somando o que foi para a
/// Casa e o que foi para cada morador, para conferir com o valor do banco.
///
/// Sem importação, só se conhece a parte da Casa lançada no app.
class CardInvoiceBreakdown extends Equatable {
  /// Linhas das importações confirmadas da fatura, sem repetir.
  final List<InvoiceFileLine> lines;

  /// Compras da Casa no app nessa fatura: id e valor.
  final Map<String, Money> houseExpenses;

  CardInvoiceBreakdown({required Iterable<InvoiceFileLine> lines, required this.houseExpenses})
    : lines = _dedupe(lines);

  /// A mesma compra em duas importações (prévia e fatura fechada) conta uma vez.
  static List<InvoiceFileLine> _dedupe(Iterable<InvoiceFileLine> lines) {
    final seen = <String>{};
    return [
      for (final line in lines)
        if (line.signature == null || seen.add('${line.isRefund}|${line.signature}')) line,
    ];
  }

  bool get hasImport => lines.isNotEmpty;

  /// Compras da Casa lançadas no app que nenhuma linha importada criou ou casou.
  Map<String, Money> get houseOutsideFile {
    final linked = {for (final line in lines) ?line.expenseId};
    return {
      for (final entry in houseExpenses.entries)
        if (!linked.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Soma das compras da Casa no app.
  Money get houseInApp => _sum(houseExpenses.values);

  static Money _sum(Iterable<Money> values) => Money(values.fold<int>(0, (acc, m) => acc + m.cents));

  /// Total do arquivo: compras menos estornos.
  Money get fileTotal =>
      Money(lines.fold<int>(0, (acc, line) => acc + (line.isRefund ? -line.amount.cents : line.amount.cents)));

  /// Fatura inteira: o arquivo mais as compras da Casa lançadas só no app.
  /// Sem importação, é a parte da Casa.
  Money get total => fileTotal + _sum(houseOutsideFile.values);

  /// As partes, na ordem de mostrar: Casa, empréstimos, pessoal, terceiros,
  /// ignorado, fora por ciclo fechado, estornos e Casa fora do arquivo.
  List<InvoicePart> get parts {
    final grouped = <(InvoicePartKind, String?), ({int cents, int count})>{};
    var refunds = 0;
    var refundCount = 0;
    for (final line in lines) {
      if (line.isRefund) {
        refunds += line.amount.cents;
        refundCount++;
        continue;
      }
      final member = line.kind == InvoicePartKind.loan || line.kind == InvoicePartKind.personal ? line.memberId : null;
      final key = (line.kind, member);
      final current = grouped[key] ?? (cents: 0, count: 0);
      grouped[key] = (cents: current.cents + line.amount.cents, count: current.count + 1);
    }

    final ordered = grouped.entries.toList()
      ..sort((a, b) {
        final byKind = a.key.$1.index.compareTo(b.key.$1.index);
        return byKind != 0 ? byKind : b.value.cents.compareTo(a.value.cents);
      });
    final outside = houseOutsideFile;
    return [
      for (final entry in ordered)
        InvoicePart(
          kind: entry.key.$1,
          memberId: entry.key.$2,
          amount: Money(entry.value.cents),
          count: entry.value.count,
        ),
      if (refundCount > 0) InvoicePart(kind: null, amount: Money(-refunds), count: refundCount),
      if (outside.isNotEmpty)
        InvoicePart(
          kind: InvoicePartKind.house,
          amount: _sum(outside.values),
          count: outside.length,
          outsideFile: true,
        ),
    ];
  }

  /// Diferença entre o valor que o banco cobra e a fatura do app
  /// (positiva: o banco cobra mais).
  Money differenceFrom(Money bankAmount) => bankAmount - total;

  @override
  List<Object?> get props => [lines, houseExpenses];
}
