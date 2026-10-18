import 'package:equatable/equatable.dart';

import '../../../../core/domain/value_objects/money.dart';
import 'house_settings.dart';

/// O dinheiro que entrou no Caixa do ciclo sem ser aporte, separado por
/// origem: cada tipo segue a regra que a casa escolheu para ele no rateio.
class OpeningInflows extends Equatable {
  /// Sobra que o fechamento do ciclo anterior deixou no Caixa.
  final Money rolledSurplus;

  /// Empréstimos do Caixa pagos de volta fora do fechamento (0088).
  final Money houseLoansRepaid;

  /// Resgates de cada caixinha devolvidos ao Caixa do ciclo, menos os
  /// depósitos tirados dele (líquido por caixinha; pode ser negativo).
  final Map<String, Money> vaultWithdrawalsByVault;

  /// Nome de cada caixinha, para a memória de cálculo.
  final Map<String, String> vaultNames;

  /// Entrada de fora (reservado: ainda não há de onde ler).
  final Money thirdParty;

  const OpeningInflows({
    this.rolledSurplus = const Money.zero(),
    this.houseLoansRepaid = const Money.zero(),
    this.vaultWithdrawalsByVault = const {},
    this.vaultNames = const {},
    this.thirdParty = const Money.zero(),
  });

  /// Resgates de todas as caixinhas, líquidos (o mesmo que getVaultReturnsForCycle).
  Money get vaultWithdrawalsTotal => Money(
        vaultWithdrawalsByVault.values.fold<int>(0, (acc, m) => acc + m.cents),
      );

  OpeningInflows copyWith({
    Money? rolledSurplus,
    Money? houseLoansRepaid,
    Map<String, Money>? vaultWithdrawalsByVault,
    Map<String, String>? vaultNames,
    Money? thirdParty,
  }) =>
      OpeningInflows(
        rolledSurplus: rolledSurplus ?? this.rolledSurplus,
        houseLoansRepaid: houseLoansRepaid ?? this.houseLoansRepaid,
        vaultWithdrawalsByVault: vaultWithdrawalsByVault ?? this.vaultWithdrawalsByVault,
        vaultNames: vaultNames ?? this.vaultNames,
        thirdParty: thirdParty ?? this.thirdParty,
      );

  @override
  List<Object?> get props => [rolledSurplus, houseLoansRepaid, vaultWithdrawalsByVault, vaultNames, thirdParty];
}

/// De onde veio uma parte do dinheiro que já está no Caixa.
enum OpeningInflowKind { rolledSurplus, houseLoansRepaid, vaultWithdrawal, thirdParty }

/// Uma parte do dinheiro do Caixa com a regra que vale para ela.
class OpeningInflowPart extends Equatable {
  final OpeningInflowKind kind;

  /// Nunca negativo: depósito em caixinha não é entrada.
  final Money amount;

  /// Nulo: a casa não escolheu e vale o comportamento anterior à regra (0091).
  final OpeningBalanceRule? rule;

  final String? vaultId;
  final String? vaultName;

  const OpeningInflowPart({
    required this.kind,
    required this.amount,
    required this.rule,
    this.vaultId,
    this.vaultName,
  });

  /// Título na memória de cálculo quando abate o aporte.
  String get abatementTitle => switch (kind) {
        OpeningInflowKind.rolledSurplus => 'Sobra do ciclo anterior abatida',
        OpeningInflowKind.houseLoansRepaid => 'Empréstimo do Caixa pago de volta abatido',
        OpeningInflowKind.vaultWithdrawal => vaultName != null && vaultName!.isNotEmpty
            ? 'Resgate da caixinha $vaultName abatido'
            : 'Resgate de caixinha abatido',
        OpeningInflowKind.thirdParty => 'Entrada de fora abatida',
      };

  /// Separa [inflows] por origem, cada uma com a regra de [rules]. Sobra e
  /// empréstimo sem escolha própria seguem [fallback] (a regra única de 0091).
  static List<OpeningInflowPart> split(
    OpeningInflows inflows,
    OpeningInflowRules rules,
    OpeningBalanceRule? fallback,
  ) {
    Money positive(Money m) => m.cents > 0 ? m : const Money.zero();
    final vaultIds = inflows.vaultWithdrawalsByVault.keys.toList()..sort();
    return [
      OpeningInflowPart(
        kind: OpeningInflowKind.rolledSurplus,
        amount: positive(inflows.rolledSurplus),
        rule: rules.rolledSurplusRule(fallback),
      ),
      OpeningInflowPart(
        kind: OpeningInflowKind.houseLoansRepaid,
        amount: positive(inflows.houseLoansRepaid),
        rule: rules.houseLoansRepaidRule(fallback),
      ),
      for (final id in vaultIds)
        OpeningInflowPart(
          kind: OpeningInflowKind.vaultWithdrawal,
          amount: positive(inflows.vaultWithdrawalsByVault[id]!),
          rule: rules.vaultRule(id),
          vaultId: id,
          vaultName: inflows.vaultNames[id],
        ),
      OpeningInflowPart(
        kind: OpeningInflowKind.thirdParty,
        amount: positive(inflows.thirdParty),
        rule: rules.thirdPartyRule(fallback),
      ),
    ].where((p) => p.amount.cents > 0).toList();
  }

  @override
  List<Object?> get props => [kind, amount, rule, vaultId, vaultName];
}
