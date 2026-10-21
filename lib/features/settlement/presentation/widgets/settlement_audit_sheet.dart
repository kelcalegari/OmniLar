import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/share_helper.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../domain/entities/member_audit_trail.dart';
import '../../domain/entities/settlement_summary.dart';

/// Modal para auditoria e conferência detalhada da memória de cálculo do fechamento do ciclo.
class SettlementAuditSheet extends StatefulWidget {
  final SettlementSummary summary;
  final String? initialMemberId;
  final bool isEmbedded;

  const SettlementAuditSheet({
    super.key,
    required this.summary,
    this.initialMemberId,
    this.isEmbedded = false,
  });

  static Future<void> show({
    required BuildContext context,
    required SettlementSummary summary,
    String? initialMemberId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettlementAuditSheet(
        summary: summary,
        initialMemberId: initialMemberId,
      ),
    );
  }

  @override
  State<SettlementAuditSheet> createState() => _SettlementAuditSheetState();
}

class _SettlementAuditSheetState extends State<SettlementAuditSheet> {
  late String _selectedMemberId;
  String _expenseFilter = 'all'; // 'all', 'common', 'exclusive'

  @override
  void initState() {
    super.initState();
    final firstMemberId =
        widget.summary.memberBalances.firstOrNull?.memberId ?? '';
    _selectedMemberId = widget.initialMemberId ?? firstMemberId;
  }

