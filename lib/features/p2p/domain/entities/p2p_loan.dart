import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'p2p_installment.dart';

enum LoanStatus {
  pendingAcceptance,
  active,
  paid,
  forgiven,
  renegotiated,
}

/// Modalidade de pagamento do empréstimo.
enum LoanRepaymentMode {
  /// Parcelado: parcelas com vencimento mensal, cobradas no Fechamento do Ciclo.
  installments,

  /// Livre / Sem prazo: o devedor abate o valor que puder, quando puder.
  /// Não possui vencimento e nunca entra no Fechamento do Ciclo (RN01).
  openEnded,
}

/// De onde saiu o dinheiro de um empréstimo do Caixa da Casa (0086).
enum HouseLoanFunding {
  /// Do Caixa do ciclo em andamento: sai da sobra do ciclo de [P2PLoan.fundedOn].
  cycle,

  /// De uma Caixinha ([P2PLoan.repayToVaultId]), para onde os pagamentos voltam.
  vault,
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
  final LoanRepaymentMode repaymentMode;

  /// Parcelado: se as parcelas são cobradas automaticamente no Fechamento do Ciclo.
  /// Quando false, as datas servem só de lembrete e o pagamento é sempre manual.
  final bool settleInCycle;

  /// Identificador do "Caixa da Casa" quando ele é o credor (ex: reposição de Caixinha).
  static const String houseLenderId = 'entity_caixa';

  /// Data técnica gravada na parcela única de um empréstimo sem prazo.
  /// Nunca é exibida ao usuário: a regra de negócio usa [repaymentMode].
  static final DateTime openEndedPlaceholderDueDate = DateTime(2099, 12, 31);

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
    this.repaymentMode = LoanRepaymentMode.installments,
    this.settleInCycle = true,
    this.repayToVaultId,
    this.awaitingAcceptance = false,
    this.houseFunding,
    this.fundedOn,
  });

  /// Empréstimo do Caixa da Casa: de onde o dinheiro saiu (null nos acordos
  /// antigos e nos criados pelo fechamento, que não tiram dinheiro do Caixa).
  final HouseLoanFunding? houseFunding;

  /// Dia em que o dinheiro saiu do Caixa ou da Caixinha.
  final DateTime? fundedOn;

  /// Saiu do Caixa do ciclo [cycle] (e diminui a sobra dele).
  bool fundedFromCycle(FinancialCycle cycle) =>
      isHouseLender &&
      houseFunding == HouseLoanFunding.cycle &&
      fundedOn != null &&
      cycle.contains(fundedOn!);

  /// Lançado por outra pessoa e ainda não aceito pelo devedor (migration 0082):
  /// fica fora do Fechamento do Ciclo até o aceite.
  final bool awaitingAcceptance;

  /// Acordo com o Lar criado quando uma Caixinha cobriu quem pagou a menos:
  /// cada pagamento dele volta para essa Caixinha, e não para o Caixa.
  final String? repayToVaultId;

  /// Empréstimo livre, sem vencimento (paga quando puder).
  bool get isOpenEnded => repaymentMode == LoanRepaymentMode.openEnded;

  /// As parcelas deste empréstimo são cobradas no Fechamento do Ciclo.
  bool get entersCycleSettlement => !isOpenEnded && settleInCycle && !awaitingAcceptance;

  /// Parcelas em aberto, da mais antiga para a mais nova (ordem de abatimento).
  List<P2PInstallment> get openInstallments {
    final open = installments
        .where((i) => !i.isFullyPaid && !i.isForgiven && !i.isCancelled)
        .toList()
      ..sort((a, b) {
        final byDate = a.dueDate.compareTo(b.dueDate);
        return byDate != 0 ? byDate : a.number.compareTo(b.number);
      });
    return open;
  }

  /// Parcelas cobradas no fechamento de [cycle]: as que vencem nele e as
  /// atrasadas de ciclos anteriores que continuam em aberto.
  List<P2PInstallment> installmentsChargedIn(FinancialCycle cycle) {
    if (!entersCycleSettlement) return const [];
    return openInstallments.where((i) => !i.dueDate.isAfter(cycle.endDate)).toList();
  }

  /// O credor é o Caixa da Casa (e não um morador).
  bool get isHouseLender => lenderMemberId == houseLenderId;

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
    String? title,
    String? description,
    Money? totalAmount,
    LoanStatus? status,
    int? installmentsCount,
    DateTime? createdAt,
    DateTime? firstDueDate,
    List<P2PInstallment>? installments,
    String? attachmentUrl,
    LoanRepaymentMode? repaymentMode,
    bool? settleInCycle,
    String? repayToVaultId,
    bool? awaitingAcceptance,
    HouseLoanFunding? houseFunding,
    DateTime? fundedOn,
  }) {
    return P2PLoan(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      totalAmount: totalAmount ?? this.totalAmount,
      lenderMemberId: lenderMemberId,
      borrowerMemberId: borrowerMemberId,
      installmentsCount: installmentsCount ?? this.installmentsCount,
      createdAt: createdAt ?? this.createdAt,
      firstDueDate: firstDueDate ?? this.firstDueDate,
      status: status ?? this.status,
      installments: installments ?? this.installments,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      repaymentMode: repaymentMode ?? this.repaymentMode,
      settleInCycle: settleInCycle ?? this.settleInCycle,
      repayToVaultId: repayToVaultId ?? this.repayToVaultId,
      awaitingAcceptance: awaitingAcceptance ?? this.awaitingAcceptance,
      houseFunding: houseFunding ?? this.houseFunding,
      fundedOn: fundedOn ?? this.fundedOn,
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
        repaymentMode,
        settleInCycle,
        repayToVaultId,
        awaitingAcceptance,
        houseFunding,
        fundedOn,
      ];
}
