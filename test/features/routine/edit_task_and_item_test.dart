import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';
import 'package:omni_lar/features/shopping/data/datasources/mock_shopping_datasource.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/data/repositories/p2p_repository_impl.dart';

void main() {
  group('Edição de tarefa', () {
    test('altera título, prazo, prioridade e custo sem mexer na conclusão', () async {
      final dataSource = MockCalendarDataSource();
      final created = DateTime(2026, 10, 1);
      await dataSource.addTask(
        TaskItem(
          id: 't-edit',
          title: 'Trocar lâmpada',
          dueDate: DateTime(2026, 10, 20),
          createdByMemberId: 'member_carlos',
          createdAt: created,
        ),
      );

      await dataSource.updateTask(
        TaskItem(
          id: 't-edit',
          title: 'Trocar lâmpada da sala',
          description: 'Comprar LED',
          dueDate: DateTime(2026, 10, 25),
          priority: TaskPriority.high,
          cost: const Money(3500),
          createdByMemberId: 'member_carlos',
          createdAt: created,
        ),
      );

      final task = (await dataSource.getTasks(includeArchived: true)).firstWhere((t) => t.id == 't-edit');
      expect(task.title, 'Trocar lâmpada da sala');
      expect(task.description, 'Comprar LED');
      expect(task.dueDate, DateTime(2026, 10, 25));
      expect(task.priority, TaskPriority.high);
      expect(task.cost, const Money(3500));
      expect(task.isCompleted, isFalse);
      expect(task.createdAt, created);
    });
  });

  group('Edição de item de compra', () {
    test('altera nome, quantidade e marcação de pessoal', () async {
      final dataSource = MockShoppingDataSource(
        financeRepository: FinanceRepositoryImpl(MockFinanceDataSource()),
        p2pRepository: P2PRepositoryImpl(MockP2PDataSource()),
      );
      final list = (await dataSource.getLists()).first;
      final original = (await dataSource.getItems(list.id)).first;

      await dataSource.updateItem(
        original.copyWith(name: 'Café especial', quantity: 3, isPersonal: !original.isPersonal),
      );

      final items = await dataSource.getItems(list.id);
      final edited = items.firstWhere((i) => i.id == original.id);
      expect(edited.name, 'Café especial');
      expect(edited.quantity, 3);
      expect(edited.isPersonal, !original.isPersonal);
      expect(items.length, (await dataSource.getItems(list.id)).length);
    });
  });
}
