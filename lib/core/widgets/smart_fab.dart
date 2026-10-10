import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../../features/finance/presentation/pages/add_expense_page.dart';
import '../../features/finance/presentation/pages/add_contribution_page.dart';
import '../../features/p2p/presentation/pages/create_loan_page.dart';
import '../../features/calendar/presentation/cubit/calendar_cubit.dart';
import '../../features/calendar/presentation/widgets/add_event_sheet.dart';
import '../../features/calendar/presentation/widgets/add_task_sheet.dart';
import '../../features/capture/presentation/pages/smart_scanner_page.dart';
import '../../features/reconciliation/presentation/widgets/split_invoice_modal.dart';

class SmartFAB extends StatelessWidget {
  final bool isExtended;

  const SmartFAB({
    this.isExtended = false,
    super.key,
  });

  void _showActionsModal(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 520,
      child: const _SmartFABContent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isExtended) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: FilledButton.icon(
          onPressed: () => _showActionsModal(context),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Nova Ação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    return FloatingActionButton(
      onPressed: () => _showActionsModal(context),
      tooltip: 'Ações Rápidas',
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }
}

class _SmartFABContent extends StatelessWidget {
  const _SmartFABContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = !context.isMobile;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDesktop) ...[
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
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: AppColors.primary, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Ações Rápidas',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (isDesktop)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Fechar',
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Inteligência
          _buildSectionHeader('Inteligência'),
          Row(
            children: [
              _buildActionButton(
                context,
                icon: Icons.qr_code_scanner_rounded,
                label: 'Escanear',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  SmartScannerPage.show(context);
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.auto_awesome_rounded,
                label: 'Assistente',
                color: AppColors.accent,
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Assistente IA em breve (Fase 7)')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Financeiro
          _buildSectionHeader('Financeiro'),
          Row(
            children: [
              _buildActionButton(
                context,
                icon: Icons.shopping_cart_outlined,
                label: 'Gasto da Casa',
                color: AppColors.primaryLight,
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: const AddExpensePage(),
                  );
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.swap_horiz_rounded,
                label: 'Empréstimo',
                color: AppColors.debtRed,
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: const CreateLoanPage(),
                  );
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.move_to_inbox_rounded,
                label: 'Aporte',
                color: AppColors.creditGreen,
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: const AddContributionPage(),
                  );
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.flash_on_rounded,
                label: 'Fechamento',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/fechamento');
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.call_split_rounded,
                label: 'Rachar Fatura',
                color: AppColors.accent,
                onTap: () {
                  Navigator.pop(context);
                  SplitInvoiceModal.show(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Casa / Organização
          _buildSectionHeader('Organização'),
          Row(
            children: [
              _buildActionButton(
                context,
                icon: Icons.event_available_rounded,
                label: 'Evento',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  final activeMemberId = context.read<CalendarCubit>().state.activeMemberId;
                  AddEventSheet.show(context, activeMemberId);
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.check_circle_outline_rounded,
                label: 'Tarefa',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  final activeMemberId = context.read<CalendarCubit>().state.activeMemberId;
                  AddTaskSheet.show(context, activeMemberId);
                },
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                icon: Icons.playlist_add_rounded,
                label: 'Item Compra',
                color: Colors.purple,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/compras');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
