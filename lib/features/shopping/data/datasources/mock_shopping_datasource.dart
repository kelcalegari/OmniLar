import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../p2p/domain/services/p2p_calculator.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';

class MockShoppingDataSource {
  final FinanceRepository financeRepository;
  final P2PRepository p2pRepository;

  final List<ShoppingList> _lists = [
    const ShoppingList(
      id: 'list_mercado',
      name: 'Supermercado & Feira',
      icon: 'shopping_cart_outlined',
      isDefault: true,
    ),
    const ShoppingList(
      id: 'list_farmacia',
      name: 'Farmácia',
      icon: 'local_pharmacy_outlined',
    ),
  ];

  final List<ShoppingItem> _items = [
    const ShoppingItem(
      id: 'item_1',
      listId: 'list_mercado',
      name: 'Café em Grãos',
      quantity: 2,
      unit: 'pct',
      category: 'Mercearia',
      isBought: false,
      estimatedPrice: Money(4500),
    ),
    const ShoppingItem(
      id: 'item_2',
      listId: 'list_mercado',
      name: 'Leite Integral',
      quantity: 6,
      unit: 'l',
      category: 'Laticínios',
      isBought: true,
      boughtBy: 'member_carlos',
      estimatedPrice: Money(2990),
    ),
    const ShoppingItem(
      id: 'item_3',
      listId: 'list_mercado',
      name: 'Banana Prata',
      quantity: 1.5,
      unit: 'kg',
      category: 'Hortifruti',
      isBought: false,
      estimatedPrice: Money(1200),
    ),
    const ShoppingItem(
      id: 'item_4',
      listId: 'list_mercado',
      name: 'Shampoo Especial',
      quantity: 1,
      unit: 'un',
      category: 'Higiene',
      isPersonal: true,
      assignedMemberId: 'member_marina',
      isBought: false,
      estimatedPrice: Money(3500),
    ),
  ];

  final List<ShoppingTrip> _trips = [];

  MockShoppingDataSource({
    required this.financeRepository,
    required this.p2pRepository,
  });

  Future<List<ShoppingList>> getLists() async => List.unmodifiable(_lists);

  Future<List<ShoppingItem>> getItems(String listId) async {
    return _items.where((i) => i.listId == listId).toList();
  }

  // RN03: Se o item já existir como pendente, soma a quantidade
  Future<void> addItem(ShoppingItem item) async {
    final existingIndex = _items.indexWhere(
      (i) =>
          i.listId == item.listId &&
          !i.isBought &&
          i.name.trim().toLowerCase() == item.name.trim().toLowerCase(),
    );

    if (existingIndex != -1) {
      final existing = _items[existingIndex];
      _items[existingIndex] = existing.copyWith(
        quantity: existing.quantity + item.quantity,
      );
    } else {
      _items.insert(0, item);
    }
  }

  Future<void> toggleItemBought(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      final item = _items[index];
      final newBought = !item.isBought;
      _items[index] = item.copyWith(
        isBought: newBought,
        boughtAt: newBought ? DateTime.now() : null,
      );
    }
  }

  Future<void> deleteItem(String itemId) async {
    _items.removeWhere((i) => i.id == itemId);
  }

  // RN06: Encerramento com integração ao Caixa da Casa e Empréstimos P2P
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  }) async {
    final now = DateTime.now();

    // 1. Desconta itens pessoais do gasto coletivo da casa
    final personalCents = personalItemsAmount?.cents ?? 0;
    final houseExpensesCents = (totalAmount.cents - personalCents).clamp(0, totalAmount.cents);
    final houseExpenseAmount = Money(houseExpensesCents);

    String? createdExpenseId;
    if (houseExpenseAmount.cents > 0) {
      createdExpenseId = 'exp_shop_${now.millisecondsSinceEpoch}';
      final members = await financeRepository.getMembers();
      final splitPercentages = {
        for (final m in members) m.id: m.defaultSplitPercent > 0 ? m.defaultSplitPercent : (100.0 / members.length),
      };

      await financeRepository.addExpense(
        HouseExpense(
          id: createdExpenseId,
          title: 'Compras de Mercado',
          amount: houseExpenseAmount,
          date: now,
          categoryId: 'cat_mercado',
          paidByMemberId: paidByMemberId,
          paymentMethodId: paymentMethodId,
          splitRule: SplitRule.percentage(splitPercentages),
        ),
      );
    }

    // 2. Cria empréstimo P2P para itens pessoais de outro membro
    String? createdLoanId;
    if (personalCents > 0 &&
        personalDebtorMemberId != null &&
        personalDebtorMemberId != paidByMemberId) {
      createdLoanId = 'loan_shop_${now.millisecondsSinceEpoch}';
      final personalTotal = Money(personalCents);
      final installments = P2PCalculator.generateInstallments(
        loanId: createdLoanId,
        totalAmount: personalTotal,
        installmentsCount: 1,
        firstDueDate: now.add(const Duration(days: 30)),
      );

      await p2pRepository.createLoan(
        P2PLoan(
          id: createdLoanId,
          title: 'Item Pessoal na Compra de Mercado',
          description: 'Comprado junto com a feira/mercado da casa',
          totalAmount: personalTotal,
          lenderMemberId: paidByMemberId,
          borrowerMemberId: personalDebtorMemberId,
          installmentsCount: 1,
          createdAt: now,
          firstDueDate: installments.first.dueDate,
          installments: installments,
        ),
      );
    }

    final trip = ShoppingTrip(
      id: 'trip_${now.millisecondsSinceEpoch}',
      listId: listId,
      totalAmount: totalAmount,
      paymentMethodId: paymentMethodId,
      houseExpenseId: createdExpenseId,
      p2pLoanId: createdLoanId,
      completedAt: now,
    );

    _trips.insert(0, trip);

    // Remove os itens comprados desta lista para a próxima compra
    _items.removeWhere((i) => i.listId == listId && i.isBought);

    return trip;
  }
}
