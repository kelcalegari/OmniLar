import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';

/// De onde veio uma entrada de fora.
enum HouseInflowSource {
  thirdPartyPix('third_party_pix', 'Pix de terceiro'),
  refund('refund', 'Reembolso'),
  storeReturn('store_return', 'Devolução'),
  other('other', 'Outro');

  final String dbValue;
  final String label;
  const HouseInflowSource(this.dbValue, this.label);

  /// Valor desconhecido vira [other].
  static HouseInflowSource fromDb(String? value) =>
      values.where((s) => s.dbValue == value).firstOrNull ?? other;
}

/// Dinheiro que entrou no Caixa da Casa sem ser aporte de um morador: o Pix
/// de alguém de fora, um reembolso, uma devolução de loja (0096). Entra no
/// Caixa do ciclo do dia em que caiu e segue a regra "Entrada de fora" da casa.
///
/// Diferente do repasse de terceiros ([ThirdPartyReceipt]), que fica guardado
/// numa caixinha até pagar uma fatura e não entra no Caixa do ciclo.
class HouseInflow extends Equatable {
  final String id;
  final Money amount;
  final DateTime receivedOn;
  final String description;
  final HouseInflowSource source;

  /// Despesa que a entrada reembolsa (null: nenhuma em especial).
  final String? expenseId;

  /// Morador que lançou (só ele ou um administrador corrige e exclui).
  final String? createdBy;

  const HouseInflow({
    required this.id,
    required this.amount,
    required this.receivedOn,
    required this.description,
    this.source = HouseInflowSource.other,
    this.expenseId,
    this.createdBy,
  });

  /// Quem pode corrigir e excluir: quem lançou ou um administrador.
  bool canEdit({required String? memberId, bool isAdmin = false}) =>
      isAdmin || (memberId != null && memberId == createdBy);

  HouseInflow copyWith({
    Money? amount,
    DateTime? receivedOn,
    String? description,
    HouseInflowSource? source,
    String? expenseId,
    bool clearExpense = false,
  }) =>
      HouseInflow(
        id: id,
        amount: amount ?? this.amount,
        receivedOn: receivedOn ?? this.receivedOn,
        description: description ?? this.description,
        source: source ?? this.source,
        expenseId: clearExpense ? null : (expenseId ?? this.expenseId),
        createdBy: createdBy,
      );

  /// Soma das entradas que caem em [cycle] (todas, sem ciclo).
  static Money total(Iterable<HouseInflow> inflows, {FinancialCycle? cycle}) => Money(
        inflows
            .where((i) => cycle == null || cycle.contains(i.receivedOn))
            .fold<int>(0, (acc, i) => acc + i.amount.cents),
      );

  @override
  List<Object?> get props => [id, amount, receivedOn, description, source, expenseId, createdBy];
}
