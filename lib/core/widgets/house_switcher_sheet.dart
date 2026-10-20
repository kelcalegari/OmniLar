import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../features/admin/presentation/cubit/account_access_cubit.dart';
import '../../features/auth/domain/entities/house.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_state.dart';
import '../di/service_locator.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../../features/settings/presentation/widgets/house_management_panel.dart';

/// Seletor de Casas para contas que participam ou gerenciam múltiplos lares.
/// Adapta-se como BottomSheet no celular e Dialog no Desktop/Web.
class HouseSwitcherSheet extends StatelessWidget {
  const HouseSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    if (context.isWideScreen) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: const HouseSwitcherSheet(),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HouseSwitcherSheet(),
    );
  }

  void _handleCreateHouse(BuildContext context, AuthState authState) {
    final accessCubit = sl<AccountAccessCubit>();
    final isPremium = accessCubit.state.isPremium;
    final currentUserId = authState.user?.id;
    final ownedCount = authState.userHouses
        .where((h) => h.createdBy == currentUserId)
        .length;

    // Usuário no plano Free já é dono de 1 casa: diálogo acolhedor do Premium
    if (!isPremium && ownedCount >= 1) {
      showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(
            Icons.workspace_premium_rounded,
            color: Colors.amber,
            size: 44,
          ),
          title: const Text(
            'Múltiplas Casas no Omni Lar',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'No plano Free você pode criar e administrar 1 casa.\n\n'
            'O Omni Lar Premium permite criar e gerenciar até 3 casas (como casa de praia, '
            'sítio, apoio aos pais ou república) com a mesma conta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Agora não'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                Navigator.of(context).pop();
                context.push('/ajustes');
              },
              icon: const Icon(Icons.star_rounded, size: 18),
              label: const Text('Conhecer o Premium'),
            ),
          ],
        ),
      );
      return;
    }

    // Autorizado a criar: fecha o seletor e vai para o formulário
    Navigator.of(context).pop();
    context.push('/casas/nova?tab=create');
  }

  void _handleJoinHouse(BuildContext context) {
    Navigator.of(context).pop();
    context.push('/casas/nova?tab=invite');
  }

  void _showMinimumHouseDialog(BuildContext context, String actionLabel) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 36),
        title: const Text('Mínimo de 1 Casa Ativa', textAlign: TextAlign.center),
        content: Text(
          'Você precisa ter pelo menos uma casa ativa no Omni Lar.\n\n'
          'Para $actionLabel esta residência, crie uma nova casa ou entre em outra residência primeiro.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _handleArchive(BuildContext context, House house, int totalHouses) {
    if (totalHouses <= 1) {
      _showMinimumHouseDialog(context, 'arquivar');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.archive_outlined, color: Colors.amber, size: 36),
        title: Text('Arquivar "${house.name}"?'),
        content: const Text(
          'A casa será ocultada da sua lista do dia a dia, mas todo o histórico financeiro '
          'e lançamentos continuarão preservados com segurança.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final authCubit = context.read<AuthCubit>();
              final ok = await authCubit.archiveHouse(house.id);
              if (ok) {
                messenger.showSnackBar(
                  SnackBar(content: Text('A casa "${house.name}" foi arquivada. 📦')),
                );
              } else {
                final err = authCubit.state.errorMessage ?? 'Não foi possível arquivar a casa.';
                messenger.showSnackBar(
                  SnackBar(backgroundColor: AppColors.debtRed, content: Text(err)),
                );
              }
            },
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );
  }

  void _handleDelete(BuildContext context, House house, int totalHouses) {
    if (totalHouses <= 1) {
      _showMinimumHouseDialog(context, 'excluir');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DeleteHouseModal(house: house),
        ),
      ),
    );
  }

  void _handleLeave(BuildContext context, House house, int totalHouses) {
    if (totalHouses <= 1) {
      _showMinimumHouseDialog(context, 'sair de');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.debtRed, size: 36),
        title: Text('Sair de "${house.name}"?'),
        content: const Text(
          'Deseja realmente deixar de morar nesta casa?\n\n'
          'Seu histórico financeiro permanece preservado para os outros moradores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final authCubit = context.read<AuthCubit>();
              final ok = await authCubit.leaveHouse(house.id);
              if (ok) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Você saiu da casa "${house.name}".')),
                );
              } else {
                final err = authCubit.state.errorMessage ?? 'Não foi possível sair da casa.';
                messenger.showSnackBar(
                  SnackBar(backgroundColor: AppColors.debtRed, content: Text(err)),
                );
              }
            },
            child: const Text('Sair da Casa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final currentHouse = authState.house;
        final currentUserId = authState.user?.id;
        final houses = authState.userHouses.isNotEmpty
            ? authState.userHouses
            : (currentHouse != null ? [currentHouse] : <House>[]);

        final accessCubit = sl<AccountAccessCubit>();
        final isPremium = accessCubit.state.isPremium;
        final ownedCount = houses.where((h) => h.createdBy == currentUserId).length;
        final showPremiumBadge = !isPremium && ownedCount >= 1;

        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: context.isWideScreen
                ? const BorderRadius.all(Radius.circular(20))
                : const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!context.isWideScreen)
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    // Cabeçalho
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.home_work_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Minhas Casas',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                'Selecione o ambiente que deseja gerenciar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Lista de Casas
                    ...houses.map((house) {
                      final isActive = house.id == currentHouse?.id;
                      final isOwner = house.createdBy == currentUserId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : theme.cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isActive
                                  ? AppColors.primary.withValues(alpha: 0.5)
                                  : Colors.grey.withValues(alpha: 0.2),
                              width: isActive ? 1.5 : 1,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: isActive
                                ? null
                                : () async {
                                    Navigator.of(context).pop();
                                    await context
                                        .read<AuthCubit>()
                                        .switchHouse(house.id);
                                  },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isActive
                                        ? AppColors.primary
                                        : Colors.grey.withValues(alpha: 0.15),
                                    child: Icon(
                                      Icons.home_rounded,
                                      size: 20,
                                      color: isActive
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          house.name,
                                          style: TextStyle(
                                            fontWeight: isActive
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isOwner
                                                    ? Colors.amber.withValues(
                                                        alpha: 0.18,
                                                      )
                                                    : Colors.blue.withValues(
                                                        alpha: 0.12,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isOwner ? 'Dono' : 'Morador',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isOwner
                                                      ? Colors.amber.shade900
                                                      : Colors.blue.shade800,
                                                ),
                                              ),
                                            ),
                                            if (isActive) ...[
                                              const SizedBox(width: 6),
                                              const Text(
                                                '• Ativa agora',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isActive)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.primary,
                                        size: 20,
                                      ),
                                    ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert_rounded,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Opções da casa',
                                    onSelected: (val) {
                                      if (val == 'archive') {
                                        _handleArchive(context, house, houses.length);
                                      } else if (val == 'delete') {
                                        _handleDelete(context, house, houses.length);
                                      } else if (val == 'leave') {
                                        _handleLeave(context, house, houses.length);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      if (isOwner) ...[
                                        const PopupMenuItem(
                                          value: 'archive',
                                          child: Row(
                                            children: [
                                              Icon(Icons.archive_outlined, size: 18, color: Colors.amber),
                                              SizedBox(width: 8),
                                              Text('Arquivar casa'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_forever_rounded, size: 18, color: AppColors.debtRed),
                                              SizedBox(width: 8),
                                              Text(
                                                'Excluir permanentemente',
                                                style: TextStyle(color: AppColors.debtRed),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else ...[
                                        const PopupMenuItem(
                                          value: 'leave',
                                          child: Row(
                                            children: [
                                              Icon(Icons.exit_to_app_rounded, size: 18, color: AppColors.debtRed),
                                              SizedBox(width: 8),
                                              Text(
                                                'Sair da casa',
                                                style: TextStyle(color: AppColors.debtRed),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    // Ações de rodapé
                    OutlinedButton.icon(
                      onPressed: () => _handleCreateHouse(context, authState),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_home_rounded, size: 20),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Criar nova casa'),
                          if (showPremiumBadge) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 12,
                                    color: Colors.amber,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    'Premium',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _handleJoinHouse(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.group_add_rounded, size: 20),
                      label: const Text('Entrar com código de convite'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
