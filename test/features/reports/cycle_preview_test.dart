import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/finance/domain/entities/card_invoice.dart';
import 'package:omni_lar/features/reports/domain/entities/payment_due_entry.dart';
import 'package:omni_lar/features/reports/domain/services/cycle_preview_builder.dart';
import 'package:omni_lar/features/reports/domain/services/payment_calendar_builder.dart';
import 'package:omni_lar/features/reports/presentation/cubit/reports_cubit.dart';
import 'package:omni_lar/features/reports/presentation/widgets/cycle_preview_section.dart';
import 'package:omni_lar/features/reports/presentation/widgets/payment_calendar_section.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/repositories/settlement_repository.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';
import 'package:omni_lar/features/settlement/domain/services/open_invoice_choices.dart';

final cycle = FinancialCycle(
  start: DateTime(2026, 10, 10),
  end: DateTime(2026, 11, 9),
);
final today = DateTime(2026, 10, 20);

const members = [
  HouseMember(
    id: 'm_ana',
    name: 'Ana Souza',
    role: 'owner',
    defaultSplitPercent: 50,
  ),
  HouseMember(
    id: 'm_bia',
    name: 'Bia Lima',
    role: 'member',
    defaultSplitPercent: 50,
  ),
];

const anaCard = PaymentMethod(
  id: 'pm_card_ana',
  name: 'Nubank Ana',
  type: PaymentMethodType.card,
  ownerMemberId: 'm_ana',
  closingDay: 28,
  dueDay: 5,
);
const houseCard = PaymentMethod(
  id: 'pm_card_casa',
  name: 'Cartão da Casa',
  type: PaymentMethodType.card,
  closingDay: 25,
  dueDay: 1,
);
const houseAccount = PaymentMethod(
  id: 'pm_conta',
  name: 'Conta da Casa',
  type: PaymentMethodType.account,
);
const biaPix = PaymentMethod(
  id: 'pm_pix_bia',
  name: 'Pix Bia',
  type: PaymentMethodType.pix,
  ownerMemberId: 'm_bia',
);
const methods = [anaCard, houseCard, houseAccount, biaPix];

const split = SplitRule.percentage({'m_ana': 50, 'm_bia': 50});

HouseExpense expense(
  String id,
  int cents, {
  required String method,
  ExpenseStatus status = ExpenseStatus.pending,
  DateTime? date,
  DateTime? dueDate,
  String categoryId = 'cat_casa',
  String paidBy = 'm_ana',
  bool outOfPocket = false,
}) => HouseExpense(
  id: id,
  title: id,
  amount: Money(cents),
  date: date ?? DateTime(2026, 10, 12),
  dueDate: dueDate,
  categoryId: categoryId,
  paidByMemberId: paidBy,
  paymentMethodId: method,
  splitRule: split,
  status: status,
  paidOutOfPocket: outOfPocket,
);

/// Uma compra em aberto na fatura do cartão da Ana, uma no cartão da casa e
/// uma conta de luz pendente que a Bia paga pelo Pix dela.
final expenses = [
  expense('mercado', 40000, method: anaCard.id, dueDate: DateTime(2026, 11, 5)),
  expense(
    'farmacia',
    10000,
    method: houseCard.id,
    dueDate: DateTime(2026, 11, 1),
  ),
  expense('luz', 20000, method: biaPix.id, dueDate: DateTime(2026, 10, 15)),
];

SettlementSummary hubSummary({List<P2PLoan> loans = const []}) =>
    const GlobalClearingEngine().computeSettlement(
      cycle: cycle,
      members: members,
      expenses: applyOpenInvoiceChoices(expenses, methods, const {}),
      contributions: const [],
      loans: loans,
    );

class _FakeSettlementRepository implements SettlementRepository {
  final SettlementSummary summary;
  _FakeSettlementRepository(this.summary);

  @override
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  }) async => summary;

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) async {}

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {}

  @override
  Future<bool> isCycleSettled(FinancialCycle cycle) async => false;
}

