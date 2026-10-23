import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../finance/domain/services/receipt_attachment_service.dart';
import '../../notifications/domain/entities/app_notification.dart';
import '../../notifications/presentation/cubit/notifications_cubit.dart';
import '../domain/entities/capture_proposal.dart';
import '../domain/services/capture_draft_codec.dart';
import '../domain/services/capture_service.dart';
import 'capture_draft_store.dart';

/// Estado de um job em segundo plano de leitura por IA.
enum BackgroundCaptureStatus { idle, waiting, processing, ready, failed }

class BackgroundCaptureEvent {
  final BackgroundCaptureStatus status;
  final CaptureDraft? draft;
  final String? message;
  final int? secondsLeft;

  const BackgroundCaptureEvent({
    required this.status,
    this.draft,
    this.message,
    this.secondsLeft,
  });
}

/// Processa em segundo plano uma captura que encontrou limite por minuto (429)
/// ou instabilidade do Gemini (RN14, RN17, RN20).
///
/// Quando a leitura fica pronta:
/// - grava o rascunho no [CaptureDraftStore] (ou avisa a tela aberta se a
///   pessoa já estiver editando manualmente, para não sobrescrever, RN17);
/// - registra uma notificação sem valor nem estabelecimento no sino (RN20) e
///   emite um evento para a faixa global do app abrir direto a revisão.
class CaptureBackgroundQueue {
  final CaptureService captureService;
  final CaptureDraftStore draftStore;
  final NotificationsCubit? Function()? getNotificationsCubit;

  CaptureBackgroundQueue({
    required this.captureService,
    required this.draftStore,
    this.getNotificationsCubit,
  });

  final ValueNotifier<BackgroundCaptureEvent> state = ValueNotifier(
    const BackgroundCaptureEvent(status: BackgroundCaptureStatus.idle),
  );

  Timer? _countdownTimer;
  int _activeToken = 0;

  /// Verdadeiro enquanto a tela de revisão está aberta para edição manual;
  /// nesse caso a resposta tardia não sobrescreve o store sozinha (RN17).
  bool isEditingInForeground = false;

  bool get isActive =>
      state.value.status == BackgroundCaptureStatus.waiting ||
      state.value.status == BackgroundCaptureStatus.processing;

  /// Enfileira o documento para nova tentativa em segundo plano após
  /// [initialDelaySeconds]. Faz até [maxAttempts] tentativas.
  void enqueue({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    int initialDelaySeconds = 30,
    int maxAttempts = 3,
  }) {
    cancel();
    final token = ++_activeToken;
    _scheduleAttempt(
      token: token,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      delaySeconds: initialDelaySeconds,
      attempt: 1,
      maxAttempts: maxAttempts,
    );
  }

