import '../../domain/entities/card_invoice.dart';
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
import '../../domain/entities/audit_entry.dart';
import '../../domain/services/cycle_expense_filter.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import 'finance_datasource.dart';

class SupabaseFinanceDataSource implements FinanceDataSource {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseFinanceDataSource({
    required this.client,
    required this.getCurrentHouseId,
  });

  String get _houseId => getCurrentHouseId();

  bool _isUuid(String? id) {
    if (id == null || id.isEmpty) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(id);
  }

  @override
  Future<List<HouseMember>> getMembers() async {
    try {
      final rows = await client
          .from('house_members')
          .select('id, user_id, role, default_split_percent, default_fixed_amount_cents, profile:profiles(full_name, avatar_url, pix_key)')
          .eq('house_id', _houseId)
          .filter('left_at', 'is', null)
          .order('joined_at', ascending: true);

      if (rows.isEmpty) {
        final current = client.auth.currentUser;
        if (current != null) {
          final profile = await client.from('profiles').select('full_name, avatar_url, pix_key').eq('id', current.id).maybeSingle();
          return [
            HouseMember(
              id: current.id,
              name: profile?['full_name'] as String? ?? current.userMetadata?['full_name'] as String? ?? current.email ?? 'Você',
              avatarUrl: profile?['avatar_url'] as String?,
              role: 'owner',
              defaultSplitPercent: 100.0,
              pixKey: profile?['pix_key'] as String?,
            ),
          ];
        }
      }

      return rows.map((r) {
        final profile = r['profile'] as Map<String, dynamic>?;
        final name = profile?['full_name'] as String? ?? 'Membro';
        final avatar = profile?['avatar_url'] as String?;
        final role = r['role'] as String? ?? 'member';
        final split = (r['default_split_percent'] as num?)?.toDouble() ?? 50.0;
        final fixedAmount = (r['default_fixed_amount_cents'] as num?)?.toInt();

        return HouseMember(
          id: r['user_id'] as String,
          name: name,
          avatarUrl: avatar,
          role: role,
          defaultSplitPercent: split,
          defaultFixedAmountCents: fixedAmount,
          pixKey: profile?['pix_key'] as String?,
        );
      }).toList();
    } catch (e) {
      // Fallback resiliente caso default_split_percent ou profile embed falhem no schema cache
      try {
        final rows = await client
            .from('house_members')
            .select('id, user_id, role')
            .eq('house_id', _houseId);

        final userIds = rows.map((r) => r['user_id'] as String).toList();
        final profiles = userIds.isNotEmpty
            ? await client.from('profiles').select('id, full_name, avatar_url, pix_key').filter('id', 'in', userIds)
            : <Map<String, dynamic>>[];
        final profileMap = {for (final p in profiles) p['id'] as String: p};

        return rows.map((r) {
          final uId = r['user_id'] as String;
          final profile = profileMap[uId];
          final name = profile?['full_name'] as String? ?? 'Membro';
          final avatar = profile?['avatar_url'] as String?;
          final role = r['role'] as String? ?? 'member';

          return HouseMember(
            id: uId,
            name: name,
            avatarUrl: avatar,
            role: role,
            defaultSplitPercent: 50.0,
            pixKey: profile?['pix_key'] as String?,
          );
        }).toList();
      } catch (errFallback) {
        final current = client.auth.currentUser;
        if (current != null) {
          return [
            HouseMember(
              id: current.id,
              name: current.userMetadata?['full_name'] as String? ?? current.email ?? 'Você',
              role: 'owner',
              defaultSplitPercent: 100.0,
            ),
          ];
        }
        throw ServerFailure('Erro ao buscar membros da casa: $e');
      }
    }
  }

