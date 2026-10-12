import 'dart:async';
import 'offline_queue.dart';

typedef OfflineActionHandler = Future<void> Function(Map<String, dynamic> payload);

/// Resultado de uma tentativa de envio da fila offline.
class OfflineDrainResult {
  final int synced;
  final int discarded;

  const OfflineDrainResult({this.synced = 0, this.discarded = 0});
}

/// Guarda na fila as gravações feitas sem conexão e as reenvia quando a rede volta.
///
/// Cobre apenas ações que podem ser repetidas sem duplicar dados (o registro já
/// sai do aparelho com o id definitivo). Pagamentos e empréstimos ficam de fora
/// de propósito: precisam da resposta do servidor na hora.
class OfflineSyncService {
  static const int maxRetries = 5;
  static const String _scopeKey = '_scope';

  final OfflineQueueManager queue;

  /// Usuário e casa atuais ("userId|houseId"), ou null quando não há sessão real.
  final String? Function() currentScope;

  final _handlers = <OfflineActionType, OfflineActionHandler>{};
  bool _draining = false;

  OfflineSyncService({required this.queue, required this.currentScope});

  /// Só há fila com sessão real em uma casa (o modo demo grava em memória).
  bool get isActive => currentScope() != null;

  /// Ações da fila que pertencem ao usuário e à casa atuais.
  List<OfflineQueuedAction> get pendingForCurrentScope {
    final scope = currentScope();
    if (scope == null) return const [];
    return queue.pendingActions.where((a) => a.payload[_scopeKey] == scope).toList();
  }

  void registerHandler(OfflineActionType type, OfflineActionHandler handler) {
    _handlers[type] = handler;
  }

  /// Falha de rede (e não uma recusa do servidor): vale tentar de novo depois.
  static bool isNetworkError(Object error) {
    final text = error.toString();
    const markers = [
      'SocketException',
      'Failed host lookup',
      'ClientException',
      'Connection refused',
      'Connection closed',
      'Connection reset',
      'Network is unreachable',
      'TimeoutException',
      'XMLHttpRequest error',
      'Failed to fetch',
    ];
    return markers.any(text.contains);
  }

  static bool _isDuplicate(Object error) {
    final text = error.toString();
    return text.contains('23505') || text.contains('duplicate key');
  }

  /// Executa [action]; sem conexão, guarda [payload] na fila e retorna false.
  Future<bool> runOrQueue(
    OfflineActionType type,
    Map<String, dynamic> Function() payload,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (e) {
      final scope = currentScope();
      if (scope == null || !isNetworkError(e)) rethrow;
      queue.enqueue(type, {...payload(), _scopeKey: scope});
      return false;
    }
  }

  /// Reenvia, em ordem, o que está na fila do usuário e da casa atuais.
  Future<OfflineDrainResult> drain() async {
    if (_draining) return const OfflineDrainResult();
    _draining = true;
    int synced = 0;
    int discarded = 0;

    try {
      for (final action in pendingForCurrentScope) {
        final handler = _handlers[action.type];
        if (handler == null) continue;

        final payload = Map<String, dynamic>.from(action.payload)..remove(_scopeKey);
        try {
          await handler(payload);
          queue.remove(action.id);
          synced++;
        } catch (e) {
          if (_isDuplicate(e)) {
            // Já tinha chegado ao servidor na primeira tentativa
            queue.remove(action.id);
            synced++;
          } else if (isNetworkError(e)) {
            break; // Continua sem conexão: tenta tudo de novo mais tarde
          } else if (action.retryCount + 1 >= maxRetries) {
            queue.remove(action.id);
            discarded++;
          } else {
            queue.registerFailedAttempt(action.id);
          }
        }
      }
    } finally {
      _draining = false;
    }

    return OfflineDrainResult(synced: synced, discarded: discarded);
  }
}
