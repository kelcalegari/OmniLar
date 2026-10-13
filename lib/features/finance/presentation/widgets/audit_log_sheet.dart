import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/audit_entry.dart';
import '../cubit/finance_cubit.dart';

Future<void> showAuditLogSheet({
  required BuildContext context,
  String? entityId,
  String? title,
}) {
  return showAdaptiveModal(
    context: context,
    maxWidth: 520,
    child: _AuditLogSheetContent(
      entityId: entityId,
      title: title ?? 'Histórico & Auditoria',
    ),
  );
}

/// Histórico de auditoria para ficar dentro de uma página (sem a moldura da janela).
class AuditLogView extends StatelessWidget {
  final String? entityId;

  const AuditLogView({super.key, this.entityId});

  @override
  Widget build(BuildContext context) =>
      _AuditLogSheetContent(entityId: entityId, title: '', embedded: true);
}

class _AuditLogSheetContent extends StatefulWidget {
  final String? entityId;
  final String title;

  /// Dentro de uma página: sem alça, sem cabeçalho e sem botão de fechar.
  final bool embedded;

  const _AuditLogSheetContent({
    this.entityId,
    required this.title,
    this.embedded = false,
  });

  @override
  State<_AuditLogSheetContent> createState() => _AuditLogSheetContentState();
}

class _AuditLogSheetContentState extends State<_AuditLogSheetContent> {
  late Future<List<AuditEntry>> _auditFuture;

  @override
  void initState() {
    super.initState();
    _auditFuture = context.read<FinanceCubit>().getAuditLog(entityId: widget.entityId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: widget.embedded
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
          : const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedded) ...[
          // Alça de arraste
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cabeçalho
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.history_edu_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Rastreabilidade de alterações e exclusões',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ],

          // Lista de Logs
          FutureBuilder<List<AuditEntry>>(
            future: _auditFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.verified_outlined, size: 40, color: Colors.grey),
                      SizedBox(height: 10),
                      Text(
                        'Nenhum evento registrado ainda',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Todas as criações, edições e exclusões desta casa ficam gravadas aqui para total transparência.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(log.createdAt);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: log.actionColor.withValues(alpha: 0.15),
                        child: Icon(log.actionIcon, color: log.actionColor, size: 18),
                      ),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: log.actionColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              log.actionLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: log.actionColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${log.entityName} por ${log.actorName ?? "Membro"}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          if (log.diff != null && log.diff!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _formatDiff(log.diff!),
                              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDiff(Map<String, dynamic> diff) {
    if (diff.containsKey('title')) {
      return 'Título: "${diff['title']}"';
    }
    if (diff.containsKey('new') && diff['new'] is Map) {
      final newMap = diff['new'] as Map;
      if (newMap.containsKey('title')) {
        return 'Título: "${newMap['title']}"';
      }
    }
    return 'Registro auditado no ledger da casa';
  }
}
