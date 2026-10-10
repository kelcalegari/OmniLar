import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

class ShoppingTrip extends Equatable {
  final String id;
  final String listId;
  final Money totalAmount;
  final String paymentMethodId;
  final String? houseExpenseId;
  final String? p2pLoanId;
  final DateTime completedAt;

  const ShoppingTrip({
    required this.id,
    required this.listId,
    required this.totalAmount,
    required this.paymentMethodId,
    this.houseExpenseId,
    this.p2pLoanId,
    required this.completedAt,
  });

  @override
  List<Object?> get props => [id, listId, totalAmount, paymentMethodId, houseExpenseId, p2pLoanId, completedAt];
}