  void _scheduleAttempt({
    required int token,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int delaySeconds,
    required int attempt,
    required int maxAttempts,
  }) {
    if (token != _activeToken) return;
    var remaining = delaySeconds < 1 ? 1 : delaySeconds;
    state.value = BackgroundCaptureEvent(
      status: BackgroundCaptureStatus.waiting,
      secondsLeft: remaining,
      message: 'Aguardando para ler "$fileName" em segundo plano...',
    );

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (token != _activeToken) {
        timer.cancel();
        return;
      }
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        unawaited(
          _executeAttempt(
            token: token,
            bytes: bytes,
            fileName: fileName,
            mimeType: mimeType,
            attempt: attempt,
            maxAttempts: maxAttempts,
          ),
        );
      } else {
        state.value = BackgroundCaptureEvent(
          status: BackgroundCaptureStatus.waiting,
          secondsLeft: remaining,
          message: 'Aguardando para ler "$fileName" em segundo plano...',
        );
      }
    });
  }

  Future<void> _executeAttempt({
    required int token,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int attempt,
    required int maxAttempts,
  }) async {
    if (token != _activeToken) return;
    state.value = BackgroundCaptureEvent(
      status: BackgroundCaptureStatus.processing,
      message: 'Lendo "$fileName" em segundo plano...',
    );

    final attachment = ReceiptAttachmentFile(
      name: fileName,
      bytes: bytes,
      sizeBytes: bytes.length,
      contentType: mimeType,
    );

    try {
      final proposal = await captureService.processDocumentFile(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      if (token != _activeToken) return;
      await _onProposalReady(proposal, attachment);
    } on CaptureAiError catch (e) {
      if (token != _activeToken) return;
      if (e.canRetry && attempt < maxAttempts) {
        _scheduleAttempt(
          token: token,
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          delaySeconds: e.retryAfterSeconds ?? 30,
          attempt: attempt + 1,
          maxAttempts: maxAttempts,
        );
        return;
      }
      await _onFinalFailure(fileName, attachment, e.message);
    } catch (_) {
      if (token != _activeToken) return;
      await _onFinalFailure(
        fileName,
        attachment,
        'Não foi possível ler esta captura automaticamente.',
      );
    }
  }

  Future<void> _onProposalReady(
    CaptureProposal proposal,
    ReceiptAttachmentFile attachment,
  ) async {
    final isBoleto = proposal.documentType == DocumentType.boleto;
    final itemsSum = proposal.items.fold<int>(0, (sum, i) => sum + i.totalPrice.cents);
    final draft = CaptureDraft(
      savedAt: DateTime.now(),
      proposal: proposal,
      titleText: proposal.title,
      amountText: proposal.totalAmount.cents > 0
          ? (proposal.totalAmount.cents / 100).toStringAsFixed(2)
          : '',
      originalAmountCents: itemsSum > 0 ? itemsSum : proposal.totalAmount.cents,
      originalItems: proposal.items,
      dueDate: isBoleto ? proposal.dueDate : null,
      alreadyPaid: !isBoleto,
      documentDate: proposal.date,
      paidOn: DateTime.now(),
      attachmentFile: attachment,
    );

    // RN17: se a pessoa estiver editando na tela agora, não sobrescreve o store;
    // a tela aberta recebe o evento `ready` e oferece aplicar só nos campos vazios.
    if (!isEditingInForeground) {
      await draftStore.save(draft);
    }

    // RN20: notificação genérica sem valor nem nome do estabelecimento
    _pushSafeNotification(
      id: 'notif_capture_ready_${DateTime.now().millisecondsSinceEpoch}',
      type: 'capture_ready',
      title: 'Uma captura está pronta para revisar',
      body: 'Toque para conferir os dados antes de confirmar o lançamento.',
    );

    state.value = BackgroundCaptureEvent(
      status: BackgroundCaptureStatus.ready,
      draft: draft,
      message: 'Uma captura está pronta para revisar.',
    );
  }

  Future<void> _onFinalFailure(
    String fileName,
    ReceiptAttachmentFile attachment,
    String errorMessage,
  ) async {
    final manual = CaptureService.manualProposal(fileName);
    final draft = CaptureDraft(
      savedAt: DateTime.now(),
      proposal: manual,
      titleText: manual.title,
      amountText: '',
      originalAmountCents: 0,
      originalItems: const [],
      alreadyPaid: manual.documentType != DocumentType.boleto,
      documentDate: manual.date,
      paidOn: DateTime.now(),
      attachmentFile: attachment,
    );

    if (!isEditingInForeground) {
      await draftStore.save(draft);
    }

    _pushSafeNotification(
      id: 'notif_capture_failed_${DateTime.now().millisecondsSinceEpoch}',
      type: 'capture_failed',
      title: 'Captura salva para preenchimento manual',
      body: 'Não foi possível ler automaticamente. Sua foto está guardada para revisar.',
    );

    state.value = BackgroundCaptureEvent(
      status: BackgroundCaptureStatus.failed,
      draft: draft,
      message: errorMessage,
    );
  }

  void _pushSafeNotification({
    required String id,
    required String type,
    required String title,
    required String body,
  }) {
    final cubit = getNotificationsCubit?.call();
    cubit?.pushLocalNotification(
      AppNotification(
        id: id,
        type: type,
        category: NotificationCategory.despesas,
        title: title,
        body: body,
        deeplink: '/captura/revisar',
        isEssential: true,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Limpa o aviso de conclusão depois que o usuário abriu ou dispensou.
  void acknowledge() {
    if (!isActive) {
      state.value = const BackgroundCaptureEvent(status: BackgroundCaptureStatus.idle);
    }
  }

  void cancel() {
    _activeToken++;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    state.value = const BackgroundCaptureEvent(status: BackgroundCaptureStatus.idle);
  }
}
