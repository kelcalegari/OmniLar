import '../../../calendar/domain/entities/task_item.dart';
import '../../../shopping/domain/entities/shopping_item.dart';

/// Subtítulo do atalho de Compras: quantos itens faltam comprar na lista.
/// Sem a lista carregada ainda, não arrisca número.
String shoppingShortcutSubtitle(List<ShoppingItem> items, {required bool loaded}) {
  if (!loaded) return 'Lista da casa';
  final pending = items.where((i) => !i.isBought).length;
  if (pending == 0) return 'Lista em dia';
  return pending == 1 ? '1 item' : '$pending itens';
}

/// Subtítulo do atalho de Tarefas: atrasadas primeiro, depois as de hoje,
/// depois as pendentes sem data para hoje.
String tasksShortcutSubtitle(List<TaskItem> tasks, {required bool loaded, DateTime? now}) {
  if (!loaded) return 'Da casa';
  final today = now ?? DateTime.now();
  final pending = tasks.where((t) => !t.isCompleted).toList();
  final overdue = pending.where((t) => t.isOverdue).length;
  if (overdue > 0) return overdue == 1 ? '1 atrasada' : '$overdue atrasadas';
  final dueToday = pending.where((t) {
    final d = t.dueDate;
    return d != null && d.year == today.year && d.month == today.month && d.day == today.day;
  }).length;
  if (dueToday > 0) return '$dueToday hoje';
  if (pending.isEmpty) return 'Tudo em dia';
  return pending.length == 1 ? '1 pendente' : '${pending.length} pendentes';
}
