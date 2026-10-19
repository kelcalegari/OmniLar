import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../../features/finance/presentation/pages/add_expense_page.dart';
import '../../features/finance/presentation/pages/add_contribution_page.dart';
import '../../features/finance/presentation/cubit/finance_cubit.dart';
import '../../features/finance/presentation/widgets/house_inflows_card.dart';
import '../../features/p2p/presentation/pages/create_loan_page.dart';
import '../../features/calendar/presentation/cubit/calendar_cubit.dart';
import '../../features/calendar/presentation/widgets/add_event_sheet.dart';
import '../../features/calendar/presentation/widgets/add_task_sheet.dart';
import '../../features/shopping/presentation/cubit/shopping_cubit.dart';
import '../../features/capture/presentation/pages/smart_scanner_page.dart';
import '../../features/assistant/presentation/pages/assistant_chat_page.dart';
import 'save_feedback.dart';

enum QuickActionFocus {
  home,
  tasks,
  calendar,
  p2p,
  general,
}

class SmartFAB extends StatelessWidget {
  final bool isExtended;
  final int currentTab;

  const SmartFAB({
    this.isExtended = false,
    this.currentTab = 0,
    super.key,
  });

  QuickActionFocus get _focus {
    switch (currentTab) {
      case 0:
        return QuickActionFocus.home;
      case 1:
        return QuickActionFocus.tasks;
      case 2:
        return QuickActionFocus.calendar;
      case 3:
        return QuickActionFocus.p2p;
      default:
        return QuickActionFocus.general;
    }
  }

