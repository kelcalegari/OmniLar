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

  /// Parcelas da Casa, pelo número, a partir da [firstNumber].
  final List<HouseExpense> expenses;
  final List<P2PLoan> loans;

  /// Primeira parcela lançada: numa compra já em andamento, as de antes
  /// ficam de fora.
  final int firstNumber;

  const InstallmentPurchase({
    required this.plan,
    this.expenses = const [],
    this.loans = const [],
    this.firstNumber = 1,
  });

  /// Monta a compra de [total] em [count] vezes no cartão [card]. As parcelas
  /// caem uma por fatura, a partir da fatura da [purchaseDate]; o centavo que
  /// sobra da divisão fica nas primeiras, como fazem os bancos.
  ///
  /// Com [debtorMemberId], a compra é do morador: no cartão de um morador
  /// vira um empréstimo do dono com [count] parcelas; no da Casa, um
  /// empréstimo por fatura, cada um saindo do Caixa do ciclo em que ela vence.
  /// A compra à vista do morador é a de [count] 1: um empréstimo só, e o
  /// plano de 1 parcela faz a fatura reconhecer a linha.
  ///
  /// Compra já em andamento: [firstNumber] é a próxima parcela que vem. As
  /// faturas continuam contadas da [purchaseDate] (a parcela 2 vem um mês
  /// depois da 1), e só entram as parcelas de [firstNumber] em diante.
  static InstallmentPurchase build({
    required String title,
    required Money total,
    required int count,
    required DateTime purchaseDate,
    required PaymentMethod card,
    required String categoryId,
    required String paidByMemberId,
    required SplitRule splitRule,
    int firstNumber = 1,
    String? debtorMemberId,
    String? debtorName,
    String? createdBy,
    DateTime? now,
    String Function() newId = generateUuidV4,
  }) {
    // À vista (1 vez) só para o morador: a da Casa é uma despesa comum
    if (count < (debtorMemberId == null ? 2 : 1) || count > 99) {
      throw ArgumentError('A compra parcelada tem de 2 a 99 parcelas.');
    }
    if (firstNumber < 1 || firstNumber > count) {
      throw ArgumentError('A próxima parcela fica entre 1 e $count.');
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
    final numbers = [for (var n = firstNumber; n <= count; n++) n];
    final forDebtor = debtorMemberId != null;
    final planId = newId();
    final plan = InstallmentPlan(
      id: planId,
      paymentMethodId: card.id,
      merchantKey: InstallmentMatcher.merchantKeyOf(title),
      title: title,
      total: count,
      installmentAmount: parts.first,
      anchorNumber: firstNumber,
      anchorLineDate: purchaseDate,
      anchorDueDate: addMonths(firstDue, firstNumber - 1),
      destination: forDebtor ? LineDestination.splitP2P : LineDestination.house,
      categoryId: forDebtor ? null : categoryId,
      assignedMemberId: debtorMemberId,
      origin: InstallmentPlanOrigin.manual,
    );

    if (!forDebtor) {
      return InstallmentPurchase(
        plan: plan,
        firstNumber: firstNumber,
        expenses: [
          for (final number in numbers)
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
              installmentPlanId: planId,
            ),
        ],
      );
    }

    final createdAt = now ?? DateTime.now();
    final lender = card.ownerMemberId ?? P2PLoan.houseLenderId;
    final who = debtorName == null ? '' : ' — $debtorName';
    final upfront = count == 1;
    if (lender != P2PLoan.houseLenderId) {
      final remaining = numbers.fold<int>(0, (acc, n) => acc + parts[n - 1].cents);
      return InstallmentPurchase(
        plan: plan,
        firstNumber: firstNumber,
        loans: [
          P2PLoan(
            id: newId(),
            title: upfront
                ? '$title (à vista no ${card.name})$who'
                : firstNumber == 1
                ? '$title ($count× no ${card.name})$who'
                : '$title (parcelas $firstNumber a $count no ${card.name})$who',
            description: upfront
                ? 'Compra à vista no ${card.name}'
                : 'Compra parcelada em $count vezes no ${card.name}',
            totalAmount: Money(remaining),
            lenderMemberId: lender,
            borrowerMemberId: debtorMemberId,
            installmentsCount: numbers.length,
            createdAt: createdAt,
            // Quem deve paga cada parcela junto com a fatura dela
            firstDueDate: addMonths(firstDue, firstNumber - 1),
            installmentPlanIds: [planId],
          ),
        ],
      );
    }
    return InstallmentPurchase(
      plan: plan,
      firstNumber: firstNumber,
      loans: [
        for (final number in numbers)
          P2PLoan(
            id: newId(),
            title: upfront ? '$title (à vista no ${card.name})$who' : '$title ($number/$count)$who',
            description: upfront
                ? 'Compra à vista no ${card.name}'
                : 'Parcela $number de $count no ${card.name}',
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
