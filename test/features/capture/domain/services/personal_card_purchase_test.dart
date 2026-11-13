import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/domain/services/personal_card_purchase.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';

void main() {
  const houseCard = PaymentMethod(
    id: 'pm_inter',
    name: 'Inter Credito',
    type: PaymentMethodType.card,
    closingDay: 5,
    dueDay: 12,
  );
  const kelCard = PaymentMethod(
    id: 'pm_kel',
    name: 'Cartão do Kel',
    type: PaymentMethodType.card,
    closingDay: 5,
    dueDay: 12,
    ownerMemberId: 'kel',
  );
  const pix = PaymentMethod(id: 'pm_pix', name: 'Pix', type: PaymentMethodType.pix);

  InvoiceItemDraft item(String id, {bool personal = true, String? member}) => InvoiceItemDraft(
        id: id,
        name: 'Carvão $id',
        unitPrice: const Money(3685),
        totalPrice: const Money(3685),
        isPersonal: personal,
        assignedMemberId: member,
      );

  String? debtor({
    List<InvoiceItemDraft>? items,
    PaymentMethod? card = houseCard,
    bool paid = true,
    bool others = false,
  }) =>
      PersonalCardPurchase.debtorOf(
        items: items ?? [item('a', member: 'cris'), item('b', member: 'cris')],
        card: card,
        alreadyPaid: paid,
        hasOtherPayments: others,
        launcherId: 'kel',
      );

  test('nota toda pessoal de um morador no cartão da Casa vira empréstimo dele', () {
    expect(debtor(), 'cris');
  });

  test('no cartão de outro morador também, com o dono como credor', () {
    expect(debtor(card: kelCard), 'cris');
  });

  test('o dono do cartão não deve para si mesmo', () {
    expect(debtor(card: kelCard, items: [item('a', member: 'kel')]), isNull);
  });

  test('item pessoal sem responsável é de quem lançou', () {
    expect(debtor(items: [item('a')]), 'kel');
  });

  test('nota com item da Casa segue como despesa', () {
    expect(debtor(items: [item('a', member: 'cris'), item('b', personal: false)]), isNull);
  });

  test('itens de moradores diferentes seguem como despesa', () {
    expect(debtor(items: [item('a', member: 'cris'), item('b', member: 'kel')]), isNull);
  });

  test('fora do cartão, a pagar ou com vários meios segue como despesa', () {
    expect(debtor(card: pix), isNull);
    expect(debtor(paid: false), isNull);
    expect(debtor(others: true), isNull);
    expect(debtor(items: const []), isNull);
  });
}
