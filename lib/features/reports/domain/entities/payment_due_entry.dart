import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';

enum PaymentDueKind {
  /// Super Pix do fechamento do ciclo.
  closing,

  /// Parcela de empréstimo cobrada fora do fechamento (só lembrete de data).
  installment,

  /// Fatura de cartão em aberto.
  invoice,

  /// Conta pendente (boleto, conta fixa).
  bill,

  /// Empréstimo sem prazo: paga quando puder.
  openEnded,
}

/// Um pagamento com data (ou sem prazo) de alguém para alguém.
class PaymentDueEntry {
  final PaymentDueKind kind;

  /// Null só no empréstimo sem prazo.
  final DateTime? date;
  final String title;
  final Money amount;

  /// Quem paga: um morador, ou null para o Caixa da Casa.
  final String? payerId;
  final String payerName;

  /// Quem recebe: um morador, ou null para o Caixa ou alguém de fora
  /// (fatura, boleto).
  final String? receiverId;
  final String? receiverName;
  final bool isOverdue;

  /// Quem paga é reembolsado no fechamento (fatura ou conta paga do bolso).
  final bool reimbursedAtClosing;

  /// Linha digitável do boleto ou código da fatura, quando foi guardado.
  final String? barcode;

  const PaymentDueEntry({
    required this.kind,
    required this.date,
    required this.title,
    required this.amount,
    required this.payerId,
    required this.payerName,
    this.receiverId,
    this.receiverName,
    this.isOverdue = false,
    this.reimbursedAtClosing = false,
    this.barcode,
  });

  bool involves(String memberId) =>
      payerId == memberId || receiverId == memberId;
}

/// Calendário de pagamentos de um ciclo: do que está atrasado até o
/// fechamento, mais os empréstimos sem prazo.
class PaymentCalendar {
  final FinancialCycle cycle;

  /// Em ordem de data; os sem prazo ficam no fim.
  final List<PaymentDueEntry> entries;

  /// Dia de referência do calendário (o que venceu antes dele está atrasado).
  final DateTime today;

  const PaymentCalendar({
    required this.cycle,
    required this.entries,
    required this.today,
  });

  List<PaymentDueEntry> forMember(String memberId) =>
      entries.where((e) => e.involves(memberId)).toList();

  /// O que [memberId] desembolsa até o fim do ciclo (com data).
  Money outgoingOf(String memberId) => Money(
    entries
        .where((e) => e.payerId == memberId && e.date != null)
        .fold<int>(0, (acc, e) => acc + e.amount.cents),
  );

  /// O que [memberId] recebe até o fim do ciclo (com data).
  Money incomingOf(String memberId) => Money(
    entries
        .where((e) => e.receiverId == memberId && e.date != null)
        .fold<int>(0, (acc, e) => acc + e.amount.cents),
  );
}
