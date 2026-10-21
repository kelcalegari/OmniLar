import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../settlement/domain/entities/member_audit_trail.dart';
import '../../../settlement/domain/entities/super_pix_transfer.dart';

/// Fatura ou conta ainda em aberto que a prévia considera paga por alguém:
/// a mesma escolha padrão que o fechamento usa quando ninguém mexe.
class AssumedPayment {
  final String title;
  final DateTime dueDate;
  final Money amount;

  /// Quem paga: um morador (que é reembolsado no fechamento) ou null para o
  /// Caixa da Casa.
  final String? payerMemberId;
  final bool isInvoice;
  final bool isOverdue;

  /// Linha digitável do boleto ou código da fatura, quando foi guardado.
  final String? barcode;

  const AssumedPayment({
    required this.title,
    required this.dueDate,
    required this.amount,
    required this.payerMemberId,
    required this.isInvoice,
    required this.isOverdue,
    this.barcode,
  });

  bool get paidByHouse => payerMemberId == null;
}

/// Prévia do fechamento de um morador: os mesmos números do Hub de
/// Liquidação, com a origem de cada um.
class MemberCyclePreview {
  final String memberId;
  final String memberName;
  final Money contributionDue;
  final Money contributionPaid;
  final Money outOfPocket;
  final Money contributionRefund;
  final Money p2pToPay;
  final Money p2pToReceive;

  /// Positivo = recebe no fechamento; negativo = paga.
  final Money net;

  /// Super Pix em que o morador paga e em que recebe.
  final List<SuperPixTransfer> transfersOut;
  final List<SuperPixTransfer> transfersIn;

  /// Parcelas cobradas neste fechamento (do ciclo e atrasadas).
  final List<P2PInstallmentAudit> installmentsToPay;
  final List<P2PInstallmentAudit> installmentsToReceive;

  /// Faturas e contas em aberto que a prévia considera pagas por ele.
  final List<AssumedPayment> assumedPayments;

  /// Parte dele no que ainda falta lançar das categorias variáveis (só no
  /// rateio por percentual; zero quando não há projeção).
  final Money projectedExtraShare;

  /// Parcelas de empréstimo já amortizadas/pagas neste ciclo
  final List<P2PInstallmentAudit> installmentsPaidInCycle;
  final Money p2pPaidInCycle;

  const MemberCyclePreview({
    required this.memberId,
    required this.memberName,
    required this.contributionDue,
    required this.contributionPaid,
    required this.outOfPocket,
    required this.contributionRefund,
    required this.p2pToPay,
    required this.p2pToReceive,
    required this.net,
    this.transfersOut = const [],
    this.transfersIn = const [],
    this.installmentsToPay = const [],
    this.installmentsToReceive = const [],
    this.assumedPayments = const [],
    this.projectedExtraShare = const Money.zero(),
    this.installmentsPaidInCycle = const [],
    this.p2pPaidInCycle = const Money.zero(),
  });

  bool get pays => net.isNegative;
  bool get receives => net.isPositive;

  /// Saldo projetado até o fim do ciclo (a estimativa sai do que ele recebe).
  Money get projectedNet => Money(net.cents - projectedExtraShare.cents);
}

/// Prévia do fechamento de um ciclo, por morador.
class CyclePreview {
  final FinancialCycle cycle;

  /// O ciclo já foi fechado: os números são os do retrato gravado.
  final bool isSettled;
  final DateTime? settledAt;
  final List<MemberCyclePreview> members;

  /// Faturas e contas em aberto e quem a prévia considera que paga cada uma.
  final List<AssumedPayment> assumedPayments;

  /// O que ainda falta lançar das categorias variáveis até o fim do ciclo
  /// (estimativa do planejador; zero quando não há projeção).
  final Money projectedExtra;

  /// Modelo de aportes fixos: a projeção mexe no balde, não no aporte.
  final bool usesFixedContributions;

  /// Aportes fixos: quanto o ciclo passa do balde hoje e na projeção.
  final Money bucketOverflow;
  final Money projectedBucketOverflow;

  const CyclePreview({
    required this.cycle,
    required this.isSettled,
    this.settledAt,
    required this.members,
    this.assumedPayments = const [],
    this.projectedExtra = const Money.zero(),
    this.usesFixedContributions = false,
    this.bucketOverflow = const Money.zero(),
    this.projectedBucketOverflow = const Money.zero(),
  });

  bool get hasProjection => projectedExtra.isPositive;

  MemberCyclePreview? memberById(String id) =>
      members.where((m) => m.memberId == id).firstOrNull;
}
