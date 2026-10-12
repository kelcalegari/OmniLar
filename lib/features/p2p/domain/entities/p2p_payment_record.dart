import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

/// Um pagamento/abatimento registrado para um empréstimo P2P.
class P2PPaymentRecord extends Equatable {
  final Money amount;
  final DateTime paidAt;

  const P2PPaymentRecord({required this.amount, required this.paidAt});

  @override
  List<Object?> get props => [amount, paidAt];
}
