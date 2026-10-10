import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'split_rule.dart';

enum ExpenseStatus {
  paid,
  pending, // Conta futura / provisionada
}

class HouseExpense extends Equatable {
  final String id;
  final String title;
  final Money amount;
  final DateTime date;
  final DateTime? dueDate;
  final String categoryId;
  final String paidByMemberId;
  final String paymentMethodId;
  final SplitRule splitRule;
  final ExpenseStatus status;
  final bool isRecurring;
  final bool paidOutOfPocket;
  final String? notes;

  const HouseExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    this.dueDate,
    required this.categoryId,
    required this.paidByMemberId,
    required this.paymentMethodId,
    required this.splitRule,
    this.status = ExpenseStatus.paid,
    this.isRecurring = false,
    this.paidOutOfPocket = false,
    this.notes,
  });

  bool get isPaid => status == ExpenseStatus.paid;
  bool get isPending => status == ExpenseStatus.pending;

  @override
  List<Object?> get props => [
        id,
        title,
        amount,
        date,
        dueDate,
        categoryId,
        paidByMemberId,
        paymentMethodId,
        splitRule,
        status,
        isRecurring,
        paidOutOfPocket,
        notes,
      ];
}
