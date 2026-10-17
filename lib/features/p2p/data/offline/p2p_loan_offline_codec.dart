import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/entities/p2p_loan.dart';

/// Serialização de empréstimos para a fila offline.

Map<String, dynamic> p2pLoanToJson(P2PLoan loan, {String? id}) => {
  'id': id ?? loan.id,
  'title': loan.title,
  'description': loan.description,
  'totalCents': loan.totalAmount.cents,
  'lenderMemberId': loan.lenderMemberId,
  'borrowerMemberId': loan.borrowerMemberId,
  'installmentsCount': loan.installmentsCount,
  'createdAt': loan.createdAt.toIso8601String(),
  'firstDueDate': loan.firstDueDate.toIso8601String(),
  'status': loan.status.name,
  'repaymentMode': loan.repaymentMode.name,
  'settleInCycle': loan.settleInCycle,
  'repayToVaultId': loan.repayToVaultId,
  'houseFunding': loan.houseFunding?.name,
  'fundedOn': loan.fundedOn?.toIso8601String(),
  'installments': [
    for (final inst in loan.installments)
      {
        'id': inst.id,
        'number': inst.number,
        'totalCount': inst.totalCount,
        'amountCents': inst.amount.cents,
        'paidCents': inst.paidAmount.cents,
        'dueDate': inst.dueDate.toIso8601String(),
        'paidAt': inst.paidAt?.toIso8601String(),
        'isForgiven': inst.isForgiven,
        'isCancelled': inst.isCancelled,
      },
  ],
};

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;

P2PLoan p2pLoanFromJson(Map<String, dynamic> json) {
  final id = json['id'] as String;
  return P2PLoan(
    id: id,
    title: json['title'] as String,
    description: json['description'] as String?,
    totalAmount: Money((json['totalCents'] as num).toInt()),
    lenderMemberId: json['lenderMemberId'] as String,
    borrowerMemberId: json['borrowerMemberId'] as String,
    installmentsCount: (json['installmentsCount'] as num?)?.toInt() ?? 1,
    createdAt: DateTime.parse(json['createdAt'] as String),
    firstDueDate: DateTime.parse(json['firstDueDate'] as String),
    status: _enumByName(LoanStatus.values, json['status'], LoanStatus.active),
    repaymentMode: _enumByName(
      LoanRepaymentMode.values,
      json['repaymentMode'],
      LoanRepaymentMode.installments,
    ),
    settleInCycle: json['settleInCycle'] as bool? ?? true,
    repayToVaultId: json['repayToVaultId'] as String?,
    houseFunding: HouseLoanFunding.values.where((v) => v.name == json['houseFunding']).firstOrNull,
    fundedOn: DateTime.tryParse(json['fundedOn'] as String? ?? ''),
    installments: [
      for (final raw in (json['installments'] as List<dynamic>? ?? const []))
        P2PInstallment(
          id: (raw as Map)['id'] as String,
          loanId: id,
          number: (raw['number'] as num).toInt(),
          totalCount: (raw['totalCount'] as num?)?.toInt() ?? 1,
          amount: Money((raw['amountCents'] as num).toInt()),
          paidAmount: Money((raw['paidCents'] as num?)?.toInt() ?? 0),
          dueDate: DateTime.parse(raw['dueDate'] as String),
          paidAt: raw['paidAt'] != null ? DateTime.parse(raw['paidAt'] as String) : null,
          isForgiven: raw['isForgiven'] as bool? ?? false,
          isCancelled: raw['isCancelled'] as bool? ?? false,
        ),
    ],
  );
}
