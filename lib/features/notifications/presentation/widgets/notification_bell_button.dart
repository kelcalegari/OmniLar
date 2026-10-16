import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubit/notifications_cubit.dart';

/// Sino da Home com a contagem de não lidas. Abre a lista de notificações.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (a, b) => a.unreadCount != b.unreadCount,
      builder: (context, state) {
        final unread = state.unreadCount;
        return IconButton(
          tooltip: unread == 0 ? 'Notificações' : 'Notificações ($unread não lidas)',
          onPressed: () => context.push('/notificacoes'),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}
