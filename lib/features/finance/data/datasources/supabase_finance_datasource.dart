import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/split_rule.dart';
import 'finance_datasource.dart';

class SupabaseFinanceDataSource implements FinanceDataSource {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseFinanceDataSource({
    required this.client,
    required this.getCurrentHouseId,
  });

  String get _houseId => getCurrentHouseId();

  @override
  Future<List<HouseMember>> getMembers() async {
    try {
      final rows = await client
          .from('house_members')
          .select('id, user_id, role, default_split_percent, profile:profiles(full_name, avatar_url)')
          .eq('house_id', _houseId);

      return rows.map((r) {
        final profile = r['profile'] as Map<String, dynamic>?;
        final name = profile?['full_name'] as String? ?? 'Membro';
        final avatar = profile?['avatar_url'] as String?;
        final role = r['role'] as String? ?? 'member';
        final split = (r['default_split_percent'] as num?)?.toDouble() ?? 50.0;

        return HouseMember(
          id: r['user_id'] as String,
          name: name,
          avatarUrl: avatar,
          role: role,
          defaultSplitPercent: split,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar membros da casa: $e');
    }
  }

  @override
  Future<List<ExpenseCategory>> getCategories() async {
    try {
      final rows = await client
          .from('categories')
          .select()
          .eq('house_id', _houseId);

      return rows.map((r) {
        return ExpenseCategory(
          id: r['id'] as String,
          name: r['name'] as String,
          icon: r['icon'] as String? ?? 'category_outlined',
          colorHex: r['color_hex'] as String? ?? '0xFF2196F3',
          ownerMemberId: r['owner_member_id'] as String?,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar categorias: $e');
    }
  }

  @override
  Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      final rows = await client
          .from('payment_methods')
          .select()
          .eq('house_id', _houseId);

      return rows.map((r) {
        final typeStr = r['type'] as String? ?? 'pix';
        PaymentMethodType type;
        switch (typeStr) {
          case 'card':
          case 'credit_card':
            type = PaymentMethodType.card;
            break;
          case 'vr':
            type = PaymentMethodType.vr;
            break;
          case 'va':
            type = PaymentMethodType.va;
            break;
          case 'cash':
            type = PaymentMethodType.cash;
            break;
          case 'account':
            type = PaymentMethodType.account;
            break;
          default:
            type = PaymentMethodType.pix;
        }

        return PaymentMethod(
          id: r['id'] as String,
          name: r['name'] as String,
          type: type,
          ownerMemberId: r['owner_member_id'] as String?,
          closingDay: (r['closing_day'] ?? r['card_closing_day'] as num?)?.toInt(),
          dueDay: (r['due_day'] ?? r['card_due_day'] as num?)?.toInt(),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar métodos de pagamento: $e');
    }
  }

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async {
    try {
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .isFilter('project_id', null)
          .gte('due_date', cycle.startDate.toIso8601String().split('T')[0])
          .lte('due_date', cycle.endDate.toIso8601String().split('T')[0])
          .order('due_date', ascending: false);

      return rows.map((r) => _mapRowToHouseExpense(r)).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar despesas do ciclo: $e');
    }
  }

  @override
  Future<List<HouseExpense>> getExpensesForProject(String projectId) async {
    try {
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .eq('project_id', projectId)
          .order('date', ascending: false);

      return rows.map((r) => _mapRowToHouseExpense(r)).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar despesas do projeto: $e');
    }
  }

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async {
    try {
      final rows = await client
          .from('contributions')
          .select('*, profile:profiles(full_name)')
          .eq('house_id', _houseId)
          .gte('date', cycle.startDate.toIso8601String().split('T')[0])
          .lte('date', cycle.endDate.toIso8601String().split('T')[0]);

      return rows.map((r) {
        return Contribution(
          id: r['id'] as String,
          memberId: r['member_id'] as String,
          amount: Money((r['amount_cents'] as num).toInt()),
          date: DateTime.parse(r['date'] as String),
          paymentMethodId: r['payment_method_id'] as String?,
          proofAttachmentId: r['proof_attachment_id'] as String?,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar aportes: $e');
    }
  }

  @override
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle) async {
    try {
      final expenses = await getExpensesForCycle(cycle);
      final contributions = await getContributionsForCycle(cycle);

      final memberContributions = <String, Money>{};
      int totalContributionsCents = 0;
      for (final c in contributions) {
        totalContributionsCents += c.amount.cents;
        final current = memberContributions[c.memberId]?.cents ?? 0;
        memberContributions[c.memberId] = Money(current + c.amount.cents);
      }

      int totalExpensesPaidCents = 0;
      int committedFutureExpensesCents = 0;
      final memberExpensesPaid = <String, Money>{};

      for (final exp in expenses) {
        if (exp.isPaid) {
          totalExpensesPaidCents += exp.amount.cents;
          final current = memberExpensesPaid[exp.paidByMemberId]?.cents ?? 0;
          memberExpensesPaid[exp.paidByMemberId] = Money(current + exp.amount.cents);
        } else {
          committedFutureExpensesCents += exp.amount.cents;
        }
      }

      final folegoCents = totalContributionsCents - (totalExpensesPaidCents + committedFutureExpensesCents);

      return FinancialCycleSummary(
        cycle: cycle,
        totalContributions: Money(totalContributionsCents),
        totalExpensesPaid: Money(totalExpensesPaidCents),
        committedFutureExpenses: Money(committedFutureExpensesCents),
        folego: Money(folegoCents),
        memberContributions: memberContributions,
        memberExpensesPaid: memberExpensesPaid,
      );
    } catch (e) {
      throw ServerFailure('Erro ao calcular resumo do ciclo: $e');
    }
  }

  @override
  Future<void> addExpense(HouseExpense expense) async {
    try {
      final expenseRow = {
        'id': expense.id,
        'house_id': _houseId,
        'title': expense.title,
        'amount_cents': expense.amount.cents,
        'category_id': expense.categoryId,
        'payment_method_id': expense.paymentMethodId,
        'paid_by_id': expense.paidByMemberId,
        'paid_out_of_pocket': expense.paidOutOfPocket,
        'due_date': (expense.dueDate ?? expense.date).toIso8601String().split('T')[0],
        'date': expense.date.toIso8601String(),
        'cycle_start_date': expense.date.toIso8601String().split('T')[0],
        'split_type': _splitTypeToString(expense.splitRule.type),
        'status': expense.isPaid ? 'paid' : 'pending',
        'is_recurring': expense.isRecurring,
        'is_variable': expense.isVariable,
        'due_day': expense.dueDay,
        'is_active': expense.isActive,
        'recurring_series_id': expense.recurringSeriesId,
        'project_id': expense.projectId,
        'notes': expense.notes,
        'created_by': client.auth.currentUser?.id ?? expense.paidByMemberId,
      };

      await client.from('house_expenses').insert(expenseRow);

      if (expense.items.isNotEmpty) {
        final itemRows = expense.items.map((item) {
          return {
            'id': item.id,
            'expense_id': expense.id,
            'title': item.title,
            'amount_cents': item.amount.cents,
            'category_id': item.categoryId,
            'responsible_member_id': item.responsibleMemberId,
            'split_type': item.splitRule != null ? _splitTypeToString(item.splitRule!.type) : null,
          };
        }).toList();

        await client.from('house_expense_items').insert(itemRows);
      }
    } catch (e) {
      throw ServerFailure('Erro ao adicionar despesa: $e');
    }
  }

  @override
  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await client.from('house_expenses').update({
        'title': expense.title,
        'amount_cents': expense.amount.cents,
        'category_id': expense.categoryId,
        'payment_method_id': expense.paymentMethodId,
        'paid_by_id': expense.paidByMemberId,
        'paid_out_of_pocket': expense.paidOutOfPocket,
        'due_date': (expense.dueDate ?? expense.date).toIso8601String().split('T')[0],
        'status': expense.isPaid ? 'paid' : 'pending',
        'notes': expense.notes,
      }).eq('id', expense.id);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar despesa: $e');
    }
  }

  @override
  Future<void> deleteExpense(
    String expenseId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await client.from('house_expenses').delete().eq('id', expenseId);
    } catch (e) {
      throw ServerFailure('Erro ao excluir despesa: $e');
    }
  }

  @override
  Future<List<HouseExpense>> getRecurringExpenses() async {
    try {
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .eq('is_recurring', true)
          .eq('is_active', true);

      return rows.map((r) => _mapRowToHouseExpense(r)).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar assinaturas recorrentes: $e');
    }
  }

  @override
  Future<void> addContribution(Contribution contribution) async {
    try {
      await client.from('contributions').insert({
        'id': contribution.id,
        'house_id': _houseId,
        'member_id': contribution.memberId,
        'amount_cents': contribution.amount.cents,
        'date': contribution.date.toIso8601String().split('T')[0],
        'cycle_start_date': contribution.date.toIso8601String().split('T')[0],
      });
    } catch (e) {
      throw ServerFailure('Erro ao adicionar aporte: $e');
    }
  }

  @override
  Future<void> addCategory(ExpenseCategory category) async {
    try {
      await client.from('categories').insert({
        'id': category.id,
        'house_id': _houseId,
        'name': category.name,
        'icon': category.icon,
        'color_hex': category.colorHex,
        'owner_member_id': category.ownerMemberId,
      });
    } catch (e) {
      throw ServerFailure('Erro ao criar categoria: $e');
    }
  }

  @override
  Future<void> addPaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await client.from('payment_methods').insert({
        'id': paymentMethod.id,
        'house_id': _houseId,
        'name': paymentMethod.name,
        'type': paymentMethod.type.name,
        'owner_member_id': paymentMethod.ownerMemberId,
        'closing_day': paymentMethod.closingDay,
        'due_day': paymentMethod.dueDay,
        'color_hex': paymentMethod.colorHex,
      });
    } catch (e) {
      throw ServerFailure('Erro ao criar método de pagamento: $e');
    }
  }

  @override
  Future<List<SavingsVault>> getSavingsVaults() async {
    try {
      final rows = await client
          .from('savings_vaults')
          .select()
          .eq('house_id', _houseId)
          .order('created_at', ascending: false);

      return rows.map((r) {
        return SavingsVault(
          id: r['id'] as String,
          name: r['name'] as String,
          targetAmount: Money((r['target_amount_cents'] as num).toInt()),
          currentBalance: Money((r['current_balance_cents'] as num).toInt()),
          icon: r['icon'] as String? ?? 'savings',
          colorHex: r['color_hex'] as String? ?? '#10B981',
          createdAt: DateTime.parse(r['created_at'] as String),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar caixinhas da casa: $e');
    }
  }

  @override
  Future<void> createSavingsVault(SavingsVault vault) async {
    try {
      await client.from('savings_vaults').insert({
        'id': vault.id,
        'house_id': _houseId,
        'name': vault.name,
        'target_amount_cents': vault.targetAmount.cents,
        'current_balance_cents': vault.currentBalance.cents,
        'icon': vault.icon,
        'color_hex': vault.colorHex,
      });
    } catch (e) {
      throw ServerFailure('Erro ao criar caixinha: $e');
    }
  }

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    try {
      await client.from('savings_transactions').insert({
        'vault_id': vaultId,
        'house_id': _houseId,
        'member_id': memberId,
        'type': 'deposit',
        'amount_cents': amount.cents,
        'notes': description,
      });

      final vault = await client.from('savings_vaults').select('current_balance_cents').eq('id', vaultId).single();
      final current = (vault['current_balance_cents'] as num).toInt();
      await client.from('savings_vaults').update({
        'current_balance_cents': current + amount.cents,
      }).eq('id', vaultId);
    } catch (e) {
      throw ServerFailure('Erro ao depositar na caixinha: $e');
    }
  }

  @override
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    try {
      await client.from('savings_transactions').insert({
        'vault_id': vaultId,
        'house_id': _houseId,
        'member_id': memberId,
        'type': 'withdraw',
        'amount_cents': amount.cents,
        'notes': description,
      });

      final vault = await client.from('savings_vaults').select('current_balance_cents').eq('id', vaultId).single();
      final current = (vault['current_balance_cents'] as num).toInt();
      await client.from('savings_vaults').update({
        'current_balance_cents': (current - amount.cents).clamp(0, current),
      }).eq('id', vaultId);
    } catch (e) {
      throw ServerFailure('Erro ao resgatar da caixinha: $e');
    }
  }

  // --- Helpers de Mapeamento ---
  HouseExpense _mapRowToHouseExpense(Map<String, dynamic> r) {
    final rawItems = r['house_expense_items'] as List<dynamic>? ?? [];
    final items = rawItems.map((item) {
      return HouseExpenseItem(
        id: item['id'] as String,
        expenseId: item['expense_id'] as String,
        title: item['title'] as String,
        amount: Money((item['amount_cents'] as num).toInt()),
        categoryId: item['category_id'] as String?,
        responsibleMemberId: item['responsible_member_id'] as String?,
      );
    }).toList();

    final statusStr = r['status'] as String? ?? 'paid';
    final status = statusStr == 'pending' ? ExpenseStatus.pending : ExpenseStatus.paid;

    return HouseExpense(
      id: r['id'] as String,
      title: r['title'] as String,
      amount: Money((r['amount_cents'] as num).toInt()),
      date: DateTime.parse(r['date'] as String? ?? r['created_at'] as String),
      dueDate: r['due_date'] != null ? DateTime.tryParse(r['due_date'] as String) : null,
      categoryId: r['category_id'] as String? ?? 'cat_geral',
      paidByMemberId: r['paid_by_id'] as String,
      paymentMethodId: r['payment_method_id'] as String? ?? 'pm_pix',
      splitRule: const SplitRule.percentage(null),
      status: status,
      isRecurring: r['is_recurring'] as bool? ?? false,
      isVariable: r['is_variable'] as bool? ?? false,
      dueDay: (r['due_day'] as num?)?.toInt(),
      isActive: r['is_active'] as bool? ?? true,
      paidOutOfPocket: r['paid_out_of_pocket'] as bool? ?? false,
      notes: r['notes'] as String?,
      items: items,
      recurringSeriesId: r['recurring_series_id'] as String?,
      projectId: r['project_id'] as String?,
    );
  }

  String _splitTypeToString(SplitType type) {
    switch (type) {
      case SplitType.percentage:
        return 'percentage';
      case SplitType.fixed:
        return 'fixed';
      case SplitType.categoryOwner:
        return 'category_owner';
    }
  }
}
