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

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory OfflineQueuedAction.fromJson(Map<String, dynamic> json) => OfflineQueuedAction(
        id: json['id'] as String,
        type: OfflineActionType.values.byName(json['type'] as String),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        retryCount: json['retryCount'] as int? ?? 0,
      );

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

  List<Map<String, dynamic>> dumpToJson() {
    return _queue.map((a) => a.toJson()).toList();
  }

  void restoreFromJson(List<dynamic> rawList) {
    _queue.clear();
    for (final item in rawList) {
      try {
        if (item is Map<String, dynamic>) {
          _queue.add(OfflineQueuedAction.fromJson(item));
        } else if (item is Map) {
          _queue.add(OfflineQueuedAction.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (_) {}
    }
    _controller.add(List.unmodifiable(_queue));
  }

  void dispose() {
    _controller.close();
  }
}
