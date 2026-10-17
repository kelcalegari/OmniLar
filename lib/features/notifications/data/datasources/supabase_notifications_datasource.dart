import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_preferences.dart';
import 'notifications_datasource.dart';

class SupabaseNotificationsDataSource implements NotificationsDataSource {
  final SupabaseClient client;

  /// Casa atual (as preferências de grupo são por casa).
  final String Function() getCurrentHouseId;

  SupabaseNotificationsDataSource({required this.client, required this.getCurrentHouseId});

  String get _houseId {
    final id = getCurrentHouseId();
    if (id.isEmpty) throw const ServerFailure('Nenhuma casa selecionada.');
    return id;
  }

  static ({int hour, int minute})? _parseTime(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour == null || minute == null ? null : (hour: hour, minute: minute);
  }

  static String? _formatTime(({int hour, int minute})? time) => time == null
      ? null
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Future<NotificationPreferences> getPreferences() async {
    try {
      final userId = _userId;
      final groupRows = await client
          .from('notification_preferences')
          .select('category, in_app, push')
          .eq('user_id', userId)
          .eq('house_id', _houseId);
      final settings = await client
          .from('notification_settings')
          .select('quiet_hours_start, quiet_hours_end, hide_amounts, weekly_summary')
          .eq('user_id', userId)
          .maybeSingle();
      return NotificationPreferences(
        byGroup: {
          for (final row in groupRows)
            NotificationCategory.fromName(row['category'] as String?): GroupPreference(
              inApp: row['in_app'] as bool? ?? true,
              push: row['push'] as bool? ?? true,
            ),
        },
        quietStart: _parseTime(settings?['quiet_hours_start']),
        quietEnd: _parseTime(settings?['quiet_hours_end']),
        hideAmounts: settings?['hide_amounts'] as bool? ?? false,
        weeklySummary: settings?['weekly_summary'] as bool? ?? true,
      );
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao carregar as preferências de notificação: $e');
    }
  }

  @override
  Future<void> saveGroupPreference(NotificationCategory group, GroupPreference preference) async {
    try {
      await client.from('notification_preferences').upsert({
        'user_id': _userId,
        'house_id': _houseId,
        'category': group.name,
        'in_app': preference.inApp,
        'push': preference.push,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao salvar a preferência: $e');
    }
  }

  @override
  Future<void> saveSettings(NotificationPreferences preferences) async {
    try {
      await client.from('notification_settings').upsert({
        'user_id': _userId,
        'quiet_hours_start': _formatTime(preferences.quietStart),
        'quiet_hours_end': _formatTime(preferences.quietEnd),
        'hide_amounts': preferences.hideAmounts,
        'weekly_summary': preferences.weeklySummary,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao salvar as configurações de notificação: $e');
    }
  }

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw const ServerFailure('Usuário não autenticado.');
    return id;
  }

  @override
  Future<List<AppNotification>> getNotifications({int limit = 100}) async {
    try {
      final rows = await client
          .from('notifications')
          .select('id, type, category, title, body, deeplink, is_essential, created_at, read_at')
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return [for (final row in rows) AppNotification.fromRow(row)];
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao carregar as notificações: $e');
    }
  }

  @override
  Future<void> markAsRead(String id) async {
    try {
      await client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id)
          .filter('read_at', 'is', null);
    } catch (e) {
      throw ServerFailure('Erro ao marcar a notificação como lida: $e');
    }
  }

  @override
  Future<void> markAllAsRead() async {
    try {
      await client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', _userId)
          .filter('read_at', 'is', null);
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao marcar as notificações como lidas: $e');
    }
  }

  @override
  Stream<void> watchNotifications() {
    final userId = _userId;
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        // Tempo real da migration 0064, filtrado pelo destinatário
        channel = client
            .channel('notifications-$userId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) {
                if (!controller.isClosed) controller.add(null);
              },
            )
            .subscribe();
      },
      onCancel: () {
        final current = channel;
        channel = null;
        if (current != null) client.removeChannel(current);
      },
    );
    return controller.stream;
  }
}
