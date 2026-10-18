import 'dart:async';

import 'house_expense_payload.dart';
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
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/services/cycle_expense_filter.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import 'finance_datasource.dart';
import '../../../../core/offline/offline_snapshot.dart';

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
  Stream<void> watchHouseChanges() {
    final houseId = _houseId;
    if (!_isUuid(houseId)) {
      throw const ServerFailure('Casa ainda não carregada.');
    }

    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        // Um canal por assinatura: o fechamento de um não derruba o do outro
        var pending = client.channel('house-finance-$houseId-${identityHashCode(controller)}');
        // Despesas e moradores (0050); aportes, empréstimos e caixinhas (0061)
        for (final table in const [
          'house_expenses',
          'house_members',
          'contributions',
          'p2p_loans',
          'savings_vaults',
          // Entradas de terceiros (0090)
          'third_party_receipts',
        ]) {
          pending = pending.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'house_id',
              value: houseId,
            ),
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          );
        }
        // Parcelas não têm house_id: sem filtro, o RLS entrega só as da casa
        pending = pending.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'p2p_installments',
          callback: (_) {
            if (!controller.isClosed) controller.add(null);
          },
        );
        channel = pending.subscribe();
      },
      onCancel: () {
        final current = channel;
        channel = null;
        if (current != null) client.removeChannel(current);
      },
    );
    return controller.stream;
  }

  @override
  Future<List<HouseMember>> getMembers() async {
    try {
      final rows = await OfflineSnapshot.instance.rows(
        'members_$_houseId',
        () async => await client
            .from('house_members')
            .select('id, user_id, role, default_split_percent, default_fixed_amount_cents, profile:profiles(full_name, avatar_url, pix_key)')
            .eq('house_id', _houseId)
            .filter('left_at', 'is', null)
            .order('joined_at', ascending: true),
      );

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
      final rows = await OfflineSnapshot.instance.rows(
        'categories_$_houseId',
        () async => await client.from('categories').select().eq('house_id', _houseId),
      );

      if (rows.isNotEmpty) {
        return rows.map((r) {
          return ExpenseCategory(
            id: r['id'] as String,
            name: r['name'] as String,
            icon: r['icon'] as String? ?? 'category_outlined',
            colorHex: r['color_hex'] as String? ?? '0xFF2196F3',
            ownerMemberId: r['owner_member_id'] as String?,
            isVariableSpend: r['is_variable_spend'] as bool?,
          );
        }).toList();
      }

      // A casa recebe as categorias padrão ao ser criada (no banco). Criá-las
      // aqui quando a lista vinha vazia duplicava tudo em leituras simultâneas.
      return const [];
    } catch (e) {
      throw ServerFailure('Erro ao buscar categorias: $e');
    }
  }

  @override
  Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      final rows = await OfflineSnapshot.instance.rows(
        'payment_methods_$_houseId',
        () async => await client
            .from('payment_methods')
            .select()
            .eq('house_id', _houseId)
            .neq('is_active', false),
      );

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

      // A casa recebe as formas de pagamento padrão ao ser criada (no banco).
      // Criá-las aqui quando a lista vinha vazia duplicava tudo.
      return const [];
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

      // Ciclo atual ou futuro: o banco cria as contas recorrentes que ainda
      // não existem até o fim dele. Falhar aqui não impede a leitura.
      if (!cycle.endDate.isBefore(DateTime.now())) {
        try {
          await client.rpc('generate_recurring_expenses', params: {
            'p_house_id': _houseId,
            'p_until': endDate,
          });
        } catch (_) {}
      }

      // Candidatas: vencem no ciclo, estão pendentes desde antes dele ou foram
      // lançadas ou baixadas nele. A regra de competência decide quais realmente entram.
      final rows = await OfflineSnapshot.instance.rows(
        'expenses_${_houseId}_$startDate',
        () async => await client
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
            .order('due_date', ascending: false),
      );

      final cardRows = await OfflineSnapshot.instance.rows(
        'card_ids_$_houseId',
        () async => await client
            .from('payment_methods')
            .select('id')
            .eq('house_id', _houseId)
            .eq('type', 'card'),
      );
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
  Future<Money> getOpeningBalance(FinancialCycle cycle) async {
    final parts = await Future.wait([_rolledSurplus(cycle), getVaultReturnsForCycle(cycle)]);
    return parts[0] + parts[1];
  }

  /// Empréstimos que o Caixa do ciclo liberou (0086), fora os recusados.
  Future<Money> _houseLoansFunded(FinancialCycle cycle) async {
    String dateOnly(DateTime d) => d.toIso8601String().split('T')[0];
    try {
      final rows = await OfflineSnapshot.instance.rows(
        'house_loans_funded_${_houseId}_${dateOnly(cycle.startDate)}',
        () async => await client
            .from('p2p_loans')
            .select('total_amount_cents')
            .eq('house_id', _houseId)
            .eq('house_funding', 'cycle')
            .neq('status', 'cancelled')
            .gte('funded_on', dateOnly(cycle.startDate))
            .lte('funded_on', dateOnly(cycle.endDate)),
      );
      return Money(rows.fold<int>(0, (acc, r) => acc + ((r['total_amount_cents'] as num?)?.toInt() ?? 0)));
    } catch (_) {
      return const Money.zero();
    }
  }

  /// Sobra que o fechamento do ciclo anterior deixou no Caixa.
  Future<Money> _rolledSurplus(FinancialCycle cycle) async {
    var rolledCents = 0;
    try {
      String dateOnly(DateTime d) => d.toIso8601String().split('T')[0];
      // Só o ciclo imediatamente anterior conta: os ciclos são mensais
      final row = await OfflineSnapshot.instance.row(
        'rolled_${_houseId}_${dateOnly(cycle.startDate)}',
        () async => await client
            .from('settlements')
            .select('surplus_rolled_cents')
            .eq('house_id', _houseId)
            .neq('status', 'cancelled')
            .lt('cycle_start_date', dateOnly(cycle.startDate))
            .gte('cycle_start_date', dateOnly(cycle.startDate.subtract(const Duration(days: 62))))
            .order('cycle_start_date', ascending: false)
            .limit(1)
            .maybeSingle(),
      );
      rolledCents = (row?['surplus_rolled_cents'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    return Money(rolledCents);
  }

  @override
  Future<DateTime?> getHouseStartDate() async {
    try {
      final houseId = _houseId;
      final rows = await Future.wait<Map<String, dynamic>?>([
        client.from('houses').select('created_at').eq('id', houseId).maybeSingle(),
        client
            .from('house_expenses')
            .select('date')
            .eq('house_id', houseId)
            .isFilter('project_id', null)
            .isFilter('deleted_at', null)
            .order('date')
            .limit(1)
            .maybeSingle(),
        client
            .from('house_expenses')
            .select('due_date')
            .eq('house_id', houseId)
            .isFilter('project_id', null)
            .isFilter('deleted_at', null)
            .not('due_date', 'is', null)
            .order('due_date')
            .limit(1)
            .maybeSingle(),
        client
            .from('contributions')
            .select('cycle_start_date')
            .eq('house_id', houseId)
            .order('cycle_start_date')
            .limit(1)
            .maybeSingle(),
      ]);
      DateTime? earliest;
      for (final row in rows) {
        final raw = row?.values.first;
        final date = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
        if (date != null && (earliest == null || date.isBefore(earliest))) earliest = date;
      }
      return earliest;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle) async {
    try {
      String dateOnly(DateTime d) => d.toIso8601String().split('T')[0];
      final rows = await OfflineSnapshot.instance.rows(
        'vault_returns_${_houseId}_${dateOnly(cycle.startDate)}',
        () async => await client
            .from('savings_transactions')
            .select('amount_cents, type')
            .eq('house_id', _houseId)
            .gte('cycle_start_date', dateOnly(cycle.startDate))
            .lte('cycle_start_date', dateOnly(cycle.endDate)),
      );
      // Depósito tirado do Caixa do ciclo desfaz parte do que as caixinhas devolveram
      return Money(rows.fold<int>(0, (acc, r) {
        final cents = (r['amount_cents'] as num).toInt();
        return acc + (r['type'] == 'withdraw' ? cents : -cents);
      }));
    } catch (_) {
      return const Money.zero();
    }
  }

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async {
    try {
      final start = cycle.startDate.toIso8601String().split('T')[0];
      final end = cycle.endDate.toIso8601String().split('T')[0];
      final rows = await OfflineSnapshot.instance.rows('contributions_${_houseId}_$start', () async {
        try {
          return await client
              .from('contributions')
              .select('*, profile:profiles(full_name)')
              .eq('house_id', _houseId)
              .gte('cycle_start_date', start)
              .lte('cycle_start_date', end);
        } catch (_) {
          return await client
              .from('contributions')
              .select()
              .eq('house_id', _houseId)
              .gte('cycle_start_date', start)
              .lte('cycle_start_date', end);
        }
      });

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
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  }) async {
    try {
      // O que não veio pronto é lido junto com a sobra e as devoluções das caixinhas
      final expensesFuture = expenses != null ? Future.value(expenses) : getExpensesForCycle(cycle);
      final contributionsFuture =
          contributions != null ? Future.value(contributions) : getContributionsForCycle(cycle);
      final rolledFuture = _rolledSurplus(cycle);
      final vaultReturnsFuture = getVaultReturnsForCycle(cycle);
      final loansFundedFuture = _houseLoansFunded(cycle);
      await Future.wait<void>(
        [expensesFuture, contributionsFuture, rolledFuture, vaultReturnsFuture, loansFundedFuture],
      );
      final loansFunded = await loansFundedFuture;
      final cycleExpenses = await expensesFuture;
      final cycleContributions = await contributionsFuture;
      final vaultReturns = await vaultReturnsFuture;

      final memberContributions = <String, Money>{};
      int totalContributionsCents = 0;
      for (final c in cycleContributions) {
        totalContributionsCents += c.amount.cents;
        final current = memberContributions[c.memberId]?.cents ?? 0;
        memberContributions[c.memberId] = Money(current + c.amount.cents);
      }

      int totalExpensesPaidCents = 0;
      int committedFutureExpensesCents = 0;
      final memberExpensesPaid = <String, Money>{};

      for (final exp in cycleExpenses) {
        if (exp.isPaid) {
          totalExpensesPaidCents += exp.amount.cents;
          final current = memberExpensesPaid[exp.paidByMemberId]?.cents ?? 0;
          memberExpensesPaid[exp.paidByMemberId] = Money(current + exp.amount.cents);
        } else {
          committedFutureExpensesCents += exp.amount.cents;
        }
      }

      // A sobra deixada pelo ciclo anterior e as devoluções das caixinhas entram como folga do Caixa
      final openingBalance = await rolledFuture + vaultReturns;
      // Empréstimos que o Caixa liberou no ciclo também saíram dele
      final folegoCents = openingBalance.cents +
          totalContributionsCents -
          (totalExpensesPaidCents + committedFutureExpensesCents) -
          loansFunded.cents;

      return FinancialCycleSummary(
        cycle: cycle,
        totalContributions: Money(totalContributionsCents),
        totalExpensesPaid: Money(totalExpensesPaidCents),
        committedFutureExpenses: Money(committedFutureExpensesCents),
        folego: Money(folegoCents),
        memberContributions: memberContributions,
        memberExpensesPaid: memberExpensesPaid,
        vaultReturns: vaultReturns,
        houseLoansFunded: loansFunded,
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

      // Despesa, sub-itens e rateio entram juntos: ou tudo, ou nada
      await client.rpc('create_house_expense', params: {
        'p_expense': houseExpensePayload(
          expense,
          houseId: _houseId,
          currentUserId: client.auth.currentUser?.id,
          dueDate: dueDate,
        ),
      });
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao adicionar despesa: $e');
    }
  }

  /// Substitui as regras de rateio gravadas para a despesa.
  Future<void> _syncSplitRules(String expenseId, HouseExpense expense) async {
    await client.from('split_rules').delete().eq('expense_id', expenseId);

    final rows = [
      for (final row in splitRuleRows(expense)) {...row, 'expense_id': expenseId},
    ];

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
        // Nulo desvincula a despesa do projeto
        'project_id': expense.projectId,
        'barcode': expense.barcode,
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

        List<Map<String, dynamic>> updatedRows = const [];
        if (scope == RecurrenceScope.allInstances) {
          updatedRows = await client
              .from('house_expenses')
              .update(recurringUpdate)
              .or('recurring_series_id.eq.$seriesId,id.eq.$seriesId')
              // Ocorrência já acertada em um fechamento fica como está
              .isFilter('settled_at', null)
              .select('id');
        } else if (scope == RecurrenceScope.thisAndFuture) {
          updatedRows = await client
              .from('house_expenses')
              .update(recurringUpdate)
              .or('recurring_series_id.eq.$seriesId,id.eq.$seriesId')
              .gte('due_date', dueDateStr)
              .isFilter('settled_at', null)
              .select('id');
        }
        // O valor e o tipo de rateio mudaram nas outras ocorrências: as regras
        // de rateio delas acompanham
        for (final row in updatedRows) {
          final otherId = row['id'] as String;
          if (otherId != expense.id) await _syncSplitRules(otherId, expense);
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
      // Série ativa: a primeira despesa dela (matriz) segue ativa, mesmo que
      // tenha sido excluída com "só esta"
      final heads = await client
          .from('house_expenses')
          .select('id')
          .eq('house_id', _houseId)
          .eq('is_recurring', true)
          .eq('is_active', true)
          .isFilter('recurring_series_id', null);
      final headIds = [for (final h in heads) h['id'] as String];
      if (headIds.isEmpty) return const [];

      final idList = headIds.join(',');
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .eq('is_recurring', true)
          .isFilter('deleted_at', null)
          .or('id.in.($idList),recurring_series_id.in.($idList)');

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
        if (category.isVariableSpend != null) 'is_variable_spend': category.isVariableSpend,
      });
    } catch (e) {
      throw ServerFailure('Erro ao criar categoria: $e');
    }
  }

  @override
  Future<void> updateCategory(ExpenseCategory category) async {
    if (!_isUuid(category.id)) return;
    final List<dynamic> rows;
    try {
      rows = await client
          .from('categories')
          .update({
            'name': category.name,
            'owner_member_id': _isUuid(category.ownerMemberId) ? category.ownerMemberId : null,
            if (category.isVariableSpend != null) 'is_variable_spend': category.isVariableSpend,
          })
          .eq('id', category.id)
          .eq('house_id', _houseId)
          .select('id');
    } catch (e) {
      throw ServerFailure('Erro ao atualizar categoria: $e');
    }
    // O banco ignora em silêncio a alteração de quem não tem permissão
    if (rows.isEmpty) {
      throw const ServerFailure(
        'Só o dono da casa, um administrador ou quem criou a categoria pode editá-la.',
      );
    }
  }

  @override
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId}) async {
    if (!_isUuid(categoryId)) return;
    if (moveToCategoryId != null) {
      // Move os lançamentos e exclui na mesma transação (migration 0059)
      try {
        await client.rpc('delete_category_moving_expenses', params: {
          'p_category_id': categoryId,
          'p_target_category_id': moveToCategoryId,
        });
      } on PostgrestException catch (e) {
        throw ServerFailure(e.message);
      }
      return;
    }
    final List<dynamic> rows;
    try {
      final expenses = await client
          .from('house_expenses')
          .select('id')
          .eq('house_id', _houseId)
          .eq('category_id', categoryId)
          .isFilter('deleted_at', null);
      final items = await client
          .from('house_expense_items')
          .select('expense_id')
          .eq('category_id', categoryId);
      final inUse = {
        for (final r in expenses) r['id'] as String,
        for (final r in items) r['expense_id'] as String,
      }.length;
      if (inUse > 0) {
        throw ServerFailure(categoryInUseMessage(inUse));
      }

      rows = await client
          .from('categories')
          .delete()
          .eq('id', categoryId)
          .eq('house_id', _houseId)
          .select('id');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      throw ServerFailure('Erro ao excluir categoria: $e');
    }
    if (rows.isEmpty) {
      throw const ServerFailure(
        'Só o dono da casa ou um administrador pode excluir categorias.',
      );
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
      final rows = await OfflineSnapshot.instance.rows(
        'vaults_$_houseId',
        () async => await client
            .from('savings_vaults')
            .select()
            .eq('house_id', _houseId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false),
      );

      return rows.map((r) {
        return SavingsVault(
          id: r['id'] as String,
          name: r['name'] as String,
          targetAmount: Money((r['target_amount_cents'] as num?)?.toInt() ?? 0),
          currentBalance: Money((r['current_balance_cents'] as num).toInt()),
          icon: r['icon'] as String? ?? 'savings',
          colorHex: r['color_hex'] as String? ?? '#10B981',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          targetDate: r['target_date'] == null ? null : DateTime.parse(r['target_date'] as String),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar caixinhas da casa: $e');
    }
  }

  @override
  Future<void> createSavingsVault(SavingsVault vault) async {
    try {
      // A caixinha nasce zerada: o saldo só muda por depósito ou resgate, que
      // deixam lançamento no histórico
      final inserted = await client
          .from('savings_vaults')
          .insert({
            if (_isUuid(vault.id)) 'id': vault.id,
            'house_id': _houseId,
            'name': vault.name,
            // Caixinha sem meta: a coluna só aceita nulo ou valor positivo
            'target_amount_cents': vault.targetAmount.cents > 0 ? vault.targetAmount.cents : null,
            'icon': vault.icon,
            'color_hex': vault.colorHex,
            if (vault.targetDate != null) 'target_date': _dateOnly(vault.targetDate!),
          })
          .select('id')
          .single();

      if (vault.currentBalance.cents > 0) {
        await client.rpc('move_vault_balance', params: {
          'p_vault_id': inserted['id'],
          'p_type': 'deposit',
          'p_amount_cents': vault.currentBalance.cents,
          'p_description': 'Saldo inicial',
        });
      }
    } catch (e) {
      throw ServerFailure('Erro ao criar caixinha: $e');
    }
  }

  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before}) async {
    try {
      var query = client
          .from('savings_transactions')
          .select('id, vault_id, member_id, amount_cents, type, description, created_at, cycle_start_date, counterpart_vault_id')
          .eq('vault_id', vaultId);
      if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
      final rows = await query.order('created_at', ascending: false).limit(limit);

      return rows.map((r) {
        return SavingsTransaction(
          id: r['id'] as String,
          vaultId: r['vault_id'] as String,
          memberId: r['member_id'] as String? ?? '',
          amount: Money((r['amount_cents'] as num).toInt()),
          type: r['type'] as String,
          description: r['description'] as String? ?? '',
          date: DateTime.parse(r['created_at'] as String).toLocal(),
          cycleStartDate: r['cycle_start_date'] == null
              ? null
              : DateTime.parse(r['cycle_start_date'] as String),
          counterpartVaultId: r['counterpart_vault_id'] as String?,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar o histórico da caixinha: $e');
    }
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T')[0];

  @override
  Future<void> updateSavingsVault(SavingsVault vault) async {
    try {
      await client.from('savings_vaults').update({
        'name': vault.name.trim(),
        // Caixinha sem meta: a coluna só aceita nulo ou valor positivo
        'target_amount_cents': vault.targetAmount.cents > 0 ? vault.targetAmount.cents : null,
        'target_date': vault.targetDate == null ? null : _dateOnly(vault.targetDate!),
        'icon': vault.icon,
        'color_hex': vault.colorHex,
      }).eq('id', vault.id);
    } catch (e) {
      throw ServerFailure('Erro ao salvar a caixinha: $e');
    }
  }

  @override
  Future<void> deleteSavingsVault(String vaultId) async {
    try {
      // O banco recusa caixinha com saldo ou que recebe parcelas de acordo em aberto
      await client.rpc('delete_savings_vault', params: {'p_vault_id': vaultId});
    } catch (e) {
      throw ServerFailure('Erro ao excluir a caixinha: $e');
    }
  }

  @override
  Future<void> transferBetweenVaults({
    required String fromVaultId,
    required String toVaultId,
    required Money amount,
    required String description,
  }) async {
    try {
      await client.rpc('transfer_between_vaults', params: {
        'p_from_vault_id': fromVaultId,
        'p_to_vault_id': toVaultId,
        'p_amount_cents': amount.cents,
        'p_description': description,
      });
    } catch (e) {
      throw ServerFailure('Erro ao transferir entre caixinhas: $e');
    }
  }

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? fromCycleStart,
  }) async {
    try {
      // Saldo e extrato mudam juntos no banco, com a caixinha travada
      await client.rpc('move_vault_balance', params: {
        'p_vault_id': vaultId,
        'p_type': 'deposit',
        'p_amount_cents': amount.cents,
        'p_description': description,
        if (fromCycleStart != null)
          'p_cycle_start_date': fromCycleStart.toIso8601String().split('T')[0],
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
    DateTime? returnToCycleStart,
  }) async {
    try {
      await client.rpc('move_vault_balance', params: {
        'p_vault_id': vaultId,
        'p_type': 'withdraw',
        'p_amount_cents': amount.cents,
        'p_description': description,
        if (returnToCycleStart != null)
          'p_cycle_start_date': returnToCycleStart.toIso8601String().split('T')[0],
      });
    } catch (e) {
      throw ServerFailure('Erro ao resgatar da caixinha: $e');
    }
  }

  @override
  Future<String> getHouseSplitModel() async {
    try {
      final row = await OfflineSnapshot.instance.row(
        'split_model_$_houseId',
        () async => await client.from('houses').select('default_split_model').eq('id', _houseId).maybeSingle(),
      );
      return row?['default_split_model'] as String? ?? 'percentage';
    } catch (_) {
      // Coluna opcional ausente no schema remoto: assume o modelo percentual
      return 'percentage';
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
      barcode: r['barcode'] as String?,
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

      // Sem limite de data: fatura atrasada há muito tempo continua para pagar.
      // Só compras sem pagamento e fora de fechamento, como em pay_card_invoice
      final rows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .eq('payment_method_id', paymentMethodId)
          .isFilter('project_id', null)
          .isFilter('deleted_at', null)
          .isFilter('settled_at', null)
          .isFilter('paid_at', null)
          .not('due_date', 'is', null);

      return CardInvoice.withImported(
        CardInvoice.groupOpenInvoices(
          paymentMethodId,
          rows.map((r) => _mapRowToHouseExpense(r)),
        ),
        await _importedInvoices(paymentMethodId, paid: false),
        paid: false,
      );
    } catch (e) {
      throw ServerFailure('Erro ao buscar faturas do cartão: $e');
    }
  }

  /// Faturas importadas do cartão (0090), para as que não têm compra da casa
  /// também aparecerem para pagar. Sem a coluna no banco, nenhuma.
  Future<List<CardInvoice>> _importedInvoices(
    String paymentMethodId, {
    required bool paid,
    DateTime? since,
  }) async {
    try {
      var query = client
          .from('import_batches')
          .select('invoice_due_date, total_cents, invoice_paid_at')
          .eq('house_id', _houseId)
          .eq('payment_method_id', paymentMethodId)
          .eq('status', 'confirmed')
          .not('invoice_due_date', 'is', null);
      query = paid ? query.not('invoice_paid_at', 'is', null) : query.isFilter('invoice_paid_at', null);
      if (since != null) query = query.gte('invoice_due_date', _dateOnly(since));
      final rows = await query;
      return [
        for (final r in rows)
          CardInvoice(
            paymentMethodId: paymentMethodId,
            dueDate: DateTime.parse(r['invoice_due_date'] as String),
            total: Money((r['total_cents'] as num?)?.toInt() ?? 0),
            purchasesCount: 0,
            paidAt: r['invoice_paid_at'] == null
                ? null
                : DateTime.parse(r['invoice_paid_at'] as String).toLocal(),
            importOnly: true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
    bool paidByHouse = false,
  }) async {
    try {
      // O banco confere se algum dos ciclos envolvidos já foi fechado
      await client.rpc('pay_card_invoice', params: {
        'p_payment_method_id': paymentMethodId,
        'p_due_date': invoiceDueDate.toIso8601String().split('T')[0],
        'p_paid_at': paidAt.toUtc().toIso8601String(),
        'p_paid_by_house': paidByHouse,
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

      return CardInvoice.withImported(
        CardInvoice.groupPaidInvoices(
          paymentMethodId,
          rows.map((r) => _mapRowToHouseExpense(r)),
        ),
        await _importedInvoices(paymentMethodId, paid: true, since: since),
        paid: true,
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

  @override
  Future<List<CardInvoiceCode>> getCardInvoiceCodes() async {
    try {
      // Todos: é uma linha por cartão por mês
      final rows = await client
          .from('card_invoice_codes')
          .select('payment_method_id, due_date, barcode')
          .eq('house_id', _houseId);
      return [
        for (final r in rows)
          CardInvoiceCode(
            paymentMethodId: r['payment_method_id'] as String,
            dueDate: DateTime.parse(r['due_date'] as String),
            barcode: r['barcode'] as String,
          ),
      ];
    } catch (e) {
      throw ServerFailure('Erro ao buscar códigos das faturas: $e');
    }
  }

  @override
  Future<void> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  }) async {
    try {
      final dueDate = invoiceDueDate.toIso8601String().split('T')[0];
      final code = barcode?.trim() ?? '';
      if (code.isEmpty) {
        await client
            .from('card_invoice_codes')
            .delete()
            .eq('payment_method_id', paymentMethodId)
            .eq('due_date', dueDate);
        return;
      }
      await client.from('card_invoice_codes').upsert({
        'house_id': _houseId,
        'payment_method_id': paymentMethodId,
        'due_date': dueDate,
        'barcode': code,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'payment_method_id,due_date');
    } catch (e) {
      throw ServerFailure('Erro ao guardar o código da fatura: $e');
    }
  }

  /// Quantos dias as entradas já usadas continuam na lista.
  static const _usedReceiptsDays = 62;

  @override
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts() async {
    try {
      if (!_isUuid(_houseId)) return const [];
      final usedSince = DateTime.now().subtract(const Duration(days: _usedReceiptsDays));
      final rows = await client
          .from('third_party_receipts')
          .select(
            'id, payer_name, description, amount_cents, received_on, vault_id, payment_method_id, '
            'used_mode, used_payment_method_id, used_due_date, used_at',
          )
          .eq('house_id', _houseId)
          .or('status.eq.held,used_at.gte.${usedSince.toUtc().toIso8601String()}')
          .order('received_on', ascending: false)
          .order('created_at', ascending: false);
      return [
        for (final r in rows)
          ThirdPartyReceipt(
            id: r['id'] as String,
            payerName: r['payer_name'] as String,
            description: r['description'] as String?,
            amount: Money((r['amount_cents'] as num).toInt()),
            receivedOn: DateTime.parse(r['received_on'] as String),
            vaultId: r['vault_id'] as String,
            paymentMethodId: r['payment_method_id'] as String?,
            use: ThirdPartyReceiptUse.fromDb(r['used_mode'] as String?),
            usedPaymentMethodId: r['used_payment_method_id'] as String?,
            usedDueDate: r['used_due_date'] == null ? null : DateTime.parse(r['used_due_date'] as String),
            usedAt: r['used_at'] == null ? null : DateTime.parse(r['used_at'] as String).toLocal(),
          ),
      ];
    } catch (e) {
      throw ServerFailure('Erro ao buscar os repasses de terceiros: $e');
    }
  }

  @override
  Future<void> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  }) async {
    try {
      // A entrada e o depósito na caixinha são gravados juntos no banco
      await client.rpc('register_third_party_receipt', params: {
        'p_house_id': _houseId,
        'p_payer_name': payerName.trim(),
        'p_amount_cents': amount.cents,
        'p_received_on': _dateOnly(receivedOn),
        'p_vault_id': vaultId,
        'p_payment_method_id': _isUuid(paymentMethodId) ? paymentMethodId : null,
        'p_description': description?.trim(),
      });
    } catch (e) {
      throw ServerFailure('Erro ao registrar o repasse: $e');
    }
  }

  @override
  Future<void> useThirdPartyReceipts({
    required List<String> receiptIds,
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) async {
    if (receiptIds.isEmpty) return;
    try {
      await client.rpc('use_third_party_receipts', params: {
        'p_receipt_ids': receiptIds,
        'p_mode': use.dbValue,
        'p_payment_method_id': _isUuid(paymentMethodId) ? paymentMethodId : null,
        'p_due_date': invoiceDueDate == null ? null : _dateOnly(invoiceDueDate),
      });
    } catch (e) {
      throw ServerFailure('Erro ao usar o repasse: $e');
    }
  }

  @override
  Future<void> reopenThirdPartyReceipts({
    List<String>? receiptIds,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) async {
    if (receiptIds != null && receiptIds.isEmpty) return;
    if (receiptIds == null && (!_isUuid(paymentMethodId) || invoiceDueDate == null)) return;
    try {
      await client.rpc('reopen_third_party_receipts', params: {
        'p_receipt_ids': receiptIds,
        'p_payment_method_id': receiptIds == null ? paymentMethodId : null,
        'p_due_date': receiptIds == null ? _dateOnly(invoiceDueDate!) : null,
      });
    } catch (e) {
      throw ServerFailure('Erro ao devolver o repasse para a caixinha: $e');
    }
  }

  @override
  Future<void> deleteThirdPartyReceipt(String receiptId) async {
    try {
      await client.rpc('delete_third_party_receipt', params: {'p_receipt_id': receiptId});
    } catch (e) {
      throw ServerFailure('Erro ao excluir o repasse: $e');
    }
  }
}
