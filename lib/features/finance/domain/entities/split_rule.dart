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
          int allocatedCents = 0;
          for (int i = 0; i < memberIds.length; i++) {
            final id = memberIds[i];
            final percent = percentages![id] ?? 0.0;
            if (i == memberIds.length - 1) {
              // Garante que a soma bate exatamente o total em centavos
              allocations[id] = Money(totalAmount.cents - allocatedCents);
            } else {
              final share = totalAmount.percentage(percent);
              allocations[id] = share;
              allocatedCents += share.cents;
            }
          }
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

  @override
  List<Object?> get props => [type, percentages, fixedAmounts, singleResponsibleMemberId];
}
