import '../../../../core/domain/value_objects/money.dart';

enum TransactionType {
  expense, // Saída (-)
  inflow,  // Entrada (+)
}

enum TransactionOrigin {
  houseExpense,       // Despesa comum da casa / Cartão
  contribution,       // Aporte de morador na caixinha
  houseInflow,        // Entrada externa da casa (venda, caução, etc)
  thirdPartyReceipt,  // Repasse de terceiro / visita
  vaultReturn,        // Resgate de caixinha devolvido ao caixa
  loanRepayment,      // Amortização / pagamento de empréstimo (P2P ou Caixa da Casa)
}

/// Representa qualquer transação financeira unificada (entrada ou saída) da casa.
class HouseTransaction {
  final String id;
  final String title;
  final Money amount;
  final TransactionType type;
  final TransactionOrigin origin;
  final DateTime date;
  final DateTime? dueDate;
  final String? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColorHex;
  final String? memberId;
  final String? memberName;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final bool isPending;
  final String? notes;
  final dynamic rawEntity;

  const HouseTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.origin,
    required this.date,
    this.dueDate,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    this.categoryColorHex,
    this.memberId,
    this.memberName,
    this.paymentMethodId,
    this.paymentMethodName,
    this.isPending = false,
    this.notes,
    this.rawEntity,
  });

  bool get isExpense => type == TransactionType.expense;
  bool get isInflow => type == TransactionType.inflow;
}
