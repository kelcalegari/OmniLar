import 'dart:async';

import '../../domain/entities/app_notification.dart';
import 'notifications_datasource.dart';

/// Modo demo: notificações de exemplo só no sino, sem push.
class MockNotificationsDataSource implements NotificationsDataSource {
  final StreamController<void> _changes = StreamController<void>.broadcast();
  late final List<AppNotification> _items = _seed(DateTime.now());

  static List<AppNotification> _seed(DateTime now) => [
        AppNotification(
          id: 'notif_loan',
          type: 'loan_created',
          category: NotificationCategory.emprestimos,
          title: 'Novo empréstimo',
          body: 'Marina registrou que você deve R\$ 250,00 a ela: Conserto da Furadeira',
          deeplink: '/pessoal/emprestimo/loan_furadeira',
          isEssential: true,
          createdAt: now.subtract(const Duration(minutes: 12)),
        ),
        AppNotification(
          id: 'notif_event',
          type: 'event_invite',
          category: NotificationCategory.agenda,
          title: 'Convite: Jantar de Aniversário de Carlos',
          body: 'Jantar de Aniversário de Carlos, daqui a 2 dias. Você foi marcado como necessário',
          deeplink: '/agenda/evento/event_1',
          isEssential: true,
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
        AppNotification(
          id: 'notif_task',
          type: 'task_assigned',
          category: NotificationCategory.tarefas,
          title: 'Nova tarefa',
          body: 'Comprar pó de café, até sexta',
          deeplink: '/tarefas',
          isEssential: true,
          createdAt: now.subtract(const Duration(days: 1, hours: 2)),
          readAt: now.subtract(const Duration(days: 1)),
        ),
        AppNotification(
          id: 'notif_settlement',
          type: 'settlement_confirmed',
          category: NotificationCategory.fechamento,
          title: 'Ciclo fechado',
          body: 'Ciclo fechado. Você recebe R\$ 120,00 de Carlos.',
          deeplink: '/casa/fechamento',
          isEssential: true,
          createdAt: now.subtract(const Duration(days: 4)),
          readAt: now.subtract(const Duration(days: 4)),
        ),
      ];

  @override
  Future<List<AppNotification>> getNotifications({int limit = 100}) async =>
      List.unmodifiable(_items.take(limit));

  @override
  Future<void> markAsRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0 || _items[index].isRead) return;
    _items[index] = _items[index].copyWith(readAt: DateTime.now());
    _changes.add(null);
  }

  @override
  Future<void> markAllAsRead() async {
    final now = DateTime.now();
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].isRead) _items[i] = _items[i].copyWith(readAt: now);
    }
    _changes.add(null);
  }

  @override
  Stream<void> watchNotifications() => _changes.stream;
}
