import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/app_notification.dart';
import 'notifications_datasource.dart';

class SupabaseNotificationsDataSource implements NotificationsDataSource {
  final SupabaseClient client;

  SupabaseNotificationsDataSource({required this.client});

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
