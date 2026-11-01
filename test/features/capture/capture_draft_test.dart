import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/capture/data/capture_draft_store.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/domain/services/capture_draft_codec.dart';
import 'package:omni_lar/features/capture/presentation/pages/smart_scanner_page.dart';
import 'package:omni_lar/features/finance/domain/services/receipt_attachment_service.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  group('CaptureDraftCodec & CaptureDraftStore', () {
    final baseProposal = CaptureProposal(
      id: 'prop_draft_1',
      documentType: DocumentType.nfce,
      title: 'Supermercado Sol',
      totalAmount: const Money(14250),
      date: DateTime(2026, 10, 22, 12),
      merchantOrBeneficiary: 'SOL LTDA',
      rawCode: 'https://sefaz.sp.gov.br/qrcode?p=123',
      capturedAt: DateTime(2026, 10, 22, 14, 30),
      items: const [
        InvoiceItemDraft(
          id: 'item_1',
          name: 'Arroz 5kg',
          quantity: 1,
          unitPrice: Money(2890),
          totalPrice: Money(2890),
          isPersonal: false,
        ),
        InvoiceItemDraft(
          id: 'item_2',
          name: 'Vinho',
          quantity: 1,
          unitPrice: Money(11360),
          totalPrice: Money(11360),
          isPersonal: true,
          assignedMemberId: 'member_marina',
        ),
      ],
    );

    test('serializa e restaura todos os campos e o anexo da revisão', () {
      final attachment = ReceiptAttachmentFile(
        name: 'cupom.jpg',
        bytes: Uint8List.fromList([10, 20, 30, 40]),
        sizeBytes: 4,
        contentType: 'image/jpeg',
      );
      final draft = CaptureDraft(
        savedAt: DateTime(2026, 10, 22, 15, 0),
        proposal: baseProposal,
        titleText: 'Mercado do mês',
        amountText: '142.50',
        originalAmountCents: 14250,
        originalItems: baseProposal.items,
        selectedCategoryId: 'cat_food',
        selectedPaymentMethodId: 'pm_caixa',
        dueDate: DateTime(2026, 10, 25, 12),
        alreadyPaid: false,
        markRecurring: true,
        recurringVariable: false,
        documentDate: DateTime(2026, 10, 25, 12),
        paidOn: DateTime(2026, 10, 22, 12),
        attachmentFile: attachment,
      );

      final restored = CaptureDraftCodec.fromJson(CaptureDraftCodec.toJson(draft))!;

      expect(restored.displayTitle, 'Mercado do mês');
      expect(restored.proposal.id, 'prop_draft_1');
      expect(restored.proposal.totalAmount.cents, 14250);
      expect(restored.proposal.items.length, 2);
      expect(restored.proposal.items[1].isPersonal, isTrue);
      expect(restored.proposal.items[1].assignedMemberId, 'member_marina');
      expect(restored.selectedCategoryId, 'cat_food');
      expect(restored.selectedPaymentMethodId, 'pm_caixa');
      expect(restored.alreadyPaid, isFalse);
      expect(restored.markRecurring, isTrue);
      expect(restored.recurringVariable, isFalse);
      expect(restored.attachmentFile?.name, 'cupom.jpg');
      expect(restored.attachmentFile?.bytes, [10, 20, 30, 40]);
    });

    test('isola por casa, limpa ao descartar e expira após 30 dias (RN19)', () async {
      final store = CaptureDraftStore(null, () => 'house_a');
      final freshDraft = CaptureDraft(
        savedAt: DateTime.now(),
        proposal: baseProposal,
        titleText: 'Compra fresca',
        amountText: '142.50',
        originalAmountCents: 14250,
        originalItems: baseProposal.items,
        alreadyPaid: true,
        documentDate: baseProposal.date,
        paidOn: baseProposal.date,
      );

      await store.save(freshDraft);
      expect((await store.load('house_a'))?.displayTitle, 'Compra fresca');
      expect(await store.load('house_b'), isNull);

      await store.clear('house_a');
      expect(await store.load('house_a'), isNull);

      final expiredDraft = CaptureDraft(
        savedAt: DateTime.now().subtract(const Duration(days: 31)),
        proposal: baseProposal,
        titleText: 'Compra antiga',
        amountText: '142.50',
        originalAmountCents: 14250,
        originalItems: baseProposal.items,
        alreadyPaid: true,
        documentDate: baseProposal.date,
        paidOn: baseProposal.date,
      );
      await store.save(expiredDraft, 'house_a');
      expect(await store.load('house_a'), isNull);
    });
  });

  group('Na tela (SmartScannerPage)', () {
    setUpAll(() async {
      if (!sl.isRegistered<AuthCubit>()) {
        await initServiceLocator();
      }
      await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
      await sl<FinanceCubit>().loadCycleData();
    });

    setUp(() async {
      await sl<CaptureDraftStore>().clear();
    });

    Widget buildHost() => BlocProvider<FinanceCubit>.value(
          value: sl<FinanceCubit>(),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SmartScannerPage()),
            ),
          ),
        );

    testWidgets('sair durante a revisão guarda o rascunho e permite retomar ou descartar (RN16)', (tester) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // Simula a leitura de um cupom no modo demo
      final simulateBtn = find.text('Simular Leitura de Cupom NFC-e (Mercado)');
      await tester.ensureVisible(simulateBtn);
      await tester.tap(simulateBtn);
      await tester.pumpAndSettle();

      // Edita o título na revisão
      final titleField = find.widgetWithText(TextField, 'Título do gasto');
      await tester.enterText(titleField, 'Mercado editado no rascunho');
      await tester.pump(const Duration(milliseconds: 600));

      // Sai da tela sem confirmar (dispose salva imediatamente)
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final saved = await sl<CaptureDraftStore>().load();
      expect(saved, isNotNull);
      expect(saved!.displayTitle, 'Mercado editado no rascunho');

      // Reabre o scanner: banner de rascunho em andamento aparece
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('capture_draft_banner')), findsOneWidget);
      expect(find.textContaining('Revisão em andamento: Mercado editado no rascunho'), findsOneWidget);

      // Toca em Retomar e recupera o título editado
      await tester.tap(find.byKey(const Key('capture_resume_draft')));
      await tester.pumpAndSettle();

      expect(find.text('Revisar Lançamento'), findsOneWidget);
      expect(find.text('Mercado editado no rascunho'), findsOneWidget);

      // Voltar / Re-escanear limpa o rascunho
      final backBtn = find.text('Voltar / Re-escanear');
      await tester.ensureVisible(backBtn);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      expect(await sl<CaptureDraftStore>().load(), isNull);
    });
  });
}
