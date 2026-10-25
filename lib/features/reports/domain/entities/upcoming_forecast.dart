import '../../../../core/domain/value_objects/money.dart';
import 'cycle_preview.dart';
import 'payment_due_entry.dart';

/// O que já está contratado para um ciclo futuro: a prévia do fechamento só
/// com o que já foi lançado (sem estimativa) e as parcelas fora do fechamento.
class UpcomingCycleForecast {
  final CyclePreview preview;
  final List<PaymentDueEntry> outsideClosing;

  /// Parcelas de compras no cartão que um morador ainda vai dever neste
  /// ciclo: o banco já vai cobrar, mas o empréstimo só nasce com a fatura.
  /// Já estão somadas na prévia do morador.
  final List<PaymentDueEntry> projected;

  const UpcomingCycleForecast({
    required this.preview,
    this.outsideClosing = const [],
    this.projected = const [],
  });
}

/// Compra parcelada no cartão que um morador deve: quanto ainda vem, uma
/// parcela por fatura, até a última.
class InstallmentProjection {
  final String planId;
  final String title;
  final String borrowerId;
  final String borrowerName;

  /// Null quando quem recebe é o Caixa da Casa (cartão da Casa).
  final String? lenderId;
  final String lenderName;
  final Money monthly;
  final int remainingCount;
  final DateTime lastDueDate;

  /// O devedor já aceitou o parcelamento: os empréstimos nascem aceitos.
  final bool accepted;

  const InstallmentProjection({
    required this.planId,
    required this.title,
    required this.borrowerId,
    required this.borrowerName,
    required this.lenderId,
    required this.lenderName,
    required this.monthly,
    required this.remainingCount,
    required this.lastDueDate,
    required this.accepted,
  });

  Money get remaining => Money(monthly.cents * remainingCount);

  bool involves(String memberId) =>
      borrowerId == memberId || lenderId == memberId;
}

/// Quando cada empréstimo em aberto termina de ser pago.
class LoanPayoff {
  final String loanId;
  final String title;
  final String borrowerId;
  final String borrowerName;
  final String? lenderId;
  final String lenderName;
  final Money remaining;
  final int openInstallments;

  /// Vencimento da última parcela em aberto.
  final DateTime lastDueDate;

  const LoanPayoff({
    required this.loanId,
    required this.title,
    required this.borrowerId,
    required this.borrowerName,
    required this.lenderId,
    required this.lenderName,
    required this.remaining,
    required this.openInstallments,
    required this.lastDueDate,
  });

  bool involves(String memberId) =>
      borrowerId == memberId || lenderId == memberId;
}

class UpcomingForecast {
  final List<UpcomingCycleForecast> cycles;
  final List<LoanPayoff> payoffs;
  final List<InstallmentProjection> installments;

  const UpcomingForecast({
    required this.cycles,
    required this.payoffs,
    this.installments = const [],
  });
}
