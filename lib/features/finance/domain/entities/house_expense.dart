import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'house_expense_item.dart';
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
  final List<HouseExpenseItem> items;
  final String? recurringSeriesId; // Vincula esta despesa à série/assinatura recorrente matriz
  final String? projectId; // Vincula esta despesa a um projeto compartilhado (ex: viagem, reforma, meta)
  final DateTime? paidAt; // Quando uma conta que estava pendente recebeu baixa (define o ciclo em que ela conta)
  final DateTime? settledAt; // Quando entrou em um fechamento de ciclo (o reembolso de quem pagou do bolso já foi acertado)

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
    this.items = const [],
    this.recurringSeriesId,
    this.projectId,
    this.paidAt,
    this.settledAt,
  });

  bool get isPaid => status == ExpenseStatus.paid;
  bool get isPending => status == ExpenseStatus.pending;

  /// Despesa vinculada a um Projeto Compartilhado (viagem, reforma, evento...).
  /// Regra: despesas de projeto NÃO entram no Caixa da Casa, no Fôlego nem no
  /// fechamento do ciclo; são rateadas apenas entre os participantes do projeto.
  bool get isProjectExpense => projectId != null;

  /// Data efetiva de vencimento ou de referência
  DateTime get effectiveDueDate => dueDate ?? date;

  /// Verifica se a despesa está vencida/em atraso (pendente e com data anterior a hoje)
  bool get isOverdue {
    if (!isPending) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(effectiveDueDate.year, effectiveDueDate.month, effectiveDueDate.day);
    return due.isBefore(today);
  }

  /// Quantidade de dias corridos em atraso
  int get daysOverdue {
    if (!isOverdue) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(effectiveDueDate.year, effectiveDueDate.month, effectiveDueDate.day);
    return today.difference(due).inDays;
  }

  /// Se a despesa possui sub-itens desmembrados (ex: condomínio com água, gás, obras)
  bool get isItemized => items.isNotEmpty;

  /// Soma dos valores de todos os sub-itens em centavos
  int get itemsTotalCents => items.fold<int>(0, (acc, item) => acc + item.amount.cents);

  /// Verifica se os sub-itens somam exatamente o total do boleto
  bool get isItemsBalanced => !isItemized || itemsTotalCents == amount.cents;

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
    List<HouseExpenseItem>? items,
    String? recurringSeriesId,
    String? projectId,
    DateTime? paidAt,
    bool clearPaidAt = false,
    DateTime? settledAt,
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
      items: items ?? this.items,
      recurringSeriesId: recurringSeriesId ?? this.recurringSeriesId,
      projectId: projectId ?? this.projectId,
      paidAt: clearPaidAt ? null : (paidAt ?? this.paidAt),
      settledAt: settledAt ?? this.settledAt,
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
        items,
        recurringSeriesId,
        projectId,
        paidAt,
        settledAt,
      ];
}
