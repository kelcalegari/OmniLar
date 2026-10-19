import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/house_expense_payload.dart';
import 'package:omni_lar/features/finance/data/offline/house_expense_offline_codec.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/receipt_attachment_service.dart';

void main() {
  group('ReceiptAttachmentService', () {
    test('bucketName is receipts and maxSizeBytes is 10MB', () {
      expect(ReceiptAttachmentService.bucketName, 'receipts');
      expect(ReceiptAttachmentService.maxSizeBytes, 10 * 1024 * 1024);
    });

    test('ReceiptAttachmentFile identifies image and pdf correctly', () {
      final img = ReceiptAttachmentFile(
        name: 'cupom.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
        sizeBytes: 3,
        contentType: 'image/jpeg',
      );
      expect(img.isImage, isTrue);
      expect(img.isPdf, isFalse);

      final pdf = ReceiptAttachmentFile(
        name: 'nota_fiscal.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
        sizeBytes: 3,
        contentType: 'application/pdf',
      );
      expect(pdf.isImage, isFalse);
      expect(pdf.isPdf, isTrue);
    });
  });

  group('HouseExpense attachment fields and getters', () {
    test('hasAttachment is true only when attachmentPath is non-empty', () {
      final expenseWithout = HouseExpense(
        id: 'exp_1',
        title: 'Supermercado',
        amount: const Money(15000),
        date: DateTime(2026, 10, 19),
        categoryId: 'cat_mercado',
        paidByMemberId: 'mem_1',
        paymentMethodId: 'pm_1',
        splitRule: const SplitRule.percentage(null),
      );
      expect(expenseWithout.hasAttachment, isFalse);
      expect(expenseWithout.isAttachmentPurged, isFalse);

      final expenseWith = expenseWithout.copyWith(
        attachmentPath: 'house_123/expenses/exp_1_172938291.jpg',
        attachmentName: 'cupom_mercado.jpg',
        attachmentContentType: 'image/jpeg',
        attachmentSizeBytes: 102400,
      );
      expect(expenseWith.hasAttachment, isTrue);
      expect(expenseWith.attachmentName, 'cupom_mercado.jpg');
      expect(expenseWith.attachmentSizeBytes, 102400);
      expect(expenseWith.isAttachmentPurged, isFalse);

      final purged = expenseWith.copyWith(
        attachmentPurgedAt: DateTime(2026, 11, 30),
      );
      expect(purged.isAttachmentPurged, isTrue);
    });

    test('copyWith clearAttachment clears attachment fields', () {
      final expenseWith = HouseExpense(
        id: 'exp_1',
        title: 'Supermercado',
        amount: const Money(15000),
        date: DateTime(2026, 10, 19),
        categoryId: 'cat_mercado',
        paidByMemberId: 'mem_1',
        paymentMethodId: 'pm_1',
        splitRule: const SplitRule.percentage(null),
        attachmentPath: 'house_123/expenses/exp_1_172938291.jpg',
        attachmentName: 'cupom_mercado.jpg',
        attachmentContentType: 'image/jpeg',
        attachmentSizeBytes: 102400,
      );

      final cleared = expenseWith.copyWith(clearAttachment: true);
      expect(cleared.hasAttachment, isFalse);
      expect(cleared.attachmentPath, isNull);
      expect(cleared.attachmentName, isNull);
      expect(cleared.attachmentContentType, isNull);
      expect(cleared.attachmentSizeBytes, isNull);
    });
  });

  group('Offline codec attachment serialization', () {
    test('houseExpenseToJson and houseExpenseFromJson preserve attachment fields', () {
      final purgedDate = DateTime(2026, 11, 30, 10, 0, 0);
      final expense = HouseExpense(
        id: 'exp_offline',
        title: 'Farmácia',
        amount: const Money(4590),
        date: DateTime(2026, 10, 19),
        categoryId: 'cat_saude',
        paidByMemberId: 'mem_2',
        paymentMethodId: 'pm_card',
        splitRule: const SplitRule.percentage(null),
        attachmentPath: 'house_abc/expenses/exp_offline_123.pdf',
        attachmentName: 'receita_e_cupom.pdf',
        attachmentContentType: 'application/pdf',
        attachmentSizeBytes: 204850,
        attachmentPurgedAt: purgedDate,
      );

      final json = houseExpenseToJson(expense);
      expect(json['attachmentPath'], 'house_abc/expenses/exp_offline_123.pdf');
      expect(json['attachmentName'], 'receita_e_cupom.pdf');
      expect(json['attachmentContentType'], 'application/pdf');
      expect(json['attachmentSizeBytes'], 204850);
      expect(json['attachmentPurgedAt'], purgedDate.toIso8601String());

      final roundtrip = houseExpenseFromJson(json);
      expect(roundtrip.attachmentPath, expense.attachmentPath);
      expect(roundtrip.attachmentName, expense.attachmentName);
      expect(roundtrip.attachmentContentType, expense.attachmentContentType);
      expect(roundtrip.attachmentSizeBytes, expense.attachmentSizeBytes);
      expect(roundtrip.attachmentPurgedAt, purgedDate);
      expect(roundtrip.hasAttachment, isTrue);
      expect(roundtrip.isAttachmentPurged, isTrue);
    });
  });

  group('houseExpensePayload', () {
    test('includes attachment columns in payload when present', () {
      const houseUuid = '550e8400-e29b-41d4-a716-446655440000';
      const expenseUuid = '550e8400-e29b-41d4-a716-446655440001';
      final expense = HouseExpense(
        id: expenseUuid,
        title: 'Restaurante',
        amount: const Money(9800),
        date: DateTime.utc(2026, 10, 19),
        categoryId: 'cat_geral',
        paidByMemberId: 'mem_carlos',
        paymentMethodId: 'pm_pix',
        splitRule: const SplitRule.percentage(null),
        attachmentPath: '$houseUuid/expenses/${expenseUuid}_123.jpg',
        attachmentName: 'comprovante_pix.jpg',
        attachmentContentType: 'image/jpeg',
        attachmentSizeBytes: 54321,
      );

      final payload = houseExpensePayload(
        expense,
        houseId: houseUuid,
        currentUserId: 'mem_carlos',
      );

      expect(payload['attachment_path'], '$houseUuid/expenses/${expenseUuid}_123.jpg');
      expect(payload['attachment_name'], 'comprovante_pix.jpg');
      expect(payload['attachment_content_type'], 'image/jpeg');
      expect(payload['attachment_size_bytes'], 54321);
    });
  });
}