  void _showActionsModal(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 540,
      child: _SmartFABContent(focus: _focus),
    );
  }

  IconData get _fabIcon {
    switch (_focus) {
      case QuickActionFocus.calendar:
        return Icons.event_available_rounded;
      case QuickActionFocus.tasks:
        return Icons.add_task_rounded;
      case QuickActionFocus.p2p:
        return Icons.handshake_rounded;
      case QuickActionFocus.home:
      case QuickActionFocus.general:
        return Icons.add_rounded;
    }
  }

  String get _fabTooltip {
    switch (_focus) {
      case QuickActionFocus.calendar:
        return 'Ações da Agenda';
      case QuickActionFocus.tasks:
        return 'Ações de Tarefas & Compras';
      case QuickActionFocus.p2p:
        return 'Ações de Empréstimos';
      case QuickActionFocus.home:
        return 'Ações Financeiras';
      case QuickActionFocus.general:
        return 'Ações Rápidas';
    }
  }

  String get _extendedLabel {
    switch (_focus) {
      case QuickActionFocus.calendar:
        return 'Novo Evento';
      case QuickActionFocus.tasks:
        return 'Nova Tarefa';
      case QuickActionFocus.p2p:
        return 'Empréstimo';
      case QuickActionFocus.home:
        return 'Novo Gasto';
      case QuickActionFocus.general:
        return 'Nova Ação';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isExtended) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SizedBox(
          width: 132,
          height: 44,
          child: Tooltip(
            message: _fabTooltip,
            child: FilledButton.icon(
              onPressed: () => _showActionsModal(context),
              icon: Icon(_fabIcon, size: 18),
              label: Text(
                _extendedLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      );
    }

    return FloatingActionButton(
      onPressed: () => _showActionsModal(context),
      tooltip: _fabTooltip,
      child: Icon(_fabIcon, size: 28),
    );
  }
}

class _SmartFABContent extends StatelessWidget {
  final QuickActionFocus focus;

  const _SmartFABContent({required this.focus});

  void _showQuickAddShoppingSheet(BuildContext context) {
    final controller = TextEditingController();
    bool isPersonal = false;

    showAdaptiveModal(
      context: context,
      maxWidth: 480,
      child: StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shopping_cart_outlined, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Novo Item de Compra',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'O que precisa comprar?',
                    hintText: 'Ex: Leite, Café, Detergente...',
                    prefixIcon: const Icon(Icons.add_shopping_cart_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (val) async {
                    if (val.trim().isNotEmpty) {
                      final cubit = context.read<ShoppingCubit>();
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(dialogCtx);
                      final ok = await cubit.addItem(name: val.trim(), isPersonal: isPersonal);
                      showSaveFeedback(
                        messenger,
                        ok: ok,
                        success: '"$val" adicionado à lista de compras!',
                        failure: cubit.state.errorMessage,
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Item Pessoal (só meu)', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Todos veem na lista; o valor é separado ao fechar a compra', style: TextStyle(fontSize: 12)),
                  value: isPersonal,
                  onChanged: (val) => setModalState(() => isPersonal = val ?? false),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isNotEmpty) {
                      final cubit = context.read<ShoppingCubit>();
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(dialogCtx);
                      final ok = await cubit.addItem(name: text, isPersonal: isPersonal);
                      showSaveFeedback(
                        messenger,
                        ok: ok,
                        success: '"$text" adicionado à lista de compras!',
                        failure: cubit.state.errorMessage,
                      );
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar à Lista'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !context.isMobile;

    String headerTitle;
    String focusBadge;
    IconData headerIcon;

    switch (focus) {
      case QuickActionFocus.calendar:
        headerTitle = 'Ações da Agenda';
        focusBadge = 'Foco: Agenda do Lar';
        headerIcon = Icons.calendar_month_rounded;
        break;
      case QuickActionFocus.tasks:
        headerTitle = 'Ações de Rotina';
        focusBadge = 'Foco: Tarefas & Compras';
        headerIcon = Icons.checklist_rtl_rounded;
        break;
      case QuickActionFocus.p2p:
        headerTitle = 'Ações Pessoais & P2P';
        focusBadge = 'Foco: Empréstimos';
        headerIcon = Icons.handshake_rounded;
        break;
      case QuickActionFocus.home:
        headerTitle = 'Ações do Lar & Finanças';
        focusBadge = 'Foco: Gestão da Casa';
        headerIcon = Icons.home_work_rounded;
        break;
      case QuickActionFocus.general:
        headerTitle = 'Ações Rápidas';
        focusBadge = 'Ações Globais';
        headerIcon = Icons.bolt_rounded;
        break;
    }

    return SingleChildScrollView(
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
              Row(
                children: [
                  Icon(headerIcon, color: AppColors.primary, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    headerTitle,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              focusBadge,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 1. SEÇÃO EM FOCO (CONTEXTUALIZADA)
          _buildFocusedActions(context),
          const SizedBox(height: 20),

          // 2. SEÇÃO SECUNDÁRIA (DEMAIS AÇÕES GLOBAIS)
          _buildSecondaryActions(context),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildFocusedActions(BuildContext context) {
    switch (focus) {
      case QuickActionFocus.calendar:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Em Destaque para a Agenda'),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.event_available_rounded,
                  label: 'Novo Evento',
                  subtitle: 'Adicionar à agenda',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    final activeMemberId = context.read<CalendarCubit>().state.activeMemberId;
                    AddEventSheet.show(context, activeMemberId);
                  },
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                  context,
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Escanear Convite',
                  subtitle: 'Ler dados com IA',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    SmartScannerPage.show(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.auto_awesome_rounded,
                  label: 'Assistente da Agenda',
                  subtitle: 'Perguntar sobre a rotina',
                  color: AppColors.accent,
                  onTap: () {
                    Navigator.pop(context);
                    AssistantChatPage.show(context);
                  },
                ),
              ],
            ),
          ],
        );

      case QuickActionFocus.tasks:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Em Destaque para Tarefas & Compras'),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Nova Tarefa',
                  subtitle: 'Atribuir a um membro',
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
                  icon: Icons.add_shopping_cart_rounded,
                  label: 'Item de Compra',
                  subtitle: 'Adicionar à lista',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.pop(context);
                    _showQuickAddShoppingSheet(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Escanear Lista',
                  subtitle: 'Digitalizar com IA',
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
                  label: 'Assistente de Rotina',
                  subtitle: 'Organizar tarefas',
                  color: AppColors.accent,
                  onTap: () {
                    Navigator.pop(context);
                    AssistantChatPage.show(context);
                  },
                ),
              ],
            ),
          ],
        );

      case QuickActionFocus.p2p:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Em Destaque para Empréstimos & Pessoal'),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.handshake_rounded,
                  label: 'Novo Empréstimo',
                  subtitle: 'Emprestar ou pedir',
                  color: AppColors.primary,
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
                  icon: Icons.receipt_long_rounded,
                  label: 'Gasto Pessoal',
                  subtitle: 'Só da minha conta',
                  color: Colors.indigo,
                  onTap: () {
                    Navigator.pop(context);
                    showAdaptiveModal(
                      context: context,
                      maxWidth: 540,
                      child: const AddExpensePage(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.auto_awesome_rounded,
                  label: 'Assistente P2P',
                  subtitle: 'Simular parcelas e juros',
                  color: AppColors.accent,
                  onTap: () {
                    Navigator.pop(context);
                    AssistantChatPage.show(context);
                  },
                ),
              ],
            ),
          ],
        );

      case QuickActionFocus.home:
      case QuickActionFocus.general:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Em Destaque para o Lar & Finanças'),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.shopping_cart_outlined,
                  label: 'Gasto da Casa',
                  subtitle: 'Despesa compartilhada',
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
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Escanear Nota',
                  subtitle: 'Leitura com IA',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    SmartScannerPage.show(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.move_to_inbox_rounded,
                  label: 'Novo Aporte',
                  subtitle: 'Saldo da casa',
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
                  icon: Icons.south_west_rounded,
                  label: 'Entrada de fora',
                  subtitle: 'Pix, repasse, reembolso',
                  color: AppColors.creditGreen,
                  onTap: () => _openHouseInflowForm(context),
                ),
              ],
            ),
          ],
        );
    }
  }

  /// Entrada de fora (0096): o formulário abre por cima, já fora deste menu.
  void _openHouseInflowForm(BuildContext context) {
    final cubit = context.read<FinanceCubit>();
    Navigator.pop(context);
    showHouseInflowForm(context, cubit, cubit.state);
  }

  Widget _buildSecondaryActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        _buildSectionHeader('Outras Ações Rápidas'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (focus != QuickActionFocus.home) ...[
              _buildCompactActionChip(
                context,
                icon: Icons.shopping_cart_outlined,
                label: 'Gasto da Casa',
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: const AddExpensePage(),
                  );
                },
              ),
              _buildCompactActionChip(
                context,
                icon: Icons.qr_code_scanner_rounded,
                label: 'Escanear',
                onTap: () {
                  Navigator.pop(context);
                  SmartScannerPage.show(context);
                },
              ),
              _buildCompactActionChip(
                context,
                icon: Icons.move_to_inbox_rounded,
                label: 'Aporte',
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: const AddContributionPage(),
                  );
                },
              ),
            ],
            if (focus != QuickActionFocus.calendar)
              _buildCompactActionChip(
                context,
                icon: Icons.event_available_rounded,
                label: 'Novo Evento',
                onTap: () {
                  Navigator.pop(context);
                  final activeMemberId = context.read<CalendarCubit>().state.activeMemberId;
                  AddEventSheet.show(context, activeMemberId);
                },
              ),
            if (focus != QuickActionFocus.tasks) ...[
              _buildCompactActionChip(
                context,
                icon: Icons.check_circle_outline_rounded,
                label: 'Nova Tarefa',
                onTap: () {
                  Navigator.pop(context);
                  final activeMemberId = context.read<CalendarCubit>().state.activeMemberId;
                  AddTaskSheet.show(context, activeMemberId);
                },
              ),
              _buildCompactActionChip(
                context,
                icon: Icons.add_shopping_cart_rounded,
                label: 'Item de Compra',
                onTap: () {
                  Navigator.pop(context);
                  _showQuickAddShoppingSheet(context);
                },
              ),
            ],
            if (focus != QuickActionFocus.p2p)
              _buildCompactActionChip(
                context,
                icon: Icons.handshake_rounded,
                label: 'Empréstimo P2P',
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: const CreateLoanPage(),
                  );
                },
              ),
            _buildCompactActionChip(
              context,
              icon: Icons.flash_on_rounded,
              label: 'Fechamento',
              onTap: () {
                Navigator.pop(context);
                context.push('/fechamento');
              },
            ),
            _buildCompactActionChip(
              context,
              icon: Icons.auto_awesome_rounded,
              label: 'Assistente IA',
              onTap: () {
                Navigator.pop(context);
                AssistantChatPage.show(context);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.primary),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: Theme.of(context).cardColor,
      side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onPressed: onTap,
    );
  }
}
