import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

enum ShortfallAction {
  createP2PLoan, // Quem recebeu cobriu a diferença -> Vira novo Empréstimo P2P
  deductFromVault, // Cobrir com Caixinha da Casa (Fundo de Reserva)
  rolloverPending, // Deixar como saldo pendente para o próximo ciclo
  forgiveRemainder, // O credor anistiou/perdoou o saldo restante
}

enum VaultRepaymentMode {
  grant, // A Fundo Perdido: a caixinha absorve o valor, sem gerar dívida/reposição
  installments, // Empréstimo do Lar parcelado (vence nos próximos ciclos)
  openEnded, // Empréstimo do Lar aberto / sem vencimento fixo (vai pagando quando der)
}

class TransferSettlementResolution extends Equatable {
  final String transferId;
  final Money amountExpected;
  final Money amountPaid;
  final ShortfallAction shortfallAction;
  final int loanInstallmentsCount; // Para parcelamento (1 a 12 parcelas)
  final bool loanHasNoDueDate; // Empréstimo aberto sem vencimento fixo (vai pagando quando der)
  final String? vaultId; // Para deductFromVault
  final VaultRepaymentMode vaultRepaymentMode; // Modo de reposição da caixinha
  final String? notes;

  const TransferSettlementResolution({
    required this.transferId,
    required this.amountExpected,
    required this.amountPaid,
    this.shortfallAction = ShortfallAction.createP2PLoan,
    this.loanInstallmentsCount = 1,
    this.loanHasNoDueDate = false,
    this.vaultId,
    this.vaultRepaymentMode = VaultRepaymentMode.grant,
    this.notes,
  });

  bool get isFullPayment => amountPaid >= amountExpected;
  bool get isPartialPayment => amountPaid < amountExpected;
  Money get shortfall =>
      isPartialPayment ? (amountExpected - amountPaid) : const Money.zero();

  TransferSettlementResolution copyWith({
    String? transferId,
    Money? amountExpected,
    Money? amountPaid,
    ShortfallAction? shortfallAction,
    int? loanInstallmentsCount,
    bool? loanHasNoDueDate,
    String? vaultId,
    VaultRepaymentMode? vaultRepaymentMode,
    String? notes,
  }) {
    return TransferSettlementResolution(
      transferId: transferId ?? this.transferId,
      amountExpected: amountExpected ?? this.amountExpected,
      amountPaid: amountPaid ?? this.amountPaid,
      shortfallAction: shortfallAction ?? this.shortfallAction,
      loanInstallmentsCount:
          loanInstallmentsCount ?? this.loanInstallmentsCount,
      loanHasNoDueDate: loanHasNoDueDate ?? this.loanHasNoDueDate,
      vaultId: vaultId ?? this.vaultId,
      vaultRepaymentMode: vaultRepaymentMode ?? this.vaultRepaymentMode,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
    transferId,
    amountExpected,
    amountPaid,
    shortfallAction,
    loanInstallmentsCount,
    loanHasNoDueDate,
    vaultId,
    vaultRepaymentMode,
    notes,
  ];
}
