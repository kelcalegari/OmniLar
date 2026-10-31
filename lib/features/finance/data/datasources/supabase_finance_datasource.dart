import 'dart:async';

import 'house_expense_payload.dart';
import 'house_expense_row.dart';
import '../../domain/entities/house_initial_balance.dart';
import '../../domain/entities/house_settings.dart';
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
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/opening_inflows.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/house_inflow.dart';
import '../../domain/entities/budget_alert_stages.dart';
import '../../domain/entities/category_default_split.dart';
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
          // Entradas de fora (0096)
          'house_inflows',
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
            defaultSplit: CategoryDefaultSplit.fromJson(r['default_split']),
            budgetAlertStages: r['budget_alert_stages'] == null
                ? null
                : BudgetAlertStages.fromJson(r['budget_alert_stages']),
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
            usualInvoicePayerId: r['usual_invoice_payer'] as String?,
            cycleAssignment: CardCycleAssignment.fromDb(r['cycle_assignment']),
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

      // Cartões e em qual ciclo cada um conta a compra (0104); banco sem a
      // coluna lê só os ids e vale o vencimento da fatura
      List<Map<String, dynamic>> cardRows;
      try {
        cardRows = await OfflineSnapshot.instance.rows(
          'card_cycles_$_houseId',
          () async => await client
              .from('payment_methods')
              .select('id, cycle_assignment')
              .eq('house_id', _houseId)
              .eq('type', 'card'),
        );
      } catch (_) {
        cardRows = await OfflineSnapshot.instance.rows(
          'card_ids_$_houseId',
          () async => await client
              .from('payment_methods')
              .select('id')
              .eq('house_id', _houseId)
              .eq('type', 'card'),
        );
      }
      final cardAssignments = {
        for (final r in cardRows)
          r['id'] as String: CardCycleAssignment.fromDb(r['cycle_assignment']),
      };

      return rows
          .map((r) => houseExpenseFromRow(r))
          .where(
            (e) => expenseBelongsToCycle(
              e,
              cycle,
              isCardPayment: cardAssignments.containsKey(e.paymentMethodId),
              cardCycleAssignment:
                  cardAssignments[e.paymentMethodId] ?? CardCycleAssignment.invoiceDue,
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

      return rows.map((r) => houseExpenseFromRow(r)).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar despesas do projeto: $e');
    }
  }

  @override
  Future<Money> getOpeningBalance(FinancialCycle cycle) async {
    final parts = await Future.wait([
      _rolledSurplus(cycle),
      getVaultReturnsForCycle(cycle),
      _houseLoansRepaidToCycle(cycle),
      _houseInflowsTotal(cycle),
    ]);
    return parts[0] + parts[1] + parts[2] + parts[3];
  }

  /// Entradas de fora do ciclo (0096). Sem a tabela (migration ainda não
  /// aplicada) ou sem conexão, nada entra.
  Future<Money> _houseInflowsTotal(FinancialCycle cycle) async {
    try {
      return HouseInflow.total(await getHouseInflowsForCycle(cycle));
    } catch (_) {
      return const Money.zero();
    }
  }

  /// Empréstimos do Caixa do ciclo pagos fora do fechamento (0088): o dinheiro
  /// voltou ao Caixa no ciclo em que foi pago.
  Future<Money> _houseLoansRepaidToCycle(FinancialCycle cycle) async {
    String dateOnly(DateTime d) => d.toIso8601String().split('T')[0];
    try {
      final cents = await client.rpc('house_loans_repaid_to_cycle', params: {
        'p_house_id': _houseId,
        'p_start': dateOnly(cycle.startDate),
        'p_end': dateOnly(cycle.endDate),
      });
      return Money((cents as num?)?.toInt() ?? 0);
    } catch (_) {
      return const Money.zero();
    }
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

  /// Sobra que o fechamento do ciclo anterior deixou no Caixa. Sem fechamento
  /// anterior, o primeiro ciclo da casa começa com o saldo que ela já tinha na
  /// conta (0093).
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
      if (row == null) {
        final initial = await getHouseInitialBalance();
        return initial.rolledSurplusFor(cycle, hasPreviousSettlement: false);
      }
      rolledCents = (row['surplus_rolled_cents'] as num?)?.toInt() ?? 0;
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
    final byVault = await _vaultReturnsByVault(cycle);
    return Money(byVault.values.fold<int>(0, (acc, m) => acc + m.cents));
  }

  /// Resgates devolvidos ao Caixa do ciclo, por caixinha.
  Future<Map<String, Money>> _vaultReturnsByVault(FinancialCycle cycle) async {
    try {
      String dateOnly(DateTime d) => d.toIso8601String().split('T')[0];
      final rows = await OfflineSnapshot.instance.rows(
        'vault_returns_by_vault_${_houseId}_${dateOnly(cycle.startDate)}',
        () async => await client
            .from('savings_transactions')
            .select('vault_id, amount_cents, type')
            .eq('house_id', _houseId)
            .gte('cycle_start_date', dateOnly(cycle.startDate))
            .lte('cycle_start_date', dateOnly(cycle.endDate)),
      );
      // Depósito tirado do Caixa do ciclo desfaz parte do que as caixinhas devolveram
      final cents = <String, int>{};
      for (final r in rows) {
        final amount = (r['amount_cents'] as num).toInt();
        final vaultId = r['vault_id']?.toString() ?? '';
        cents[vaultId] = (cents[vaultId] ?? 0) + (r['type'] == 'withdraw' ? amount : -amount);
      }
      return {for (final e in cents.entries) e.key: Money(e.value)};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle) async {
    final rolledFuture = _rolledSurplus(cycle);
    final loansRepaidFuture = _houseLoansRepaidToCycle(cycle);
    final byVaultFuture = _vaultReturnsByVault(cycle);
    final vaultsFuture = getSavingsVaults().catchError((_) => <SavingsVault>[]);
    final thirdPartyFuture = _houseInflowsTotal(cycle);
    await Future.wait<void>([rolledFuture, loansRepaidFuture, byVaultFuture, vaultsFuture, thirdPartyFuture]);
    return OpeningInflows(
      rolledSurplus: await rolledFuture,
      houseLoansRepaid: await loansRepaidFuture,
      vaultWithdrawalsByVault: await byVaultFuture,
      vaultNames: {for (final v in await vaultsFuture) v.id: v.name},
      thirdParty: await thirdPartyFuture,
    );
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
        final dateStr = (r['paid_at'] ?? r['date'] ?? r['cycle_start_date'] ?? r['created_at']) as String?;
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
      final vaultReturnsFuture = _vaultReturnsByVault(cycle);
      final loansFundedFuture = _houseLoansFunded(cycle);
      final loansRepaidFuture = _houseLoansRepaidToCycle(cycle);
      final thirdPartyFuture = _houseInflowsTotal(cycle);
      await Future.wait<void>([
        expensesFuture,
        contributionsFuture,
        rolledFuture,
        vaultReturnsFuture,
        loansFundedFuture,
        loansRepaidFuture,
        thirdPartyFuture,
      ]);
      final loansFunded = await loansFundedFuture;
      final cycleExpenses = await expensesFuture;
      final cycleContributions = await contributionsFuture;
      final inflows = OpeningInflows(
        rolledSurplus: await rolledFuture,
        houseLoansRepaid: await loansRepaidFuture,
        vaultWithdrawalsByVault: await vaultReturnsFuture,
        thirdParty: await thirdPartyFuture,
      );
      final vaultReturns = inflows.vaultWithdrawalsTotal;

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

      // A sobra deixada pelo ciclo anterior, as devoluções das caixinhas, os
      // empréstimos do ciclo já pagos e as entradas de fora entram como folga do Caixa
      final openingBalance =
          inflows.rolledSurplus + vaultReturns + inflows.houseLoansRepaid + inflows.thirdParty;
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
        openingInflows: inflows,
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
        if (expense.paidByParticipantId != null && _isUuid(expense.paidByParticipantId))
          'paid_by_participant_id': expense.paidByParticipantId
        else if (expense.paidByParticipantId == null)
          'paid_by_participant_id': null,
        'paid_by_id': expense.paidByParticipantId != null
            ? (client.auth.currentUser?.id ?? expense.paidByMemberId)
            : (_isUuid(expense.paidByMemberId)
                ? expense.paidByMemberId
                : (client.auth.currentUser?.id ?? expense.paidByMemberId)),
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
        'description': expense.description,
        'notes': expense.notes,
        // Nulo desvincula a despesa do projeto
        'project_id': expense.projectId,
        'barcode': expense.barcode,
        'attachment_path': expense.attachmentPath,
        'attachment_name': expense.attachmentName,
        'attachment_content_type': expense.attachmentContentType,
        'attachment_size_bytes': expense.attachmentSizeBytes,
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
          'description': expense.description,
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

      return rows.map((r) => houseExpenseFromRow(r)).toList();
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
  Future<void> updateContribution(Contribution contribution) async {
    List<dynamic> rows;
    try {
      rows = await client.from('contributions').update({
        'member_id': contribution.memberId,
        'amount_cents': contribution.amount.cents,
        'cycle_start_date': contribution.date.toIso8601String().split('T')[0],
        'paid_at': contribution.date.toUtc().toIso8601String(),
      }).eq('id', contribution.id).eq('house_id', _houseId).select('id');
    } catch (e) {
      throw ServerFailure('Erro ao atualizar aporte: $e');
    }
    if (rows.isEmpty) {
      throw const ServerFailure(
        'Só quem lançou ou um administrador altera este aporte, e só com o ciclo aberto.',
      );
    }
  }

  @override
  Future<void> deleteContribution(String contributionId) async {
    List<dynamic> rows;
    try {
      rows = await client.from('contributions')
          .delete()
          .eq('id', contributionId)
          .eq('house_id', _houseId)
          .select('id');
    } catch (e) {
      throw ServerFailure('Erro ao excluir aporte: $e');
    }
    if (rows.isEmpty) {
      throw const ServerFailure(
        'Só quem lançou ou um administrador exclui este aporte, e só com o ciclo aberto.',
      );
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
        if (category.defaultSplit != null) 'default_split': category.defaultSplit!.toJson(),
        if (category.budgetAlertStages != null) 'budget_alert_stages': category.budgetAlertStages!.toJson(),
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
            // Null limpa o padrão (volta à divisão da casa)
            'default_split': category.defaultSplit?.toJson(),
            // Null volta aos estágios da casa (0099)
            'budget_alert_stages': category.budgetAlertStages?.toJson(),
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
      // Só cartão tem quem costuma pagar a fatura (0100)
      if (paymentMethod.isCreditCard && _isUuid(paymentMethod.usualInvoicePayerId)) {
        payload['usual_invoice_payer'] = paymentMethod.usualInvoicePayerId;
      }
      // Em qual ciclo a compra conta (0104): só quando foge do padrão
      if (paymentMethod.isCreditCard &&
          paymentMethod.cycleAssignment != CardCycleAssignment.invoiceDue) {
        payload['cycle_assignment'] = paymentMethod.cycleAssignment.dbValue;
      }
      try {
        await client.from('payment_methods').insert(payload);
      } catch (e) {
        // Banco sem a 0100/0104: cria sem os parâmetros que ele não conhece
        if (!payload.containsKey('usual_invoice_payer') && !payload.containsKey('cycle_assignment')) {
          rethrow;
        }
        payload.remove('usual_invoice_payer');
        payload.remove('cycle_assignment');
        await client.from('payment_methods').insert(payload);
      }
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
      Future<void> save() => client
          .from('payment_methods')
          .update(payload)
          .eq('id', paymentMethod.id)
          .eq('house_id', _houseId);
      // Null limpa a sugestão de quem costuma pagar a fatura (0100)
      payload['usual_invoice_payer'] =
          paymentMethod.isCreditCard && _isUuid(paymentMethod.usualInvoicePayerId)
              ? paymentMethod.usualInvoicePayerId
              : null;
      payload['cycle_assignment'] = paymentMethod.isCreditCard
          ? paymentMethod.cycleAssignment.dbValue
          : CardCycleAssignment.invoiceDue.dbValue;
      try {
        await save();
      } catch (e) {
        // Banco sem a 0100/0104: grava o resto e deixa os parâmetros de fora
        final text = e.toString();
        if (!text.contains('usual_invoice_payer') && !text.contains('cycle_assignment')) rethrow;
        payload.remove('usual_invoice_payer');
        payload.remove('cycle_assignment');
        await save();
      }
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
          monthlyGoal: (r['monthly_goal_cents'] as num?) == null ? null : Money((r['monthly_goal_cents'] as num).toInt()),
          countsInQuota: r['counts_in_quota'] == true,
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
            // Só vão se a caixinha já nasce na cota: o banco só deixa administradores
            if (vault.countsInQuota) 'counts_in_quota': true,
            if (vault.monthlyGoal != null) 'monthly_goal_cents': vault.monthlyGoal!.cents,
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
    final base = {
      'name': vault.name.trim(),
      // Caixinha sem meta: a coluna só aceita nulo ou valor positivo
      'target_amount_cents': vault.targetAmount.cents > 0 ? vault.targetAmount.cents : null,
      'target_date': vault.targetDate == null ? null : _dateOnly(vault.targetDate!),
      'icon': vault.icon,
      'color_hex': vault.colorHex,
    };
    try {
      try {
        // Meta na cota (0102): valores iguais aos gravados passam; só administradores mudam
        await client.from('savings_vaults').update({
          ...base,
          'counts_in_quota': vault.countsInQuota,
          'monthly_goal_cents':
              vault.monthlyGoal != null && vault.monthlyGoal!.cents > 0 ? vault.monthlyGoal!.cents : null,
        }).eq('id', vault.id);
      } on PostgrestException catch (e) {
        // Banco sem a 0102: grava o que ele já conhece
        if (!e.message.contains('counts_in_quota') && !e.message.contains('monthly_goal_cents')) rethrow;
        await client.from('savings_vaults').update(base).eq('id', vault.id);
      }
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

  @override
  Future<Map<String, Money>> getMemberIncomes() async {
    try {
      // A policy de member_incomes só devolve o que a visibilidade da casa permite
      final rows = await client
          .from('member_incomes')
          .select('user_id, monthly_income_cents')
          .eq('house_id', _houseId);
      return {
        for (final r in rows)
          r['user_id'] as String: Money((r['monthly_income_cents'] as num).toInt()),
      };
    } catch (_) {
      // Banco sem a 0102: ninguém informou renda
      return {};
    }
  }

  @override
  Future<void> setMyIncome(Money? income) async {
    try {
      if (income != null && income.cents <= 0) {
        throw const ServerFailure('A renda deve ser maior que zero.');
      }
      await client.rpc('set_my_income', params: {
        'p_house_id': _houseId,
        'p_income_cents': income?.cents,
      });
    } on ServerFailure {
      rethrow;
    } catch (e) {
      throw ServerFailure('Não foi possível salvar a renda: $e');
    }
  }

  @override
  Future<HouseSettings> getHouseSettings() async {
    try {
      final row = await OfflineSnapshot.instance.row(
        'house_settings_$_houseId',
        () async {
          // Da mais nova para a mais antiga: banco sem a 0116, a 0104, a 0103, a 0102, a 0101, a 0100, a 0099, a 0098, a 0097, a 0094 ou a 0092
          // ainda lê as colunas que já tem
          const attempts = [
            HouseSettings.columns,
            HouseSettings.columnsBefore0116,
            HouseSettings.columnsBefore0104,
            HouseSettings.columnsBefore0103,
            HouseSettings.columnsBefore0102,
            HouseSettings.columnsBefore0101,
            HouseSettings.columnsBefore0100,
            HouseSettings.columnsBefore0099,
            HouseSettings.columnsBefore0098,
            HouseSettings.columnsBefore0097,
            HouseSettings.columnsBefore0094,
          ];
          for (final columns in attempts) {
            try {
              return await client.from('houses').select(columns).eq('id', _houseId).maybeSingle();
            } catch (_) {}
          }
          // Colunas da 0091 ainda não aplicadas lançam daqui para o catch abaixo
          return await client
              .from('houses')
              .select(HouseSettings.columnsBefore0092)
              .eq('id', _houseId)
              .maybeSingle();
        },
      );
      return HouseSettings.fromJson(row);
    } catch (_) {
      // Colunas da 0091 ainda não aplicadas no banco: valem os padrões
      return const HouseSettings();
    }
  }

  @override
  Future<HouseInitialBalance> getHouseInitialBalance() async {
    try {
      final row = await OfflineSnapshot.instance.row(
        'house_initial_balance_$_houseId',
        () async =>
            await client.from('houses').select(HouseInitialBalance.columns).eq('id', _houseId).maybeSingle(),
      );
      return HouseInitialBalance.fromJson(row);
    } catch (_) {
      // Colunas da 0093 ainda não aplicadas no banco: a casa começou do zero
      return const HouseInitialBalance();
    }
  }

  @override
  Future<HouseInitialBalance> setHouseInitialBalance({
    required Money reserve,
    required Money cash,
    required DateTime cycleStart,
  }) async {
    try {
      final result = await client.rpc('set_house_initial_balance', params: {
        'p_house_id': _houseId,
        'p_reserve_cents': reserve.cents,
        'p_cash_cents': cash.cents,
        'p_cycle_start': cycleStart.toIso8601String().split('T')[0],
      });
      return HouseInitialBalance.fromJson(Map<String, dynamic>.from(result as Map));
    } catch (e) {
      throw ServerFailure(_initialBalanceError(e));
    }
  }

  /// Mensagem do banco (ex.: ciclo já fechado) sem o embrulho do PostgREST.
  static String _initialBalanceError(Object e) {
    final message = e is PostgrestException ? e.message : e.toString();
    return 'Não foi possível salvar o saldo inicial: $message';
  }

  @override
  Future<HouseSettings> updateHouseSettings(Map<String, dynamic> changes) async {
    try {
      final result = await client.rpc('update_house_settings', params: {
        'p_house_id': _houseId,
        'p_settings': changes,
      });
      return HouseSettings.fromJson(Map<String, dynamic>.from(result as Map));
    } catch (e) {
      throw ServerFailure('Não foi possível salvar as configurações da casa: $e');
    }
  }

  // --- Helpers de Mapeamento ---
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
          rows.map((r) => houseExpenseFromRow(r)),
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
          rows.map((r) => houseExpenseFromRow(r)),
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

  // --- Entradas de fora (0096) ---
  HouseInflow _mapHouseInflow(Map<String, dynamic> r) => HouseInflow(
        id: r['id'] as String,
        amount: Money((r['amount_cents'] as num).toInt()),
        receivedOn: DateTime.parse(r['received_on'] as String),
        description: (r['description'] as String?) ?? '',
        source: HouseInflowSource.fromDb(r['source'] as String?),
        expenseId: r['expense_id'] as String?,
        createdBy: r['created_by'] as String?,
      );

  Map<String, dynamic> _houseInflowRow(HouseInflow inflow) => {
        'amount_cents': inflow.amount.cents,
        'received_on': _dateOnly(inflow.receivedOn),
        'description': inflow.description.trim(),
        'source': inflow.source.dbValue,
        'expense_id': _isUuid(inflow.expenseId) ? inflow.expenseId : null,
      };

  /// O banco recusa (RLS) entrada em ciclo fechado; a mensagem diz o porquê.
  static String _houseInflowError(Object e, String fallback) {
    final text = e.toString();
    if (text.contains('row-level security') || text.contains('42501')) {
      return 'O ciclo desse dia já foi fechado. Reabra o ciclo no Fechamento para mexer nas entradas dele.';
    }
    return '$fallback: $e';
  }

  @override
  Future<List<HouseInflow>> getHouseInflowsForCycle(FinancialCycle cycle) async {
    try {
      if (!_isUuid(_houseId)) return const [];
      final start = _dateOnly(cycle.startDate);
      final rows = await OfflineSnapshot.instance.rows(
        'house_inflows_${_houseId}_$start',
        () async => await client
            .from('house_inflows')
            .select('id, amount_cents, received_on, description, source, expense_id, created_by')
            .eq('house_id', _houseId)
            .gte('received_on', start)
            .lte('received_on', _dateOnly(cycle.endDate))
            .order('received_on', ascending: false)
            .order('created_at', ascending: false),
      );
      return rows.map(_mapHouseInflow).toList();
    } catch (e) {
      throw ServerFailure('Erro ao buscar as entradas de fora: $e');
    }
  }

  @override
  Future<void> addHouseInflow(HouseInflow inflow) async {
    try {
      await client.from('house_inflows').insert({
        ..._houseInflowRow(inflow),
        'house_id': _houseId,
        'created_by': client.auth.currentUser?.id,
      });
    } catch (e) {
      throw ServerFailure(_houseInflowError(e, 'Erro ao lançar a entrada de fora'));
    }
  }

  @override
  Future<void> updateHouseInflow(HouseInflow inflow) async {
    List<dynamic> rows;
    try {
      rows = await client
          .from('house_inflows')
          .update(_houseInflowRow(inflow))
          .eq('id', inflow.id)
          .eq('house_id', _houseId)
          .select('id');
    } catch (e) {
      throw ServerFailure(_houseInflowError(e, 'Erro ao corrigir a entrada de fora'));
    }
    // Sem linha alterada: o RLS barrou (outro morador ou ciclo fechado)
    if (rows.isEmpty) {
      throw const ServerFailure(
        'Só quem lançou ou um administrador corrige esta entrada, e só com o ciclo aberto.',
      );
    }
  }

  @override
  Future<void> deleteHouseInflow(String inflowId) async {
    List<dynamic> rows;
    try {
      rows = await client
          .from('house_inflows')
          .delete()
          .eq('id', inflowId)
          .eq('house_id', _houseId)
          .select('id');
    } catch (e) {
      throw ServerFailure(_houseInflowError(e, 'Erro ao excluir a entrada de fora'));
    }
    if (rows.isEmpty) {
      throw const ServerFailure(
        'Só quem lançou ou um administrador exclui esta entrada, e só com o ciclo aberto.',
      );
    }
  }
}
