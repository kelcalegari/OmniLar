import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:omni_lar/features/notifications/data/datasources/mock_notifications_datasource.dart';
import 'package:omni_lar/features/notifications/domain/entities/app_notification.dart';
import 'package:omni_lar/features/notifications/presentation/cubit/notifications_cubit.dart';
import 'package:omni_lar/features/notifications/presentation/pages/notifications_page.dart';

AppNotification _n(String id, DateTime createdAt) => AppNotification(
      id: id,
      type: 'task_assigned',
      category: NotificationCategory.tarefas,
      title: 't',
      body: 'b',
      createdAt: createdAt,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('NotificationsCubit (modo demo)', () {
    test('carrega as notificações de exemplo e conta as não lidas', () async {
      final cubit = NotificationsCubit(MockNotificationsDataSource());
      await cubit.load();

      expect(cubit.state.status, NotificationsStatus.success);
      expect(cubit.state.items, hasLength(4));
      expect(cubit.state.unreadCount, 2);
      await cubit.close();
    });

    test('marcar uma como lida diminui a contagem', () async {
      final cubit = NotificationsCubit(MockNotificationsDataSource());
      await cubit.load();
      await cubit.markAsRead('notif_loan');

      expect(cubit.state.unreadCount, 1);
      expect(cubit.state.items.firstWhere((n) => n.id == 'notif_loan').isRead, isTrue);
      await cubit.close();
    });

    test('marcar todas como lidas zera a contagem e sobrevive a recarregar', () async {
      final source = MockNotificationsDataSource();
      final cubit = NotificationsCubit(source);
      await cubit.load();
      await cubit.markAllAsRead();
      expect(cubit.state.unreadCount, 0);

      await cubit.load();
      expect(cubit.state.unreadCount, 0);
      await cubit.close();
    });

    test('os deeplinks de exemplo apontam para as rotas do item', () async {
      final items = await MockNotificationsDataSource().getNotifications();
      final links = items.map((n) => n.deeplink).toList();
      expect(links, contains('/pessoal/emprestimo/loan_furadeira'));
      expect(links, contains('/agenda/evento/event_1'));
    });
  });

  group('groupNotificationsByDay', () {
    test('separa em Hoje, Ontem e a data', () {
      final now = DateTime(2026, 10, 16, 15);
      final groups = groupNotificationsByDay([
        _n('a', DateTime(2026, 10, 16, 9)),
        _n('b', DateTime(2026, 10, 16, 1)),
        _n('c', DateTime(2026, 10, 15, 23)),
        _n('d', DateTime(2026, 10, 2, 8)),
        _n('e', DateTime(2025, 12, 31, 8)),
      ], now);

      expect(groups.map((g) => g.label).toList(),
          ['Hoje', 'Ontem', '2 de outubro', '31 de dezembro de 2025']);
      expect(groups.first.items.map((n) => n.id), ['a', 'b']);
    });
  });

  group('AppNotification.fromRow', () {
    test('lê a linha do banco', () {
      final n = AppNotification.fromRow({
        'id': '1',
        'type': 'loan_created',
        'category': 'emprestimos',
        'title': 'Novo empréstimo',
        'body': 'corpo',
        'deeplink': '/pessoal/emprestimo/x',
        'is_essential': true,
        'created_at': '2026-10-16T12:00:00Z',
        'read_at': null,
      });
      expect(n.category, NotificationCategory.emprestimos);
      expect(n.isEssential, isTrue);
      expect(n.isRead, isFalse);
    });

    test('grupo desconhecido cai em Casa', () {
      expect(NotificationCategory.fromName('outro'), NotificationCategory.casa);
    });
  });
}