  @override
  Future<List<ExpenseCategory>> getCategories() async {
    try {
      final rows = await client
          .from('categories')
          .select()
          .eq('house_id', _houseId);

      if (rows.isNotEmpty) {
        return rows.map((r) {
          return ExpenseCategory(
            id: r['id'] as String,
            name: r['name'] as String,
            icon: r['icon'] as String? ?? 'category_outlined',
            colorHex: r['color_hex'] as String? ?? '0xFF2196F3',
            ownerMemberId: r['owner_member_id'] as String?,
          );
        }).toList();
      }

      // Provisiona categorias padrão para nova casa
      final defaultList = [
        {'name': 'Supermercado', 'icon': 'shopping_cart_outlined', 'color_hex': '#10B981'},
        {'name': 'Moradia / Aluguel', 'icon': 'home_outlined', 'color_hex': '#3B82F6'},
        {'name': 'Contas (Luz, Água, Net)', 'icon': 'bolt_outlined', 'color_hex': '#F59E0B'},
        {'name': 'Transporte', 'icon': 'directions_car_outlined', 'color_hex': '#EC4899'},
        {'name': 'Lazer e Restaurantes', 'icon': 'restaurant_outlined', 'color_hex': '#8B5CF6'},
        {'name': 'Saúde e Farmácia', 'icon': 'local_hospital_outlined', 'color_hex': '#EF4444'},
      ];

      try {
        final toInsert = defaultList.map((d) => {
          'house_id': _houseId,
          'name': d['name'],
          'icon': d['icon'],
          'color_hex': d['color_hex'],
        }).toList();
        final inserted = await client.from('categories').insert(toInsert).select();
        return inserted.map((r) => ExpenseCategory(
          id: r['id'] as String,
          name: r['name'] as String,
          icon: r['icon'] as String? ?? 'category_outlined',
          colorHex: r['color_hex'] as String? ?? '0xFF2196F3',
          ownerMemberId: r['owner_member_id'] as String?,
        )).toList();
      } catch (_) {
        return defaultList.map((d) => ExpenseCategory(
          id: 'cat_${d['name']!.toLowerCase().replaceAll(' ', '_')}',
          name: d['name']!,
          icon: d['icon']!,
          colorHex: d['color_hex']!,
        )).toList();
      }
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
          .eq('house_id', _houseId)
          .neq('is_active', false);

      if (rows.isNotEmpty) {
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
            ownerMemberId: (r['owner_member_id'] ?? r['owner_id']) as String?,
            closingDay: (r['closing_day'] ?? r['card_closing_day'] as num?)?.toInt(),
            dueDay: (r['due_day'] ?? r['card_due_day'] as num?)?.toInt(),
          );
        }).toList();
      }

      // Provisiona métodos de pagamento padrão para nova casa
      final defaultPms = [
        {'name': 'Pix / Transferência', 'type': 'pix'},
        {'name': 'Cartão de Crédito', 'type': 'card'},
        {'name': 'Dinheiro', 'type': 'cash'},
      ];

      try {
        final toInsert = defaultPms.map((d) => {
          'house_id': _houseId,
          'name': d['name'],
          'type': d['type'],
        }).toList();
        final inserted = await client.from('payment_methods').insert(toInsert).select();
        return inserted.map((r) {
          final typeStr = r['type'] as String? ?? 'pix';
          return PaymentMethod(
            id: r['id'] as String,
            name: r['name'] as String,
            type: typeStr == 'card' ? PaymentMethodType.card : (typeStr == 'cash' ? PaymentMethodType.cash : PaymentMethodType.pix),
          );
        }).toList();
      } catch (_) {
        return const [
          PaymentMethod(id: 'pm_pix', name: 'Pix / Transferência', type: PaymentMethodType.pix),
          PaymentMethod(id: 'pm_cartao', name: 'Cartão de Crédito', type: PaymentMethodType.card),
          PaymentMethod(id: 'pm_dinheiro', name: 'Dinheiro', type: PaymentMethodType.cash),
        ];
      }
    } catch (e) {
      throw ServerFailure('Erro ao buscar métodos de pagamento: $e');
    }
  }

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async {
    try {
      final startDate = cycle.startDate.toIso8601String().split('T')[0];
      final endDate = cycle.endDate.toIso8601String().split('T')[0];
      final startInstant = cycle.startDate.toUtc().toIso8601String();
      final endInstant = cycle.endDate.toUtc().toIso8601String();

      // Candidatas: vencem no ciclo, estão pendentes desde antes dele ou foram
      // lançadas ou baixadas nele. A regra de competência decide quais realmente entram.
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .isFilter('project_id', null)
          .isFilter('deleted_at', null)
          .or(
            'and(due_date.gte.$startDate,due_date.lte.$endDate),'
            'and(status.eq.pending,due_date.lt.$startDate),'
            'and(date.gte."$startInstant",date.lte."$endInstant"),'
            'and(paid_at.gte."$startInstant",paid_at.lte."$endInstant")',
          )
          .order('due_date', ascending: false);

      final cardRows = await client
          .from('payment_methods')
          .select('id')
          .eq('house_id', _houseId)
          .eq('type', 'card');
      final cardIds = {for (final r in cardRows) r['id'] as String};

      return rows
          .map((r) => _mapRowToHouseExpense(r))
          .where(
            (e) => expenseBelongsToCycle(
              e,
              cycle,
              isCardPayment: cardIds.contains(e.paymentMethodId),
            ),
          )
          .toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar despesas do ciclo: $e');
    }
  }

  @override
  Future<List<HouseExpense>> getExpensesForProject(String projectId) async {
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await client
            .from('house_expenses')
            .select('*, house_expense_items(*), split_rules(*)')
            .eq('house_id', _houseId)
            .eq('project_id', projectId)
            .isFilter('deleted_at', null)
            .order('date', ascending: false);
      } catch (_) {
        rows = await client
            .from('house_expenses')
            .select('*, house_expense_items(*), split_rules(*)')
            .eq('house_id', _houseId)
            .eq('project_id', projectId)
            .isFilter('deleted_at', null)
            .order('due_date', ascending: false);
      }

      return rows.map((r) => _mapRowToHouseExpense(r)).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar despesas do projeto: $e');
    }
  }

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async {
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await client
            .from('contributions')
            .select('*, profile:profiles(full_name)')
            .eq('house_id', _houseId)
            .gte('cycle_start_date', cycle.startDate.toIso8601String().split('T')[0])
            .lte('cycle_start_date', cycle.endDate.toIso8601String().split('T')[0]);
      } catch (_) {
        rows = await client
            .from('contributions')
            .select()
            .eq('house_id', _houseId)
            .gte('cycle_start_date', cycle.startDate.toIso8601String().split('T')[0])
            .lte('cycle_start_date', cycle.endDate.toIso8601String().split('T')[0]);
      }

      return rows.map((r) {
        final dateStr = (r['created_at'] ?? r['cycle_start_date']) as String?;
        final date = dateStr != null ? (DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now()) : DateTime.now();
        return Contribution(
          id: r['id'] as String,
          memberId: r['member_id'] as String,
          amount: Money((r['amount_cents'] as num).toInt()),
          date: date,
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
      // Compra no cartão sem vencimento informado: vale o vencimento da fatura,
      // qualquer que seja a tela que lançou a despesa.
      var dueDate = expense.dueDate;
      if (dueDate == null && _isUuid(expense.paymentMethodId)) {
        final method = await client
            .from('payment_methods')
            .select('type, closing_day, due_day')
            .eq('id', expense.paymentMethodId)
            .maybeSingle();
        final closingDay = (method?['closing_day'] as num?)?.toInt();
        final dueDay = (method?['due_day'] as num?)?.toInt();
        if (method?['type'] == 'card' && closingDay != null && dueDay != null) {
          dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
            purchaseDate: expense.date,
            closingDay: closingDay,
            dueDay: dueDay,
          );
        }
      }

      final expenseRow = {
        if (_isUuid(expense.id)) 'id': expense.id,
        'house_id': _houseId,
        'title': expense.title,
        'amount_cents': expense.amount.cents,
        if (_isUuid(expense.categoryId)) 'category_id': expense.categoryId,
        if (_isUuid(expense.paymentMethodId)) 'payment_method_id': expense.paymentMethodId,
        'paid_by_id': _isUuid(expense.paidByMemberId)
            ? expense.paidByMemberId
            : (client.auth.currentUser?.id ?? expense.paidByMemberId),
        'paid_out_of_pocket': expense.paidOutOfPocket,
        'due_date': (dueDate ?? expense.date).toIso8601String().split('T')[0],
        'date': expense.date.toUtc().toIso8601String(),
        'cycle_start_date': expense.date.toIso8601String().split('T')[0],
        'split_type': _splitTypeToString(expense.splitRule.type),
        'status': expense.isPaid ? 'paid' : 'pending',
        'paid_at': expense.isPaid ? expense.paidAt?.toUtc().toIso8601String() : null,
        'is_recurring': expense.isRecurring,
        'is_variable': expense.isVariable,
        'due_day': expense.dueDay,
        'is_active': expense.isActive,
        'recurring_series_id': expense.recurringSeriesId,
        'project_id': expense.projectId,
        'notes': expense.notes,
        'created_by': client.auth.currentUser?.id ?? expense.paidByMemberId,
      };

      Map<String, dynamic> insertedRow;
      try {
        insertedRow = await client.from('house_expenses').insert(expenseRow).select().single();
      } catch (insertErr) {
        if (insertErr.toString().contains('PGRST204') ||
            insertErr.toString().contains('column') ||
            insertErr.toString().contains('schema cache')) {
          final fallbackRow = Map<String, dynamic>.from(expenseRow);
          fallbackRow.remove('date');
          fallbackRow.remove('cycle_start_date');
          fallbackRow.remove('split_type');
          fallbackRow.remove('project_id');
          fallbackRow.remove('paid_at');
          insertedRow = await client.from('house_expenses').insert(fallbackRow).select().single();
        } else {
          rethrow;
        }
      }

      final insertedExpenseId = insertedRow['id'] as String;

      if (expense.items.isNotEmpty) {
        final itemRows = expense.items.map((item) {
          return {
            if (_isUuid(item.id)) 'id': item.id,
            'expense_id': insertedExpenseId,
            'title': item.title,
            'amount_cents': item.amount.cents,
            if (_isUuid(item.categoryId)) 'category_id': item.categoryId,
            if (_isUuid(item.responsibleMemberId))
              'responsible_member_id': item.responsibleMemberId,
            'split_type': item.splitRule != null ? _splitTypeToString(item.splitRule!.type) : null,
          };
        }).toList();

        try {
          await client.from('house_expense_items').insert(itemRows);
        } catch (itemErr) {
          if (itemErr.toString().contains('PGRST204') ||
              itemErr.toString().contains('split_type')) {
            final fallbackItems = itemRows.map((r) {
              final copy = Map<String, dynamic>.from(r);
              copy.remove('split_type');
              return copy;
            }).toList();
            await client.from('house_expense_items').insert(fallbackItems);
          } else {
            rethrow;
          }
        }
      }

      try {
        await _syncSplitRules(insertedExpenseId, expense);
      } catch (splitErr) {
        throw ServerFailure(
          'A despesa foi salva, mas o rateio personalizado não foi gravado. Edite a despesa para definir o rateio de novo. ($splitErr)',
        );
      }
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao adicionar despesa: $e');
    }
  }

  /// Substitui as regras de rateio gravadas para a despesa.
  Future<void> _syncSplitRules(String expenseId, HouseExpense expense) async {
    await client.from('split_rules').delete().eq('expense_id', expenseId);

    final rule = expense.splitRule;
    final rows = <Map<String, dynamic>>[];

    if (rule.type == SplitType.percentage && rule.percentages != null) {
      final memberIds = rule.percentages!.keys.where(_isUuid).toList();
      final allocations = rule.calculateAllocations(
        totalAmount: expense.amount,
        memberIds: memberIds,
      );
      for (final memberId in memberIds) {
        rows.add({
          'expense_id': expenseId,
          'member_id': memberId,
          'percentage_basis_points':
              (rule.percentages![memberId]! * 100).round().clamp(0, 10000),
          'calculated_cents': allocations[memberId]?.cents ?? 0,
        });
      }
    } else if (rule.type == SplitType.fixed && rule.fixedAmounts != null) {
      for (final entry in rule.fixedAmounts!.entries) {
        if (!_isUuid(entry.key)) continue;
        rows.add({
          'expense_id': expenseId,
          'member_id': entry.key,
          'fixed_amount_cents': entry.value.cents,
          'calculated_cents': entry.value.cents,
        });
      }
    } else if (rule.type == SplitType.categoryOwner &&
        _isUuid(rule.singleResponsibleMemberId)) {
      rows.add({
        'expense_id': expenseId,
        'member_id': rule.singleResponsibleMemberId,
        'percentage_basis_points': 10000,
        'calculated_cents': expense.amount.cents,
      });
    }

    if (rows.isNotEmpty) {
      await client.from('split_rules').insert(rows);
    }
  }

  @override
  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      final dueDateStr = (expense.dueDate ?? expense.date).toIso8601String().split('T')[0];
      final updateData = <String, dynamic>{
        'title': expense.title,
        'amount_cents': expense.amount.cents,
        if (_isUuid(expense.categoryId)) 'category_id': expense.categoryId,
        if (_isUuid(expense.paymentMethodId)) 'payment_method_id': expense.paymentMethodId,
        'paid_by_id': _isUuid(expense.paidByMemberId)
            ? expense.paidByMemberId
            : (client.auth.currentUser?.id ?? expense.paidByMemberId),
        'paid_out_of_pocket': expense.paidOutOfPocket,
        'due_date': dueDateStr,
        'date': expense.date.toUtc().toIso8601String(),
        'split_type': _splitTypeToString(expense.splitRule.type),
        'status': expense.isPaid ? 'paid' : 'pending',
        'paid_at': expense.isPaid ? expense.paidAt?.toUtc().toIso8601String() : null,
        'is_recurring': expense.isRecurring,
        'is_variable': expense.isVariable,
        'due_day': expense.dueDay,
        'is_active': expense.isActive,
        'notes': expense.notes,
        if (expense.projectId != null) 'project_id': expense.projectId,
      };

      await client.from('house_expenses').update(updateData).eq('id', expense.id);

      // Sincroniza sub-itens (house_expense_items)
      try {
        await client.from('house_expense_items').delete().eq('expense_id', expense.id);
      } catch (_) {}

      if (expense.items.isNotEmpty) {
        final itemRows = expense.items.map((item) {
          return {
            if (_isUuid(item.id)) 'id': item.id,
            'expense_id': expense.id,
            'title': item.title,
            'amount_cents': item.amount.cents,
            if (_isUuid(item.categoryId)) 'category_id': item.categoryId,
            if (_isUuid(item.responsibleMemberId))
              'responsible_member_id': item.responsibleMemberId,
            'split_type': item.splitRule != null ? _splitTypeToString(item.splitRule!.type) : null,
          };
        }).toList();

        try {
          await client.from('house_expense_items').insert(itemRows);
        } catch (_) {}
      }

      // Sincroniza regras de rateio (split_rules)
      await _syncSplitRules(expense.id, expense);

      // Tratamento de escopo para recorrências
      if (expense.isRecurring && scope != RecurrenceScope.thisInstanceOnly) {
        final seriesId = expense.recurringSeriesId ?? expense.id;
        final recurringUpdate = <String, dynamic>{
          'title': expense.title,
          'amount_cents': expense.amount.cents,
          if (_isUuid(expense.categoryId)) 'category_id': expense.categoryId,
          if (_isUuid(expense.paymentMethodId)) 'payment_method_id': expense.paymentMethodId,
          'split_type': _splitTypeToString(expense.splitRule.type),
          'is_variable': expense.isVariable,
          'due_day': expense.dueDay,
        };

        if (scope == RecurrenceScope.allInstances) {
          await client
              .from('house_expenses')
              .update(recurringUpdate)
              .or('recurring_series_id.eq.$seriesId,id.eq.$seriesId');
        } else if (scope == RecurrenceScope.thisAndFuture) {
          await client
              .from('house_expenses')
              .update(recurringUpdate)
              .or('recurring_series_id.eq.$seriesId,id.eq.$seriesId')
              .gte('due_date', dueDateStr);
        }
      }
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
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // 1. Tenta RPC com security definer no Supabase passando o escopo
      try {
        final res = await client.rpc('delete_house_expense', params: {
          'p_expense_id': expenseId,
          'p_scope': scope.name,
        });
        if (res == true) return;
      } on PostgrestException catch (e) {
        // Recusa do próprio banco (ex: despesa já acertada em um fechamento):
        // não tenta contornar pela gravação direta
        if (e.code == 'P0001') throw ServerFailure(e.message);
      } catch (_) {}

      // 2. Busca dados da despesa atual para guiar a exclusão direta caso a RPC falhe
      final current = await client
          .from('house_expenses')
          .select('id, recurring_series_id, is_recurring, due_date, date')
          .eq('id', expenseId)
          .maybeSingle();

      final seriesId = current != null
          ? (current['recurring_series_id'] as String? ??
              ((current['is_recurring'] == true) ? current['id'] as String? : null))
          : null;
      final expenseDateStr = current != null
          ? ((current['due_date'] ?? current['date']) as String?)
          : null;

      if (scope == RecurrenceScope.allInstances) {
        // Soft delete na própria despesa imediatamente
        await client
            .from('house_expenses')
            .update({'deleted_at': nowIso, 'is_active': false})
            .eq('id', expenseId);

        // Se houver série vinculada, desativa e deleta a matriz e ocorrências
        if (seriesId != null) {
          if (seriesId != expenseId) {
            await client
                .from('house_expenses')
                .update({'deleted_at': nowIso, 'is_active': false})
                .eq('id', seriesId);
          }
          await client
              .from('house_expenses')
              .update({'deleted_at': nowIso, 'is_active': false})
              .eq('recurring_series_id', seriesId);
        }
        return;
      } else if (scope == RecurrenceScope.thisAndFuture) {
        if (seriesId != null) {
          await client
              .from('house_expenses')
              .update({'is_active': false})
              .eq('id', seriesId);

          if (expenseDateStr != null) {
            await client
                .from('house_expenses')
                .update({'deleted_at': nowIso})
                .eq('recurring_series_id', seriesId)
                .gte('due_date', expenseDateStr);
          }
        }
        await client
            .from('house_expenses')
            .update({'deleted_at': nowIso})
            .eq('id', expenseId);
        return;
      } else {
        // RecurrenceScope.thisInstanceOnly
        final updated = await client
            .from('house_expenses')
            .update({'deleted_at': nowIso})
            .eq('id', expenseId)
            .select('id');

        if (updated.isNotEmpty) return;

        // Se soft delete não alterou linhas, tenta delete físico
        final deleted = await client
            .from('house_expenses')
            .delete()
            .eq('id', expenseId)
            .select('id');

        if (deleted.isEmpty) {
          throw ServerFailure(
            'Não foi possível excluir a despesa. Permissão negada pelo Supabase (RLS). Execute a migration 0016 no SQL Editor.',
          );
        }
        return;
      }
    } on ServerFailure {
      rethrow;
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
          .eq('is_active', true)
          .isFilter('deleted_at', null);

      return rows.map((r) => _mapRowToHouseExpense(r)).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar assinaturas recorrentes: $e');
    }
  }

  @override
  Future<void> addContribution(Contribution contribution) async {
    try {
      final currentUserId = client.auth.currentUser?.id ?? contribution.memberId;
      await client.from('contributions').insert({
        if (_isUuid(contribution.id)) 'id': contribution.id,
        'house_id': _houseId,
        'member_id': contribution.memberId,
        'amount_cents': contribution.amount.cents,
        'cycle_start_date': contribution.date.toIso8601String().split('T')[0],
        'paid_at': contribution.date.toUtc().toIso8601String(),
        'created_by': currentUserId,
      });
    } catch (e) {
      throw ServerFailure('Erro ao adicionar aporte: $e');
    }
  }

  @override
  Future<void> addCategory(ExpenseCategory category) async {
    try {
      await client.from('categories').insert({
        if (_isUuid(category.id)) 'id': category.id,
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
      final payload = <String, dynamic>{
        'house_id': _houseId,
        'name': paymentMethod.name,
        'type': paymentMethod.type.name,
        'closing_day': paymentMethod.closingDay,
        'due_day': paymentMethod.dueDay,
        'color_hex': paymentMethod.colorHex,
        'is_active': true,
      };
      if (_isUuid(paymentMethod.id)) {
        payload['id'] = paymentMethod.id;
      }
      if (_isUuid(paymentMethod.ownerMemberId)) {
        payload['owner_id'] = paymentMethod.ownerMemberId;
        payload['owner_member_id'] = paymentMethod.ownerMemberId;
      }
      await client.from('payment_methods').insert(payload);
    } catch (e) {
      throw ServerFailure('Erro ao criar método de pagamento: $e');
    }
  }

  @override
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) async {
    try {
      if (!_isUuid(paymentMethod.id)) return;
      final ownerId = _isUuid(paymentMethod.ownerMemberId) ? paymentMethod.ownerMemberId : null;
      final payload = <String, dynamic>{
        'name': paymentMethod.name,
        'type': paymentMethod.type.name,
        'owner_id': ownerId,
        'owner_member_id': ownerId,
        'closing_day': paymentMethod.closingDay,
        'due_day': paymentMethod.dueDay,
        'color_hex': paymentMethod.colorHex,
      };
      await client
          .from('payment_methods')
          .update(payload)
          .eq('id', paymentMethod.id)
          .eq('house_id', _houseId);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar método de pagamento: $e');
    }
  }

  @override
  Future<void> deletePaymentMethod(String paymentMethodId) async {
    try {
      if (!_isUuid(paymentMethodId)) return;
      await client
          .from('payment_methods')
          .update({'is_active': false})
          .eq('id', paymentMethodId)
          .eq('house_id', _houseId);
    } catch (e) {
      throw ServerFailure('Erro ao excluir método de pagamento: $e');
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
          targetAmount: Money((r['target_amount_cents'] as num?)?.toInt() ?? 0),
          currentBalance: Money((r['current_balance_cents'] as num).toInt()),
          icon: r['icon'] as String? ?? 'savings',
          colorHex: r['color_hex'] as String? ?? '#10B981',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
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
        if (_isUuid(vault.id)) 'id': vault.id,
        'house_id': _houseId,
        'name': vault.name,
        // Caixinha sem meta: a coluna só aceita nulo ou valor positivo
        'target_amount_cents': vault.targetAmount.cents > 0 ? vault.targetAmount.cents : null,
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
      // Saldo e extrato mudam juntos no banco, com a caixinha travada
      await client.rpc('move_vault_balance', params: {
        'p_vault_id': vaultId,
        'p_type': 'deposit',
        'p_amount_cents': amount.cents,
        'p_description': description,
      });
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
      await client.rpc('move_vault_balance', params: {
        'p_vault_id': vaultId,
        'p_type': 'withdraw',
        'p_amount_cents': amount.cents,
        'p_description': description,
      });
    } catch (e) {
      throw ServerFailure('Erro ao resgatar da caixinha: $e');
    }
  }

  @override
  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  }) async {
    try {
      // 1. Atualiza os percentuais e montantes fixos em house_members
      for (final entry in percentages.entries) {
        final memberId = entry.key;
        final pct = entry.value;
        final fixedCents = fixedAmountsCents[memberId];

        try {
          await client
              .from('house_members')
              .update({
                'default_split_percent': pct,
                'default_fixed_amount_cents': ?fixedCents,
              })
              .eq('house_id', _houseId)
              .eq('user_id', memberId);
        } catch (_) {
          // Fallback resiliente caso default_fixed_amount_cents ainda não exista no schema cache
          await client
              .from('house_members')
              .update({'default_split_percent': pct})
              .eq('house_id', _houseId)
              .eq('user_id', memberId);
        }
      }

      // 2. Se a tabela houses suportar default_split_model, atualiza
      try {
        await client
            .from('houses')
            .update({'default_split_model': splitModel})
            .eq('id', _houseId);
      } catch (_) {
        // Ignora silenciosamente caso a coluna opcional não exista no schema remoto
      }
    } catch (e) {
      throw ServerFailure('Erro ao atualizar modelo de rateio da casa: $e');
    }
  }

  // --- Helpers de Mapeamento ---
  HouseExpense _mapRowToHouseExpense(Map<String, dynamic> r) {
    final rawItems = r['house_expense_items'] as List<dynamic>? ?? [];
    final items = rawItems.map((item) {
      final respId = item['responsible_member_id'] as String?;
      return HouseExpenseItem(
        id: item['id'] as String,
        expenseId: item['expense_id'] as String,
        title: item['title'] as String,
        amount: Money((item['amount_cents'] as num).toInt()),
        categoryId: item['category_id'] as String?,
        responsibleMemberId: respId,
        splitRule: respId != null ? SplitRule.singleResponsible(respId) : null,
      );
    }).toList();

    final statusStr = r['status'] as String? ?? 'paid';
    final status = statusStr == 'pending' ? ExpenseStatus.pending : ExpenseStatus.paid;

    final splitTypeStr = r['split_type'] as String? ?? 'percentage';
    final rawSplitRules = r['split_rules'] as List<dynamic>? ?? [];

    SplitRule splitRule;
    if (splitTypeStr == 'category_owner') {
      final responsibleId = rawSplitRules.isNotEmpty
          ? rawSplitRules.first['member_id'] as String?
          : null;
      // Despesas antigas não têm a regra gravada: assume quem pagou
      splitRule = SplitRule.singleResponsible(responsibleId ?? r['paid_by_id'] as String?);
    } else if (splitTypeStr == 'fixed') {
      final fixedMap = <String, Money>{};
      for (final sr in rawSplitRules) {
        final mId = sr['member_id'] as String?;
        final fixedCents = (sr['fixed_amount_cents'] as num?)?.toInt() ?? 0;
        if (mId != null && fixedCents > 0) fixedMap[mId] = Money(fixedCents);
      }
      splitRule = SplitRule.fixed(fixedMap.isNotEmpty ? fixedMap : null);
    } else {
      final pctMap = <String, double>{};
      for (final sr in rawSplitRules) {
        final mId = sr['member_id'] as String?;
        final basisPoints = (sr['percentage_basis_points'] as num?)?.toInt();
        if (mId != null && basisPoints != null) {
          pctMap[mId] = basisPoints / 100.0;
        }
      }
      splitRule = SplitRule.percentage(pctMap.isNotEmpty ? pctMap : null);
    }

    return HouseExpense(
      id: r['id'] as String,
      title: r['title'] as String,
      amount: Money((r['amount_cents'] as num).toInt()),
      date: DateTime.parse(r['date'] as String? ?? r['created_at'] as String).toLocal(),
      dueDate: r['due_date'] != null ? DateTime.tryParse(r['due_date'] as String) : null,
      categoryId: r['category_id'] as String? ?? 'cat_geral',
      paidByMemberId: r['paid_by_id'] as String,
      paymentMethodId: r['payment_method_id'] as String? ?? 'pm_pix',
      splitRule: splitRule,
      status: status,
      isRecurring: r['is_recurring'] as bool? ?? false,
      isVariable: r['is_variable'] as bool? ?? false,
      dueDay: (r['due_day'] as num?)?.toInt(),
      isActive: r['is_active'] as bool? ?? true,
      settledAt: r['settled_at'] != null ? DateTime.tryParse(r['settled_at'] as String)?.toLocal() : null,
      paidAt: r['paid_at'] != null ? DateTime.tryParse(r['paid_at'] as String)?.toLocal() : null,
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

  @override
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) async {
    try {
      var query = client
          .from('v_audit_timeline')
          .select()
          .eq('house_id', _houseId);

      if (entityId != null) {
        query = query.eq('entity_id', entityId);
      }

      final rows = await query.order('created_at', ascending: false).limit(limit);

      return (rows as List<dynamic>).map((r) {
        return AuditEntry(
          id: r['id'] as String,
          houseId: r['house_id'] as String?,
          actorId: r['actor_id'] as String?,
          actorName: r['actor_name'] as String?,
          actorAvatarUrl: r['actor_avatar_url'] as String?,
          entityType: r['entity_type'] as String,
          entityId: r['entity_id'] as String,
          action: r['action'] as String,
          diff: r['diff'] as Map<String, dynamic>?,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        );
      }).toList();
    } catch (e) {
      // Fallback para tabela direta audit_log se a view v_audit_timeline ainda não estiver em cache
      try {
        var query = client
            .from('audit_log')
            .select()
            .eq('house_id', _houseId);

        if (entityId != null) {
          query = query.eq('entity_id', entityId);
        }

        final rows = await query.order('created_at', ascending: false).limit(limit);

        return (rows as List<dynamic>).map((r) {
          return AuditEntry(
            id: r['id'] as String,
            houseId: r['house_id'] as String?,
            actorId: r['actor_id'] as String?,
            entityType: r['entity_type'] as String,
            entityId: r['entity_id'] as String,
            action: r['action'] as String,
            diff: r['diff'] as Map<String, dynamic>?,
            createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          );
        }).toList();
      } catch (_) {
        return [];
      }
    }
  }

  @override
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId) async {
    try {
      if (!_isUuid(paymentMethodId)) return const [];

      // Só faturas recentes: compras antigas nunca marcadas não poluem a lista
      final since = DateTime.now().subtract(const Duration(days: 62));
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .eq('payment_method_id', paymentMethodId)
          .isFilter('project_id', null)
          .isFilter('deleted_at', null)
          .isFilter('paid_at', null)
          .gte('due_date', since.toIso8601String().split('T')[0]);

      return CardInvoice.groupOpenInvoices(
        paymentMethodId,
        rows.map((r) => _mapRowToHouseExpense(r)),
      );
    } catch (e) {
      throw ServerFailure('Erro ao buscar faturas do cartão: $e');
    }
  }

  @override
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
  }) async {
    try {
      // O banco confere se algum dos ciclos envolvidos já foi fechado
      await client.rpc('pay_card_invoice', params: {
        'p_payment_method_id': paymentMethodId,
        'p_due_date': invoiceDueDate.toIso8601String().split('T')[0],
        'p_paid_at': paidAt.toUtc().toIso8601String(),
      });
    } catch (e) {
      throw ServerFailure('Erro ao registrar pagamento da fatura: $e');
    }
  }

  @override
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId) async {
    try {
      if (!_isUuid(paymentMethodId)) return const [];

      final since = DateTime.now().subtract(const Duration(days: 62));
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .eq('payment_method_id', paymentMethodId)
          .isFilter('project_id', null)
          .isFilter('deleted_at', null)
          .not('paid_at', 'is', null)
          .gte('due_date', since.toIso8601String().split('T')[0]);

      return CardInvoice.groupPaidInvoices(
        paymentMethodId,
        rows.map((r) => _mapRowToHouseExpense(r)),
      );
    } catch (e) {
      throw ServerFailure('Erro ao buscar faturas pagas do cartão: $e');
    }
  }

  @override
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  }) async {
    try {
      await client.rpc('undo_card_invoice_payment', params: {
        'p_payment_method_id': paymentMethodId,
        'p_due_date': invoiceDueDate.toIso8601String().split('T')[0],
      });
    } catch (e) {
      throw ServerFailure('Erro ao desfazer pagamento da fatura: $e');
    }
  }
}
