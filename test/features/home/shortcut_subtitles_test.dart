import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';
import 'package:omni_lar/features/home/presentation/widgets/shortcut_subtitles.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_item.dart';

ShoppingItem item(String id, {bool bought = false}) =>
    ShoppingItem(id: id, listId: 'l', name: id, isBought: bought);

TaskItem task(String id, {DateTime? due, bool done = false}) => TaskItem(
      id: id,
      title: id,
      dueDate: due,
      isCompleted: done,
      createdByMemberId: 'm',
      createdAt: DateTime(2026),
    );

void main() {
  group('shoppingShortcutSubtitle', () {
    test('conta só o que falta comprar', () {
      final items = [item('a'), item('b'), item('c', bought: true)];
      expect(shoppingShortcutSubtitle(items, loaded: true), '2 itens');
      expect(shoppingShortcutSubtitle([item('a')], loaded: true), '1 item');
      expect(shoppingShortcutSubtitle([item('a', bought: true)], loaded: true), 'Lista em dia');
    });

    test('sem carregar não mostra número', () {
      expect(shoppingShortcutSubtitle(const [], loaded: false), 'Lista da casa');
    });
  });

  group('tasksShortcutSubtitle', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));

    test('atrasadas vêm primeiro', () {
      expect(tasksShortcutSubtitle([task('a', due: yesterday), task('b', due: today)], loaded: true, now: now),
          '1 atrasada');
    });

    test('conta as de hoje', () {
      expect(tasksShortcutSubtitle([task('a', due: today), task('b', due: today), task('c', due: nextWeek)],
          loaded: true, now: now), '2 hoje');
    });

    test('sem nada para hoje mostra pendentes ou tudo em dia', () {
      expect(tasksShortcutSubtitle([task('a', due: nextWeek)], loaded: true, now: now), '1 pendente');
      expect(tasksShortcutSubtitle([task('a', due: today, done: true)], loaded: true, now: now), 'Tudo em dia');
    });
  });
}
