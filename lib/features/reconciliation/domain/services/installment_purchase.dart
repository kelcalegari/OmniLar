import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/utils/uuid.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/services/credit_card_invoice_calculator.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/imported_statement_line.dart';
import '../entities/installment_plan.dart';
import 'installment_matcher.dart';

/// Compra parcelada no cartão lançada à mão, pronta para gravar de uma vez:
/// o plano e as parcelas da Casa (todas previstas, cada fatura confirma a sua)
/// ou os empréstimos do morador que deve a compra.
class InstallmentPurchase {
  final InstallmentPlan plan;

  /// Parcelas da Casa, pelo número (a primeira é a 1).
  final List<HouseExpense> expenses;
  final List<P2PLoan> loans;

  const InstallmentPurchase({
    required this.plan,
    this.expenses = const [],
    this.loans = const [],
  });

  /// Monta a compra de [total] em [count] vezes no cartão [card]. As parcelas
  /// caem uma por fatura, a partir da fatura da [purchaseDate]; o centavo que
  /// sobra da divisão fica nas primeiras, como fazem os bancos.
  ///
  /// Com [debtorMemberId], a compra é do morador: no cartão de um morador
  /// vira um empréstimo do dono com [count] parcelas; no da Casa, um
  /// empréstimo por fatura, cada um saindo do Caixa do ciclo em que ela vence.
  static InstallmentPurchase build({
    required String title,
    required Money total,
    required int count,
    required DateTime purchaseDate,
    required PaymentMethod card,
    required String categoryId,
    required String paidByMemberId,
    required SplitRule splitRule,
    String? debtorMemberId,
    String? debtorName,
    String? createdBy,
    DateTime? now,
    String Function() newId = generateUuidV4,
  }) {
    if (count < 2 || count > 99) {
      throw ArgumentError('A compra parcelada tem de 2 a 99 parcelas.');
    }
    final closingDay = card.closingDay;
    final dueDay = card.dueDay;
    if (!card.isCreditCard || closingDay == null || dueDay == null) {
      throw ArgumentError('O cartão precisa dos dias de fechamento e vencimento.');
    }
    final firstDue = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
      purchaseDate: purchaseDate,
      closingDay: closingDay,
      dueDay: dueDay,
    );
    final parts = total.splitEqually(count);
    final forDebtor = debtorMemberId != null;
    final planId = newId();
    final plan = InstallmentPlan(
      id: planId,
      paymentMethodId: card.id,
      merchantKey: InstallmentMatcher.merchantKeyOf(title),
      title: title,
      total: count,
      installmentAmount: parts.first,
      anchorNumber: 1,
      anchorLineDate: purchaseDate,
      anchorDueDate: firstDue,
      destination: forDebtor ? LineDestination.splitP2P : LineDestination.house,
      categoryId: forDebtor ? null : categoryId,
      assignedMemberId: debtorMemberId,
      origin: InstallmentPlanOrigin.manual,
    );

    if (!forDebtor) {
      return InstallmentPurchase(
        plan: plan,
        expenses: [
          for (var number = 1; number <= count; number++)
            HouseExpense(
              id: newId(),
              title: '$title ($number/$count)',
              amount: parts[number - 1],
              date: addMonths(purchaseDate, number - 1),
              dueDate: addMonths(firstDue, number - 1),
              categoryId: categoryId,
              paidByMemberId: paidByMemberId,
              paymentMethodId: card.id,
              // Pendente até a fatura ser paga: quem pagou se decide no pagamento
              paidOutOfPocket: false,
              splitRule: splitRule,
              status: ExpenseStatus.pending,
              createdBy: createdBy,
              notes: 'Compra parcelada em $count vezes no ${card.name}, lançada à mão',
            ),
        ],
      );
    }

    final createdAt = now ?? DateTime.now();
    final lender = card.ownerMemberId ?? P2PLoan.houseLenderId;
    final who = debtorName == null ? '' : ' — $debtorName';
    if (lender != P2PLoan.houseLenderId) {
      return InstallmentPurchase(
        plan: plan,
        loans: [
          P2PLoan(
            id: newId(),
            title: '$title ($count× no ${card.name})$who',
            description: 'Compra parcelada em $count vezes no ${card.name}',
            totalAmount: total,
            lenderMemberId: lender,
            borrowerMemberId: debtorMemberId,
            installmentsCount: count,
            createdAt: createdAt,
            // Quem deve paga cada parcela junto com a fatura dela
            firstDueDate: firstDue,
            installmentPlanIds: [planId],
          ),
        ],
      );
    }
    return InstallmentPurchase(
      plan: plan,
      loans: [
        for (var number = 1; number <= count; number++)
          P2PLoan(
            id: newId(),
            title: '$title ($number/$count)$who',
            description: 'Parcela $number de $count no ${card.name}',
            totalAmount: parts[number - 1],
            lenderMemberId: lender,
            borrowerMemberId: debtorMemberId,
            installmentsCount: 1,
            createdAt: createdAt,
            firstDueDate: addMonths(firstDue, number - 1),
            // A fatura de cada parcela sai do Caixa do ciclo em que vence
            houseFunding: HouseLoanFunding.cycle,
            fundedOn: addMonths(firstDue, number - 1),
            installmentPlanIds: [planId],
          ),
      ],
    );
  }
}
