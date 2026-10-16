import 'package:equatable/equatable.dart';

/// Grupo da notificação (seção 4 do plano_notificacoes.md), usado no ícone e
/// nas preferências.
enum NotificationCategory {
  casa,
  despesas,
  fechamento,
  emprestimos,
  caixinhas,
  compras,
  tarefas,
  agenda,
  projetos,
  assistente,
  conta;

  static NotificationCategory fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => NotificationCategory.casa);
}

/// Uma notificação do sino. Quem grava é o banco (gatilhos da migration
/// 0065); o app só lê e marca como lida.
class AppNotification extends Equatable {
  final String id;
  final String type;
  final NotificationCategory category;
  final String title;
  final String body;

  /// Rota do GoRouter que abre o item, por exemplo `/pessoal/emprestimo/{id}`.
  final String? deeplink;
  final bool isEssential;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    this.deeplink,
    this.isEssential = false,
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
        id: id,
        type: type,
        category: category,
        title: title,
        body: body,
        deeplink: deeplink,
        isEssential: isEssential,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
        id: row['id'] as String,
        type: row['type'] as String? ?? '',
        category: NotificationCategory.fromName(row['category'] as String?),
        title: row['title'] as String? ?? '',
        body: row['body'] as String? ?? '',
        deeplink: row['deeplink'] as String?,
        isEssential: row['is_essential'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        readAt: row['read_at'] != null ? DateTime.parse(row['read_at'] as String).toLocal() : null,
      );

  @override
  List<Object?> get props => [id, type, category, title, body, deeplink, isEssential, createdAt, readAt];
}
