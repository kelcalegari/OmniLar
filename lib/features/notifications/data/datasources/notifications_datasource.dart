import '../../domain/entities/app_notification.dart';

abstract class NotificationsDataSource {
  /// As notificações do morador logado, da mais nova para a mais antiga.
  Future<List<AppNotification>> getNotifications({int limit = 100});

  Future<void> markAsRead(String id);

  Future<void> markAllAsRead();

  /// Avisa quando chega ou muda uma notificação do morador (tempo real).
  Stream<void> watchNotifications();
}
