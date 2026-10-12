import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class AuditEntry {
  final String id;
  final String? houseId;
  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;
  final String entityType;
  final String entityId;
  final String action;
  final Map<String, dynamic>? diff;
  final DateTime createdAt;

  const AuditEntry({
    required this.id,
    this.houseId,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    required this.entityType,
    required this.entityId,
    required this.action,
    this.diff,
    required this.createdAt,
  });

  String get actionLabel {
    switch (action) {
      case 'create':
        return 'Criado';
      case 'update':
        return 'Editado';
      case 'soft_delete':
      case 'delete':
        return 'Excluído';
      case 'restore':
        return 'Restaurado';
      default:
        return action;
    }
  }

  IconData get actionIcon {
    switch (action) {
      case 'create':
        return Icons.add_circle_outline_rounded;
      case 'update':
        return Icons.edit_outlined;
      case 'soft_delete':
      case 'delete':
        return Icons.delete_outline_rounded;
      case 'restore':
        return Icons.restore_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  Color get actionColor {
    switch (action) {
      case 'create':
        return AppColors.creditGreen;
      case 'update':
        return AppColors.primary;
      case 'soft_delete':
      case 'delete':
        return AppColors.debtRed;
      case 'restore':
        return AppColors.accent;
      default:
        return Colors.grey;
    }
  }

  String get entityName {
    switch (entityType) {
      case 'house_expenses':
        return 'Despesa';
      case 'contributions':
        return 'Aporte';
      case 'p2p_loans':
        return 'Empréstimo P2P';
      case 'savings_vaults':
        return 'Caixinha';
      case 'settlements':
        return 'Liquidação';
      default:
        return entityType;
    }
  }
}
