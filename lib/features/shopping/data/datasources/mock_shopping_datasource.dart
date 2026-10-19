import '../../../finance/domain/services/expense_launch_defaults.dart';
import 'dart:async';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/import_params.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../p2p/domain/services/p2p_calculator.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';
import 'shopping_datasource.dart';

class MockShoppingDataSource implements ShoppingDataSource {
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
      isBought: false,
      estimatedPrice: Money(4500),
    ),
    const ShoppingItem(
      id: 'item_2',
      listId: 'list_mercado',
      name: 'Leite Integral',
      quantity: 6,
      unit: 'l',
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
      isBought: false,
      estimatedPrice: Money(1200),
    ),
    const ShoppingItem(
      id: 'item_4',
      listId: 'list_mercado',
      name: 'Shampoo Especial',
      quantity: 1,
      unit: 'un',
      isPersonal: true,
      assignedMemberId: 'member_marina',
      isBought: false,
      estimatedPrice: Money(3500),
    ),
  ];

  final List<ShoppingTrip> _trips = [];
  final StreamController<List<ShoppingItem>> _itemsController =
      StreamController<List<ShoppingItem>>.broadcast();

  MockShoppingDataSource({
    required this.financeRepository,
    required this.p2pRepository,
  });

  void _notifyItems(String listId) {
    if (!_itemsController.isClosed) {
      _itemsController.add(_items.where((i) => i.listId == listId).toList());
    }
  }

  @override
  Future<List<ShoppingList>> getLists() async => List.unmodifiable(_lists);

  @override
  Future<List<ShoppingItem>> getItems(String listId) async {
    return _items.where((i) => i.listId == listId).toList();
  }

  @override
  Stream<List<ShoppingItem>> watchItems(String listId) async* {
    yield _items.where((i) => i.listId == listId).toList();
    yield* _itemsController.stream;
  }

  // RN03: Se o item já existir como pendente, soma a quantidade
  @override
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
    _notifyItems(item.listId);
  }

  @override
  Future<void> toggleItemBought(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      final item = _items[index];
      final newBought = !item.isBought;
      _items[index] = item.copyWith(
        isBought: newBought,
        boughtAt: newBought ? DateTime.now() : null,
      );
      _notifyItems(item.listId);
    }
  }

  @override
  Future<void> setItemBought(String itemId, {required bool bought, DateTime? at}) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    final item = _items[index];
    _items[index] = item.copyWith(isBought: bought, boughtAt: bought ? (at ?? DateTime.now()) : null);
    _notifyItems(item.listId);
  }

  @override
  Future<void> updateItem(ShoppingItem item) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    _items[index] = item;
    _notifyItems(item.listId);
  }

  @override
  Future<void> deleteItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      final listId = _items[index].listId;
      _items.removeAt(index);
      _notifyItems(listId);
    }
  }

  // RN06: Encerramento com integração ao Caixa da Casa e Empréstimos P2P
  @override
  Future<void> updateListDefaults(String listId, {String? categoryId, required ImportSplitMode splitMode}) async {
    final index = _lists.indexWhere((l) => l.id == listId);
    if (index < 0) return;
    _lists[index] = _lists[index].copyWith(
      defaultCategoryId: categoryId,
      clearDefaultCategory: categoryId == null,
      defaultSplitMode: splitMode,
    );
  }

  @override
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    String? paymentMethodId,
    String? paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  }) async {
    final now = DateTime.now();

    // 1. Desconta itens pessoais do gasto coletivo da casa
    final personalCents = personalItemsAmount?.cents ?? 0;
    final houseExpensesCents = (totalAmount.cents - personalCents).clamp(0, totalAmount.cents);
    final houseExpenseAmount = Money(houseExpensesCents);
    final members = await financeRepository.getMembers();

    String? createdExpenseId;
    if (houseExpenseAmount.cents > 0) {
      createdExpenseId = 'exp_shop_${now.millisecondsSinceEpoch}';
      final splitPercentages = {
        for (final m in members) m.id: m.defaultSplitPercent > 0 ? m.defaultSplitPercent : (100.0 / members.length),
      };

      final effectivePayerId = paidByMemberId ?? (members.isNotEmpty ? members.first.id : 'member_carlos');
      final paymentMethods = await financeRepository.getPaymentMethods();
      final effectivePmId = paymentMethodId ?? (paymentMethods.isNotEmpty ? paymentMethods.first.id : 'pm_cash');
      final paymentMethod = paymentMethods.where((p) => p.id == effectivePmId).firstOrNull;
      final waitsForInvoice = ExpenseLaunchDefaults.waitsForInvoice(paymentMethod);
      // Padrões da lista (0101); sem escolha, a divisão e a categoria de sempre
      final list = _lists.where((l) => l.id == listId).firstOrNull;
      final hasListDefaults =
          list != null && (list.defaultCategoryId != null || list.defaultSplitMode != ImportSplitMode.category);
      final category = hasListDefaults
          ? ExpenseLaunchDefaults.matchCategory(
              await financeRepository.getCategories(),
              preferred: list.defaultCategoryId,
              nameKeywords: const ['mercado'],
            )
          : null;
      await financeRepository.addExpense(
        HouseExpense(
          id: createdExpenseId,
          title: 'Compras de Mercado',
          amount: houseExpenseAmount,
          date: now,
          categoryId: category?.id ?? 'cat_mercado',
          paidByMemberId: effectivePayerId,
          paymentMethodId: effectivePmId,
          paidOutOfPocket: !waitsForInvoice,
          status: waitsForInvoice ? ExpenseStatus.pending : ExpenseStatus.paid,
          splitRule: hasListDefaults
              ? ExpenseLaunchDefaults.splitRuleForMode(
                  mode: list.defaultSplitMode,
                  category: category,
                  members: members,
                  paidByMemberId: effectivePayerId,
                )
              : SplitRule.percentage(splitPercentages),
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
          lenderMemberId: paidByMemberId ?? (members.isNotEmpty ? members.first.id : 'member_carlos'),
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
    _notifyItems(listId);

    return trip;
  }
}
