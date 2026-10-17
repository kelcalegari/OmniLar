import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_preferences.dart';

abstract class NotificationsDataSource {
  /// As notificações do morador logado, da mais nova para a mais antiga.
  Future<List<AppNotification>> getNotifications({int limit = 100});

  Future<void> markAsRead(String id);

  Future<void> markAllAsRead();

  /// Avisa quando chega ou muda uma notificação do morador (tempo real).
  Stream<void> watchNotifications();

  /// Preferências do morador logado na casa atual.
  Future<NotificationPreferences> getPreferences();

  /// Grava a preferência de um grupo na casa atual.
  Future<void> saveGroupPreference(NotificationCategory group, GroupPreference preference);

  /// Grava as configurações gerais (horário silencioso, valores e resumo semanal).
  Future<void> saveSettings(NotificationPreferences preferences);
}
