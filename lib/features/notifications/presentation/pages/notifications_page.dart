import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../domain/entities/app_notification.dart';
import '../cubit/notifications_cubit.dart';

/// Lista do sino, agrupada por dia, com "marcar todas como lidas". Tocar numa
/// notificação marca como lida e abre o item pelo deeplink.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsCubit>().load();
    });
  }

  void _open(AppNotification notification) {
    context.read<NotificationsCubit>().markAsRead(notification.id);
    final link = notification.deeplink;
    if (link == null || !link.startsWith('/')) return;
    // Sai do sino antes de ir ao item: o painel que a tela do item abre não
    // pode ficar preso à página do sino, que sai da pilha com a navegação.
    final router = GoRouter.of(context);
    if (context.canPop()) {
      context.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => router.go(link));
    } else {
      router.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notificações', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (state.unreadCount > 0)
                TextButton.icon(
                  onPressed: () => context.read<NotificationsCubit>().markAllAsRead(),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Marcar todas como lidas'),
                ),
            ],
          ),
          body: _buildBody(context, state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, NotificationsState state) {
    if (state.status == NotificationsStatus.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == NotificationsStatus.failure && state.items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        text: 'Não foi possível carregar as notificações.',
        action: TextButton(
          onPressed: () => context.read<NotificationsCubit>().load(),
          child: const Text('Tentar de novo'),
        ),
      );
    }
    if (state.items.isEmpty) {
      return const _Message(
        icon: Icons.notifications_none_rounded,
        text: 'Nenhuma notificação por aqui.',
      );
    }

    final groups = groupNotificationsByDay(state.items, DateTime.now());
    return RefreshIndicator(
      onRefresh: () => context.read<NotificationsCubit>().load(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final group in groups) ...[
            ResponsiveContainer(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    group.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
            for (final n in group.items)
              ResponsiveContainer(
                child: _NotificationTile(notification: n, onTap: () => _open(n)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Um dia da lista: "Hoje", "Ontem" ou a data.
class NotificationDayGroup {
  final String label;
  final List<AppNotification> items;

  const NotificationDayGroup(this.label, this.items);
}

/// Agrupa por dia, na ordem recebida (da mais nova para a mais antiga).
List<NotificationDayGroup> groupNotificationsByDay(List<AppNotification> items, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  String labelFor(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (day.year == today.year) return DateFormat("d 'de' MMMM", 'pt_BR').format(day);
    return DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(day);
  }

  final groups = <NotificationDayGroup>[];
  for (final n in items) {
    final label = labelFor(n.createdAt);
    if (groups.isEmpty || groups.last.label != label) {
      groups.add(NotificationDayGroup(label, [n]));
    } else {
      groups.last.items.add(n);
    }
  }
  return groups;
}

IconData notificationIcon(NotificationCategory category) => switch (category) {
      NotificationCategory.casa => Icons.home_rounded,
      NotificationCategory.despesas => Icons.receipt_long_rounded,
      NotificationCategory.fechamento => Icons.event_available_rounded,
      NotificationCategory.emprestimos => Icons.handshake_rounded,
      NotificationCategory.caixinhas => Icons.savings_rounded,
      NotificationCategory.compras => Icons.shopping_cart_rounded,
      NotificationCategory.tarefas => Icons.task_alt_rounded,
      NotificationCategory.agenda => Icons.calendar_month_rounded,
      NotificationCategory.projetos => Icons.folder_shared_rounded,
      NotificationCategory.assistente => Icons.auto_awesome_rounded,
      NotificationCategory.conta => Icons.manage_accounts_rounded,
    };

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !notification.isRead;
    final accent = notification.isEssential && unread ? AppColors.primary : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: unread ? AppColors.primary.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withValues(alpha: 0.12),
                child: Icon(notificationIcon(notification.category), size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(notification.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.Hm('pt_BR').format(notification.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: color)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