  void _copyAuditToClipboard(MemberAuditTrail audit) {
    final buffer = StringBuffer();
    buffer.writeln('🔍 Memória de Cálculo do Fechamento • Omni Lar');
    buffer.writeln('📅 Ciclo: ${widget.summary.cycle.formattedPeriod}');
    buffer.writeln('👤 Morador(a): ${audit.memberName}');
    buffer.writeln('');
    buffer.writeln('📊 EQUAÇÃO DO SALDO LÍQUIDO:');
    buffer.writeln(
      '  (+) Reembolsos do Bolso: ${audit.outOfPocketTotal.formatted}',
    );
    buffer.writeln(
      '  (-) Aporte Pendente da Casa: ${audit.pendingContribution.formatted} (Meta: ${audit.contributionDue.formatted} | Pago: ${audit.contributionPaid.formatted})',
    );
    if (audit.contributionRefund.cents > 0) {
      buffer.writeln(
        '  (+) Devolução da Sobra (já aportada): ${audit.contributionRefund.formatted}',
      );
    }
    buffer.writeln(
      '  (+) Empréstimos a Receber: ${audit.p2pLentTotal.formatted}',
    );
    buffer.writeln(
      '  (-) Empréstimos a Pagar: ${audit.p2pBorrowedTotal.formatted}',
    );
    buffer.writeln('  -------------------------------------------');
    buffer.writeln(
      '  (=) SALDO LÍQUIDO FINAL: ${audit.netBalance.formatted} (${audit.netBalance.cents >= 0 ? 'A Receber' : 'A Pagar'})',
    );
    buffer.writeln('');

    final commonShares = audit.commonExpenseShares;
    final exclusiveShares = audit.exclusiveExpenseShares;

    if (audit.expenseShares.isNotEmpty) {
      buffer.writeln(
        '🛒 DESPESAS DA CASA NA COTA (${audit.expenseShares.length} lançamentos):',
      );
      if (commonShares.isNotEmpty) {
        buffer.writeln('  🏠 GASTOS RATEADOS EM COMUM (${commonShares.length} itens - Total: ${audit.sharedHouseSharesTotal.formatted}):');
        for (final s in commonShares) {
          final payerInfo = s.paidByMemberName != null ? ' • Pago por ${s.paidByMemberName}' : '';
          final catInfo = s.categoryName != null ? ' • [${s.categoryName}]' : '';
          buffer.writeln(
            '    • ${s.expenseTitle}$catInfo: ${s.allocatedAmount.formatted} (${s.ruleDescription} de ${s.totalExpenseAmount.formatted}$payerInfo)',
          );
        }
      }
      if (exclusiveShares.isNotEmpty) {
        buffer.writeln('  👤 GASTOS EXCLUSIVOS DO MORADOR (${exclusiveShares.length} itens - Total: ${audit.personalItemsSharesTotal.formatted}):');
        for (final s in exclusiveShares) {
          final payerInfo = s.paidByMemberName != null ? ' • Pago por ${s.paidByMemberName}' : '';
          final catInfo = s.categoryName != null ? ' • [${s.categoryName}]' : '';
          buffer.writeln(
            '    • ${s.expenseTitle}$catInfo: ${s.allocatedAmount.formatted} (100% Exclusivo$payerInfo)',
          );
        }
      }
      buffer.writeln('');
    }

    if (audit.outOfPocketExpenses.isNotEmpty) {
      buffer.writeln(
        '💳 DESPESAS PAGAS DO PRÓPRIO BOLSO (${audit.outOfPocketExpenses.length} itens):',
      );
      for (final o in audit.outOfPocketExpenses) {
        buffer.writeln('  • ${o.title}: ${o.amount.formatted}');
      }
      buffer.writeln('');
    }

    if (audit.p2pReceivables.isNotEmpty || audit.p2pPayables.isNotEmpty) {
      buffer.writeln('🤝 EMPRÉSTIMOS P2P NESTE CICLO:');
      for (final r in audit.p2pReceivables) {
        buffer.writeln(
          '  • A Receber de ${r.otherMemberName}: ${r.amount.formatted} (${r.description} - ${r.installmentNumber}/${r.totalInstallments})',
        );
      }
      for (final p in audit.p2pPayables) {
        buffer.writeln(
          '  • A Pagar para ${p.otherMemberName}: ${p.amount.formatted} (${p.description} - ${p.installmentNumber}/${p.totalInstallments})',
        );
      }
      buffer.writeln('');
    }

    shareText(
 context,
 buffer.toString(),
 onCopied:
      SnackBar(
        backgroundColor: AppColors.primary,
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Memória de cálculo de ${audit.memberName} copiada!',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audit = widget.summary.auditTrails[_selectedMemberId];

    return Container(
      constraints: widget.isEmbedded
          ? const BoxConstraints.expand()
          : BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: widget.isEmbedded
            ? BorderRadius.circular(16)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: widget.isEmbedded
            ? Border.all(color: Colors.grey.withValues(alpha: 0.15))
            : null,
      ),
      child: Column(
        children: [
          // Barra de arraste (apenas no modal mobile)
          if (!widget.isEmbedded)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

          // Cabeçalho
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calculate_outlined,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Auditoria do Cálculo',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              widget.summary.cycle.formattedPeriod,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isEmbedded)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Seletor de Morador (caso haja mais de um na casa)
          if (widget.summary.memberBalances.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: widget.summary.memberBalances.map((m) {
                  final isSelected = m.memberId == _selectedMemberId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: isSelected,
                      label: Text(m.memberName),
                      avatar: CircleAvatar(
                        backgroundColor: isSelected
                            ? Colors.white
                            : AppColors.primary.withValues(alpha: 0.2),
                        child: Text(
                          m.memberName.isNotEmpty ? m.memberName[0] : '?',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.black87,
                          ),
                        ),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedMemberId = m.memberId;
                            _expenseFilter = 'all';
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

          // Conteúdo rolável com o detalhamento
          Expanded(
            child: audit == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Nenhum dado de auditoria disponível para este morador.',
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      // Card de Resultado e Equação
                      _buildEquationCard(context, audit),
                      const SizedBox(height: 16),

                      // Seção 1: Cota de Despesas da Casa
                      _buildExpenseSharesSection(context, audit),
                      const SizedBox(height: 12),

                      // Seção 2: Aportes Realizados
                      _buildContributionsSection(context, audit),
                      const SizedBox(height: 12),

                      // Seção 3: Reembolsos do Próprio Bolso
                      _buildOutOfPocketSection(context, audit),
                      const SizedBox(height: 12),

                      // Seção 4: Empréstimos P2P
                      _buildP2PSection(context, audit),
                      const SizedBox(height: 24),

                      // Botão de Copiar Memória de Cálculo
                      OutlinedButton.icon(
                        onPressed: () => _copyAuditToClipboard(audit),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: Text(
                          'Copiar memória de cálculo de ${audit.memberName}',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquationCard(BuildContext context, MemberAuditTrail audit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCreditor = audit.netBalance.cents > 0;
    final isDebtor = audit.netBalance.cents < 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCreditor
            ? AppColors.creditGreen.withValues(alpha: 0.08)
            : isDebtor
            ? AppColors.debtRed.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCreditor
              ? AppColors.creditGreen.withValues(alpha: 0.3)
              : isDebtor
              ? AppColors.debtRed.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Saldo Líquido de ${audit.memberName}:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCreditor
                      ? AppColors.creditGreen
                      : isDebtor
                      ? AppColors.debtRed
                      : Colors.grey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isCreditor ? 'A RECEBER' : (isDebtor ? 'A PAGAR' : 'ZERADO'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PrivacySensitiveText(
            isCreditor
                ? '+${audit.netBalance.formatted}'
                : (isDebtor
                      ? '-${audit.netBalance.abs().formatted}'
                      : audit.netBalance.formatted),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: isCreditor
                  ? AppColors.creditGreen
                  : isDebtor
                  ? AppColors.debtRed
                  : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Fórmula de Composição:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          _buildEquationLine(
            icon: Icons.add_circle_outline_rounded,
            iconColor: AppColors.creditGreen,
            label: 'Despesas do Bolso (Reembolso da Casa)',
            value: '+${audit.outOfPocketTotal.formatted}',
          ),
          _buildEquationLine(
            icon: Icons.remove_circle_outline_rounded,
            iconColor: AppColors.debtRed,
            label: 'Aporte Pendente (Meta menos o já pago)',
            value: '-${audit.pendingContribution.formatted}',
          ),
          if (audit.contributionRefund.cents > 0)
            _buildEquationLine(
              icon: Icons.add_circle_outline_rounded,
              iconColor: AppColors.creditGreen,
              label: 'Devolução da Sobra (já aportada)',
              value: '+${audit.contributionRefund.formatted}',
            ),
          _buildEquationLine(
            icon: Icons.add_circle_outline_rounded,
            iconColor: AppColors.creditGreen,
            label: 'Empréstimos P2P a Receber',
            value: '+${audit.p2pLentTotal.formatted}',
          ),
          _buildEquationLine(
            icon: Icons.remove_circle_outline_rounded,
            iconColor: AppColors.debtRed,
            label: 'Empréstimos P2P a Pagar',
            value: '-${audit.p2pBorrowedTotal.formatted}',
          ),
          if (audit.p2pPaidInCycleTotal.isPositive) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.creditGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.creditGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Desembolsado no Ciclo: ${audit.totalDisbursedInCycle.formatted}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.creditGreen,
                          ),
                        ),
                        Text(
                          '${audit.contributionPaid.formatted} Aporte + ${audit.p2pPaidInCycleTotal.formatted} Empréstimos',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEquationLine({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          PrivacySensitiveText(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showExpenseShareDetails(
    BuildContext context,
    ExpenseShareAudit share,
    MemberAuditTrail audit,
  ) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final isPersonal = share.isPersonal;
    final isAuditedPayer = share.paidByMemberId != null && share.paidByMemberId == audit.memberId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isPersonal ? Colors.deepOrange : AppColors.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPersonal ? Icons.person_rounded : Icons.home_work_rounded,
                    color: isPersonal ? Colors.deepOrange : AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        share.expenseTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPersonal ? 'Gasto Exclusivo do Morador' : 'Gasto Rateado em Comum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPersonal ? Colors.deepOrange : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            _buildDetailRow('Data do Lançamento', dateFormat.format(share.date)),
            if (share.categoryName != null)
              _buildDetailRow('Categoria', share.categoryName!),
            if (share.paidByMemberName != null)
              _buildDetailRow(
                'Quem Pagou',
                '${share.paidByMemberName!}${share.paymentMethodName != null ? " (${share.paymentMethodName})" : ""}',
              ),
            _buildDetailRow('Valor Total da Conta da Casa', share.totalExpenseAmount.formatted),
            _buildDetailRow('Regra de Cálculo Aplicada', share.ruleDescription),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isPersonal ? AppColors.debtRed : AppColors.primary).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (isPersonal ? AppColors.debtRed : AppColors.primary).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cota de ${audit.memberName}:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  PrivacySensitiveText(
                    share.allocatedAmount.formatted,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isPersonal ? AppColors.debtRed : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (isAuditedPayer) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.creditGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.creditGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Como ${audit.memberName} pagou esta despesa do bolso, o reembolso total já está computado a seu favor nos créditos.',
                        style: const TextStyle(fontSize: 11, color: AppColors.creditGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseSharesSection(
    BuildContext context,
    MemberAuditTrail audit,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final commonShares = audit.commonExpenseShares;
    final exclusiveShares = audit.exclusiveExpenseShares;

    final filteredShares = _expenseFilter == 'common'
        ? commonShares
        : _expenseFilter == 'exclusive'
            ? exclusiveShares
            : audit.expenseShares;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho da seção
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cota de Despesas da Casa (${audit.expenseShares.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Transações do ciclo computadas na sua responsabilidade',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                PrivacySensitiveText(
                  audit.contributionDue.formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.debtRed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Card Resumo Comum vs Exclusivo
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _expenseFilter = 'common'),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.home_work_outlined, size: 14, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Rateio Comum (${commonShares.length})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: _expenseFilter == 'common' ? FontWeight.bold : FontWeight.w500,
                                      color: _expenseFilter == 'common' ? AppColors.primary : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            PrivacySensitiveText(
                              audit.sharedHouseSharesTotal.formatted,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _expenseFilter = 'exclusive'),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_outline_rounded, size: 14, color: Colors.deepOrange),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Exclusivos (${exclusiveShares.length})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: _expenseFilter == 'exclusive' ? FontWeight.bold : FontWeight.w500,
                                      color: _expenseFilter == 'exclusive' ? Colors.deepOrange : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            PrivacySensitiveText(
                              audit.personalItemsSharesTotal.formatted,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Filtro por SegmentedButton / ChoiceChips
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Todas (${audit.expenseShares.length})', style: const TextStyle(fontSize: 11)),
                  selected: _expenseFilter == 'all',
                  onSelected: (val) {
                    if (val) setState(() => _expenseFilter = 'all');
                  },
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('🏠 Em Comum (${commonShares.length})', style: const TextStyle(fontSize: 11)),
                  selected: _expenseFilter == 'common',
                  onSelected: (val) {
                    if (val) setState(() => _expenseFilter = 'common');
                  },
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('👤 Exclusivas (${exclusiveShares.length})', style: const TextStyle(fontSize: 11)),
                  selected: _expenseFilter == 'exclusive',
                  onSelected: (val) {
                    if (val) setState(() => _expenseFilter = 'exclusive');
                  },
                ),
              ],
            ),
            const Divider(height: 16),

            // Lista transação por transação
            if (filteredShares.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    _expenseFilter == 'exclusive'
                        ? 'Nenhum gasto exclusivo para este morador.'
                        : _expenseFilter == 'common'
                            ? 'Nenhum gasto rateado em comum neste ciclo.'
                            : 'Nenhuma despesa alocada para este morador.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredShares.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final s = filteredShares[i];
                  final isExclusive = s.isPersonal;

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showExpenseShareDetails(context, s, audit),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2, right: 10),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: (isExclusive ? Colors.deepOrange : AppColors.primary).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isExclusive ? Icons.person_rounded : Icons.home_work_rounded,
                              size: 16,
                              color: isExclusive ? Colors.deepOrange : AppColors.primary,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(bottom: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: (isExclusive ? Colors.deepOrange : AppColors.primary).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isExclusive ? '100% EXCLUSIVO' : 'RATEIO COMUM',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isExclusive ? Colors.deepOrange : AppColors.primary,
                                    ),
                                  ),
                                ),
                                Text(
                                  s.expenseTitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${s.ruleDescription} • Total da conta: ${s.totalExpenseAmount.formatted}',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                ),
                                if (s.paidByMemberName != null || s.categoryName != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (s.categoryName != null) s.categoryName!,
                                      if (s.paidByMemberName != null) 'Pago por ${s.paidByMemberName!}',
                                    ].join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              PrivacySensitiveText(
                                s.allocatedAmount.formatted,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isExclusive ? Colors.deepOrange : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Icon(Icons.chevron_right_rounded, size: 14, color: Colors.grey),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContributionsSection(
    BuildContext context,
    MemberAuditTrail audit,
  ) {
    final hasPending = audit.pendingContribution.cents > 0;

    return _buildSectionCard(
      title: 'Aportes Efetuados (${audit.contributionsMade.length})',
      subtitle: hasPending
          ? 'Falta aportar ${audit.pendingContribution.formatted} para cobrir sua cota'
          : 'Cota de despesas 100% quitada!',
      totalFormatted: audit.contributionPaid.formatted,
      totalColor: AppColors.creditGreen,
      children: audit.contributionsMade.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nenhum aporte registrado durante o ciclo.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ]
          : audit.contributionsMade.map((c) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Aporte em ${c.date.day.toString().padLeft(2, '0')}/${c.date.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: const Text(
                  'Depósito no Caixa da Casa',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: PrivacySensitiveText(
                  c.amount.formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.creditGreen,
                  ),
                ),
              );
            }).toList(),
    );
  }

  Widget _buildOutOfPocketSection(
    BuildContext context,
    MemberAuditTrail audit,
  ) {
    return _buildSectionCard(
      title:
          'Despesas Pagas do Próprio Bolso (${audit.outOfPocketExpenses.length})',
      subtitle:
          'Valores que você adiantou para a Casa e tem direito a reembolso',
      totalFormatted: audit.outOfPocketTotal.formatted,
      totalColor: AppColors.creditGreen,
      children: audit.outOfPocketExpenses.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nenhuma despesa paga com dinheiro pessoal.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ]
          : audit.outOfPocketExpenses.map((o) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  o.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: const Text(
                  'Pago com recursos próprios (crédito contra a Casa)',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: PrivacySensitiveText(
                  '+${o.amount.formatted}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.creditGreen,
                  ),
                ),
              );
            }).toList(),
    );
  }

  Widget _buildP2PSection(BuildContext context, MemberAuditTrail audit) {
    final hasReceivables = audit.p2pReceivables.isNotEmpty;
    final hasPayables = audit.p2pPayables.isNotEmpty;
    final hasPaidInCycle = audit.p2pPaidInCycle.isNotEmpty;

    return _buildSectionCard(
      title: 'Empréstimos Interpessoais P2P',
      subtitle: hasPaidInCycle && !hasReceivables && !hasPayables
          ? 'Parcelas quitadas durante este ciclo'
          : 'Parcelas vencidas com outros moradores neste ciclo',
      totalFormatted: audit.p2pLentTotal.cents >= audit.p2pBorrowedTotal.cents
          ? '+${Money(audit.p2pLentTotal.cents - audit.p2pBorrowedTotal.cents).formatted}'
          : '-${Money(audit.p2pBorrowedTotal.cents - audit.p2pLentTotal.cents).formatted}',
      totalColor: audit.p2pLentTotal.cents >= audit.p2pBorrowedTotal.cents
          ? AppColors.creditGreen
          : AppColors.debtRed,
      children: (!hasReceivables && !hasPayables && !hasPaidInCycle)
          ? [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nenhum empréstimo P2P com vencimento neste ciclo.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ]
          : [
              if (hasReceivables) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'A RECEBER DE OUTROS:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: AppColors.creditGreen,
                    ),
                  ),
                ),
                ...audit.p2pReceivables.map(
                  (r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${r.otherMemberName} • ${r.description}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'Parcela ${r.installmentNumber} de ${r.totalInstallments}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: PrivacySensitiveText(
                      '+${r.amount.formatted}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.creditGreen,
                      ),
                    ),
                  ),
                ),
              ],
              if (audit.p2pPaidInCycle.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'QUITADOS / PAGOS NESTE CICLO:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: AppColors.creditGreen,
                    ),
                  ),
                ),
                ...audit.p2pPaidInCycle.map(
                  (p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${p.otherMemberName} • ${p.description}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'Parcela ${p.installmentNumber} de ${p.totalInstallments} • Quitado no ciclo',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.creditGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'QUITADO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.creditGreen,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (hasPayables) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'A PAGAR PARA OUTROS:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: AppColors.debtRed,
                    ),
                  ),
                ),
                ...audit.p2pPayables.map(
                  (p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${p.otherMemberName} • ${p.description}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'Parcela ${p.installmentNumber} de ${p.totalInstallments}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: PrivacySensitiveText(
                      '-${p.amount.formatted}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.debtRed,
                      ),
                    ),
                  ),
                ),
              ],
            ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required String totalFormatted,
    required Color totalColor,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                PrivacySensitiveText(
                  totalFormatted,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: totalColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
