import '../../../../core/domain/value_objects/money.dart';
import '../entities/category.dart';
import '../entities/contribution.dart';
import '../entities/house_expense.dart';
import '../entities/house_inflow.dart';
import '../entities/house_member.dart';
import '../entities/house_transaction.dart';
import '../entities/payment_method.dart';
import '../entities/third_party_receipt.dart';
import '../value_objects/transaction_filter.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';

class TransactionAggregatorMetrics {
  final Money totalInflows;
  final Money totalExpenses;
  final Money netBalance;
  final int count;

  const TransactionAggregatorMetrics({
    required this.totalInflows,
    required this.totalExpenses,
    required this.netBalance,
    required this.count,
  });

  static const empty = TransactionAggregatorMetrics(
    totalInflows: Money.zero(),
    totalExpenses: Money.zero(),
    netBalance: Money.zero(),
    count: 0,
  );
}

class TransactionAggregator {
  TransactionAggregator._();

  /// Converte todas as fontes financeiras do Omni Lar em uma lista unificada de transações.
  static List<HouseTransaction> aggregate({
    required List<HouseExpense> expenses,
    required List<Contribution> contributions,
    required List<HouseInflow> inflows,
    required List<ThirdPartyReceipt> receipts,
    required List<ExpenseCategory> categories,
    required List<HouseMember> members,
    required List<PaymentMethod> paymentMethods,
    List<P2PLoan> loans = const [],
  }) {
    final categoryMap = {for (final c in categories) c.id: c};
    final memberMap = {for (final m in members) m.id: m};
    final methodMap = {for (final p in paymentMethods) p.id: p};

    final list = <HouseTransaction>[];

    // 1. Despesas da casa (Saídas)
    for (final e in expenses) {
      final cat = categoryMap[e.categoryId];
      final member = memberMap[e.paidByMemberId];
      final method = methodMap[e.paymentMethodId];

      list.add(
        HouseTransaction(
          id: 'exp_${e.id}',
          title: e.title,
          amount: e.amount,
          type: TransactionType.expense,
          origin: TransactionOrigin.houseExpense,
          date: e.date,
          dueDate: e.dueDate,
          categoryId: e.categoryId,
          categoryName: cat?.name,
          categoryIcon: cat?.icon,
          categoryColorHex: cat?.colorHex,
          memberId: e.paidByMemberId,
          memberName: member?.name,
          paymentMethodId: e.paymentMethodId,
          paymentMethodName: method?.name,
          isPending: e.status == ExpenseStatus.pending,
          notes: e.notes,
          rawEntity: e,
        ),
      );
    }

    // 2. Aportes na Caixinha Geral (Entradas)
    for (final c in contributions) {
      final member = memberMap[c.memberId];
      final method = c.paymentMethodId != null ? methodMap[c.paymentMethodId] : null;

      list.add(
        HouseTransaction(
          id: 'cont_${c.id}',
          title: 'Aporte de ${member?.name.split(' ').first ?? 'Morador'}',
          amount: c.amount,
          type: TransactionType.inflow,
          origin: TransactionOrigin.contribution,
          date: c.date,
          memberId: c.memberId,
          memberName: member?.name,
          paymentMethodId: c.paymentMethodId,
          paymentMethodName: method?.name,
          notes: null,
          rawEntity: c,
        ),
      );
    }

    // 3. Entradas externas da casa (Inflows)
    for (final inf in inflows) {
      list.add(
        HouseTransaction(
          id: 'inf_${inf.id}',
          title: inf.description,
          amount: inf.amount,
          type: TransactionType.inflow,
          origin: TransactionOrigin.houseInflow,
          date: inf.receivedOn,
          notes: inf.source.label,
          rawEntity: inf,
        ),
      );
    }

    // 4. Repasses de Terceiros
    for (final r in receipts) {
      list.add(
        HouseTransaction(
          id: 'rec_${r.id}',
          title: 'Repasse de ${r.payerName}',
          amount: r.amount,
          type: TransactionType.inflow,
          origin: TransactionOrigin.thirdPartyReceipt,
          date: r.receivedOn,
          notes: r.description,
          rawEntity: r,
        ),
      );
    }

    // 5. Amortizações e Pagamentos de Empréstimos / Acordos
    for (final loan in loans) {
      final borrower = memberMap[loan.borrowerMemberId];
      final lender = memberMap[loan.lenderMemberId];
      final lenderLabel = loan.isHouseLender ? 'Caixa da Casa' : (lender?.name ?? 'Morador');

      for (final inst in loan.installments) {
        if (inst.paidAmount.cents <= 0) continue;
        final payDate = inst.paidAt ?? inst.dueDate;

        list.add(
          HouseTransaction(
            id: 'loan_pay_${inst.id}',
            title: 'Amortização: ${loan.title} (${inst.number}/${inst.totalCount})',
            amount: inst.paidAmount,
            type: loan.isHouseLender ? TransactionType.inflow : TransactionType.expense,
            origin: TransactionOrigin.loanRepayment,
            date: payDate,
            dueDate: inst.dueDate,
            memberId: loan.borrowerMemberId,
            memberName: borrower?.name,
            notes: loan.isHouseLender
                ? 'Pago por ${borrower?.name ?? 'Morador'} para o Caixa da Casa'
                : 'Pago por ${borrower?.name ?? 'Morador'} para $lenderLabel',
            rawEntity: inst,
          ),
        );
      }
    }

    // Ordenar da mais recente para a mais antiga
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Aplica todos os filtros definidos no [filter].
  static List<HouseTransaction> filter(
    List<HouseTransaction> transactions,
    TransactionFilter filter,
  ) => filterTransactions(transactions, filter);

  /// Aplica todos os filtros definidos no [filter].
  static List<HouseTransaction> filterTransactions(
    List<HouseTransaction> transactions,
    TransactionFilter filter,
  ) {
    return transactions.where((t) {
      // 1. Tipo (Entrada / Saída)
      if (filter.type != null && t.type != filter.type) {
        return false;
      }

      // 2. Modo Período por Data Range (quando ativo)
      if (filter.periodMode == PeriodMode.dateRange) {
        if (filter.startDate != null) {
          final startDay = DateTime(
            filter.startDate!.year,
            filter.startDate!.month,
            filter.startDate!.day,
          );
          if (t.date.isBefore(startDay)) return false;
        }
        if (filter.endDate != null) {
          final endDay = DateTime(
            filter.endDate!.year,
            filter.endDate!.month,
            filter.endDate!.day,
            23,
            59,
            59,
            999,
          );
          if (t.date.isAfter(endDay)) return false;
        }
      }

      // 3. Categorias (se houver seleção)
      if (filter.categoryIds.isNotEmpty) {
        if (t.categoryId == null || !filter.categoryIds.contains(t.categoryId)) {
          return false;
        }
      }

      // 4. Morador
      if (filter.memberId != null) {
        if (t.memberId != filter.memberId) {
          return false;
        }
      }

      // 5. Forma de Pagamento
      if (filter.paymentMethodId != null) {
        if (t.paymentMethodId != filter.paymentMethodId) {
          return false;
        }
      }

      // 6. Apenas pendentes
      if (filter.onlyPending == true) {
        if (!t.isPending) return false;
      }

      // 7. Busca textual (título, notas, morador, categoria)
      if (filter.searchQuery.trim().isNotEmpty) {
        final query = filter.searchQuery.toLowerCase().trim();
        final matchTitle = t.title.toLowerCase().contains(query);
        final matchCat = t.categoryName?.toLowerCase().contains(query) ?? false;
        final matchMember = t.memberName?.toLowerCase().contains(query) ?? false;
        final matchMethod = t.paymentMethodName?.toLowerCase().contains(query) ?? false;
        final matchNotes = t.notes?.toLowerCase().contains(query) ?? false;

        if (!matchTitle && !matchCat && !matchMember && !matchMethod && !matchNotes) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Calcula as métricas agregadas (total de entradas, saídas e saldo líquido).
  static TransactionAggregatorMetrics calculateMetrics(
    List<HouseTransaction> transactions,
  ) => computeMetrics(transactions);

  /// Calcula as métricas agregadas (total de entradas, saídas e saldo líquido).
  static TransactionAggregatorMetrics computeMetrics(List<HouseTransaction> transactions) {
    var inflowsCents = 0;
    var expensesCents = 0;

    for (final t in transactions) {
      if (t.type == TransactionType.inflow) {
        inflowsCents += t.amount.cents;
      } else {
        expensesCents += t.amount.cents;
      }
    }

    final totalInflows = Money(inflowsCents);
    final totalExpenses = Money(expensesCents);
    final netBalance = Money(inflowsCents - expensesCents);

    return TransactionAggregatorMetrics(
      totalInflows: totalInflows,
      totalExpenses: totalExpenses,
      netBalance: netBalance,
      count: transactions.length,
    );
  }
}
