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

/// Partes que não são uma linha comum do arquivo.
enum InvoicePartExtra {
  /// Estornos e créditos aplicados a compras (valor negativo).
  refunds,

  /// Créditos que a importação ignorou: ficam fora do total (o pagamento da
  /// fatura anterior às vezes chega assim).
  ignoredCredits,

  /// Compras do arquivo que a importação não lançou nem registrou (deu como
  /// já importadas): estão no total do arquivo, mas não no app.
  notLaunched,

  /// Compras da Casa lançadas no app que não estão em nenhum arquivo.
  outsideFile,
}

/// Uma parte da fatura inteira: Casa, empréstimo de alguém, pessoal...
class InvoicePart extends Equatable {
  /// Para onde foram as compras; null nas partes de [extra].
  final InvoicePartKind? kind;
  final InvoicePartExtra? extra;

  /// Morador da parte (empréstimo ou pessoal).
  final String? memberId;
  final Money amount;
  final int count;

  /// Entra no total da fatura.
  bool get counted => extra != InvoicePartExtra.ignoredCredits;

  /// Pede atenção: o app e o arquivo não concordam aqui.
  bool get needsAttention => extra == InvoicePartExtra.outsideFile || extra == InvoicePartExtra.notLaunched;

  const InvoicePart({required this.amount, required this.count, this.kind, this.extra, this.memberId});

  @override
  List<Object?> get props => [kind, extra, memberId, amount, count];
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

  /// Soma das compras do arquivo mais completo importado para a fatura (o
  /// total que a importação mostrou), para achar compras que ficaram sem linha.
  final Money? importedFileTotal;

  CardInvoiceBreakdown({required Iterable<InvoiceFileLine> lines, required this.houseExpenses, this.importedFileTotal})
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

  /// Compras com linha registrada.
  Money get _purchases => _sum([
    for (final line in lines)
      if (!line.isRefund) line.amount,
  ]);

  /// Créditos aplicados a compras; os ignorados ficam fora.
  Iterable<InvoiceFileLine> get _appliedRefunds =>
      lines.where((line) => line.isRefund && line.kind != InvoicePartKind.ignored);

  /// Compras do arquivo que ficaram sem linha registrada.
  Money get notLaunched {
    final file = importedFileTotal;
    if (file == null) return const Money.zero();
    final missing = file - _purchases;
    return missing.isPositive ? missing : const Money.zero();
  }

  /// Total do arquivo: compras (com as que ficaram sem linha) menos créditos aplicados.
  Money get fileTotal => _purchases + notLaunched - _sum(_appliedRefunds.map((l) => l.amount));

  /// Fatura inteira: o arquivo mais as compras da Casa lançadas só no app.
  /// Sem importação, é a parte da Casa.
  Money get total => fileTotal + _sum(houseOutsideFile.values);

  /// As partes, na ordem de mostrar: Casa, empréstimos, pessoal, terceiros,
  /// ignorado, fora por ciclo fechado, e depois as de [InvoicePartExtra].
  List<InvoicePart> get parts {
    final grouped = <(InvoicePartKind, String?), ({int cents, int count})>{};
    for (final line in lines) {
      if (line.isRefund) continue;
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
    final applied = _appliedRefunds.toList();
    final ignored = lines.where((line) => line.isRefund && line.kind == InvoicePartKind.ignored).toList();
    final outside = houseOutsideFile;
    return [
      for (final entry in ordered)
        InvoicePart(
          kind: entry.key.$1,
          memberId: entry.key.$2,
          amount: Money(entry.value.cents),
          count: entry.value.count,
        ),
      if (!notLaunched.isZero) InvoicePart(extra: InvoicePartExtra.notLaunched, amount: notLaunched, count: 0),
      if (applied.isNotEmpty)
        InvoicePart(
          extra: InvoicePartExtra.refunds,
          amount: -_sum(applied.map((l) => l.amount)),
          count: applied.length,
        ),
      if (outside.isNotEmpty)
        InvoicePart(extra: InvoicePartExtra.outsideFile, amount: _sum(outside.values), count: outside.length),
      if (ignored.isNotEmpty)
        InvoicePart(
          extra: InvoicePartExtra.ignoredCredits,
          amount: -_sum(ignored.map((l) => l.amount)),
          count: ignored.length,
        ),
    ];
  }

  /// Diferença entre o valor que o banco cobra e a fatura do app
  /// (positiva: o banco cobra mais).
  Money differenceFrom(Money bankAmount) => bankAmount - total;

  @override
  List<Object?> get props => [lines, houseExpenses, importedFileTotal];
}
