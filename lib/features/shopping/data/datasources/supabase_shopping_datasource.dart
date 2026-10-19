import '../../../finance/data/datasources/house_expense_payload.dart';
import '../../../finance/domain/services/credit_card_invoice_calculator.dart';
import '../../../p2p/data/datasources/p2p_loan_payload.dart';
import '../../../../core/utils/uuid.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../finance/domain/entities/import_params.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';
import 'shopping_datasource.dart';
import '../../../../core/offline/offline_snapshot.dart';

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
      final rows = await OfflineSnapshot.instance.rows(
        'shopping_lists_$_houseId',
        () async => await client
            .from('shopping_lists')
            .select()
            .eq('house_id', _houseId)
            .order('created_at', ascending: true),
      );

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
          defaultCategoryId: r['default_category_id'] as String?,
          defaultSplitMode: ImportSplitMode.fromDb(r['default_split_mode']),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar listas de compras: $e');
    }
  }

  @override
  Future<List<ShoppingItem>> getItems(String listId) async {
    try {
      final rows = await OfflineSnapshot.instance.rows(
        'shopping_items_$listId',
        () async => await client
            .from('shopping_items')
            .select()
            .eq('list_id', listId)
            .order('created_at', ascending: false),
      );

      return rows.map((r) {
        final estCents = r['estimated_cents'] as int?;
        final actCents = r['actual_cents'] as int?;

        return ShoppingItem(
          id: r['id'] as String,
          listId: r['list_id'] as String,
          name: r['name'] as String,
          quantity: (r['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: r['unit'] as String? ?? 'un',
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
  Future<void> setItemBought(String itemId, {required bool bought, DateTime? at}) async {
    try {
      await client.from('shopping_items').update({
        'is_bought': bought,
        'bought_by': bought ? client.auth.currentUser?.id : null,
        'bought_at': bought ? (at ?? DateTime.now()).toUtc().toIso8601String() : null,
      }).eq('id', itemId);
    } catch (e) {
      throw ServerFailure('Erro ao marcar item de compras: $e');
    }
  }

  @override
  Future<void> updateItem(ShoppingItem item) async {
    try {
      await client.from('shopping_items').update({
        'name': item.name.trim(),
        'quantity': item.quantity,
        'unit': item.unit,
        'is_personal': item.isPersonal,
      }).eq('id', item.id);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar item da lista de compras: $e');
    }
  }

  @override
  Future<void> updateListDefaults(
    String listId, {
    String? categoryId,
    required ImportSplitMode splitMode,
  }) async {
    try {
      await client.from('shopping_lists').update({
        'default_category_id': categoryId,
        'default_split_mode': splitMode == ImportSplitMode.category ? null : splitMode.dbValue,
      }).eq('id', listId).eq('house_id', _houseId);
    } catch (e) {
      throw ServerFailure('Erro ao salvar os padrões da lista de compras: $e');
    }
  }

  /// Categoria e divisão padrão da lista (0101); banco sem a 0101 ou lista sem
  /// escolha vale o de sempre.
  Future<({String? categoryId, ImportSplitMode splitMode})> _listDefaults(String listId) async {
    try {
      final row = await client
          .from('shopping_lists')
          .select('default_category_id, default_split_mode')
          .eq('id', listId)
          .maybeSingle();
      return (
        categoryId: row?['default_category_id'] as String?,
        splitMode: ImportSplitMode.fromDb(row?['default_split_mode']),
      );
    } catch (_) {
      return (categoryId: null, splitMode: ImportSplitMode.category);
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

      Map<String, dynamic>? expensePayload;
      String? createdExpenseId;
      if (houseExpenseAmount.cents > 0) {
        // Id real desde já, para a viagem de compras apontar para a despesa
        createdExpenseId = generateUuidV4();
        final members = await financeRepository.getMembers();
        final listDefaults = await _listDefaults(listId);
        // Categoria escolhida na lista; sem ela (ou se foi apagada), a de mercado
        final category = ExpenseLaunchDefaults.matchCategory(
          await financeRepository.getCategories(),
          preferred: listDefaults.categoryId,
          nameKeywords: const ['mercado'],
        );
        final paymentMethod = (await financeRepository.getPaymentMethods())
            .where((pm) => pm.id == paymentMethodId)
            .firstOrNull;

        // Compra no cartão vence com a fatura, como em qualquer outro lançamento
        DateTime? dueDate;
        if (paymentMethod != null &&
            paymentMethod.isCreditCard &&
            paymentMethod.closingDay != null &&
            paymentMethod.dueDay != null) {
          dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
            purchaseDate: now,
            closingDay: paymentMethod.closingDay!,
            dueDay: paymentMethod.dueDay!,
          );
        }

        expensePayload = houseExpensePayload(
          HouseExpense(
            id: createdExpenseId,
            title: 'Compras de Mercado',
            amount: houseExpenseAmount,
            date: now,
            categoryId: category?.id ?? 'cat_mercado',
            paidByMemberId: paidByMemberId,
            paymentMethodId: paymentMethodId,
            paidOutOfPocket: ExpenseLaunchDefaults.launchPaidOutOfPocket(paymentMethod),
            status: ExpenseLaunchDefaults.launchStatus(paymentMethod),
            splitRule: ExpenseLaunchDefaults.splitRuleForMode(
              mode: listDefaults.splitMode,
              category: category,
              members: members,
              paidByMemberId: paidByMemberId,
            ),
          ),
          houseId: _houseId,
          currentUserId: client.auth.currentUser?.id,
          dueDate: dueDate,
        );
      }

      // Itens pessoais de outro morador: empréstimo dele para quem pagou
      Map<String, dynamic>? loanPayload;
      String? createdLoanId;
      if (personalCents > 0 &&
          personalDebtorMemberId != null &&
          personalDebtorMemberId != paidByMemberId) {
        createdLoanId = generateUuidV4();
        final personalTotal = Money(personalCents);
        final firstDueDate = now.add(const Duration(days: 30));
        loanPayload = p2pLoanPayload(
          P2PLoan(
            id: createdLoanId,
            title: 'Item Pessoal na Compra de Mercado',
            description: 'Comprado junto com a feira/mercado da casa',
            totalAmount: personalTotal,
            lenderMemberId: paidByMemberId,
            borrowerMemberId: personalDebtorMemberId,
            installmentsCount: 1,
            createdAt: now,
            firstDueDate: firstDueDate,
          ),
          houseId: _houseId,
        );
      }

      // Despesa, empréstimo, registro da viagem e limpeza dos itens comprados
      // entram juntos: ou tudo, ou nada
      final result = await client.rpc('complete_shopping_trip', params: {
        'p_plan': {
          'house_id': _houseId,
          'list_id': listId,
          'total_spent_cents': totalAmount.cents,
          'completed_at': now.toUtc().toIso8601String(),
          'expense': ?expensePayload,
          'loan': ?loanPayload,
        },
      }) as Map<String, dynamic>;
      final tripId = result['trip_id'] as String;

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
