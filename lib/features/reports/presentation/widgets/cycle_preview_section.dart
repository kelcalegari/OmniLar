import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../settlement/domain/entities/member_audit_trail.dart';
import '../../../settlement/presentation/widgets/settlement_audit_sheet.dart';
import '../../domain/entities/cycle_preview.dart';
import '../cubit/reports_cubit.dart';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String _date(DateTime d) => '${_day(d)}/${d.year}';

/// Seção "Prévia do fechamento": quanto cada morador paga ou recebe no
/// fechamento do ciclo, com os mesmos números do Hub de Liquidação.
class CyclePreviewSection extends StatelessWidget {
  /// Morador logado (abre a prévia dele); vazio mostra todos.
  final String currentMemberId;

  /// "Todos" escolhido (vale também para o calendário de pagamentos).
  final bool showAll;
  final ValueChanged<bool> onShowAllChanged;

  /// Moradores sem aporte fixo definido no modelo de aportes fixos.
  final List<String> membersWithoutFixedContribution;
  final VoidCallback onRetry;

  const CyclePreviewSection({
    super.key,
    required this.currentMemberId,
    required this.showAll,
    required this.onShowAllChanged,
    this.membersWithoutFixedContribution = const [],
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        final preview = state.preview;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, state),
                const SizedBox(height: 12),
                if (preview == null && state.status == ReportsStatus.failure)
                  _error(state.errorMessage)
                else if (preview == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ..._body(context, preview),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, ReportsState state) {
    final preview = state.preview;
    String subtitle = '';
    if (preview != null) {
      final today = DateTime.now();
      final end = preview.cycle.endDate;
      if (preview.isSettled) {
        subtitle = preview.settledAt != null
            ? 'Fechado em ${_date(preview.settledAt!)}'
            : 'Ciclo fechado';
      } else if (end.isBefore(DateTime(today.year, today.month, today.day))) {
        subtitle = 'O ciclo terminou em ${_date(end)} e ainda não foi fechado';
      } else {
        subtitle = 'Fechamento a partir de ${_date(end)} (fim do ciclo)';
      }
    }
    return Row(
      children: [
        const Icon(
          Icons.event_available_rounded,
          color: AppColors.primary,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Prévia do fechamento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
        if (state.status == ReportsStatus.loading && preview != null)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (state.summary != null && (preview?.members.isNotEmpty ?? false))
          IconButton(
            icon: const Icon(Icons.calculate_outlined, size: 20),
            tooltip: 'Memória de cálculo',
            onPressed: () => SettlementAuditSheet.show(
              context: context,
              summary: state.summary!,
              initialMemberId: _hasMe(preview!) ? currentMemberId : null,
            ),
          ),
      ],
    );
  }

  Widget _error(String? message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message ?? 'Não foi possível montar a prévia do fechamento.',
          style: const TextStyle(fontSize: 12, color: AppColors.debtRed),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Tentar de novo'),
        ),
      ],
    );
  }

  bool _hasMe(CyclePreview preview) =>
      currentMemberId.isNotEmpty && preview.memberById(currentMemberId) != null;

  List<Widget> _body(BuildContext context, CyclePreview preview) {
    if (preview.members.isEmpty) {
      return const [
        Text(
          'Este fechamento foi gravado antes do detalhe por morador. Os valores estão no Hub de Liquidação.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ];
    }

    final hasMe = _hasMe(preview);
    final showEveryone = showAll || !hasMe;
    final shown = showEveryone
        ? preview.members
        : [preview.memberById(currentMemberId)!];

    return [
      if (hasMe)
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Minha prévia')),
              ButtonSegment(value: true, label: Text('Todos')),
            ],
            selected: {showAll},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onShowAllChanged(s.first),
          ),
        ),
      if (hasMe) const SizedBox(height: 12),
      if (membersWithoutFixedContribution.isNotEmpty && !preview.isSettled)
        _notice(
          '${membersWithoutFixedContribution.join(', ')} '
          '${membersWithoutFixedContribution.length == 1 ? 'está' : 'estão'} sem aporte fixo definido '
          'e não entra${membersWithoutFixedContribution.length == 1 ? '' : 'm'} no fechamento.',
          AppColors.debtRed,
        ),
      if (preview.usesFixedContributions && !preview.isSettled)
        _bucketNotice(preview),
      for (final member in shown)
        _MemberPreviewCard(member: member, preview: preview),
      if (showEveryone && preview.assumedPayments.any((a) => a.paidByHouse))
        _housePayments(
          preview.assumedPayments.where((a) => a.paidByHouse).toList(),
        ),
    ];
  }

  Widget _notice(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _bucketNotice(CyclePreview preview) {
    if (preview.bucketOverflow.isPositive) {
      return _notice(
        'Os gastos já passam do balde dos aportes fixos em ${preview.bucketOverflow.formatted}. '
        'O excedente é rateado no fechamento (ou coberto por uma caixinha).',
        AppColors.debtRed,
      );
    }
    if (preview.projectedBucketOverflow.isPositive) {
      return _notice(
        'Projeção até o fim do ciclo: os gastos devem passar do balde em '
        '${preview.projectedBucketOverflow.formatted} (estimativa das categorias variáveis).',
        Colors.orange,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _housePayments(List<AssumedPayment> payments) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pagas pelo Caixa da Casa nesta prévia',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          for (final p in payments) _AssumedPaymentRow(payment: p),
        ],
      ),
    );
  }
}

