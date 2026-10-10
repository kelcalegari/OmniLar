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
  final bool isVariable; // Se true: valor varia mês a mês (consumo: luz, água). Se false: fixa (assinatura: Netflix, internet).
  final int? dueDay; // Dia do vencimento no mês (1-31)
  final bool isActive; // Se a assinatura/recorrência está ativa
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
    this.isVariable = false,
    this.dueDay,
    this.isActive = true,
    this.paidOutOfPocket = false,
    this.notes,
  });

  bool get isPaid => status == ExpenseStatus.paid;
  bool get isPending => status == ExpenseStatus.pending;

  HouseExpense copyWith({
    String? id,
    String? title,
    Money? amount,
    DateTime? date,
    DateTime? dueDate,
    String? categoryId,
    String? paidByMemberId,
    String? paymentMethodId,
    SplitRule? splitRule,
    ExpenseStatus? status,
    bool? isRecurring,
    bool? isVariable,
    int? dueDay,
    bool? isActive,
    bool? paidOutOfPocket,
    String? notes,
  }) {
    return HouseExpense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      categoryId: categoryId ?? this.categoryId,
      paidByMemberId: paidByMemberId ?? this.paidByMemberId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      splitRule: splitRule ?? this.splitRule,
      status: status ?? this.status,
      isRecurring: isRecurring ?? this.isRecurring,
      isVariable: isVariable ?? this.isVariable,
      dueDay: dueDay ?? this.dueDay,
      isActive: isActive ?? this.isActive,
      paidOutOfPocket: paidOutOfPocket ?? this.paidOutOfPocket,
      notes: notes ?? this.notes,
    );
  }

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
        isVariable,
        dueDay,
        isActive,
        paidOutOfPocket,
        notes,
      ];
}
