import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../domain/entities/cycle_preview.dart';
import '../../domain/entities/upcoming_forecast.dart';
import '../cubit/reports_cubit.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Seção "Próximos ciclos": o que já está lançado e contratado para os três
/// ciclos seguintes, por morador, e quando cada empréstimo termina.
class UpcomingCyclesSection extends StatelessWidget {
  /// Morador logado; vazio mostra todos.
  final String currentMemberId;
  final bool showAll;

  /// Pede a carga dos próximos ciclos (só quando a seção é aberta).
  final VoidCallback onRequested;

  const UpcomingCyclesSection({
    super.key,
    required this.currentMemberId,
    required this.showAll,
    required this.onRequested,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        final upcoming = state.upcoming;
        final mine =
            !showAll &&
            currentMemberId.isNotEmpty &&
            (upcoming?.cycles.firstOrNull?.preview.memberById(
                      currentMemberId,
                    ) !=
                    null ||
                (upcoming == null &&
                    state.preview?.memberById(currentMemberId) != null));

        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: ExpansionTile(
            leading: const Icon(
              Icons.event_note_rounded,
              color: AppColors.primary,
            ),
            title: const Text(
              'Próximos ciclos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text(
              'O que já está lançado e contratado, sem estimativa',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            onExpansionChanged: (open) {
              if (open && upcoming == null && !state.upcomingLoading)
                onRequested();
            },
            children: [
              if (state.upcomingLoading && upcoming == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (upcoming == null && state.upcomingError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.upcomingError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.debtRed,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onRequested,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Tentar de novo'),
                    ),
                  ],
                )
              else if (upcoming != null) ...[
                for (final cycle in upcoming.cycles) _cycle(cycle, mine),
                _payoffs(upcoming.payoffs, mine),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _cycle(UpcomingCycleForecast forecast, bool mine) {
    final preview = forecast.preview;
    final members = mine
        ? [
            if (preview.memberById(currentMemberId) != null)
              preview.memberById(currentMemberId)!,
          ]
        : preview.members;
    final outside = mine
        ? forecast.outsideClosing
              .where((e) => e.involves(currentMemberId))
              .toList()
        : forecast.outsideClosing;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            preview.cycle.formattedPeriod,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          for (final m in members) _member(m),
          if (outside.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'Fora do fechamento',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final e in outside)
              _row(
                '${_day(e.date!)} · ${e.title}',
                '${e.payerName} paga a ${e.receiverName}',
                e.amount,
              ),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _member(MemberCyclePreview m) {
    final net = m.net;
    final color = net.isNegative
        ? AppColors.debtRed
        : (net.isPositive ? AppColors.creditGreen : Colors.grey);
    final headline = net.isNegative
        ? 'paga ${Money(-net.cents).formatted}'
        : (net.isPositive ? 'recebe ${net.formatted}' : 'nada a acertar');
    final assumedCents = m.assumedPayments.fold<int>(
      0,
      (acc, a) => acc + a.amount.cents,
    );
    final details = [
      'aporte ${m.contributionDue.formatted}',
      if (m.p2pToPay.isPositive) 'parcelas a pagar ${m.p2pToPay.formatted}',
      if (m.p2pToReceive.isPositive) 'a receber ${m.p2pToReceive.formatted}',
      if (assumedCents > 0)
        'faturas e contas que paga ${Money(assumedCents).formatted} (voltam no fechamento)',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.memberName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PrivacySensitiveText(
                headline,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          PrivacySensitiveText(
            details,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _payoffs(List<LoanPayoff> payoffs, bool mine) {
    final shown = mine
        ? payoffs.where((p) => p.involves(currentMemberId)).toList()
        : payoffs;
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Quitação dos empréstimos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        for (final p in shown)
          _row(
            p.title,
            '${p.borrowerName} paga a ${p.lenderName} · '
            '${p.openInstallments} ${p.openInstallments == 1 ? 'parcela' : 'parcelas'} · '
            'última em ${_date(p.lastDueDate)}',
            p.remaining,
          ),
      ],
    );
  }

  Widget _row(String title, String subtitle, Money amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12)),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          PrivacySensitiveText(
            amount.formatted,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
