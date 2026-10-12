import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('GlobalClearingEngine (Motor de Compensação / Super Pix)', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );

    test('Caso Obrigatório RN-INT-02 da especificação: Kelvynn, Cris e Casa', () {
      final members = [
        const HouseMember(id: 'member_kelvynn', name: 'Kelvynn', role: 'owner'),
        const HouseMember(id: 'member_cris', name: 'Cris', role: 'member'),
      ];

      // Kelvynn pagou a luz de R$ 200 do próprio bolso (crédito contra a Casa)
      final expenses = [
        HouseExpense(
          id: 'exp_luz',
          title: 'Conta de Luz',
          amount: const Money(20000), // R$ 200,00
          date: DateTime(2026, 10, 15),
          paidByMemberId: 'member_kelvynn',
          paidOutOfPocket: true,
          dueDate: DateTime(2026, 10, 15),
          categoryId: 'cat_contas',
          paymentMethodId: 'pm_personal',
          splitRule: const SplitRule.percentage({
            'member_kelvynn': 60,
            'member_cris': 40,
          }),
        ),
      ];

      // Kelvynn deve R$ 100 para o Cris (P2P de um jogo)
      final loans = [
        P2PLoan(
          id: 'loan_jogo',
          title: 'Jogo de Videogame',
          totalAmount: const Money(10000), // R$ 100,00
          lenderMemberId: 'member_cris',
          borrowerMemberId: 'member_kelvynn',
          installmentsCount: 1,
          createdAt: DateTime(2026, 10, 10),
          firstDueDate: DateTime(2026, 10, 20),
          installments: [
            P2PInstallment(
              id: 'inst_jogo_1',
              loanId: 'loan_jogo',
              number: 1,
              totalCount: 1,
              amount: const Money(10000), // R$ 100,00
              dueDate: DateTime(2026, 10, 20),
            ),
          ],
        ),
      ];

      // Metas de aporte: Kelvynn deve 500, Cris deve 100
      final customTargets = {
        'member_kelvynn': const Money(50000), // R$ 500,00
        'member_cris': const Money(10000), // R$ 100,00
      };

      // Cris já pagou seu aporte de 100
      final contributions = [
        Contribution(
          id: 'contrib_cris',
          memberId: 'member_cris',
          amount: const Money(10000),
          date: DateTime(2026, 10, 6),
        ),
      ];

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: expenses,
        contributions: contributions,
        loans: loans,
        customContributionTargets: customTargets,
      );

      // Verificando Saldo Líquido do Kelvynn:
      // Aporte pago (0) - devido (500) = -500
      // Reembolso luz = +200
      // P2P para Cris = -100
      // Total Líquido Kelvynn = -500 + 200 - 100 = -400 (R$ -400,00)
      final kelvynnBalance = summary.memberBalances.firstWhere(
        (m) => m.memberId == 'member_kelvynn',
      );
      expect(kelvynnBalance.netBalance.cents, equals(-40000));
      expect(kelvynnBalance.isDebtor, isTrue);

      // Saldo Líquido do Cris:
      // Aporte pago (100) - devido (100) = 0
      // Reembolso luz = 0
      // P2P a receber = +100
      // Total Líquido Cris = +100 (R$ +100,00 a receber)
      final crisBalance = summary.memberBalances.firstWhere(
        (m) => m.memberId == 'member_cris',
      );
      expect(crisBalance.netBalance.cents, equals(10000));
      expect(crisBalance.isCreditor, isTrue);

      // Super Pix gerado:
      // O motor casa a dívida com o credor!
      expect(summary.transfers.isNotEmpty, isTrue);
      final transferToCris = summary.transfers.firstWhere(
        (t) => t.toMemberId == 'member_cris',
      );
      expect(transferToCris.fromMemberId, equals('member_kelvynn'));
      expect(
        transferToCris.amount.cents,
        equals(10000),
      ); // R$ 100,00 para o Cris

      // Total P2P compensado no ciclo deve ser exatamente R$ 100,00 (sem divisão indevida)
      expect(summary.totalP2PCleared.cents, equals(10000));
    });

    test(
      'Consistência Matemática: soma de saldos com divisões em centavos',
      () {
        final members = [
          const HouseMember(id: 'm1', name: 'Alice', defaultSplitPercent: 50),
          const HouseMember(id: 'm2', name: 'Bob', defaultSplitPercent: 50),
        ];

        final expenses = [
          HouseExpense(
            id: 'exp_1',
            title: 'Mercado',
            amount: const Money(15000), // 150,00
            date: DateTime(2026, 10, 10),
            paidByMemberId: 'm1',
            paidOutOfPocket: true,
            dueDate: DateTime(2026, 10, 10),
            categoryId: 'cat_mercado',
            paymentMethodId: 'pm_1',
            splitRule: const SplitRule.percentage({'m1': 50, 'm2': 50}),
          ),
        ];

        final summary = engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: expenses,
          contributions: [],
          loans: [],
        );

        // M1 pagou 150 do bolso, mas deve 75 de aporte -> saldo líquido: +75
        // M2 não pagou nada, deve 75 de aporte -> saldo líquido: -75
        final m1 = summary.memberBalances.firstWhere((m) => m.memberId == 'm1');
        final m2 = summary.memberBalances.firstWhere((m) => m.memberId == 'm2');

        expect(m1.netBalance.cents, equals(7500));
        expect(m2.netBalance.cents, equals(-7500));
        expect(summary.isNetZeroSum, isTrue);

        // Super Pix: M2 transfere 75 para M1
        expect(summary.transfers.length, equals(1));
        expect(summary.transfers[0].fromMemberId, equals('m2'));
        expect(summary.transfers[0].toMemberId, equals('m1'));
        expect(summary.transfers[0].amount.cents, equals(7500));
      },
    );

    test(
      'Segmentação de Boleto Composto: Condomínio de R\$ 850 com taxa, água, gás e obras exclusivas',
      () {
        final members = [
          const HouseMember(
            id: 'member_carlos',
            name: 'Carlos',
            defaultSplitPercent: 60,
          ), // Proprietário
          const HouseMember(
            id: 'member_marina',
            name: 'Marina',
            defaultSplitPercent: 40,
          ),
        ];

        // Boleto de R$ 850,00 pago por Carlos do próprio bolso:
        // - Taxa Ordinária: 500 (60% Carlos = 300, 40% Marina = 200)
        // - Água: 120 (60% Carlos = 72, 40% Marina = 48)
        // - Gás: 80 (60% Carlos = 48, 40% Marina = 32)
        // - Obras: 150 (100% Carlos = 150, 0% Marina = 0)
        // Total devido Carlos: 300 + 72 + 48 + 150 = 570 (57000 centavos)
        // Total devido Marina: 200 + 48 + 32 = 280 (28000 centavos)
        // Carlos pagou 850 do bolso -> saldo líquido Carlos = 850 - 570 = +280
        // Marina pagou 0 do bolso -> saldo líquido Marina = 0 - 280 = -280
        // Super Pix: Marina transfere R$ 280,00 para Carlos!
        final compoundExpense = HouseExpense(
          id: 'exp_condominio',
          title: 'Condomínio Solar',
          amount: const Money(85000), // R$ 850,00
          date: DateTime(2026, 10, 10),
          paidByMemberId: 'member_carlos',
          paidOutOfPocket: true,
          categoryId: 'cat_moradia',
          paymentMethodId: 'pm_card_carlos',
          splitRule: const SplitRule.percentage({
            'member_carlos': 60,
            'member_marina': 40,
          }),
          items: const [
            HouseExpenseItem(
              id: 'it_taxa',
              expenseId: 'exp_condominio',
              title: 'Taxa Ordinária',
              amount: Money(50000),
            ),
            HouseExpenseItem(
              id: 'it_agua',
              expenseId: 'exp_condominio',
              title: 'Água',
              amount: Money(12000),
            ),
            HouseExpenseItem(
              id: 'it_gas',
              expenseId: 'exp_condominio',
              title: 'Gás',
              amount: Money(8000),
            ),
            HouseExpenseItem(
              id: 'it_obras',
              expenseId: 'exp_condominio',
              title: 'Fundo de Obras',
              amount: Money(15000),
              responsibleMemberId: 'member_carlos', // 100% proprietário
              splitRule: SplitRule.singleResponsible('member_carlos'),
            ),
          ],
        );

        final summary = engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [compoundExpense],
          contributions: [],
          loans: [],
        );

        final carlosBalance = summary.memberBalances.firstWhere(
          (m) => m.memberId == 'member_carlos',
        );
        final marinaBalance = summary.memberBalances.firstWhere(
          (m) => m.memberId == 'member_marina',
        );

        expect(carlosBalance.contributionDue.cents, equals(57000)); // R$ 570,00
        expect(
          carlosBalance.outOfPocketExpenses.cents,
          equals(85000),
        ); // R$ 850,00
        expect(carlosBalance.netBalance.cents, equals(28000)); // + R$ 280,00

        expect(marinaBalance.contributionDue.cents, equals(28000)); // R$ 280,00
        expect(marinaBalance.outOfPocketExpenses.cents, equals(0));
        expect(marinaBalance.netBalance.cents, equals(-28000)); // - R$ 280,00

        expect(summary.isNetZeroSum, isTrue);
        expect(summary.transfers.length, equals(1));
        expect(summary.transfers[0].fromMemberId, equals('member_marina'));
        expect(summary.transfers[0].toMemberId, equals('member_carlos'));
        expect(summary.transfers[0].amount.cents, equals(28000));
      },
    );

    test(
      'Super Pix utiliza a Chave Pix real cadastrada pelo membro credor',
      () {
        final members = [
          const HouseMember(
            id: 'member_kelvynn',
            name: 'Kelvynn',
            defaultSplitPercent: 50,
            pixKey: 'kelvynn@pix.com',
          ),
          const HouseMember(
            id: 'member_cris',
            name: 'Cris',
            defaultSplitPercent: 50,
            pixKey: 'cris.chave.pix@banco.com',
          ),
        ];

        // Cris pagou R$ 100 do próprio bolso para a casa
        final expenses = [
          HouseExpense(
            id: 'exp_1',
            title: 'Compras',
            amount: const Money(10000), // R$ 100,00
            date: DateTime(2026, 10, 10),
            paidByMemberId: 'member_cris',
            paidOutOfPocket: true,
            dueDate: DateTime(2026, 10, 10),
            categoryId: 'cat_mercado',
            paymentMethodId: 'pm_1',
            splitRule: const SplitRule.percentage({
              'member_kelvynn': 50,
              'member_cris': 50,
            }),
          ),
        ];

        final summary = engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: expenses,
          contributions: [],
          loans: [],
        );

        // Kelvynn deve pagar R$ 50 para o Cris (Super Pix)
        expect(summary.transfers.length, equals(1));
        final transfer = summary.transfers.first;
        expect(transfer.fromMemberId, equals('member_kelvynn'));
        expect(transfer.toMemberId, equals('member_cris'));
        expect(transfer.amount.cents, equals(5000));
        expect(transfer.pixKey, equals('cris.chave.pix@banco.com'));
      },
    );

    test(
      'Utiliza chave Pix da Casa quando a transferência for direcionada para o Caixa da Casa',
      () {
        final members = [
          const HouseMember(
            id: 'member_kelvynn',
            name: 'Kelvynn',
            role: 'owner',
            defaultSplitPercent: 50,
          ),
          const HouseMember(
            id: 'member_cris',
            name: 'Cris',
            role: 'member',
            defaultSplitPercent: 50,
          ),
        ];

        // Despesa de R$ 200 paga pelo método Caixa da Casa (não do bolso pessoal)
        final expenses = [
          HouseExpense(
            id: 'exp_luz_caixa',
            title: 'Conta de Luz',
            amount: const Money(20000), // R$ 200,00
            date: DateTime(2026, 10, 15),
            paidByMemberId: 'member_kelvynn',
            paidOutOfPocket: false,
            dueDate: DateTime(2026, 10, 15),
            categoryId: 'cat_contas',
            paymentMethodId: 'pm_caixa',
            splitRule: const SplitRule.percentage({
              'member_kelvynn': 50,
              'member_cris': 50,
            }),
          ),
        ];

        // Kelvynn já fez seu aporte de 100
        final contributions = [
          Contribution(
            id: 'contrib_kelvynn',
            memberId: 'member_kelvynn',
            amount: const Money(10000),
            date: DateTime(2026, 10, 6),
          ),
        ];

        // Cris não aportou nada, logo deve 100 para o Caixa da Casa
        final summary = engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: expenses,
          contributions: contributions,
          loans: [],
          housePixKey: 'caixa.casa@banco.com',
          housePixKeyHolderName: 'Caixa Nossa Casa',
        );

        expect(summary.transfers.length, equals(1));
        final transfer = summary.transfers.first;
        expect(transfer.fromMemberId, equals('member_cris'));
        expect(transfer.toMemberId, equals('entity_caixa'));
        expect(transfer.amount.cents, equals(10000)); // R$ 100,00
        expect(transfer.pixKey, equals('caixa.casa@banco.com'));
        expect(transfer.toMemberName, contains('Caixa da Casa'));
      },
    );

    test(
      'Despesa com método da Casa cadastrado no banco (UUID e paidOutOfPocket = false) não gera crédito individual para quem operou',
      () {
        final members = [
          const HouseMember(
            id: 'member_kelvynn',
            name: 'Kelvynn',
            role: 'owner',
            defaultSplitPercent: 50,
          ),
          const HouseMember(
            id: 'member_cris',
            name: 'Cris',
            role: 'member',
            defaultSplitPercent: 50,
          ),
        ];

        // Kelvynn passou a compra no Cartão Compartilhado da Casa (UUID do banco, não pm_caixa)
        final expenses = [
          HouseExpense(
            id: 'exp_supermercado_casa',
            title: 'Supermercado da Casa',
            amount: const Money(30000), // R$ 300,00
            date: DateTime(2026, 10, 15),
            paidByMemberId:
                'member_kelvynn', // Kelvynn foi quem passou o cartão
            paidOutOfPocket: false, // Meio da Casa: não saiu do bolso pessoal
            dueDate: DateTime(2026, 10, 15),
            categoryId: 'cat_mercado',
            paymentMethodId:
                '202d7115-0b34-467d-babc-d7a11cb68471', // UUID real do banco
            splitRule: const SplitRule.percentage({
              'member_kelvynn': 50,
              'member_cris': 50,
            }),
          ),
        ];

        final summary = engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: expenses,
          contributions: [],
          loans: [],
          housePixKey: 'caixa@casa.com',
        );

        final kelvynn = summary.memberBalances.firstWhere(
          (m) => m.memberId == 'member_kelvynn',
        );
        final cris = summary.memberBalances.firstWhere(
          (m) => m.memberId == 'member_cris',
        );

        // Nenhum dos dois tem reembolso pessoal (outOfPocket = 0)
        expect(kelvynn.outOfPocketExpenses.cents, equals(0));
        expect(cris.outOfPocketExpenses.cents, equals(0));

        // Ambos devem sua cota de 150 para a Casa
        expect(kelvynn.contributionDue.cents, equals(15000));
        expect(cris.contributionDue.cents, equals(15000));
        expect(kelvynn.netBalance.cents, equals(-15000));
        expect(cris.netBalance.cents, equals(-15000));

        // O Super Pix direciona o acerto para a Casa (entity_caixa), e NÃO um morador pagando para o outro!
        for (final transfer in summary.transfers) {
          expect(transfer.toMemberId, equals('entity_caixa'));
        }
      },
    );

    test(
      'Memória de Cálculo e Auditoria: gera detalhamento completo por membro e transferência',
      () {
        final members = [
          const HouseMember(
            id: 'member_kelvynn',
            name: 'Kelvynn',
            role: 'owner',
          ),
          const HouseMember(id: 'member_cris', name: 'Cris', role: 'member'),
        ];

        final expenses = [
          HouseExpense(
            id: 'exp_mercado',
            title: 'Supermercado Mensal',
            amount: const Money(40000), // R$ 400,00
            date: DateTime(2026, 10, 10),
            paidByMemberId: 'member_kelvynn',
            paidOutOfPocket: true,
            dueDate: DateTime(2026, 10, 10),
            categoryId: 'cat_mercado',
            paymentMethodId: 'pm_personal_card',
            splitRule: const SplitRule.percentage({
              'member_kelvynn': 50,
              'member_cris': 50,
            }),
          ),
        ];

        final contributions = [
          Contribution(
            id: 'c1',
            memberId: 'member_cris',
            amount: const Money(10000), // R$ 100 já aportados
            date: DateTime(2026, 10, 12),
            paymentMethodId: 'pm_pix',
          ),
        ];

        final loans = [
          P2PLoan(
            id: 'loan_restaurante',
            title: 'Almoço no Japonês',
            totalAmount: const Money(6000), // R$ 60,00
            lenderMemberId: 'member_cris',
            borrowerMemberId: 'member_kelvynn',
            installmentsCount: 1,
            createdAt: DateTime(2026, 10, 15),
            firstDueDate: DateTime(2026, 10, 25),
            installments: [
              P2PInstallment(
                id: 'inst_1',
                loanId: 'loan_restaurante',
                number: 1,
                totalCount: 1,
                amount: const Money(6000),
                dueDate: DateTime(2026, 10, 25),
              ),
            ],
          ),
        ];

        final summary = engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: expenses,
          contributions: contributions,
          loans: loans,
        );

        // 1. Auditoria gerada para todos os membros
        expect(summary.auditTrails.containsKey('member_kelvynn'), isTrue);
        expect(summary.auditTrails.containsKey('member_cris'), isTrue);

        final auditKelvynn = summary.auditTrails['member_kelvynn']!;
        final auditCris = summary.auditTrails['member_cris']!;

        // 2. Detalhamento de despesas rateadas
        expect(auditKelvynn.expenseShares.length, equals(1));
        expect(
          auditKelvynn.expenseShares.first.expenseTitle,
          equals('Supermercado Mensal'),
        );
        expect(
          auditKelvynn.expenseShares.first.allocatedAmount.cents,
          equals(20000),
        );
        expect(auditKelvynn.contributionDue.cents, equals(20000));

        expect(auditCris.expenseShares.length, equals(1));
        expect(
          auditCris.expenseShares.first.allocatedAmount.cents,
          equals(20000),
        );
        expect(auditCris.contributionDue.cents, equals(20000));

        // 3. Aportes já realizados
        expect(auditKelvynn.contributionsMade.isEmpty, isTrue);
        expect(auditCris.contributionsMade.length, equals(1));
        expect(auditCris.contributionsMade.first.amount.cents, equals(10000));
        expect(
          auditCris.pendingContribution.cents,
          equals(10000),
        ); // 200 - 100 = 100 pendente

        // 4. Reembolsos do próprio bolso
        expect(auditKelvynn.outOfPocketExpenses.length, equals(1));
        expect(
          auditKelvynn.outOfPocketExpenses.first.amount.cents,
          equals(40000),
        );
        expect(auditKelvynn.outOfPocketTotal.cents, equals(40000));
        expect(auditCris.outOfPocketExpenses.isEmpty, isTrue);

        // 5. Parcelas P2P
        expect(auditKelvynn.p2pPayables.length, equals(1));
        expect(auditKelvynn.p2pPayables.first.amount.cents, equals(6000));
        expect(auditKelvynn.p2pPayables.first.otherMemberName, equals('Cris'));

        expect(auditCris.p2pReceivables.length, equals(1));
        expect(auditCris.p2pReceivables.first.amount.cents, equals(6000));
        expect(
          auditCris.p2pReceivables.first.otherMemberName,
          equals('Kelvynn'),
        );

        // 6. Consistência da equação matemática:
        // Kelvynn: Reembolso (400) - Aporte (200) - P2P a pagar (60) = +140 a receber
        expect(auditKelvynn.netBalance.cents, equals(14000));
        expect(auditKelvynn.mathEquationSummary, contains('400,00'));
        expect(auditKelvynn.mathEquationSummary, contains('200,00'));
        expect(auditKelvynn.mathEquationSummary, contains('60,00'));
        expect(auditKelvynn.mathEquationSummary, contains('reembolsos'));

        // Cris: -Aporte pendente (100) + P2P a receber (60) = -40 a pagar
        expect(auditCris.netBalance.cents, equals(-4000));

        // 7. Transferência com justificativa legível
        expect(summary.transfers.isNotEmpty, isTrue);
        for (final t in summary.transfers) {
          expect(t.explanation, isNotNull);
          expect(t.explanation!.isNotEmpty, isTrue);
        }
      },
    );

    test('Boleto Composto de Condomínio: R\$ 489,21 com R\$ 89,79 Pessoal e R\$ 399,42 Casa reflete perfeitamente no Fechamento', () {
      final members = [
        const HouseMember(id: 'member_kelvynn', name: 'Kelvynn', role: 'owner', defaultSplitPercent: 50.0),
        const HouseMember(id: 'member_cris', name: 'Cris', role: 'member', defaultSplitPercent: 50.0),
      ];

      // Boleto do The Empire Residence:
      // Fundo Reserva 10% (Pessoal Kelvynn): R$ 36,25
      // Taxa Fixa PBAbst (Casa): R$ 25,76
      // Consumo de Agua (Casa): R$ 11,17
      // Desp. Área de Lazer (Pessoal Kelvynn): R$ 53,54
      // Taxa de Condomínio Comum (Casa): R$ 362,49
      // Total da fatura = R$ 489,21
      final expense = HouseExpense(
        id: 'exp_condominio_empire',
        title: 'Condomínio The Empire',
        amount: const Money(48921), // R$ 489,21
        date: DateTime(2026, 10, 10),
        dueDate: DateTime(2026, 10, 10),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_kelvynn',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_kelvynn': 50, 'member_cris': 50}),
        items: [
          const HouseExpenseItem(
            id: 'i1',
            expenseId: 'exp_condominio_empire',
            title: 'Fundo Reserva 10%',
            amount: Money(3625),
            responsibleMemberId: 'member_kelvynn',
            splitRule: SplitRule.singleResponsible('member_kelvynn'),
          ),
          const HouseExpenseItem(
            id: 'i2',
            expenseId: 'exp_condominio_empire',
            title: 'Taxa Fixa PBAbst',
            amount: Money(2576),
          ),
          const HouseExpenseItem(
            id: 'i3',
            expenseId: 'exp_condominio_empire',
            title: 'Consumo de Agua',
            amount: Money(1117),
          ),
          const HouseExpenseItem(
            id: 'i4',
            expenseId: 'exp_condominio_empire',
            title: 'Desp. Área de Lazer (02/03)',
            amount: Money(5354),
            responsibleMemberId: 'member_kelvynn',
            splitRule: SplitRule.singleResponsible('member_kelvynn'),
          ),
          const HouseExpenseItem(
            id: 'i5',
            expenseId: 'exp_condominio_empire',
            title: 'Taxa de Condomínio',
            amount: Money(36249),
          ),
        ],
      );

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [expense],
        contributions: const [],
        loans: const [],
      );

      // 1. Total da despesa bate exatamente com o boleto (R$ 489,21)
      expect(summary.totalHouseExpenses.cents, equals(48921));

      // 2. Totais segregados entre Casa (R$ 399,42) e Pessoal (R$ 89,79)
      expect(summary.totalPersonalExpensesInBills.cents, equals(8979));
      expect(summary.totalSharedHouseExpenses.cents, equals(39942));

      // 3. Auditoria do Kelvynn (deve pagar a metade da casa com algoritmo do maior resto [199,72] + 100% dos itens pessoais [89,79] = R$ 289,51)
      final auditKelvynn = summary.auditTrails['member_kelvynn']!;
      expect(auditKelvynn.personalItemsSharesTotal.cents, equals(8979));
      expect(auditKelvynn.sharedHouseSharesTotal.cents, equals(19972));
      expect(auditKelvynn.contributionDue.cents, equals(28951));

      // 4. Auditoria do Cris (deve pagar a outra metade da casa [199,70] e R$ 0,00 de pessoal)
      final auditCris = summary.auditTrails['member_cris']!;
      expect(auditCris.personalItemsSharesTotal.cents, equals(0));
      expect(auditCris.sharedHouseSharesTotal.cents, equals(19970));
      expect(auditCris.contributionDue.cents, equals(19970));

      // 5. Soma total das metas dos membros cobre exatamente os R$ 489,21 do boleto
      expect(auditKelvynn.contributionDue.cents + auditCris.contributionDue.cents, equals(48921));

      // 6. As tags de auditoria foram devidamente marcadas como pessoais
      final personalItems = auditKelvynn.expenseShares.where((s) => s.isPersonal).toList();
      expect(personalItems.length, equals(2));
      expect(personalItems[0].expenseTitle, contains('Fundo Reserva 10%'));
      expect(personalItems[1].expenseTitle, contains('Desp. Área de Lazer'));
    });
  });
}
