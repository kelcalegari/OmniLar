import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/network/offline_queue.dart';
import 'package:omni_lar/core/network/offline_sync_service.dart';
import 'package:omni_lar/core/utils/uuid.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/data/offline/calendar_offline_codec.dart';
import 'package:omni_lar/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/data/offline/p2p_loan_offline_codec.dart';
import 'package:omni_lar/features/p2p/data/repositories/p2p_repository_impl.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/services/p2p_calculator.dart';

class _FlakyP2PDataSource extends MockP2PDataSource {
  bool online = false;
  final created = <P2PLoan>[];

  @override
  Future<void> createLoan(P2PLoan loan) async {
    if (!online) throw Exception('SocketException: Failed host lookup');
    created.add(loan);
    await super.createLoan(loan);
  }
}

class _FlakyCalendarDataSource extends MockCalendarDataSource {
  bool online = false;
  final updated = <TaskItem>[];

  @override
  Future<void> updateTask(TaskItem task) async {
    if (!online) throw Exception('SocketException: Failed host lookup');
    updated.add(task);
    await super.updateTask(task);
  }
}

void main() {
  late OfflineQueueManager queue;
  late OfflineSyncService sync;

  setUp(() {
    queue = OfflineQueueManager();
    sync = OfflineSyncService(queue: queue, currentScope: () => 'user-1|house-1');
  });

  tearDown(() => queue.dispose());

  P2PLoan loan() => P2PLoan(
        id: 'loan_local_1',
        title: 'Conserto do carro',
        description: 'Dividido em 3x',
        totalAmount: const Money(30000),
        lenderMemberId: 'ana',
        borrowerMemberId: 'bia',
        installmentsCount: 3,
        createdAt: DateTime(2026, 10, 13, 10),
        firstDueDate: DateTime(2026, 11, 10),
        installments: P2PCalculator.generateInstallments(
          loanId: 'loan_local_1',
          totalAmount: const Money(30000),
          installmentsCount: 3,
          firstDueDate: DateTime(2026, 11, 10),
        ),
        settleInCycle: false,
      );

  group('Empréstimo na fila offline', () {
    test('ida e volta pelo JSON preserva o empréstimo e as parcelas', () {
      final restored = p2pLoanFromJson(p2pLoanToJson(loan()));
      expect(restored.title, 'Conserto do carro');
      expect(restored.totalAmount, const Money(30000));
      expect(restored.lenderMemberId, 'ana');
      expect(restored.borrowerMemberId, 'bia');
      expect(restored.settleInCycle, isFalse);
      expect(restored.installments.length, 3);
      expect(restored.installments.fold<int>(0, (acc, i) => acc + i.amount.cents), 30000);
      expect(restored.installments.first.dueDate, DateTime(2026, 11, 10));
      expect(restored.installments.every((i) => i.loanId == 'loan_local_1'), isTrue);
    });

    test('sem conexão fica na fila e é reenviado uma vez, com o mesmo id', () async {
      final dataSource = _FlakyP2PDataSource();
      final repository = P2PRepositoryImpl(dataSource, sync);
      sync.registerHandler(
        OfflineActionType.createLoan,
        (payload) => dataSource.createLoan(p2pLoanFromJson(payload)),
      );

      await repository.createLoan(loan());
      expect(dataSource.created, isEmpty);
      final queued = sync.pendingForCurrentScope.single;
      expect(queued.type, OfflineActionType.createLoan);
      final queuedId = queued.payload['id'] as String;
      expect(isUuid(queuedId), isTrue);

      dataSource.online = true;
      final result = await sync.drain();
      expect(result.synced, 1);
      expect(sync.pendingForCurrentScope, isEmpty);
      expect(dataSource.created.single.id, queuedId);
      expect(dataSource.created.single.installments.length, 3);
    });

    test('com conexão vai direto, sem usar a fila', () async {
      final dataSource = _FlakyP2PDataSource()..online = true;
      await P2PRepositoryImpl(dataSource, sync).createLoan(loan());
      expect(dataSource.created.length, 1);
      expect(queue.pendingActions, isEmpty);
    });
  });

  group('Edição de tarefa na fila offline', () {
    test('sem conexão fica na fila e é reenviada com os dados editados', () async {
      final dataSource = _FlakyCalendarDataSource();
      final repository = CalendarRepositoryImpl(dataSource, sync);
      sync.registerHandler(
        OfflineActionType.updateTask,
        (payload) => dataSource.updateTask(taskItemFromJson(payload)),
      );

      final id = generateUuidV4();
      final task = TaskItem(
        id: id,
        title: 'Trocar o filtro',
        createdByMemberId: 'ana',
        createdAt: DateTime(2026, 10, 1),
      );
      await dataSource.addTask(task);

      await repository.updateTask(task.copyWith(title: 'Trocar o filtro da cozinha'));
      expect(dataSource.updated, isEmpty);
      expect(sync.pendingForCurrentScope.single.type, OfflineActionType.updateTask);

      dataSource.online = true;
      final result = await sync.drain();
      expect(result.synced, 1);
      expect(dataSource.updated.single.id, id);
      expect(dataSource.updated.single.title, 'Trocar o filtro da cozinha');
    });

    test('tarefa sem id real não entra na fila: o erro aparece', () async {
      final repository = CalendarRepositoryImpl(_FlakyCalendarDataSource(), sync);
      await expectLater(
        repository.updateTask(
          TaskItem(
            id: 'task_local',
            title: 'x',
            createdByMemberId: 'ana',
            createdAt: DateTime(2026, 10, 1),
          ),
        ),
        throwsException,
      );
      expect(queue.pendingActions, isEmpty);
    });
  });
}
