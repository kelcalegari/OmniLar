import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

enum SplitType {
  percentage, // Proporcional por porcentagem (ex: 60% / 40%)
  fixed, // Nominal por valores fixos em Reais (ex: R$ 50 / R$ 100)
  categoryOwner, // Responsabilidade dirigida ao dono da categoria (100%)
}

class SplitRule extends Equatable {
  final SplitType type;
  final Map<String, double>? percentages; // memberId -> percent (ex: 'user1': 60.0)
  final Map<String, Money>? fixedAmounts; // memberId -> Money (ex: 'user1': Money(5000))
  final String? singleResponsibleMemberId; // Quando for 100% para um membro específico

  const SplitRule.percentage(this.percentages)
      : type = SplitType.percentage,
        fixedAmounts = null,
        singleResponsibleMemberId = null;

  const SplitRule.fixed(this.fixedAmounts)
      : type = SplitType.fixed,
        percentages = null,
        singleResponsibleMemberId = null;

  const SplitRule.singleResponsible(this.singleResponsibleMemberId)
      : type = SplitType.categoryOwner,
        percentages = null,
        fixedAmounts = null;

  /// Retorna a alocação de responsabilidade em [Money] para cada membro para um valor total [totalAmount].
  Map<String, Money> calculateAllocations({
    required Money totalAmount,
    required List<String> memberIds,
  }) {
    final allocations = <String, Money>{};

    switch (type) {
      case SplitType.categoryOwner:
        final targetId = singleResponsibleMemberId ?? (memberIds.isNotEmpty ? memberIds.first : '');
        for (final id in memberIds) {
          allocations[id] = id == targetId ? totalAmount : const Money.zero();
        }
        break;

      case SplitType.fixed:
        if (fixedAmounts != null && fixedAmounts!.isNotEmpty) {
          for (final id in memberIds) {
            allocations[id] = fixedAmounts![id] ?? const Money.zero();
          }
        } else {
          // Fallback para divisão igualitária
          final parts = totalAmount.splitEqually(memberIds.length);
          for (int i = 0; i < memberIds.length; i++) {
            allocations[memberIds[i]] = parts[i];
          }
        }
        break;

      case SplitType.percentage:
        if (percentages != null && percentages!.isNotEmpty) {
          allocations.addAll(_allocateByWeights(totalAmount, memberIds));
        } else {
          final parts = totalAmount.splitEqually(memberIds.length);
          for (int i = 0; i < memberIds.length; i++) {
            allocations[memberIds[i]] = parts[i];
          }
        }
        break;
    }

    return allocations;
  }

  /// Reparte [totalAmount] na proporção dos percentuais: eles são normalizados
  /// pela própria soma (35/65/50 vira 35/150, 65/150 e 50/150), então ninguém
  /// "absorve o resto" por estar no fim da lista. Os centavos que sobram do
  /// arredondamento vão para quem ficou com a maior fração; só em empate exato
  /// vale a ordem da lista.
  Map<String, Money> _allocateByWeights(Money totalAmount, List<String> memberIds) {
    // Pesos inteiros (centésimos de ponto percentual) para a conta ser exata.
    final weights = [
      for (final id in memberIds)
        (percentages![id] ?? 0.0) > 0 ? (percentages![id]! * 10000).round() : 0,
    ];
    final totalWeight = weights.fold<int>(0, (acc, w) => acc + w);

    if (totalWeight <= 0) {
      final parts = totalAmount.splitEqually(memberIds.length);
      return {for (int i = 0; i < memberIds.length; i++) memberIds[i]: parts[i]};
    }

    final cents = [for (final w in weights) totalAmount.cents * w ~/ totalWeight];
    final remainders = [for (final w in weights) totalAmount.cents * w % totalWeight];
    var leftover = totalAmount.cents - cents.fold<int>(0, (acc, c) => acc + c);

    final byLargestRemainder = List.generate(memberIds.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (final i in byLargestRemainder) {
      if (leftover <= 0) break;
      if (weights[i] <= 0) continue;
      cents[i] += 1;
      leftover -= 1;
    }

    return {for (int i = 0; i < memberIds.length; i++) memberIds[i]: Money(cents[i])};
  }

  @override
  List<Object?> get props => [type, percentages, fixedAmounts, singleResponsibleMemberId];
}
