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
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primary,
                                      size: 22,
                                    )
                                  else
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: Colors.grey,
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
