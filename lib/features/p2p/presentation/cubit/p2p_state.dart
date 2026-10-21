import 'package:equatable/equatable.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../../../core/domain/value_objects/money.dart';

enum P2PStatus { initial, loading, success, failure }

class P2PState extends Equatable {
  final P2PStatus status;
  final String currentUserId;
  final List<P2PLoan> allLoans;
  final String? errorMessage;

  const P2PState({
    this.status = P2PStatus.initial,
    this.currentUserId = '',
    this.allLoans = const [],
    this.errorMessage,
  });

  /// Dívidas onde o usuário atual é o devedor (Eu Devo) e ainda ativas
  List<P2PLoan> get loansIDowe {
    return allLoans
        .where((l) =>
            l.borrowerMemberId == currentUserId &&
            l.status != LoanStatus.paid &&
            l.status != LoanStatus.forgiven &&
            l.remainingAmount.cents > 0)
        .toList();
  }

  /// Empréstimos onde o usuário atual é o credor (Me Devem) e ainda ativos
  List<P2PLoan> get loansTheyOweMe {
    return allLoans
        .where((l) =>
            l.lenderMemberId == currentUserId &&
            l.status != LoanStatus.paid &&
            l.status != LoanStatus.forgiven &&
            l.remainingAmount.cents > 0)
        .toList();
  }

  /// Empréstimos onde o Caixa da Casa é o credor e ainda ativos (Acordos com o Lar)
  List<P2PLoan> get houseLoans {
    return allLoans
        .where((l) =>
            l.isHouseLender &&
            l.status != LoanStatus.paid &&
            l.status != LoanStatus.forgiven &&
            l.remainingAmount.cents > 0)
        .toList();
  }

  /// Todos os empréstimos liquidados/quitados ou perdoados da Casa
  List<P2PLoan> get allSettledLoans {
    return allLoans
        .where((l) =>
            l.status == LoanStatus.paid ||
            l.status == LoanStatus.forgiven ||
            l.remainingAmount.cents == 0)
        .toList();
  }

  /// Empréstimos já liquidados/quitados ou perdoados envolvendo o usuário diretamente
  List<P2PLoan> get mySettledLoans {
    return allLoans
        .where((l) =>
            (l.borrowerMemberId == currentUserId || l.lenderMemberId == currentUserId) &&
            (l.status == LoanStatus.paid || l.status == LoanStatus.forgiven || l.remainingAmount.cents == 0))
        .toList();
  }

  /// Empréstimos já liquidados/quitados ou perdoados da casa (exibidos na aba de Histórico/Quitados)
  List<P2PLoan> get settledLoans => allSettledLoans;

  /// Total que os moradores devem para o Caixa da Casa
  Money get totalHouseLoansPending {
    int cents = 0;
    for (final l in houseLoans) {
      cents += l.remainingAmount.cents;
    }
    return Money(cents);
  }

  /// Total que Eu Devo (Soma das parcelas ativas)
  Money get totalIDowe {
    int cents = 0;
    for (final l in loansIDowe) {
      cents += l.remainingAmount.cents;
    }
    return Money(cents);
  }

  /// Total que Me Devem (Soma das parcelas ativas)
  Money get totalTheyOweMe {
    int cents = 0;
    for (final l in loansTheyOweMe) {
      cents += l.remainingAmount.cents;
    }
    return Money(cents);
  }

  /// Saldo Líquido P2P
  Money get netBalance => totalTheyOweMe - totalIDowe;

  P2PState copyWith({
    P2PStatus? status,
    String? currentUserId,
    List<P2PLoan>? allLoans,
    String? errorMessage,
  }) {
    return P2PState(
      status: status ?? this.status,
      currentUserId: currentUserId ?? this.currentUserId,
      allLoans: allLoans ?? this.allLoans,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, currentUserId, allLoans, errorMessage];
}
