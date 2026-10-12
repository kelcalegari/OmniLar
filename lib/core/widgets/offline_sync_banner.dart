import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../di/service_locator.dart';
import '../network/offline_queue.dart';
import '../network/offline_sync_service.dart';
import '../theme/app_colors.dart';
import '../../features/calendar/presentation/cubit/calendar_cubit.dart';
import '../../features/finance/presentation/cubit/finance_cubit.dart';
import '../../features/shopping/presentation/cubit/shopping_cubit.dart';

/// Envolve o conteúdo do app: mostra uma faixa enquanto houver alterações
/// guardadas sem conexão e tenta reenviá-las ao abrir, ao voltar para o app e
/// periodicamente enquanto a fila não estiver vazia.
class OfflineSyncHost extends StatefulWidget {
  final Widget child;

  const OfflineSyncHost({super.key, required this.child});

  @override
  State<OfflineSyncHost> createState() => _OfflineSyncHostState();
}

class _OfflineSyncHostState extends State<OfflineSyncHost> with WidgetsBindingObserver {
  static const _retryInterval = Duration(seconds: 30);

  OfflineSyncService? _sync;
  StreamSubscription<List<OfflineQueuedAction>>? _queueSubscription;
  Timer? _retryTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (!sl.isRegistered<OfflineSyncService>()) return;

    _sync = sl<OfflineSyncService>();
    WidgetsBinding.instance.addObserver(this);
    _queueSubscription = _sync!.queue.queueStream.listen((_) => _onQueueChanged());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onQueueChanged(sendNow: true));
  }

  @override
  void dispose() {
    if (_sync != null) WidgetsBinding.instance.removeObserver(this);
    _queueSubscription?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _send();
  }

  int get _pendingCount => _sync?.pendingForCurrentScope.length ?? 0;

  void _onQueueChanged({bool sendNow = false}) {
    if (!mounted) return;
    final hasPending = _pendingCount > 0;

    // O timer só existe enquanto há algo para enviar
    if (hasPending && _retryTimer == null) {
      _retryTimer = Timer.periodic(_retryInterval, (_) => _send());
    } else if (!hasPending) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }

    setState(() {});
    if (sendNow && hasPending) _send();
  }

  Future<void> _send() async {
    final sync = _sync;
    if (sync == null || _sending || _pendingCount == 0) return;

    setState(() => _sending = true);
    final result = await sync.drain();
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.synced > 0) {
      // As telas passam a mostrar o que acabou de chegar ao servidor
      context.read<FinanceCubit>().loadCycleData();
      context.read<ShoppingCubit>().loadShoppingData();
      context.read<CalendarCubit>().loadCalendarData();
    }

    if (result.synced > 0 || result.discarded > 0) {
      final parts = [
        if (result.synced > 0)
          result.synced == 1 ? '1 alteração enviada' : '${result.synced} alterações enviadas',
        if (result.discarded > 0)
          result.discarded == 1
              ? '1 alteração foi recusada pelo servidor e descartada'
              : '${result.discarded} alterações foram recusadas pelo servidor e descartadas',
      ];
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${parts.join('; ')}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingCount;
    if (pending == 0) return widget.child;

    return Column(
      children: [
        Material(
          color: AppColors.accent.withValues(alpha: 0.15),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pending == 1
                          ? '1 alteração aguardando conexão'
                          : '$pending alterações aguardando conexão',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? 'Enviando...' : 'Enviar agora'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
