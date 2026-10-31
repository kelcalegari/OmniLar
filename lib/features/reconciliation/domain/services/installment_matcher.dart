import '../entities/imported_statement_line.dart';
import '../entities/installment_plan.dart';
import 'statement_text.dart';

/// O que a parcela de uma linha ("4/10") é em relação às compras parceladas
/// que o app já conhece.
enum InstallmentMatchKind {
  /// O plano já tem essa parcela: veio em outra importação ou foi confirmada.
  alreadyImported,

  /// O plano tem essa parcela prevista: a fatura só a confirma.
  forecast,

  /// O plano existe, mas não tem essa parcela (apagada ou de antes dele).
  continues,

  /// Compra parcelada que o app ainda não conhece.
  newPlan,
}

class InstallmentMatch {
  /// Linha do arquivo (a original, quando ela foi dividida em partes).
  final String groupId;
  final InstallmentMatchKind kind;
  final InstallmentPlan? plan;
  final int number;
  final int total;

  const InstallmentMatch({
    required this.groupId,
    required this.kind,
    required this.number,
    required this.total,
    this.plan,
  });
}

/// Liga as parcelas da fatura aos planos de parcelamento do cartão, para a
/// fatura seguinte confirmar as parcelas previstas em vez de lançá-las de novo.
class InstallmentMatcher {
  const InstallmentMatcher._();

  /// Semelhança mínima entre os nomes do estabelecimento.
  static const double minSimilarity = 0.8;

  /// Diferença de valor aceita entre parcelas (centavos de arredondamento, IOF).
  static const int amountToleranceCents = 100;
  static const double amountToleranceRatio = 0.02;

  /// Folga entre a data esperada e a da linha, e entre os vencimentos.
  static const int lineDateDays = 3;
  static const int dueDateDays = 10;

  static String merchantKeyOf(String description) =>
      StatementText.normalize(StatementText.cleanTitle(description));

  static int _daysApart(DateTime a, DateTime b) => DateTime(a.year, a.month, a.day)
      .difference(DateTime(b.year, b.month, b.day))
      .inDays
      .abs();

  static bool _sameMerchant(String a, String b) =>
      a == b || StatementText.similarity(a, b) >= minSimilarity;

  static bool _closeAmount(int a, int b) {
    final larger = a > b ? a : b;
    final diff = (a - b).abs();
    return diff <= amountToleranceCents || diff <= larger * amountToleranceRatio;
  }

  /// A linha cai onde a parcela [number] do plano deveria cair? O banco mostra
  /// a data da compra em todas as parcelas ou a data avança um mês por parcela;
  /// sem nenhuma das duas, vale o vencimento da fatura.
  static bool _dateFits(
    InstallmentPlan plan,
    int number,
    DateTime lineDate,
    DateTime? invoiceDueDate,
  ) {
    final offset = number - plan.anchorNumber;
    if (_daysApart(lineDate, plan.anchorLineDate) <= lineDateDays) return true;
    if (_daysApart(lineDate, addMonths(plan.anchorLineDate, offset)) <= lineDateDays) {
      return true;
    }
    final anchorDue = plan.anchorDueDate;
    return invoiceDueDate != null &&
        anchorDue != null &&
        _daysApart(invoiceDueDate, addMonths(anchorDue, offset)) <= dueDateDays;
  }

  /// Uma resposta por linha parcelada do arquivo, pela linha original (as
  /// partes de uma divisão contam como a linha que foi dividida). Cada parcela
  /// de um plano casa com uma linha só, então duas compras iguais no mesmo
  /// lugar não se confundem. A compra lançada à mão casa pelo número de
  /// parcelas, valor e data mesmo com outro nome; a lançada para um morador
  /// já tem os empréstimos, então a parcela dela conta como já importada.
  ///
  /// A compra à vista lançada à mão para um morador é um plano de 1 parcela:
  /// casa com a linha sem parcela de mesmo valor e data da compra.
  static Map<String, InstallmentMatch> match({
    required List<ImportedStatementLine> lines,
    required List<InstallmentPlan> plans,
    DateTime? invoiceDueDate,
  }) {
    final upfrontPlans = plans.any((p) => p.total == 1);
    final groups = <String, List<ImportedStatementLine>>{};
    for (final line in lines) {
      if (!line.isPurchase || (!line.isInstallment && !upfrontPlans)) continue;
      groups.putIfAbsent(line.splitFrom ?? line.id, () => []).add(line);
    }

    final candidates = <({String groupId, InstallmentPlan plan, int score})>[];
    for (final entry in groups.entries) {
      final first = entry.value.first;
      final number = first.installmentNumber ?? 1;
      final cents = entry.value.fold<int>(0, (acc, l) => acc + l.amount.cents);
      final merchant = merchantKeyOf(first.description);
      for (final plan in plans) {
        if (plan.total != (first.installmentsTotal ?? 1)) continue;
        if (!_closeAmount(cents, plan.installmentAmount.cents)) continue;
        final sameMerchant = _sameMerchant(merchant, plan.merchantKey);
        final expected = plan.forecastOf(number) != null;
        if (!first.isInstallment) {
          // À vista: sem parcela para conferir, só a data da compra dá certeza
          if (_daysApart(first.date, plan.anchorLineDate) > lineDateDays) continue;
          candidates.add((
            groupId: entry.key,
            plan: plan,
            score: (sameMerchant ? 8 : 0) + 4 + (cents == plan.installmentAmount.cents ? 1 : 0),
          ));
          continue;
        }
        final dateFits = _dateFits(plan, number, first.date, invoiceDueDate);
        if (sameMerchant) {
          // Sem data que bata, só a parcela prevista dá certeza de que é a mesma compra
          if (!dateFits && !expected) continue;
        } else if (!plan.isManual || !dateFits) {
          // O nome digitado à mão pode não ser o do banco: vale a compra lançada
          // à mão com o mesmo número de parcelas, valor e data
          continue;
        }
        candidates.add((
          groupId: entry.key,
          plan: plan,
          // O nome que bate vence: duas compras iguais em lojas diferentes não se trocam
          score: (sameMerchant ? 8 : 0) +
              (dateFits ? 4 : 0) +
              (expected ? 2 : 0) +
              (cents == plan.installmentAmount.cents ? 1 : 0),
        ));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final result = <String, InstallmentMatch>{};
    final usedParcels = <String>{};
    for (final candidate in candidates) {
      if (result.containsKey(candidate.groupId)) continue;
      final first = groups[candidate.groupId]!.first;
      final number = first.installmentNumber ?? 1;
      final parcelKey = '${candidate.plan.id}#$number';
      if (usedParcels.contains(parcelKey)) continue;
      usedParcels.add(parcelKey);
      final plan = candidate.plan;
      result[candidate.groupId] = InstallmentMatch(
        groupId: candidate.groupId,
        plan: plan,
        number: number,
        total: plan.total,
        kind: plan.coveredByLoans || plan.handled(number)
            ? InstallmentMatchKind.alreadyImported
            : plan.forecastOf(number) != null
            ? InstallmentMatchKind.forecast
            : InstallmentMatchKind.continues,
      );
    }

    for (final entry in groups.entries) {
      if (result.containsKey(entry.key)) continue;
      final first = entry.value.first;
      // Linha à vista que não é de nenhuma compra lançada à mão: não é parcela
      if (!first.isInstallment) continue;
      result[entry.key] = InstallmentMatch(
        groupId: entry.key,
        kind: InstallmentMatchKind.newPlan,
        number: first.installmentNumber!,
        total: first.installmentsTotal!,
      );
    }
    return result;
  }
}
