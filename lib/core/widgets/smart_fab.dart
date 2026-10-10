import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../../features/finance/presentation/pages/add_expense_page.dart';
import '../../features/finance/presentation/pages/add_contribution_page.dart';
import '../../features/p2p/presentation/pages/create_loan_page.dart';

class SmartFAB extends StatelessWidget {
  const SmartFAB({super.key});

  void _showActionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                const Text(
                  'Ações Rápidas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Inteligente
                _buildSectionHeader('Inteligência'),
                Row(
                  children: [
                    _buildActionButton(
                      context,
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Escanear',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.pop(modalContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Captura Inteligente em breve (Fase 5)')),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      context,
                      icon: Icons.auto_awesome_rounded,
                      label: 'Assistente',
                      color: AppColors.accent,
                      onTap: () {
                        Navigator.pop(modalContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Assistente IA em breve (Fase 7)')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Financeiro
                _buildSectionHeader('Financeiro'),
                Row(
                  children: [
                    _buildActionButton(
                      context,
                      icon: Icons.shopping_cart_outlined,
                      label: 'Gasto da Casa',
                      color: AppColors.primaryLight,
                      onTap: () {
                        Navigator.pop(modalContext);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => const AddExpensePage(),
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
                        Navigator.pop(modalContext);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => const CreateLoanPage(),
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
                        Navigator.pop(modalContext);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => const AddContributionPage(),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      context,
                      icon: Icons.flash_on_rounded,
                      label: 'Super Pix',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.pop(modalContext);
                        context.push('/fechamento');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Casa / Organização
                _buildSectionHeader('Organização'),
                Row(
                  children: [
                    _buildActionButton(
                      context,
                      icon: Icons.event_available_rounded,
                      label: 'Evento',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.pop(modalContext);
                        context.go('/agenda');
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      context,
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Tarefa',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(modalContext);
                        context.go('/agenda');
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      context,
                      icon: Icons.playlist_add_rounded,
                      label: 'Item Compra',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.pop(modalContext);
                        context.push('/compras');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _showActionsModal(context),
      tooltip: 'Ações Rápidas',
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }
}