void main() {
  group('Planejador de aportes', () {
    test(
      'a média do histórico divide pelos ciclos, não pelos meses que o ciclo cruza',
      () {
        const category = ExpenseCategory(
          id: 'cat_mercado',
          name: 'Mercado',
          icon: 'cart',
          colorHex: '#000000',
        );
        // Um ciclo só (10/09 a 09/10) com compras em setembro e em outubro
        final history = [
          expense(
            'm1',
            60000,
            method: houseAccount.id,
            status: ExpenseStatus.paid,
            date: DateTime(2026, 9, 20),
            categoryId: 'cat_mercado',
          ),
          expense(
            'm2',
            40000,
            method: houseAccount.id,
            status: ExpenseStatus.paid,
            date: DateTime(2026, 10, 5),
            categoryId: 'cat_mercado',
          ),
        ];
        CycleFundingEstimate estimateWith(int? cycles) =>
            const CycleFundingEstimator().calculateEstimate(
              cycle: cycle,
              members: members,
              categories: const [category],
              currentCycleExpenses: const [],
              historicalExpenses: history,
              currentCycleContributions: const [],
              historicalCyclesCount: cycles,
            );

        expect(
          estimateWith(
            1,
          ).variableCategoryEstimates.single.averageMonthlyAmount.cents,
          100000,
        );
        // Sem dizer quantos ciclos: conta os meses (comportamento antigo)
        expect(
          estimateWith(
            null,
          ).variableCategoryEstimates.single.averageMonthlyAmount.cents,
          50000,
        );
      },
    );

    test('com fatura e conta em aberto, a cota pendente é a mesma do Hub', () {
      final hub = hubSummary();
      final estimate = const CycleFundingEstimator().calculateEstimate(
        cycle: cycle,
        members: members,
        categories: const [],
        currentCycleExpenses: applyOpenInvoiceChoices(
          expenses,
          methods,
          const {},
        ),
        historicalExpenses: const [],
        currentCycleContributions: const [],
        historicalCyclesCount: 1,
      );

      for (final balance in hub.memberBalances) {
        final quote = estimate.memberQuotes.firstWhere(
          (q) => q.memberId == balance.memberId,
        );
        final owes = balance.netBalance.isNegative
            ? -balance.netBalance.cents
            : 0;
        expect(quote.pendingAmount.cents, owes, reason: balance.memberName);
      }
      // Ana: 35.000 de cota - 40.000 da fatura que ela paga = nada a aportar
      expect(
        estimate.memberQuotes
            .firstWhere((q) => q.memberId == 'm_ana')
            .pendingAmount
            .cents,
        0,
      );
      // Bia: 35.000 de cota - 20.000 da luz que ela paga
      expect(
        estimate.memberQuotes
            .firstWhere((q) => q.memberId == 'm_bia')
            .pendingAmount
            .cents,
        15000,
      );
    });
  });

  group('Prévia do fechamento', () {
    const builder = CyclePreviewBuilder();

    test(
      'usa os saldos do Hub e diz quem paga cada fatura e conta em aberto',
      () {
        final hub = hubSummary();
        final preview = builder.build(
          summary: hub,
          members: members,
          expenses: expenses,
          paymentMethods: methods,
          today: today,
        );

        for (final b in hub.memberBalances) {
          expect(preview.memberById(b.memberId)!.net, b.netBalance);
        }

        final byTitle = {for (final a in preview.assumedPayments) a.title: a};
        expect(byTitle['Fatura Nubank Ana']!.payerMemberId, 'm_ana');
        expect(byTitle['Fatura Cartão da Casa']!.paidByHouse, isTrue);
        expect(byTitle['luz']!.payerMemberId, 'm_bia');
        expect(byTitle['luz']!.isOverdue, isTrue);
        expect(
          preview.memberById('m_ana')!.assumedPayments.map((a) => a.title),
          ['Fatura Nubank Ana'],
        );
      },
    );

    test(
      'a projeção entra pelo percentual de cada um e fica separada do saldo de hoje',
      () {
        final hub = hubSummary();
        final launched = expenses.fold<int>(
          0,
          (acc, e) => acc + e.amount.cents,
        );
        final estimate = CycleFundingEstimate(
          cycle: cycle,
          mode: FundingEstimateMode.historicalAverage,
          fixedCommittedExpenses: Money(launched),
          variableCategoryEstimates: const [],
          currentHouseBalance: const Money.zero(),
          totalProjectedExpenses: Money(launched + 30000),
          netFundingRequired: Money(launched + 30000),
          memberQuotes: const [],
        );
        final preview = builder.build(
          summary: hub,
          members: members,
          expenses: expenses,
          paymentMethods: methods,
          estimate: estimate,
          today: today,
        );

        expect(preview.projectedExtra.cents, 30000);
        final bia = preview.memberById('m_bia')!;
        expect(bia.projectedExtraShare.cents, 15000);
        expect(bia.projectedNet.cents, bia.net.cents - 15000);

        // Ciclo que já terminou não tem projeção
        final later = builder.build(
          summary: hub,
          members: members,
          expenses: expenses,
          paymentMethods: methods,
          estimate: estimate,
          today: DateTime(2026, 11, 20),
        );
        expect(later.hasProjection, isFalse);
      },
    );

    test(
      'parcela de acordo com o Lar aparece como devida ao Caixa da Casa',
      () {
        final loan = P2PLoan(
          id: 'acordo',
          title: 'Acordo com o Lar',
          totalAmount: const Money(10000),
          lenderMemberId: P2PLoan.houseLenderId,
          borrowerMemberId: 'm_bia',
          installmentsCount: 1,
          createdAt: DateTime(2026, 9, 1),
          firstDueDate: DateTime(2026, 9, 20),
          installments: [
            P2PInstallment(
              id: 'p1',
              loanId: 'acordo',
              number: 1,
              totalCount: 1,
              amount: const Money(10000),
              dueDate: DateTime(2026, 9, 20),
            ),
          ],
        );
        final preview = builder.build(
          summary: hubSummary(loans: [loan]),
          members: members,
          expenses: expenses,
          paymentMethods: methods,
          today: today,
        );

        final installment = preview
            .memberById('m_bia')!
            .installmentsToPay
            .single;
        expect(installment.otherMemberName, 'Caixa da Casa');
        expect(
          installment.dueDate.isBefore(cycle.startDate),
          isTrue,
          reason: 'atrasada',
        );
      },
    );

    test('ciclo fechado não considera fatura nem conta em aberto', () {
      final hub = hubSummary().copyWith(status: SettlementStatus.settled);
      final preview = builder.build(
        summary: hub,
        members: members,
        expenses: expenses,
        paymentMethods: methods,
        today: today,
      );
      expect(preview.isSettled, isTrue);
      expect(preview.assumedPayments, isEmpty);
    });
  });

  group('Calendário de pagamentos', () {
    const calendarBuilder = PaymentCalendarBuilder();

    P2PLoan loan(
      String id, {
      required String lender,
      required String borrower,
      required DateTime due,
      bool settleInCycle = true,
      LoanRepaymentMode mode = LoanRepaymentMode.installments,
    }) => P2PLoan(
      id: id,
      title: id,
      totalAmount: const Money(5000),
      lenderMemberId: lender,
      borrowerMemberId: borrower,
      installmentsCount: 1,
      createdAt: DateTime(2026, 9, 1),
      firstDueDate: due,
      settleInCycle: settleInCycle,
      repaymentMode: mode,
      installments: [
        P2PInstallment(
          id: '$id-1',
          loanId: id,
          number: 1,
          totalCount: 1,
          amount: const Money(5000),
          dueDate: due,
        ),
      ],
    );

    PaymentCalendar calendarWith(List<P2PLoan> loans) {
      final preview = const CyclePreviewBuilder().build(
        summary: hubSummary(loans: loans),
        members: members,
        expenses: expenses,
        paymentMethods: methods,
        invoiceCodes: {
          CardInvoiceCode.keyOf(anaCard.id, DateTime(2026, 11, 5)): '23790000',
        },
        today: today,
      );
      return calendarBuilder.build(
        preview: preview,
        loans: loans,
        members: members,
        today: today,
      );
    }

    test(
      'junta faturas, contas, parcelas fora do fechamento e o Super Pix',
      () {
        final calendar = calendarWith([
          loan(
            'dentro',
            lender: 'm_ana',
            borrower: 'm_bia',
            due: DateTime(2026, 10, 25),
          ),
          loan(
            'fora',
            lender: 'm_ana',
            borrower: 'm_bia',
            due: DateTime(2026, 10, 28),
            settleInCycle: false,
          ),
          loan(
            'livre',
            lender: 'm_bia',
            borrower: 'm_ana',
            due: P2PLoan.openEndedPlaceholderDueDate,
            mode: LoanRepaymentMode.openEnded,
          ),
        ]);

        // Parcela cobrada no fechamento não vira linha própria
        expect(
          calendar.entries.where((e) => e.title.startsWith('dentro')),
          isEmpty,
        );
        final fora = calendar.entries.singleWhere(
          (e) => e.title.startsWith('fora'),
        );
        expect(fora.payerId, 'm_bia');
        expect(fora.receiverId, 'm_ana');

        expect(
          calendar.entries.map((e) => e.kind),
          contains(PaymentDueKind.closing),
        );
        expect(
          calendar.entries.last.kind,
          PaymentDueKind.openEnded,
          reason: 'sem prazo fica no fim',
        );

        final invoice = calendar.entries.singleWhere(
          (e) => e.title == 'Fatura Nubank Ana',
        );
        expect(invoice.barcode, '23790000');
        expect(invoice.reimbursedAtClosing, isTrue);
        final houseInvoice = calendar.entries.singleWhere(
          (e) => e.title == 'Fatura Cartão da Casa',
        );
        expect(houseInvoice.payerId, isNull);
        expect(houseInvoice.reimbursedAtClosing, isFalse);

        // A luz venceu antes de hoje
        expect(
          calendar.entries.singleWhere((e) => e.title == 'luz').isOverdue,
          isTrue,
        );
      },
    );

    test('o Super Pix entra uma vez, no último dia do ciclo', () {
      final calendar = calendarWith(const []);
      final closings = calendar.entries.where(
        (e) => e.kind == PaymentDueKind.closing,
      );
      expect(closings, hasLength(hubSummary().transfers.length));
      final lastDay = DateTime(
        cycle.endDate.year,
        cycle.endDate.month,
        cycle.endDate.day,
      );
      expect(closings.every((e) => e.date == lastDay), isTrue);
    });

    test('ciclo futuro não traz parcela atrasada de antes dele', () {
      final next = FinancialCycle(
        start: DateTime(2026, 11, 10),
        end: DateTime(2026, 12, 9),
      );
      final preview = const CyclePreviewBuilder().build(
        summary: const GlobalClearingEngine().computeSettlement(
          cycle: next,
          members: members,
          expenses: const [],
          contributions: const [],
          loans: const [],
        ),
        members: members,
        expenses: const [],
        paymentMethods: methods,
        today: today,
      );
      final calendar = calendarBuilder.build(
        preview: preview,
        loans: [
          loan(
            'antiga',
            lender: 'm_ana',
            borrower: 'm_bia',
            due: DateTime(2026, 10, 1),
            settleInCycle: false,
          ),
          loan(
            'nova',
            lender: 'm_ana',
            borrower: 'm_bia',
            due: DateTime(2026, 11, 20),
            settleInCycle: false,
          ),
        ],
        members: members,
        today: today,
      );
      expect(calendar.entries.map((e) => e.title), ['nova 1/1']);
    });

    test('totais do morador somam só o que tem data', () {
      final calendar = calendarWith([
        loan(
          'fora',
          lender: 'm_ana',
          borrower: 'm_bia',
          due: DateTime(2026, 10, 28),
          settleInCycle: false,
        ),
        loan(
          'livre',
          lender: 'm_ana',
          borrower: 'm_bia',
          due: P2PLoan.openEndedPlaceholderDueDate,
          mode: LoanRepaymentMode.openEnded,
        ),
      ]);
      final expected = calendar.entries
          .where((e) => e.payerId == 'm_bia' && e.date != null)
          .fold<int>(0, (acc, e) => acc + e.amount.cents);
      expect(calendar.outgoingOf('m_bia').cents, expected);
      expect(
        calendar
            .forMember('m_bia')
            .any((e) => e.kind == PaymentDueKind.openEnded),
        isTrue,
      );
    });
  });

  group('Seção na tela de Relatórios', () {
    Future<void> pump(WidgetTester tester, String currentMemberId) async {
      final cubit = ReportsCubit(
        _FakeSettlementRepository(hubSummary()),
        now: () => today,
      );
      await cubit.loadPreview(
        FinanceState(
          currentCycle: cycle,
          members: members,
          expenses: expenses,
          paymentMethods: methods,
        ),
      );
      var showAll = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlocProvider.value(
                value: cubit,
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      CyclePreviewSection(
                        currentMemberId: currentMemberId,
                        showAll: showAll,
                        onShowAllChanged: (v) => setState(() => showAll = v),
                        onRetry: () {},
                      ),
                      PaymentCalendarSection(
                        currentMemberId: currentMemberId,
                        showAll: showAll,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('abre na prévia de quem está logado e mostra todos ao trocar', (
      tester,
    ) async {
      await pump(tester, 'm_bia');

      expect(find.text('Prévia do fechamento'), findsOneWidget);
      expect(find.text('Bia Lima'), findsOneWidget);
      expect(find.text('Ana Souza'), findsNothing);
      // Calendário só com o que envolve a Bia
      expect(find.text('Próximos pagamentos'), findsOneWidget);
      expect(find.text('Você paga até o fechamento'), findsOneWidget);
      expect(find.text('Fatura Nubank Ana'), findsNothing);

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Souza'), findsOneWidget);
      expect(
        find.text('Pagas pelo Caixa da Casa nesta prévia'),
        findsOneWidget,
      );
      expect(find.text('Fatura Nubank Ana'), findsOneWidget);
      expect(find.text('Você paga até o fechamento'), findsNothing);
    });

    testWidgets('sem morador logado mostra todos, sem a troca', (tester) async {
      await pump(tester, '');
      expect(find.text('Ana Souza'), findsOneWidget);
      expect(find.text('Bia Lima'), findsOneWidget);
      expect(find.text('Minha prévia'), findsNothing);
    });
  });
}
