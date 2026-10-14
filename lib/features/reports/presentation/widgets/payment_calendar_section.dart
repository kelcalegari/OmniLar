import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../domain/entities/payment_due_entry.dart';
import '../cubit/reports_cubit.dart';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Seção "Próximos pagamentos": quem paga o quê, em que dia, até o fechamento.
class PaymentCalendarSection extends StatelessWidget {
  /// Morador logado; vazio mostra todos.
  final String currentMemberId;

  /// Mostra os pagamentos de todos, e não só os do morador logado.
  final bool showAll;

  const PaymentCalendarSection({
    super.key,
    required this.currentMemberId,
    required this.showAll,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        final calendar = state.calendar;
        final preview = state.preview;
        // Ciclo fechado não tem o que pagar; sem dados, a prévia já avisa
        if (calendar == null || preview == null || preview.isSettled) {
          return const SizedBox.shrink();
        }

        final hasMe =
            currentMemberId.isNotEmpty &&
            preview.memberById(currentMemberId) != null;
        final mine = hasMe && !showAll;
        final entries = mine
            ? calendar.forMember(currentMemberId)
            : calendar.entries;

        final today = calendar.today;
        final weekEnd = today.add(const Duration(days: 7));
        final overdue = entries
            .where((e) => e.date != null && e.isOverdue)
            .toList();
        final week = entries
            .where(
              (e) =>
                  e.date != null && !e.isOverdue && e.date!.isBefore(weekEnd),
            )
            .toList();
        final later = entries
            .where(
              (e) =>
                  e.date != null && !e.isOverdue && !e.date!.isBefore(weekEnd),
            )
            .toList();
        final openEnded = entries.where((e) => e.date == null).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Próximos pagamentos',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Até o fechamento em ${_day(calendar.cycle.endDate)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (mine) ...[
                    const SizedBox(height: 12),
                    _totals(
                      calendar.outgoingOf(currentMemberId),
                      calendar.incomingOf(currentMemberId),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Nenhum pagamento até o fim do ciclo.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ..._group('Atrasados', overdue, color: AppColors.debtRed),
                  ..._group('Próximos 7 dias', week),
                  ..._group('Até o fim do ciclo', later),
                  ..._group('Sem prazo', openEnded),
                  if (!mine &&
                      entries.any(
                        (e) =>
                            e.payerId == null &&
                            e.kind != PaymentDueKind.closing,
                      ))
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Contas e faturas do Caixa da Casa aparecem para mostrar o que sai dele; '
                        'não são cobrança de nenhum morador.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _totals(Money outgoing, Money incoming) {
    Widget tile(String label, Money amount, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            PrivacySensitiveText(
              amount.formatted,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        tile('Você paga até o fechamento', outgoing, AppColors.debtRed),
        const SizedBox(width: 8),
        tile('Você recebe', incoming, AppColors.creditGreen),
      ],
    );
  }

  List<Widget> _group(
    String title,
    List<PaymentDueEntry> entries, {
    Color? color,
  }) {
    if (entries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color ?? Colors.grey,
          ),
        ),
      ),
      for (final e in entries)
        _PaymentDueRow(
          entry: e,
          currentMemberId: showAll ? '' : currentMemberId,
        ),
    ];
  }
}

class _PaymentDueRow extends StatelessWidget {
  final PaymentDueEntry entry;

  /// Destaca a direção do dinheiro para este morador (vazio = sem destaque).
  final String currentMemberId;

  const _PaymentDueRow({required this.entry, required this.currentMemberId});

  @override
  Widget build(BuildContext context) {
    final pays = currentMemberId.isNotEmpty && entry.payerId == currentMemberId;
    final receives =
        currentMemberId.isNotEmpty && entry.receiverId == currentMemberId;
    final amountColor = pays
        ? AppColors.debtRed
        : (receives ? AppColors.creditGreen : null);

    final who = entry.receiverName != null
        ? '${entry.payerName} paga a ${entry.receiverName}'
        : '${entry.payerName} paga';
    final details = [
      who,
      if (entry.kind == PaymentDueKind.installment) 'fora do fechamento',
      if (entry.reimbursedAtClosing) 'volta no fechamento',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: (entry.isOverdue ? AppColors.debtRed : AppColors.primary)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              entry.date == null ? '—' : _day(entry.date!),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: entry.isOverdue ? AppColors.debtRed : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  details,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (entry.barcode != null && entry.barcode!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copiar código',
              visualDensity: VisualDensity.compact,
              onPressed: () => copyWithFeedback(
                context,
                entry.barcode!,
                onCopied: const SnackBar(content: Text('Código copiado.')),
              ),
            ),
          PrivacySensitiveText(
            entry.amount.formatted,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
