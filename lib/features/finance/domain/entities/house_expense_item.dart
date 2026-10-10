import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'split_rule.dart';

class HouseExpenseItem extends Equatable {
  final String id;
  final String expenseId;
  final String title;
  final Money amount;
  final String? categoryId;
  final String? responsibleMemberId;
  final SplitRule? splitRule;

  const HouseExpenseItem({
    required this.id,
    required this.expenseId,
    required this.title,
    required this.amount,
    this.categoryId,
    this.responsibleMemberId,
    this.splitRule,
  });

  HouseExpenseItem copyWith({
    String? id,
    String? expenseId,
    String? title,
    Money? amount,
    String? categoryId,
    String? responsibleMemberId,
    SplitRule? splitRule,
  }) {
    return HouseExpenseItem(
      id: id ?? this.id,
      expenseId: expenseId ?? this.expenseId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      responsibleMemberId: responsibleMemberId ?? this.responsibleMemberId,
      splitRule: splitRule ?? this.splitRule,
    );
  }

  @override
  List<Object?> get props => [
        id,
        expenseId,
        title,
        amount,
        categoryId,
        responsibleMemberId,
        splitRule,
      ];
}
