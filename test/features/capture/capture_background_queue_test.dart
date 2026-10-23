import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/services/ai_config_service.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/capture/data/capture_background_queue.dart';
import 'package:omni_lar/features/capture/data/capture_draft_store.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/domain/services/capture_draft_codec.dart';
import 'package:omni_lar/features/capture/domain/services/capture_service.dart';
import 'package:omni_lar/features/capture/presentation/pages/smart_scanner_page.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/notifications/presentation/cubit/notifications_cubit.dart';

class _FakeCaptureService extends CaptureService {
  int calls = 0;
  final List<Object> responses;

  _FakeCaptureService(this.responses)
      : super(aiConfigService: sl<AiConfigService>());

  @override
  Future<CaptureProposal> processDocumentFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final idx = calls < responses.length ? calls : responses.length - 1;
    calls++;
    final res = responses[idx];
    if (res is Exception) throw res;
    return res as CaptureProposal;
  }
}

void main() {
  final sampleAiProposal = CaptureProposal(
    id: 'prop_ai_late_1',
    documentType: DocumentType.nfce,
    title: 'PANIFICADORA ESTRELA LTDA',
    totalAmount: const Money(4250),
    date: DateTime(2026, 10, 22, 12),
    merchantOrBeneficiary: 'PANIFICADORA ESTRELA LTDA',
    capturedAt: DateTime(2026, 10, 22, 14, 0),
    items: const [
      InvoiceItemDraft(
        id: 'item_pao',
        name: 'Pao Frances',
        quantity: 1,
        unitPrice: Money(1250),
        totalPrice: Money(1250),
      ),
      InvoiceItemDraft(
        id: 'item_cafe',
        name: 'Cafe Especial',
        quantity: 1,
        unitPrice: Money(3000),
        totalPrice: Money(3000),
      ),
    ],
  );

  group('CaptureBackgroundQueue (RN14, RN17, RN20)', () {
    setUpAll(() async {
      if (!sl.isRegistered<AuthCubit>()) {
        await initServiceLocator();
      }
      await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
      await sl<FinanceCubit>().loadCycleData();
    });

    test(
      'retenta após espera por minuto, salva rascunho e emite notificação sem valor nem loja (RN14, RN20)',
      () async {
        final store = CaptureDraftStore(null, () => 'house_bg_test');
        final notifCubit = sl<NotificationsCubit>();
        final service = _FakeCaptureService([
          const CaptureAiError(
            CaptureAiScope.minute,
            'Muitas leituras seguidas.',
            retryAfterSeconds: 1,
          ),
          sampleAiProposal,
        ]);

        final queue = CaptureBackgroundQueue(
          captureService: service,
          draftStore: store,
          getNotificationsCubit: () => notifCubit,
        );

        queue.enqueue(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'cupom_padaria.jpg',
          mimeType: 'image/jpeg',
          initialDelaySeconds: 1,
          maxAttempts: 3,
        );

        expect(queue.isActive, isTrue);

        // Espera a 1ª tentativa (1s) + 2ª tentativa (1s) concluir
        await Future<void>.delayed(const Duration(milliseconds: 2400));

        expect(service.calls, 2);
        expect(queue.state.value.status, BackgroundCaptureStatus.ready);

        final saved = await store.load('house_bg_test');
        expect(saved, isNotNull);
        expect(saved!.proposal.title, 'PANIFICADORA ESTRELA LTDA');
        expect(saved.proposal.totalAmount.cents, 4250);
        expect(saved.attachmentFile?.name, 'cupom_padaria.jpg');

        // RN20: a notificação não expõe valor (42,50) nem nome do estabelecimento
        final latestNotif = notifCubit.state.items.first;
        expect(latestNotif.deeplink, '/captura/revisar');
        expect(latestNotif.title, 'Uma captura está pronta para revisar');
        expect(latestNotif.title.contains('PANIFICADORA'), isFalse);
        expect(latestNotif.body.contains('PANIFICADORA'), isFalse);
        expect(latestNotif.body.contains('42'), isFalse);
      },
    );

    test(
      'quando a pessoa já está editando em primeiro plano, não sobrescreve o store sozinha (RN17)',
      () async {
        final store = CaptureDraftStore(null, () => 'house_fg_test');
        final service = _FakeCaptureService([sampleAiProposal]);
        final queue = CaptureBackgroundQueue(
          captureService: service,
          draftStore: store,
        )..isEditingInForeground = true;

        queue.enqueue(
          bytes: Uint8List.fromList([7, 8, 9]),
          fileName: 'nota.jpg',
          mimeType: 'image/jpeg',
          initialDelaySeconds: 1,
        );

        await Future<void>.delayed(const Duration(milliseconds: 1300));

        expect(queue.state.value.status, BackgroundCaptureStatus.ready);
        expect(queue.state.value.draft?.proposal.totalAmount.cents, 4250);
        // O store não foi sobrescrito pela resposta tardia
        expect(await store.load('house_fg_test'), isNull);
      },
    );
  });

  group('SmartScannerPage - Mesclagem tardia sem sobrescrever (RN17)', () {
    setUpAll(() async {
      if (!sl.isRegistered<AuthCubit>()) {
        await initServiceLocator();
      }
      await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
      await sl<FinanceCubit>().loadCycleData();
    });

    setUp(() async {
      await sl<CaptureDraftStore>().clear();
      sl<CaptureBackgroundQueue>().cancel();
    });

    testWidgets(
      'resposta tardia da IA oferece preencher só os campos vazios e preserva o título digitado (RN17)',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final manual = CaptureService.manualProposal('cupom_padaria.jpg');

        await tester.pumpWidget(
          BlocProvider<FinanceCubit>.value(
            value: sl<FinanceCubit>(),
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SmartScannerPage(initialProposal: manual),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Usuário digita um título personalizado enquanto o valor ainda está vazio (0)
        final titleField = find.widgetWithText(TextField, 'Título do gasto');
        await tester.enterText(titleField, 'Padaria do Bairro');
        await tester.pump();

        // A resposta tardia da IA chega em segundo plano
        final bgQueue = sl<CaptureBackgroundQueue>();
        bgQueue.state.value = BackgroundCaptureEvent(
          status: BackgroundCaptureStatus.ready,
          draft: CaptureDraft(
            savedAt: DateTime.now(),
            proposal: sampleAiProposal,
            titleText: sampleAiProposal.title,
            amountText: '42.50',
            originalAmountCents: 4250,
            originalItems: sampleAiProposal.items,
            alreadyPaid: true,
            documentDate: sampleAiProposal.date,
            paidOn: sampleAiProposal.date,
          ),
          message: 'Uma captura está pronta para revisar.',
        );
        await tester.pumpAndSettle();

        // A faixa de leitura tardia aparece
        expect(find.byKey(const Key('capture_late_ai_banner')), findsOneWidget);

        // Usuário aceita aplicar nos campos vazios
        await tester.tap(find.byKey(const Key('capture_apply_late_ai')));
        await tester.pumpAndSettle();

        // O título digitado pelo usuário ("Padaria do Bairro") foi preservado!
        expect(find.text('Padaria do Bairro'), findsOneWidget);
        expect(find.text('PANIFICADORA ESTRELA LTDA'), findsOneWidget); // aparece apenas como subtítulo do beneficiário
        final titleTextField = tester.widget<TextField>(titleField);
        expect(titleTextField.controller?.text, 'Padaria do Bairro');

        // E o valor e os itens que estavam vazios foram preenchidos pela IA
        expect(find.text('42.50'), findsOneWidget);
        expect(find.text('Pao Frances'), findsOneWidget);
        expect(find.text('Cafe Especial'), findsOneWidget);
      },
    );
  });
}
