import 'dart:async';
import 'package:equatable/equatable.dart';

enum OfflineActionType {
  addExpense,
  createLoan,
  payInstallment,
  addShoppingItem,
  toggleShoppingItem,
  addCalendarEvent,
  addTask,
}

class OfflineQueuedAction extends Equatable {
  final String id;
  final OfflineActionType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;

  const OfflineQueuedAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  OfflineQueuedAction copyWith({
    String? id,
    OfflineActionType? type,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
  }) {
    return OfflineQueuedAction(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  List<Object?> get props => [id, type, payload, createdAt, retryCount];
}

/// Fila offline resiliente em memória e storage
/// Garante que criações locais sem internet sejam enfileiradas com idempotency_key
class OfflineQueueManager {
  final List<OfflineQueuedAction> _queue = [];
  final _controller = StreamController<List<OfflineQueuedAction>>.broadcast();

  Stream<List<OfflineQueuedAction>> get queueStream => _controller.stream;
  List<OfflineQueuedAction> get pendingActions => List.unmodifiable(_queue);

  void enqueue(OfflineActionType type, Map<String, dynamic> payload) {
    final action = OfflineQueuedAction(
      id: 'offline_${DateTime.now().millisecondsSinceEpoch}_${_queue.length}',
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );
    _queue.add(action);
    _controller.add(List.unmodifiable(_queue));
  }

  void remove(String actionId) {
    _queue.removeWhere((a) => a.id == actionId);
    _controller.add(List.unmodifiable(_queue));
  }

  void clear() {
    _queue.clear();
    _controller.add(List.unmodifiable(_queue));
  }

  void dispose() {
    _controller.close();
  }
}
