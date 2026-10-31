import '../../../../core/domain/value_objects/money.dart';
import '../entities/p2p_loan.dart';

/// Uma linha da lista de empréstimos: um empréstimo sozinho ou as parcelas de
/// uma mesma compra parcelada no cartão.
sealed class LoanListEntry {
  const LoanListEntry();
}

class SingleLoanEntry extends LoanListEntry {
  final P2PLoan loan;
  const SingleLoanEntry(this.loan);
}

/// Compra parcelada no cartão da Casa lançada à mão (0117): cada parcela é um
/// empréstimo de 1 parcela, porque a fatura de cada mês sai do Caixa do ciclo
/// em que vence. Na lista elas aparecem juntas, como um empréstimo parcelado.
class InstallmentLoanGroup extends LoanListEntry {
  final String planId;

  /// Título da compra, sem o "(n/N)" de cada parcela.
  final String title;

  /// Total de parcelas da compra (o N do "n/N").
  final int purchaseInstallments;

  /// As parcelas desta lista (ex.: só as em aberto em Eu Devo), da primeira à última.
  final List<P2PLoan> loans;

  /// Todas as parcelas da compra que existem como empréstimo, pagas ou não.
  final List<P2PLoan> siblings;

  const InstallmentLoanGroup({
    required this.planId,
    required this.title,
    required this.purchaseInstallments,
    required this.loans,
    required this.siblings,
  });

  P2PLoan get first => loans.first;

  /// Número da parcela (o n do "n/N") de um empréstimo do grupo.
  static int numberOf(P2PLoan loan) => _parse(loan.title)?.number ?? 0;

  Money get remainingAmount =>
      loans.fold(const Money.zero(), (acc, l) => acc + l.remainingAmount);

  Money get totalAmount =>
      siblings.fold(const Money.zero(), (acc, l) => acc + l.totalAmount);

  Money get totalPaidAmount =>
      siblings.fold(const Money.zero(), (acc, l) => acc + l.totalPaidAmount);

  int get paidCount => siblings.where(_isSettled).length;

  bool get isSettled => siblings.every(_isSettled);

  bool get awaitingAcceptance => loans.any((l) => l.awaitingAcceptance);

  bool get awaitingApproval => loans.any((l) => l.awaitingApproval);

  double get progressPercentage {
    if (isSettled || totalAmount.isZero) return 1.0;
    return (totalPaidAmount.cents / totalAmount.cents).clamp(0.0, 1.0);
  }

  /// A próxima parcela em aberto (a de vencimento mais próximo).
  P2PLoan? get nextOpen => loans.where((l) => !_isSettled(l)).firstOrNull;
}

bool _isSettled(P2PLoan l) =>
    l.status == LoanStatus.paid || l.status == LoanStatus.forgiven || l.remainingAmount.cents == 0;

final _installmentTitle = RegExp(r'^(.*) \((\d+)/(\d+)\)(.*)$');

({String base, int number, int count, String suffix})? _parse(String title) {
  final m = _installmentTitle.firstMatch(title);
  if (m == null) return null;
  return (
    base: m.group(1)!,
    number: int.parse(m.group(2)!),
    count: int.parse(m.group(3)!),
    suffix: m.group(4)!,
  );
}

/// Chave da compra parcelada de um empréstimo, ou null se ele não é parcela
/// de uma: um empréstimo de 1 parcela, de uma compra só, com "(n/N)" no título.
String? _groupKey(P2PLoan l) {
  if (l.installmentsCount != 1 || l.installmentPlanIds.length != 1) return null;
  final p = _parse(l.title);
  if (p == null || p.count < 2) return null;
  return '${l.installmentPlanIds.single}|${l.lenderMemberId}|${l.borrowerMemberId}'
      '|${p.base}|${p.count}|${p.suffix}';
}

/// Junta as parcelas de uma mesma compra parcelada em uma linha só.
///
/// [loans] é a lista que vai para a tela; [all] são todos os empréstimos,
/// para o grupo contar as parcelas já pagas que não estão na lista. Um grupo
/// com uma parcela só na lista continua sendo mostrado como grupo, para a
/// última parcela não "perder" o parcelamento.
List<LoanListEntry> groupInstallmentLoans(List<P2PLoan> loans, {List<P2PLoan>? all}) {
  final byKey = <String, List<P2PLoan>>{};
  for (final l in loans) {
    final key = _groupKey(l);
    if (key != null) byKey.putIfAbsent(key, () => []).add(l);
  }
  final siblingsByKey = <String, List<P2PLoan>>{};
  for (final l in all ?? loans) {
    final key = _groupKey(l);
    if (key != null && byKey.containsKey(key)) siblingsByKey.putIfAbsent(key, () => []).add(l);
  }

  int byNumber(P2PLoan a, P2PLoan b) =>
      InstallmentLoanGroup.numberOf(a).compareTo(InstallmentLoanGroup.numberOf(b));

  final entries = <LoanListEntry>[];
  final emitted = <String>{};
  for (final l in loans) {
    final key = _groupKey(l);
    final siblings = key == null ? null : siblingsByKey[key];
    if (key == null || siblings == null || siblings.length < 2) {
      entries.add(SingleLoanEntry(l));
      continue;
    }
    if (!emitted.add(key)) continue;
    final p = _parse(l.title)!;
    entries.add(
      InstallmentLoanGroup(
        planId: l.installmentPlanIds.single,
        title: '${p.base}${p.suffix}',
        purchaseInstallments: p.count,
        loans: [...byKey[key]!]..sort(byNumber),
        siblings: [...siblings]..sort(byNumber),
      ),
    );
  }
  return entries;
}
