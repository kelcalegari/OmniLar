import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import 'imported_statement_line.dart';

/// Despesa de uma parcela do plano: a que a fatura já trouxe ou a prevista.
class InstallmentParcel {
  final HouseExpense expense;

  /// Prevista pela importação e ainda não confirmada por uma fatura.
  final bool isForecast;

  const InstallmentParcel({required this.expense, this.isForecast = false});
}

/// Compra parcelada de um cartão ("MAGALU 03/10"): liga as parcelas de uma
/// fatura às das seguintes e lembra o que a casa decidiu sobre ela.
class InstallmentPlan {
  final String id;
  final String paymentMethodId;

  /// Nome do estabelecimento sem acento, número de loja nem parcela.
  final String merchantKey;
  final String title;
  final int total;
  final Money installmentAmount;

  /// Parcela, data da linha e vencimento da fatura em que o plano nasceu: a
  /// partir deles se sabe em que fatura cai cada parcela.
  final int anchorNumber;
  final DateTime anchorLineDate;
  final DateTime? anchorDueDate;

  final LineDestination destination;
  final String? categoryId;
  final String? assignedMemberId;

  /// Despesas das parcelas, pelo número.
  final Map<int, InstallmentParcel> parcels;

  /// Parcelas que uma importação ativa já tratou, qualquer que tenha sido o
  /// destino (despesa, empréstimo, pessoal).
  final Set<int> importedNumbers;

  const InstallmentPlan({
    required this.id,
    required this.paymentMethodId,
    required this.merchantKey,
    required this.title,
    required this.total,
    required this.installmentAmount,
    required this.anchorNumber,
    required this.anchorLineDate,
    this.anchorDueDate,
    this.destination = LineDestination.house,
    this.categoryId,
    this.assignedMemberId,
    this.parcels = const {},
    this.importedNumbers = const {},
  });

  /// A parcela [number] já foi tratada: importada antes ou confirmada no app.
  bool handled(int number) =>
      importedNumbers.contains(number) ||
      (parcels[number] != null && !parcels[number]!.isForecast);

  HouseExpense? forecastOf(int number) {
    final parcel = parcels[number];
    return parcel != null && parcel.isForecast ? parcel.expense : null;
  }

  /// Vencimento da última parcela, para saber se o plano ainda está em curso.
  DateTime? get lastDueDate => anchorDueDate == null
      ? null
      : addMonths(anchorDueDate!, total - anchorNumber);

  InstallmentPlan copyWith({
    LineDestination? destination,
    String? categoryId,
    String? assignedMemberId,
    bool clearAssignedMember = false,
  }) => InstallmentPlan(
    id: id,
    paymentMethodId: paymentMethodId,
    merchantKey: merchantKey,
    title: title,
    total: total,
    installmentAmount: installmentAmount,
    anchorNumber: anchorNumber,
    anchorLineDate: anchorLineDate,
    anchorDueDate: anchorDueDate,
    destination: destination ?? this.destination,
    categoryId: categoryId ?? this.categoryId,
    assignedMemberId: clearAssignedMember
        ? null
        : (assignedMemberId ?? this.assignedMemberId),
    parcels: parcels,
    importedNumbers: importedNumbers,
  );
}

/// Despesa que passa a ser (ou continua sendo) a parcela [number] do plano.
class InstallmentLink {
  final String expenseId;
  final String planId;
  final int number;
  final bool isForecast;

  const InstallmentLink({
    required this.expenseId,
    required this.planId,
    required this.number,
    this.isForecast = false,
  });
}

/// [date] [months] meses depois (ou antes), no mesmo dia ou no último do mês.
DateTime addMonths(DateTime date, int months) {
  final firstOfTarget = DateTime(date.year, date.month + months);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  return DateTime(
    firstOfTarget.year,
    firstOfTarget.month,
    date.day > lastDay ? lastDay : date.day,
    date.hour,
    date.minute,
  );
}
