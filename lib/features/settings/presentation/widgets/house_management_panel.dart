import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/domain/entities/house.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

/// Painel de Gerenciamento da Casa: Arquivar, Excluir ou Sair da Casa,
/// respeitando a regra de que o usuário sempre deve ter pelo menos 1 casa ativa.
class HouseManagementPanel extends StatelessWidget {
  final House? house;

  const HouseManagementPanel({super.key, required this.house});

  void _showMinimumHouseDialog(BuildContext context, String actionLabel) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 36),
        title: const Text('Mínimo de 1 Casa Ativa', textAlign: TextAlign.center),
        content: Text(
          'Você precisa ter pelo menos uma casa ativa no Omni Lar.\n\n'
          'Para $actionLabel esta residência, crie uma nova casa ou aceite o convite de outra casa primeiro.',
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

  void _openArchiveDialog(BuildContext context, House house) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.archive_outlined, color: Colors.amber, size: 36),
        title: Text('Arquivar "${house.name}"?'),
        content: const Text(
          'Ao arquivar a casa, ela será ocultada da sua visualização do dia a dia, '
          'mas todo o livro-razão financeiro, lançamentos e histórico permanecerão preservados com total segurança.\n\n'
          'O app alternará automaticamente para outra de suas casas ativas.',
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
                  SnackBar(content: Text('A casa "${house.name}" foi arquivada com sucesso. 📦')),
                );
              } else {
                final err = authCubit.state.errorMessage ?? 'Não foi possível arquivar a casa.';
                messenger.showSnackBar(
                  SnackBar(backgroundColor: AppColors.debtRed, content: Text(err)),
                );
              }
            },
            child: const Text('Arquivar Casa'),
          ),
        ],
      ),
    );
  }

  void _openDeleteDialog(BuildContext context, House house) {
    showAdaptiveModal(
      context: context,
      maxWidth: 480,
      child: DeleteHouseModal(house: house),
    );
  }

  void _openLeaveDialog(BuildContext context, House house) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.debtRed, size: 36),
        title: Text('Sair de "${house.name}"?'),
        content: const Text(
          'Deseja realmente deixar de morar nesta casa?\n\n'
          'Seu histórico de lançamentos e pagamentos permanecerá registrado para os demais moradores, '
          'mas você não terá mais acesso a esta casa.',
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
    if (house == null) return const SizedBox.shrink();

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final currentUserId = authState.user?.id;
        final isOwner = house!.createdBy == currentUserId;
        final activeHousesCount = authState.userHouses.where((h) => !h.isArchived).length;
        final canRemove = activeHousesCount > 1;

        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.settings_suggest_rounded,
                        color: AppColors.debtRed,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gerenciamento da Casa',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOwner
                                ? 'Opções de encerramento e arquivamento para o proprietário'
                                : 'Opções de morador para esta casa',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!canRemove)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Esta é a sua única casa ativa. O Omni Lar exige pelo menos uma casa associada à sua conta.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (isOwner) ...[
                  // Arquivar Casa (Opção Padrão)
                  _ActionTile(
                    icon: Icons.archive_outlined,
                    iconColor: Colors.amber.shade800,
                    title: 'Arquivar Casa',
                    badge: 'Recomendado',
                    badgeColor: Colors.amber.shade800,
                    subtitle:
                        'Oculta a casa e seu dia a dia, mas mantém histórico financeiro e relatórios preservados com segurança.',
                    buttonLabel: 'Arquivar',
                    buttonColor: Colors.amber.shade800,
                    onTap: () {
                      if (!canRemove) {
                        _showMinimumHouseDialog(context, 'arquivar');
                      } else {
                        _openArchiveDialog(context, house!);
                      }
                    },
                  ),
                  const Divider(height: 28),
                  // Excluir Permanentemente (Opção Avançada)
                  _ActionTile(
                    icon: Icons.delete_forever_rounded,
                    iconColor: AppColors.debtRed,
                    title: 'Excluir Permanentemente',
                    badge: 'Avançado',
                    badgeColor: AppColors.debtRed,
                    subtitle:
                        'Ação definitiva e irreversível. Exclui a casa, lançamentos, despesas e dados de todos os moradores.',
                    buttonLabel: 'Excluir Casa',
                    buttonColor: AppColors.debtRed,
                    isDestructive: true,
                    onTap: () {
                      if (!canRemove) {
                        _showMinimumHouseDialog(context, 'excluir');
                      } else {
                        _openDeleteDialog(context, house!);
                      }
                    },
                  ),
                ] else ...[
                  // Sair da Casa (Membros)
                  _ActionTile(
                    icon: Icons.exit_to_app_rounded,
                    iconColor: AppColors.debtRed,
                    title: 'Sair da Casa',
                    subtitle:
                        'Você deixa de ser morador desta casa. Seu histórico financeiro continua registrado para os demais.',
                    buttonLabel: 'Sair da Casa',
                    buttonColor: AppColors.debtRed,
                    isDestructive: true,
                    onTap: () {
                      if (!canRemove) {
                        _showMinimumHouseDialog(context, 'sair de');
                      } else {
                        _openLeaveDialog(context, house!);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Color buttonColor;
  final String? badge;
  final Color? badgeColor;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.buttonColor,
    this.badge,
    this.badgeColor,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDestructive ? AppColors.debtRed : null,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (badgeColor ?? iconColor).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor ?? iconColor,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: buttonColor,
              side: BorderSide(color: buttonColor.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class DeleteHouseModal extends StatefulWidget {
  final House house;

  const DeleteHouseModal({super.key, required this.house});

  @override
  State<DeleteHouseModal> createState() => _DeleteHouseModalState();
}

class _DeleteHouseModalState extends State<DeleteHouseModal> {
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expectedText = widget.house.name.trim();
    final isMatch = _confirmController.text.trim().toLowerCase() == expectedText.toLowerCase();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.debtRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.debtRed,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Excluir Casa Definitivamente',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.debtRed,
                      ),
                    ),
                    Text(
                      widget.house.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Esta ação é permanente e NÃO pode ser desfeita. '
            'Todos os lançamentos, dívidas, rateios, comprovantes e dados desta residência serão apagados do banco de dados.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Para confirmar, digite exatamente o nome da casa:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  expectedText,
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                TextButton.icon(
                  onPressed: () {
                    _confirmController.text = expectedText;
                    setState(() {});
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Preencher', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Digite "$expectedText"',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (!isMatch || _isSubmitting)
                      ? null
                      : () async {
                          setState(() => _isSubmitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);
                          final authCubit = context.read<AuthCubit>();
                          final ok = await authCubit.deleteHouse(widget.house.id);
                          if (!mounted) return;
                          if (ok) {
                            navigator.pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('A casa "${widget.house.name}" foi excluída permanentemente.'),
                              ),
                            );
                          } else {
                            setState(() => _isSubmitting = false);
                            final err = authCubit.state.errorMessage ?? 'Não foi possível excluir a casa.';
                            messenger.showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.debtRed,
                                content: Text(err),
                              ),
                            );
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.debtRed,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Excluir Casa',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }
}
