import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
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

    if (audit.expenseShares.isNotEmpty) {
      buffer.writeln(
        '🛒 DESPESAS DA CASA & ITENS PESSOAIS (${audit.expenseShares.length} itens):',
      );
      if (audit.personalItemsSharesTotal.cents > 0) {
        buffer.writeln('  ↳ Gastos Comuns Compartilhados: ${audit.sharedHouseSharesTotal.formatted}');
        buffer.writeln('  ↳ Itens Pessoais Exclusivos: ${audit.personalItemsSharesTotal.formatted}');
      }
      for (final s in audit.expenseShares) {
        final personalTag = s.isPersonal ? ' [PESSOAL]' : '';
        buffer.writeln(
          '  • ${s.expenseTitle}$personalTag: ${s.allocatedAmount.formatted} (${s.ruleDescription})',
        );
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

    copyWithFeedback(
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
                'Memória de cálculo de ${audit.memberName} copiada! Pronto para colar no WhatsApp.',
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
                Row(
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auditoria do Cálculo',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          widget.summary.cycle.formattedPeriod,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                          setState(() => _selectedMemberId = m.memberId);
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
              Text(
                'Saldo Líquido de ${audit.memberName}:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
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

  Widget _buildExpenseSharesSection(
    BuildContext context,
    MemberAuditTrail audit,
  ) {
    final hasPersonal = audit.personalItemsSharesTotal.cents > 0;
    final subtitleText = hasPersonal
        ? 'Casa: ${audit.sharedHouseSharesTotal.formatted} • Itens Pessoais: ${audit.personalItemsSharesTotal.formatted}'
        : 'Sua responsabilidade sobre as contas comuns do ciclo';

    return _buildSectionCard(
      title: 'Cota de Despesas da Casa (${audit.expenseShares.length})',
      subtitle: subtitleText,
      totalFormatted: audit.contributionDue.formatted,
      totalColor: AppColors.debtRed,
      children: audit.expenseShares.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nenhuma despesa alocada para este morador.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ]
          : audit.expenseShares.map((s) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    if (s.isPersonal) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.debtRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PESSOAL',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.debtRed,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        s.expenseTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${s.ruleDescription} • Total da conta: ${s.totalExpenseAmount.formatted}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: PrivacySensitiveText(
                  s.allocatedAmount.formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              );
            }).toList(),
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

    return _buildSectionCard(
      title: 'Empréstimos Interpessoais P2P',
      subtitle: 'Parcelas vencidas com outros moradores neste ciclo',
      totalFormatted: audit.p2pLentTotal.cents >= audit.p2pBorrowedTotal.cents
          ? '+${Money(audit.p2pLentTotal.cents - audit.p2pBorrowedTotal.cents).formatted}'
          : '-${Money(audit.p2pBorrowedTotal.cents - audit.p2pLentTotal.cents).formatted}',
      totalColor: audit.p2pLentTotal.cents >= audit.p2pBorrowedTotal.cents
          ? AppColors.creditGreen
          : AppColors.debtRed,
      children: (!hasReceivables && !hasPayables)
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
