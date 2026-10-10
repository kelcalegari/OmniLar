import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'p2p_installment.dart';

enum LoanStatus {
  pendingAcceptance,
  active,
  paid,
  forgiven,
  renegotiated,
}

class P2PLoan extends Equatable {
  final String id;
  final String title;
  final String? description;
  final Money totalAmount;
  final String lenderMemberId; // Quem emprestou (Credor)
  final String borrowerMemberId; // Quem tomou o empréstimo (Devedor)
  final int installmentsCount;
  final DateTime createdAt;
  final DateTime firstDueDate;
  final LoanStatus status;
  final List<P2PInstallment> installments;
  final String? attachmentUrl;

  const P2PLoan({
    required this.id,
    required this.title,
    this.description,
    required this.totalAmount,
    required this.lenderMemberId,
    required this.borrowerMemberId,
    required this.installmentsCount,
    required this.createdAt,
    required this.firstDueDate,
    this.status = LoanStatus.active,
    this.installments = const [],
    this.attachmentUrl,
  });

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;

  /// Soma do valor restante de todas as parcelas ativas
  Money get remainingAmount {
    if (status == LoanStatus.paid || status == LoanStatus.forgiven) return const Money.zero();
    int remCents = 0;
    for (final inst in installments) {
      remCents += inst.remainingAmount.cents;
    }
    return Money(remCents);
  }

  /// Total já pago em centavos
  Money get totalPaidAmount {
    int paidCents = 0;
    for (final inst in installments) {
      paidCents += inst.paidAmount.cents;
    }
    return Money(paidCents);
  }

  /// Quantidade de parcelas pagas
  int get paidInstallmentsCount {
    return installments.where((inst) => inst.isFullyPaid).length;
  }

  /// Porcentagem do empréstimo já pago (0.0 a 1.0)
  double get progressPercentage {
    if (totalAmount.isZero) return 1.0;
    if (status == LoanStatus.paid || status == LoanStatus.forgiven) return 1.0;
    return (totalPaidAmount.cents / totalAmount.cents).clamp(0.0, 1.0);
  }

  P2PLoan copyWith({
    LoanStatus? status,
    int? installmentsCount,
    List<P2PInstallment>? installments,
  }) {
    return P2PLoan(
      id: id,
      title: title,
      description: description,
      totalAmount: totalAmount,
      lenderMemberId: lenderMemberId,
      borrowerMemberId: borrowerMemberId,
      installmentsCount: installmentsCount ?? this.installmentsCount,
      createdAt: createdAt,
      firstDueDate: firstDueDate,
      status: status ?? this.status,
      installments: installments ?? this.installments,
      attachmentUrl: attachmentUrl,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        totalAmount,
        lenderMemberId,
        borrowerMemberId,
        installmentsCount,
        createdAt,
        firstDueDate,
        status,
        installments,
        attachmentUrl,
      ];
}
