import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

enum InstallmentStatus {
  pending, // Aguardando pagamento
  partiallyPaid, // Pago parcialmente
  paid, // Liquidada
  overdue, // Vencida
  forgiven, // Perdoada
  cancelled, // Cancelada por renegociação
}

class P2PInstallment extends Equatable {
  final String id;
  final String loanId;
  final int number; // Número da parcela (ex: 1)
  final int totalCount; // Total de parcelas (ex: 3)
  final Money amount; // Valor nominal da parcela
  final Money paidAmount; // Valor já pago
  final DateTime dueDate;
  final DateTime? paidAt;
  final bool isForgiven;
  final bool isCancelled;

  const P2PInstallment({
    required this.id,
    required this.loanId,
    required this.number,
    required this.totalCount,
    required this.amount,
    this.paidAmount = const Money.zero(),
    required this.dueDate,
    this.paidAt,
    this.isForgiven = false,
    this.isCancelled = false,
  });

  Money get remainingAmount {
    if (isForgiven || isCancelled || isFullyPaid) return const Money.zero();
    final rem = amount - paidAmount;
    return rem.isNegative ? const Money.zero() : rem;
  }

  bool get isFullyPaid => paidAmount.cents >= amount.cents;

  /// Vencida: o dia do vencimento já passou (no próprio dia ainda está em dia,
  /// a mesma regra das contas da casa).
  bool get isPastDue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(today);
  }

  InstallmentStatus get status {
    if (isCancelled) return InstallmentStatus.cancelled;
    if (isForgiven) return InstallmentStatus.forgiven;
    if (isFullyPaid) return InstallmentStatus.paid;
    if (paidAmount.isPositive) return InstallmentStatus.partiallyPaid;
    if (isPastDue) return InstallmentStatus.overdue;
    return InstallmentStatus.pending;
  }

  P2PInstallment copyWith({
    Money? amount,
    Money? paidAmount,
    DateTime? dueDate,
    DateTime? paidAt,
    bool? isForgiven,
    bool? isCancelled,
    int? number,
    int? totalCount,
  }) {
    return P2PInstallment(
      id: id,
      loanId: loanId,
      number: number ?? this.number,
      totalCount: totalCount ?? this.totalCount,
      amount: amount ?? this.amount,
      paidAmount: paidAmount ?? this.paidAmount,
      dueDate: dueDate ?? this.dueDate,
      paidAt: paidAt ?? this.paidAt,
      isForgiven: isForgiven ?? this.isForgiven,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }

  @override
  List<Object?> get props => [
        id,
        loanId,
        number,
        totalCount,
        amount,
        paidAmount,
        dueDate,
        paidAt,
        isForgiven,
        isCancelled,
      ];
}
