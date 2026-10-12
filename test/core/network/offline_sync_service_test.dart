import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/network/offline_queue.dart';
import 'package:omni_lar/core/network/offline_sync_service.dart';
import 'package:omni_lar/core/utils/uuid.dart';
import 'package:omni_lar/features/finance/data/offline/house_expense_offline_codec.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';

void main() {
  group('OfflineSyncService', () {
    late OfflineQueueManager queue;
    late OfflineSyncService sync;
    String? scope;

    setUp(() {
      scope = 'user-1|house-1';
      queue = OfflineQueueManager();
      sync = OfflineSyncService(queue: queue, currentScope: () => scope);
    });

    tearDown(() => queue.dispose());

    Future<void> offline() async => throw Exception('SocketException: Failed host lookup');

    test('Com conexão executa a ação e não usa a fila', () async {
      var ran = false;
      final done = await sync.runOrQueue(
        OfflineActionType.addTask,
        () => {'title': 'Lavar louça'},
        () async => ran = true,
      );

      expect(done, isTrue);
      expect(ran, isTrue);
      expect(queue.pendingActions, isEmpty);
    });

    test('Sem conexão guarda a ação na fila do usuário e da casa atuais', () async {
      final done = await sync.runOrQueue(
        OfflineActionType.addTask,
        () => {'title': 'Lavar louça'},
        offline,
      );

      expect(done, isFalse);
      expect(sync.pendingForCurrentScope.single.payload['title'], 'Lavar louça');
    });

    test('Erro que não é de rede não vai para a fila', () async {
      await expectLater(
        sync.runOrQueue(
          OfflineActionType.addTask,
          () => {'title': 'x'},
          () async => throw Exception('new row violates row-level security policy'),
        ),
        throwsException,
      );
      expect(queue.pendingActions, isEmpty);
    });

    test('Sem sessão real (modo demo) a falha de rede é repassada', () async {
      scope = null;
      await expectLater(
        sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'x'}, offline),
        throwsException,
      );
      expect(queue.pendingActions, isEmpty);
    });

    test('Reenvia em ordem e esvazia a fila quando a conexão volta', () async {
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'A'}, offline);
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'B'}, offline);

      final sent = <String>[];
      sync.registerHandler(OfflineActionType.addTask, (payload) async {
        // O marcador interno de escopo não chega a quem grava
        expect(payload.containsKey('_scope'), isFalse);
        sent.add(payload['title'] as String);
      });

      final result = await sync.drain();

      expect(result.synced, 2);
      expect(sent, ['A', 'B']);
      expect(queue.pendingActions, isEmpty);
    });

    test('Continua sem conexão: para no primeiro erro de rede e mantém a fila', () async {
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'A'}, offline);
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'B'}, offline);
      sync.registerHandler(OfflineActionType.addTask, (_) => offline());

      final result = await sync.drain();

      expect(result.synced, 0);
      expect(queue.pendingActions.length, 2);
      expect(queue.pendingActions.every((a) => a.retryCount == 0), isTrue);
    });

    test('Registro que já tinha chegado ao servidor conta como enviado', () async {
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'A'}, offline);
      sync.registerHandler(
        OfflineActionType.addTask,
        (_) async => throw Exception('duplicate key value violates unique constraint (23505)'),
      );

      final result = await sync.drain();

      expect(result.synced, 1);
      expect(queue.pendingActions, isEmpty);
    });

    test('Ação recusada pelo servidor é descartada após o limite de tentativas', () async {
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'A'}, offline);
      sync.registerHandler(
        OfflineActionType.addTask,
        (_) async => throw Exception('violates check constraint'),
      );

      var discarded = 0;
      for (int i = 0; i < OfflineSyncService.maxRetries; i++) {
        discarded += (await sync.drain()).discarded;
      }

      expect(discarded, 1);
      expect(queue.pendingActions, isEmpty);
    });

    test('Não reenvia ações de outro usuário ou de outra casa', () async {
      await sync.runOrQueue(OfflineActionType.addTask, () => {'title': 'A'}, offline);
      var calls = 0;
      sync.registerHandler(OfflineActionType.addTask, (_) async => calls++);

      scope = 'user-2|house-1';
      final result = await sync.drain();

      expect(result.synced, 0);
      expect(calls, 0);
      expect(queue.pendingActions.length, 1);
    });
  });

  group('Serialização para a fila offline', () {
    test('Despesa composta com rateio sobrevive a ida e volta', () {
      final expense = HouseExpense(
        id: generateUuidV4(),
        title: 'Condomínio',
        amount: const Money(48921),
        date: DateTime(2026, 10, 12, 9, 30),
        dueDate: DateTime(2026, 10, 20),
        categoryId: 'cat',
        paidByMemberId: 'ana',
        paymentMethodId: 'pm',
        splitRule: const SplitRule.percentage({'ana': 60.0, 'bia': 40.0}),
        status: ExpenseStatus.pending,
        paidOutOfPocket: true,
        notes: 'Outubro',
        items: const [
          HouseExpenseItem(
            id: 'i1',
            expenseId: 'e',
            title: 'Fundo de reserva',
            amount: Money(3625),
            responsibleMemberId: 'ana',
            splitRule: SplitRule.singleResponsible('ana'),
          ),
          HouseExpenseItem(
            id: 'i2',
            expenseId: 'e',
            title: 'Água',
            amount: Money(2576),
            splitRule: SplitRule.fixed({'ana': Money(1000), 'bia': Money(1576)}),
          ),
        ],
      );

      expect(houseExpenseFromJson(houseExpenseToJson(expense)), expense);
    });

    test('generateUuidV4 gera identificadores válidos e distintos', () {
      final a = generateUuidV4();
      final b = generateUuidV4();

      expect(isUuid(a), isTrue);
      expect(isUuid(b), isTrue);
      expect(a, isNot(b));
      expect(isUuid('exp_123'), isFalse);
    });
  });
}
