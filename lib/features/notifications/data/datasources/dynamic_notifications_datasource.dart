import '../../domain/entities/app_notification.dart';
import 'notifications_datasource.dart';

class DynamicNotificationsDataSource implements NotificationsDataSource {
  final NotificationsDataSource remote;
  final NotificationsDataSource mock;
  final bool Function() isDemoMode;

  DynamicNotificationsDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  NotificationsDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Future<List<AppNotification>> getNotifications({int limit = 100}) =>
      _active.getNotifications(limit: limit);

  @override
  Future<void> markAsRead(String id) => _active.markAsRead(id);

  @override
  Future<void> markAllAsRead() => _active.markAllAsRead();

  @override
  Stream<void> watchNotifications() => _active.watchNotifications();
}