class _MemberPreviewCard extends StatelessWidget {
  final MemberCyclePreview member;
  final CyclePreview preview;

  const _MemberPreviewCard({required this.member, required this.preview});

  @override
  Widget build(BuildContext context) {
    final net = member.net;
    final color = net.isNegative
        ? AppColors.debtRed
        : (net.isPositive ? AppColors.creditGreen : Colors.grey);
    final headline = net.isNegative
        ? 'paga ${Money(-net.cents).formatted}'
        : (net.isPositive ? 'recebe ${net.formatted}' : 'nada a acertar');
    final missingCents =
        member.contributionDue.cents - member.contributionPaid.cents;
    final pendingContribution = Money(missingCents > 0 ? missingCents : 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.memberName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              PrivacySensitiveText(
                headline,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _line(
            'Aporte que falta',
            pendingContribution,
            sign: '+',
            caption:
                '${member.contributionDue.formatted} do ciclo, '
                '${member.contributionPaid.formatted} já aportado',
          ),
          if (member.outOfPocket.isPositive)
            _line('Pagou do bolso (reembolso)', member.outOfPocket, sign: '−'),
          if (member.contributionRefund.isPositive)
            _line('Sobra devolvida', member.contributionRefund, sign: '−'),
          if (member.p2pToPay.isPositive)
            _line('Parcelas a pagar', member.p2pToPay, sign: '+'),
          for (final i in member.installmentsToPay) _installment(i),
          if (member.p2pToReceive.isPositive)
            _line('Parcelas a receber', member.p2pToReceive, sign: '−'),
          for (final i in member.installmentsToReceive) _installment(i),
          if (member.transfersOut.isNotEmpty ||
              member.transfersIn.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final t in member.transfersOut)
              _transfer('Paga a ${t.toMemberName}', t.amount),
            for (final t in member.transfersIn)
              _transfer('Recebe de ${t.fromMemberName}', t.amount),
          ],
          if (member.assumedPayments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Em aberto, consideradas pagas por ${member.memberName.split(' ').first} '
              '(volta no fechamento):',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            for (final p in member.assumedPayments)
              _AssumedPaymentRow(payment: p),
          ],
          if (member.projectedExtraShare.isPositive) ...[
            const SizedBox(height: 8),
            _projection(),
          ],
        ],
      ),
    );
  }

  Widget _line(
    String label,
    Money amount, {
    required String sign,
    String? caption,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                if (caption != null)
                  PrivacySensitiveText(
                    caption,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
          PrivacySensitiveText(
            '$sign ${amount.formatted}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _installment(P2PInstallmentAudit i) {
    final overdue = i.dueDate.isBefore(preview.cycle.startDate);
    final direction = i.isReceivable ? 'de' : 'para';
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${i.description} ${i.installmentNumber}/${i.totalInstallments} '
              '$direction ${i.otherMemberName} · vence ${_day(i.dueDate)}'
              '${overdue ? ' · atrasada' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: overdue ? AppColors.debtRed : Colors.grey,
              ),
            ),
          ),
          PrivacySensitiveText(
            i.amount.formatted,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _transfer(String label, Money amount) {
    return Row(
      children: [
        const Icon(
          Icons.arrow_forward_rounded,
          size: 14,
          color: AppColors.primary,
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        PrivacySensitiveText(
          amount.formatted,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _projection() {
    final projected = member.projectedNet;
    final text = projected.isNegative
        ? 'paga ${Money(-projected.cents).formatted}'
        : (projected.isPositive
              ? 'recebe ${projected.formatted}'
              : 'nada a acertar');
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: PrivacySensitiveText(
              'Projeção até o fim do ciclo: inclui ${member.projectedExtraShare.formatted} '
              'estimados das categorias variáveis',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          PrivacySensitiveText(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _AssumedPaymentRow extends StatelessWidget {
  final AssumedPayment payment;

  const _AssumedPaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${payment.title} · vence ${_day(payment.dueDate)}'
              '${payment.isOverdue ? ' · vencida' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: payment.isOverdue ? AppColors.debtRed : Colors.grey,
              ),
            ),
          ),
          PrivacySensitiveText(
            payment.amount.formatted,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
