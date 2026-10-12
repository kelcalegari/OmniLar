import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/data/repositories/p2p_repository_impl.dart';
import 'package:omni_lar/features/shopping/data/datasources/mock_shopping_datasource.dart';
import 'package:omni_lar/features/shopping/data/repositories/shopping_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/services/credit_card_invoice_calculator.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_item.dart';

void main() {
  group('Shopping Module - Regras de Negócio (RN03, RN10, RN06)', () {
    late MockFinanceDataSource financeDataSource;
    late FinanceRepositoryImpl financeRepo;
    late MockP2PDataSource p2pDataSource;
    late P2PRepositoryImpl p2pRepo;
    late MockShoppingDataSource shoppingDataSource;
    late ShoppingRepositoryImpl shoppingRepo;

    setUp(() {
      financeDataSource = MockFinanceDataSource();
      financeRepo = FinanceRepositoryImpl(financeDataSource);
      p2pDataSource = MockP2PDataSource();
      p2pRepo = P2PRepositoryImpl(p2pDataSource);
      shoppingDataSource = MockShoppingDataSource(
        financeRepository: financeRepo,
        p2pRepository: p2pRepo,
      );
      shoppingRepo = ShoppingRepositoryImpl(shoppingDataSource);
    });

    test('RN03: Adicionar item com mesmo nome em pendente soma quantidade', () async {
      final initialItems = await shoppingRepo.getItems('list_mercado');
      final cafeItem = initialItems.firstWhere((i) => i.name.toLowerCase() == 'café em grãos');
      final initialQuantity = cafeItem.quantity; // 2.0

      // Adiciona mais 3 cafés em grãos
      await shoppingRepo.addItem(
        const ShoppingItem(
          id: 'temp_id',
          listId: 'list_mercado',
          name: 'café em grãos',
          quantity: 3,
        ),
      );

      final updatedItems = await shoppingRepo.getItems('list_mercado');
      final updatedCafe = updatedItems.firstWhere((i) => i.name.toLowerCase() == 'café em grãos');

      // Quantidade deve ter sido somada para 5.0 sem duplicar a linha
      expect(updatedCafe.quantity, equals(initialQuantity + 3));
      final allCafeOccurrences = updatedItems.where((i) => i.name.toLowerCase() == 'café em grãos').toList();
      expect(allCafeOccurrences.length, equals(1));
    });

    test('RN10: Alternar status de comprado (isBought)', () async {
      final initialItems = await shoppingRepo.getItems('list_mercado');
      final banana = initialItems.firstWhere((i) => i.name == 'Banana Prata');
      expect(banana.isBought, isFalse);

      await shoppingRepo.toggleItemBought(banana.id);

      final updatedItems = await shoppingRepo.getItems('list_mercado');
      final updatedBanana = updatedItems.firstWhere((i) => i.id == banana.id);
      expect(updatedBanana.isBought, isTrue);
    });

    test('RN06: Finalização de compra gera Despesa da Casa e Empréstimo P2P para itens pessoais', () async {
      // Temos itens comprados na lista inicial:
      // item_2: Leite Integral (R$ 29,90) - da casa
      // Vamos marcar item_4: Shampoo Especial (R$ 35,00) - pessoal da Marina como comprado
      await shoppingRepo.toggleItemBought('item_4');

      final invoiceDueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: DateTime.now(),
        closingDay: 28,
        dueDay: 5,
      );
      final expenseCycle = FinancialCycle.fromDate(date: invoiceDueDate, cycleStartDay: 5);
      final initialExpenses = await financeRepo.getExpensesForCycle(expenseCycle);
      final initialExpensesCount = initialExpenses.length;
      final initialLoans = await p2pRepo.getLoans();
      final initialLoansCount = initialLoans.length;

      // Carlos finaliza a compra pagando R$ 80,00 no caixa com Cartão
      await shoppingRepo.completeTrip(
        listId: 'list_mercado',
        totalAmount: const Money(8000), // R$ 80,00
        paymentMethodId: 'pm_card_carlos',
        paidByMemberId: 'member_carlos',
        personalItemsAmount: const Money(3500),
        personalDebtorMemberId: 'member_marina',
      );

      // Verifica que uma nova despesa da casa foi criada
      final updatedExpenses = await financeRepo.getExpensesForCycle(expenseCycle);
      expect(updatedExpenses.length, equals(initialExpensesCount + 1));
      final tripExpense = updatedExpenses.first;
      expect(tripExpense.paidByMemberId, equals('member_carlos'));

      // Verifica que um empréstimo P2P foi gerado para a Marina pagar o Carlos
      final updatedLoans = await p2pRepo.getLoans();
      expect(updatedLoans.length, equals(initialLoansCount + 1));
      final generatedLoan = updatedLoans.first;
      expect(generatedLoan.lenderMemberId, equals('member_carlos'));
      expect(generatedLoan.borrowerMemberId, equals('member_marina'));
      expect(generatedLoan.totalAmount.cents, equals(3500));
    });
  });
}
