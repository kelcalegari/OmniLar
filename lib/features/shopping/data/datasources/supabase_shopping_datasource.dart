import '../../../../core/utils/uuid.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../p2p/domain/services/p2p_calculator.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';
import 'shopping_datasource.dart';

class SupabaseShoppingDataSource implements ShoppingDataSource {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;
  final FinanceRepository financeRepository;
  final P2PRepository p2pRepository;

  SupabaseShoppingDataSource({
    required this.client,
    required this.getCurrentHouseId,
    required this.financeRepository,
    required this.p2pRepository,
  });

  String get _houseId => getCurrentHouseId();

  bool _isUuid(String id) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(id);
  }

  @override
  Future<List<ShoppingList>> getLists() async {
    try {
      final rows = await client
          .from('shopping_lists')
          .select()
          .eq('house_id', _houseId)
          .order('created_at', ascending: true);

      if (rows.isEmpty) {
        final userId = client.auth.currentUser?.id;
        final defaultListRow = {
          'house_id': _houseId,
          'name': 'Supermercado & Feira',
          'icon': 'shopping_cart_outlined',
          'is_default': true,
          'created_by': ?userId,
        };

        final created = await client
            .from('shopping_lists')
            .insert(defaultListRow)
            .select()
            .single();

        return [
          ShoppingList(
            id: created['id'] as String,
            name: created['name'] as String,
            icon: created['icon'] as String? ?? 'shopping_cart_outlined',
            isDefault: true,
          ),
        ];
      }

      return rows.map((r) {
        return ShoppingList(
          id: r['id'] as String,
          name: r['name'] as String,
          icon: r['icon'] as String? ?? 'shopping_cart_outlined',
          isDefault: (r['is_default'] as bool?) ?? false,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar listas de compras: $e');
    }
  }

  @override
  Future<List<ShoppingItem>> getItems(String listId) async {
    try {
      final rows = await client
          .from('shopping_items')
          .select('*, category:categories(name)')
          .eq('list_id', listId)
          .order('created_at', ascending: false);

      return rows.map((r) {
        final categoryMap = r['category'] as Map<String, dynamic>?;
        final categoryName = categoryMap?['name'] as String? ?? 'Geral';
        final estCents = r['estimated_cents'] as int?;
        final actCents = r['actual_cents'] as int?;

        return ShoppingItem(
          id: r['id'] as String,
          listId: r['list_id'] as String,
          name: r['name'] as String,
          quantity: (r['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: r['unit'] as String? ?? 'un',
          category: categoryName,
          isPersonal: (r['is_personal'] as bool?) ?? false,
          assignedMemberId: r['assigned_member_id'] as String?,
          isBought: (r['is_bought'] as bool?) ?? false,
          estimatedPrice: estCents != null ? Money(estCents) : null,
          actualPrice: actCents != null ? Money(actCents) : null,
          boughtBy: r['bought_by'] as String?,
          boughtAt: r['bought_at'] != null ? DateTime.tryParse(r['bought_at'] as String)?.toLocal() : null,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar itens da lista de compras: $e');
    }
  }

  @override
  Stream<List<ShoppingItem>> watchItems(String listId) {
    return client
        .from('shopping_items')
        .stream(primaryKey: ['id'])
        .eq('list_id', listId)
        .order('created_at', ascending: false)
        .map((rows) {
          return rows.map((r) {
            final estCents = r['estimated_cents'] as int?;
            final actCents = r['actual_cents'] as int?;

            return ShoppingItem(
              id: r['id'] as String,
              listId: r['list_id'] as String,
              name: r['name'] as String,
              quantity: (r['quantity'] as num?)?.toDouble() ?? 1.0,
              unit: r['unit'] as String? ?? 'un',
              category: (r['category_name'] as String?) ?? 'Geral',
              isPersonal: (r['is_personal'] as bool?) ?? false,
              assignedMemberId: r['assigned_member_id'] as String?,
              isBought: (r['is_bought'] as bool?) ?? false,
              estimatedPrice: estCents != null ? Money(estCents) : null,
              actualPrice: actCents != null ? Money(actCents) : null,
              boughtBy: r['bought_by'] as String?,
              boughtAt: r['bought_at'] != null ? DateTime.tryParse(r['bought_at'] as String)?.toLocal() : null,
            );
          }).toList();
        });
  }

  @override
  Future<void> addItem(ShoppingItem item) async {
    try {
      // RN03: Se o item já existir como pendente, soma a quantidade
      final existing = await client
          .from('shopping_items')
          .select('id, quantity')
          .eq('list_id', item.listId)
          .eq('is_bought', false)
          .ilike('name', item.name.trim());

      if (existing.isNotEmpty) {
        final existingItem = existing.first;
        final currentQty = (existingItem['quantity'] as num).toDouble();
        final newQty = currentQty + item.quantity;
        await client
            .from('shopping_items')
            .update({'quantity': newQty})
            .eq('id', existingItem['id']);
      } else {
        final userId = client.auth.currentUser?.id;
        final itemRow = {
          if (_isUuid(item.id)) 'id': item.id,
          'list_id': item.listId,
          'house_id': _houseId,
          'name': item.name.trim(),
          'quantity': item.quantity,
          'unit': item.unit,
          'is_personal': item.isPersonal,
          'assigned_member_id': item.assignedMemberId,
          'estimated_cents': item.estimatedPrice?.cents,
          'actual_cents': item.actualPrice?.cents,
          'is_bought': item.isBought,
          'bought_by': item.boughtBy,
          'bought_at': item.boughtAt?.toUtc().toIso8601String(),
          'created_by': ?userId,
        };

        await client.from('shopping_items').insert(itemRow);
      }
    } catch (e) {
      throw ServerFailure('Erro ao adicionar item na lista de compras: $e');
    }
  }

  @override
  Future<void> toggleItemBought(String itemId) async {
    try {
      final itemRow = await client
          .from('shopping_items')
          .select('is_bought')
          .eq('id', itemId)
          .single();

      final currentlyBought = (itemRow['is_bought'] as bool?) ?? false;
      final newBought = !currentlyBought;
      final userId = client.auth.currentUser?.id;

      await client.from('shopping_items').update({
        'is_bought': newBought,
        'bought_by': newBought ? userId : null,
        'bought_at': newBought ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', itemId);
    } catch (e) {
      throw ServerFailure('Erro ao alternar status do item de compras: $e');
    }
  }

  @override
  Future<void> updateItem(ShoppingItem item) async {
    try {
      await client.from('shopping_items').update({
        'name': item.name.trim(),
        'quantity': item.quantity,
        'is_personal': item.isPersonal,
      }).eq('id', item.id);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar item da lista de compras: $e');
    }
  }

  @override
  Future<void> deleteItem(String itemId) async {
    try {
      await client.from('shopping_items').delete().eq('id', itemId);
    } catch (e) {
      throw ServerFailure('Erro ao remover item da lista de compras: $e');
    }
  }

  @override
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  }) async {
    try {
      final now = DateTime.now();

      // 1. Desconta itens pessoais do gasto coletivo da casa
      final personalCents = personalItemsAmount?.cents ?? 0;
      final houseExpensesCents = (totalAmount.cents - personalCents).clamp(0, totalAmount.cents);
      final houseExpenseAmount = Money(houseExpensesCents);

      String? createdExpenseId;
      if (houseExpenseAmount.cents > 0) {
        // Id real desde já, para a viagem de compras apontar para a despesa
        createdExpenseId = generateUuidV4();
        final members = await financeRepository.getMembers();
        final category = ExpenseLaunchDefaults.matchCategory(
          await financeRepository.getCategories(),
          nameKeywords: const ['mercado'],
        );
        final paymentMethod = (await financeRepository.getPaymentMethods())
            .where((pm) => pm.id == paymentMethodId)
            .firstOrNull;

        await financeRepository.addExpense(
          HouseExpense(
            id: createdExpenseId,
            title: 'Compras de Mercado',
            amount: houseExpenseAmount,
            date: now,
            categoryId: category?.id ?? 'cat_mercado',
            paidByMemberId: paidByMemberId,
            paymentMethodId: paymentMethodId,
            paidOutOfPocket: ExpenseLaunchDefaults.paidOutOfPocket(paymentMethod),
            splitRule: ExpenseLaunchDefaults.splitRule(
              category: category,
              members: members,
              paidByMemberId: paidByMemberId,
            ),
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

      // 3. Registra a viagem de compras na tabela shopping_trips
      final userId = client.auth.currentUser?.id;
      final tripRow = {
        'house_id': _houseId,
        'list_id': listId,
        'total_spent_cents': totalAmount.cents,
        'expense_id': (createdExpenseId != null && _isUuid(createdExpenseId)) ? createdExpenseId : null,
        'created_by': ?userId,
        'completed_at': now.toUtc().toIso8601String(),
      };

      final insertedTrip = await client
          .from('shopping_trips')
          .insert(tripRow)
          .select('id')
          .single();

      final tripId = insertedTrip['id'] as String;

      // 4. Remove os itens comprados desta lista para a próxima compra
      await client
          .from('shopping_items')
          .delete()
          .eq('list_id', listId)
          .eq('is_bought', true);

      return ShoppingTrip(
        id: tripId,
        listId: listId,
        totalAmount: totalAmount,
        paymentMethodId: paymentMethodId,
        houseExpenseId: createdExpenseId,
        p2pLoanId: createdLoanId,
        completedAt: now,
      );
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao finalizar compra no supermercado: $e');
    }
  }
}
