import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/domain/repositories/auth_repository.dart';
import '../../data/datasources/notifications_datasource.dart';
import '../../domain/entities/app_notification.dart';

enum NotificationsStatus { initial, loading, success, failure }

class NotificationsState extends Equatable {
  final NotificationsStatus status;
  final List<AppNotification> items;
  final String? errorMessage;

  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.items = const [],
    this.errorMessage,
  });

  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? items,
    String? errorMessage,
  }) =>
      NotificationsState(
        status: status ?? this.status,
        items: items ?? this.items,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [status, items, errorMessage];
}

/// Sino da Home: carrega as notificações do morador, acompanha as novas pelo
/// tempo real e marca como lidas.
class NotificationsCubit extends Cubit<NotificationsState> {
  final NotificationsDataSource _dataSource;
  final AuthRepository? _authRepository;
  StreamSubscription? _authSubscription;
  StreamSubscription<void>? _changesSubscription;
  Timer? _changesDebounce;

  NotificationsCubit(this._dataSource, [this._authRepository]) : super(const NotificationsState()) {
    _authSubscription = _authRepository?.authStateChanges.listen((user) {
      // Troca de conta: o tempo real volta a ser ligado para o morador novo
      _stopWatching();
      if (user != null) {
        load();
      } else {
        emit(const NotificationsState());
      }
    });
  }

  Future<void> load() async {
    if (isClosed) return;
    if (state.items.isEmpty) emit(state.copyWith(status: NotificationsStatus.loading));
    try {
      final items = await _dataSource.getNotifications();
      if (isClosed) return;
      emit(state.copyWith(status: NotificationsStatus.success, items: items));
      _watch();
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: NotificationsStatus.failure, errorMessage: e.toString()));
      }
    }
  }

  void _watch() {
    if (_changesSubscription != null || isClosed) return;
    try {
      _changesSubscription = _dataSource.watchNotifications().listen(
        (_) {
          // Uma rajada (importação, fechamento) chega em vários avisos seguidos
          _changesDebounce?.cancel();
          _changesDebounce = Timer(const Duration(milliseconds: 500), () {
            if (!isClosed) _reloadQuietly();
          });
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _stopWatching() {
    _changesDebounce?.cancel();
    _changesDebounce = null;
    _changesSubscription?.cancel();
    _changesSubscription = null;
  }

  Future<void> _reloadQuietly() async {
    try {
      final items = await _dataSource.getNotifications();
      if (!isClosed) emit(state.copyWith(status: NotificationsStatus.success, items: items));
    } catch (_) {}
  }

  Future<void> markAsRead(String id) async {
    final index = state.items.indexWhere((n) => n.id == id);
    if (index < 0 || state.items[index].isRead) return;
    final previous = state.items;
    final updated = [...previous];
    updated[index] = updated[index].copyWith(readAt: DateTime.now());
    emit(state.copyWith(items: updated));
    try {
      await _dataSource.markAsRead(id);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(items: previous, errorMessage: e.toString()));
    }
  }

  Future<void> markAllAsRead() async {
    if (state.unreadCount == 0) return;
    final previous = state.items;
    final now = DateTime.now();
    emit(state.copyWith(items: [for (final n in previous) n.isRead ? n : n.copyWith(readAt: now)]));
    try {
      await _dataSource.markAllAsRead();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(items: previous, errorMessage: e.toString()));
    }
  }

  /// Insere uma notificação gerada localmente no aparelho (ex.: captura em 2º plano).
  void pushLocalNotification(AppNotification notification) {
    if (isClosed) return;
    final updated = [
      notification,
      ...state.items.where((n) => n.id != notification.id),
    ];
    emit(state.copyWith(status: NotificationsStatus.success, items: updated));
  }

  void resetState() {
    _stopWatching();
    emit(const NotificationsState());
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _stopWatching();
    return super.close();
  }
}
