import '../../../../core/domain/value_objects/money.dart';
import 'cycle_preview.dart';
import 'payment_due_entry.dart';

/// O que já está contratado para um ciclo futuro: a prévia do fechamento só
/// com o que já foi lançado (sem estimativa) e as parcelas fora do fechamento.
class UpcomingCycleForecast {
  final CyclePreview preview;
  final List<PaymentDueEntry> outsideClosing;

  const UpcomingCycleForecast({
    required this.preview,
    this.outsideClosing = const [],
  });
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

  const UpcomingForecast({required this.cycles, required this.payoffs});
}
