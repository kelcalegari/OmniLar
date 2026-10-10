import '../../../../core/domain/value_objects/money.dart';

enum LineDestination {
  house, // Vira Gasto da Casa
  splitP2P, // Vira Empréstimo P2P (outro membro deve para o dono do cartão)
  cardOwnerPersonal, // Gasto pessoal do dono (não afeta as contas da casa nem gera dívida)
  ignored, // Ignorado / duplicado
}

class ImportedStatementLine {
  final String id;
  final DateTime date;
  final String description;
  final Money amount;
  final LineDestination destination;
  final String? categoryId;
  final String? assignedMemberId; // Devedor no caso de splitP2P
  final bool isDuplicate;

  const ImportedStatementLine({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.destination = LineDestination.house,
    this.categoryId,
    this.assignedMemberId,
    this.isDuplicate = false,
  });

  ImportedStatementLine copyWith({
    LineDestination? destination,
    String? categoryId,
    String? assignedMemberId,
    bool? isDuplicate,
  }) {
    return ImportedStatementLine(
      id: id,
      date: date,
      description: description,
      amount: amount,
      destination: destination ?? this.destination,
      categoryId: categoryId ?? this.categoryId,
      assignedMemberId: assignedMemberId ?? this.assignedMemberId,
      isDuplicate: isDuplicate ?? this.isDuplicate,
    );
  }
}

class InvoiceSplitResult {
  final Money totalAmount;
  final Money houseAmount;
  final Money personalOwnerAmount;
  final Map<String, Money> p2pDebtsByMember; // membroDevedor -> valor que deve ao dono do cartão

  const InvoiceSplitResult({
    required this.totalAmount,
    required this.houseAmount,
    required this.personalOwnerAmount,
    required this.p2pDebtsByMember,
  });
}
