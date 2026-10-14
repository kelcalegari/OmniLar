import '../../../finance/domain/entities/house_expense.dart';
import '../entities/imported_statement_line.dart';
import 'statement_text.dart';

/// O quanto uma linha do arquivo se parece com uma despesa já lançada no app.
enum LineMatchKind {
  /// Mesmo valor, mesmo cartão/conta e data próxima: é o mesmo lançamento.
  alreadyLaunched,

  /// Mesmo valor e data próxima, mas lançado em outra forma de pagamento ou
  /// ainda como conta pendente: o usuário confirma.
  probable,

  /// Mesmo lugar e mesma data, com valor um pouco diferente (gorjeta, taxa).
  amountDiffers,
}

class LineMatch {
  final String lineId;
  final HouseExpense expense;
  final LineMatchKind kind;
  final int score;

  const LineMatch({
    required this.lineId,
    required this.expense,
    required this.kind,
    required this.score,
  });
}

/// Casa as linhas de uma fatura ou extrato com as despesas que já existem,
/// para a importação não lançar de novo o que foi digitado no app.
class StatementMatcher {
  const StatementMatcher._();

  /// A fatura costuma registrar a compra um ou dois dias depois.
  static const int dateWindowDays = 3;
  static const int otherMethodWindowDays = 2;
  static const double _maxAmountDrift = 0.25;
  static const double _minSimilarityForDrift = 0.5;

  static int _daysApart(DateTime a, DateTime b) =>
      DateTime(a.year, a.month, a.day).difference(DateTime(b.year, b.month, b.day)).inDays.abs();

  /// Menor distância entre a linha e as datas que identificam a despesa: a do
  /// lançamento e, para conta pendente, a do vencimento.
  static int _distance(ImportedStatementLine line, HouseExpense expense) {
    final byDate = _daysApart(line.date, expense.date);
    if (!expense.isPending) return byDate;
    final byDue = _daysApart(line.date, expense.effectiveDueDate);
    return byDue < byDate ? byDue : byDate;
  }

  static LineMatch? _evaluate(
    ImportedStatementLine line,
    HouseExpense expense,
    String paymentMethodId,
    bool pendingCountsAsLaunched,
  ) {
    final days = _distance(line, expense);
    if (days > dateWindowDays) return null;

    final sameMethod = expense.paymentMethodId == paymentMethodId;
    final sameAmount = expense.amount.cents == line.amount.cents;
    final similarity = StatementText.similarity(line.description, expense.title);
    // Compra no cartão fica pendente até a fatura ser paga: no mesmo cartão,
    // pendente também é "já lançada"
    final launched = expense.isPaid || (sameMethod && pendingCountsAsLaunched);
    final closeness = (dateWindowDays - days) * 10 + (similarity * 20).round();

    if (sameAmount && sameMethod && launched) {
      return LineMatch(
        lineId: line.id,
        expense: expense,
        kind: LineMatchKind.alreadyLaunched,
        score: 300 + closeness,
      );
    }

    if (sameAmount && days <= otherMethodWindowDays) {
      return LineMatch(
        lineId: line.id,
        expense: expense,
        kind: LineMatchKind.probable,
        score: 200 + closeness,
      );
    }

    if (!sameAmount && sameMethod && launched && days <= 1) {
      final larger = expense.amount.cents > line.amount.cents ? expense.amount.cents : line.amount.cents;
      final drift = (expense.amount.cents - line.amount.cents).abs() / larger;
      if (drift <= _maxAmountDrift && similarity >= _minSimilarityForDrift) {
        return LineMatch(
          lineId: line.id,
          expense: expense,
          kind: LineMatchKind.amountDiffers,
          score: 100 + closeness,
        );
      }
    }

    return null;
  }

  /// Melhor despesa para cada linha, por id da linha. Cada despesa casa com no
  /// máximo uma linha, então duas compras iguais no mesmo dia não se confundem.
  static Map<String, LineMatch> match({
    required List<ImportedStatementLine> lines,
    required List<HouseExpense> expenses,
    required String paymentMethodId,
    bool pendingCountsAsLaunched = false,
  }) {
    final candidates = <LineMatch>[];
    for (final line in lines) {
      if (!line.isPurchase) continue;
      for (final expense in expenses) {
        if (expense.isProjectExpense) continue;
        final match = _evaluate(line, expense, paymentMethodId, pendingCountsAsLaunched);
        if (match != null) candidates.add(match);
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final result = <String, LineMatch>{};
    final usedExpenses = <String>{};
    for (final candidate in candidates) {
      if (result.containsKey(candidate.lineId) || usedExpenses.contains(candidate.expense.id)) {
        continue;
      }
      result[candidate.lineId] = candidate;
      usedExpenses.add(candidate.expense.id);
    }
    return result;
  }
}
