import 'dart:typed_data';
import '../../../finance/domain/entities/house_expense.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import '../../../finance/domain/entities/savings_vault.dart';
import '../../domain/services/project_report_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/share_helper.dart';
import '../../../../core/utils/uuid.dart';
import '../../../../core/widgets/omni_logo.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/presentation/pages/add_expense_page.dart';
import '../../../settlement/domain/entities/super_pix_transfer.dart';
import '../../domain/entities/project_participant.dart';
import '../../domain/entities/project_settlement_summary.dart';
import '../../domain/entities/shared_project.dart';
import '../cubit/projects_cubit.dart';
import '../cubit/projects_state.dart';

class ProjectsHubPage extends StatefulWidget {
  const ProjectsHubPage({super.key});

  @override
  State<ProjectsHubPage> createState() => _ProjectsHubPageState();
}

class _ProjectsHubPageState extends State<ProjectsHubPage> {
  // 0: Em Andamento, 1: Concluídos / Arquivados, 2: Todos
  int _selectedFilter = 0;

  @override
  void initState() {
    super.initState();
    context.read<ProjectsCubit>().loadProjects();
  }

  List<SharedProject> _getFilteredProjects(List<SharedProject> all) {
    if (_selectedFilter == 0) {
      return all.where((p) => p.status == ProjectStatus.active || p.status == ProjectStatus.planning).toList();
    } else if (_selectedFilter == 1) {
      return all.where((p) => p.status == ProjectStatus.settled || p.status == ProjectStatus.archived).toList();
    }
    return all;
  }

  Color _getStatusColor(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.active:
        return AppColors.accent;
      case ProjectStatus.planning:
        return Colors.blue;
      case ProjectStatus.settled:
        return Colors.purple;
      case ProjectStatus.archived:
        return Colors.grey;
    }
  }

  String _getStatusLabel(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.active:
        return 'EM ANDAMENTO';
      case ProjectStatus.planning:
        return 'PLANEJAMENTO';
      case ProjectStatus.settled:
        return 'CONCLUÍDO';
      case ProjectStatus.archived:
        return 'ARQUIVADO';
    }
  }

  String _formatPeriod(DateTime? start, DateTime? end) {
    if (start != null && end != null) {
      return '${DateFormat("dd/MM").format(start)} a ${DateFormat("dd/MM/yy").format(end)}';
    } else if (start != null) {
      return 'Início ${DateFormat("dd/MM/yy").format(start)}';
    } else if (end != null) {
      return 'Até ${DateFormat("dd/MM/yy").format(end)}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const OmniLogo.icon(height: 26, width: 26),
            const SizedBox(width: 8),
            Text('Projetos & Viagens', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Novo Projeto / Viagem',
            onPressed: () => _showProjectFormDialog(context),
          ),
        ],
      ),
      body: BlocBuilder<ProjectsCubit, ProjectsState>(
        builder: (context, state) {
          if (state is ProjectsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProjectsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(state.message, style: const TextStyle(color: AppColors.debtRed)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.read<ProjectsCubit>().loadProjects(),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          if (state is ProjectsLoaded) {
            final projects = state.projects;
            if (projects.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.luggage_rounded, size: 64, color: AppColors.textSecondaryLight),
                    const SizedBox(height: 16),
                    Text('Nenhum projeto ou viagem cadastrado', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Crie um projeto para ratear custos de viagens, obras ou compras.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryLight)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Criar Projeto'),
                      onPressed: () => _showProjectFormDialog(context),
                    ),
                  ],
                ),
              );
            }

            final filteredProjects = _getFilteredProjects(projects);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Banner Explicativo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.15),
                        AppColors.accent.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.hub_rounded, color: AppColors.primary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rateios Delimitados',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cadastre viagens, compra de imóvel, reformas e investimentos com rateio e liquidação via Super Pix.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Filtro por Status
                Center(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Em Andamento')),
                      ButtonSegment(value: 1, label: Text('Concluídos')),
                      ButtonSegment(value: 2, label: Text('Todos')),
                    ],
                    selected: {_selectedFilter},
                    onSelectionChanged: (val) {
                      setState(() {
                        _selectedFilter = val.first;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),

                if (filteredProjects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Nenhum projeto neste filtro.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryLight),
                      ),
                    ),
                  )
                else
                  ...filteredProjects.map((proj) => _buildProjectCard(context, proj, state)),

                if (state.selectedProject != null && state.settlementSummary != null) ...[
                  const SizedBox(height: 24),
                  _buildSettlementSheet(context, state),
                ],
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, SharedProject project, ProjectsLoaded state) {
    final theme = Theme.of(context);
    final iconData = _getProjectIcon(project.type);
    final typeName = _getProjectTypeName(project.type);
    final totalSpent = state.projectTotals[project.id] ?? const Money.zero();
    final isOver = project.isOverBudget(totalSpent);
    final progress = project.budgetProgressPercent(totalSpent);
    final isSelected = state.selectedProject?.id == project.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? AppColors.primary : theme.dividerColor,
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.read<ProjectsCubit>().selectProject(project);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getStatusColor(project.status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconData, color: _getStatusColor(project.status), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (project.startDate != null || project.endDate != null)
                              ? '$typeName • ${_formatPeriod(project.startDate, project.endDate)}'
                              : typeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryLight),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(_getStatusLabel(project.status)),
                    backgroundColor: _getStatusColor(project.status).withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(project.status),
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    tooltip: 'Opções do projeto',
                    padding: EdgeInsets.zero,
                    onSelected: (action) async {
                      final cubit = context.read<ProjectsCubit>();
                      if (action == 'edit') {
                        _showProjectFormDialog(context, projectToEdit: project);
                      } else if (action == 'settle') {
                        await cubit.changeProjectStatus(project, ProjectStatus.settled);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Projeto marcado como Concluído!')),
                          );
                        }
                      } else if (action == 'reopen') {
                        await cubit.changeProjectStatus(project, ProjectStatus.active);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Projeto reaberto com sucesso!')),
                          );
                        }
                      } else if (action == 'archive') {
                        await cubit.changeProjectStatus(project, ProjectStatus.archived);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Projeto arquivado!')),
                          );
                        }
                      } else if (action == 'delete') {
                        _confirmDeleteProject(context, project);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Editar Projeto'),
                          ],
                        ),
                      ),
                      if (project.status == ProjectStatus.active || project.status == ProjectStatus.planning)
                        const PopupMenuItem(
                          value: 'settle',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline_rounded, color: AppColors.accent, size: 18),
                              SizedBox(width: 8),
                              Text('Marcar como Concluído'),
                            ],
                          ),
                        ),
                      if (project.status == ProjectStatus.settled || project.status == ProjectStatus.archived)
                        const PopupMenuItem(
                          value: 'reopen',
                          child: Row(
                            children: [
                              Icon(Icons.replay_rounded, color: AppColors.primary, size: 18),
                              SizedBox(width: 8),
                              Text('Reabrir Projeto'),
                            ],
                          ),
                        ),
                      if (project.status != ProjectStatus.archived)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              Icon(Icons.archive_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Arquivar'),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: AppColors.debtRed, size: 18),
                            SizedBox(width: 8),
                            Text('Excluir Projeto', style: TextStyle(color: AppColors.debtRed)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (project.description != null && project.description!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  project.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryLight),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Orçamento: ${project.targetBudget != null ? project.targetBudget!.formatted : 'Livre'}',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded, size: 16, color: AppColors.textSecondaryLight),
                      const SizedBox(width: 4),
                      Text('${project.participants.length} participantes', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              if (project.targetBudget != null && project.targetBudget!.cents > 0) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gasto: ${totalSpent.formatted} de ${project.targetBudget!.formatted}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isOver ? AppColors.debtRed : null,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isOver ? AppColors.debtRed : AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isOver ? AppColors.debtRed : AppColors.primary,
                    ),
                  ),
                ),
                if (isOver) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⚠️ Orçamento excedido em ${Money(totalSpent.cents - project.targetBudget!.cents).formatted}!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.debtRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ] else if (totalSpent.cents > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Total realizado até o momento: ${totalSpent.formatted}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryLight),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteProject(BuildContext context, SharedProject project) {
    final cubit = context.read<ProjectsCubit>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir Projeto'),
        content: Text('Tem certeza que deseja excluir "${project.title}"? Esta ação removerá o projeto da lista da casa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await cubit.deleteProject(project);
              if (context.mounted && cubit.state is! ProjectsError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Projeto excluído.')),
                );
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementSheet(BuildContext context, ProjectsLoaded state) {
    final theme = Theme.of(context);
    final summary = state.settlementSummary!;
    final proj = state.selectedProject!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Acerto de Contas: ${proj.title}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Chip(
                label: Text('Total: ${summary.totalExpenses.formatted}'),
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              ),
            ],
          ),
          if (proj.vaultId != null) ...[
            Builder(builder: (_) {
              final linkedVault = state.vaults.where((v) => v.id == proj.vaultId).firstOrNull;
              if (linkedVault == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.creditGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.savings_rounded, color: AppColors.creditGreen, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Caixinha Vinculada: ${linkedVault.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Fundo Acumulado: ${linkedVault.currentBalance.formatted}', style: const TextStyle(fontSize: 12, color: AppColors.creditGreen, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/casa/cofres'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('Ver Caixinha', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              );
            }),
          ],
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _showParticipantsDialog(context, proj),
                icon: const Icon(Icons.group_outlined, size: 18),
                label: Text('Participantes (${proj.participants.length})'),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddExpensePage(initialProjectId: proj.id),
                    ),
                  );
                  if (context.mounted) {
                    context.read<ProjectsCubit>().selectProject(proj);
                  }
                },
                icon: const Icon(Icons.post_add_rounded, size: 18),
                label: const Text('Nova Despesa'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Balanço por Participante:',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...summary.participantBalances.map((bal) {
            final isCreditor = bal.isCreditor;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bal.participantName),
                  Text(
                    '${isCreditor ? '+' : ''}${bal.netBalance.formatted}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCreditor ? AppColors.accent : (bal.isDebtor ? Colors.redAccent : AppColors.textSecondaryLight),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transferências Mínimas (Super Pix):',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (summary.transfers.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _copyProjectSettlement(context, proj, summary),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Compartilhar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.file_download_outlined, size: 20, color: AppColors.primary),
                    tooltip: 'Exportar Relatório / Planilha',
                    onSelected: (val) {
                      final vault = state.vaults.where((v) => v.id == proj.vaultId).firstOrNull;
                      if (val == 'pdf') {
                        _exportProjectPdf(context, proj, summary, state.selectedProjectExpenses ?? [], vault);
                      } else if (val == 'csv') {
                        _exportProjectCsv(context, proj, summary, state.selectedProjectExpenses ?? [], vault);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Relatório em PDF (.pdf)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'csv',
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined, size: 18, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Planilha (.csv)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (summary.transfers.isEmpty)
            Text('Nenhuma transferência pendente. Todas as contas estão zeradas!', style: theme.textTheme.bodyMedium)
          else
            ...summary.transfers.map((t) {
              return Card(
                color: theme.canvasColor,
                child: ListTile(
                  leading: const Icon(Icons.send_rounded, color: AppColors.primary),
                  title: Text('${t.fromMemberName} ➔ ${t.toMemberName}'),
                  subtitle: Text(t.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.amount.formatted,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                        tooltip: 'Enviar mensagem no WhatsApp',
                        onPressed: () => _copySingleProjectTransfer(context, proj, t),
                      ),
                    ],
                  ),
                ),
              );
            }),

          // Despesas Lançadas no Projeto
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Despesas do Projeto:',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${state.selectedProjectExpenses?.length ?? 0} despesa(s)',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryLight),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.selectedProjectExpenses == null || state.selectedProjectExpenses!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhuma despesa lançada ainda. Use o botão "Nova Despesa" acima para adicionar a primeira!',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryLight,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...state.selectedProjectExpenses!.map((exp) {
              return Card(
                color: theme.canvasColor,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(exp.title, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      ),
                      if (exp.notes != null && exp.notes!.contains('[Câmbio:')) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            exp.notes!.substring(
                              exp.notes!.indexOf('[Câmbio:') + 9,
                              exp.notes!.indexOf('@', exp.notes!.indexOf('[Câmbio:')),
                            ).trim(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accent),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${DateFormat("dd/MM/yyyy").format(exp.date)} • Pago por ${_resolveMemberName(summary, proj, exp.paidByMemberId)}',
                  ),
                  trailing: Text(
                    exp.amount.formatted,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _resolveMemberName(ProjectSettlementSummary summary, SharedProject project, String memberId) {
    for (final bal in summary.participantBalances) {
      if (bal.participantId == memberId) return bal.participantName;
    }
    for (final p in project.participants) {
      if (p.id == memberId || p.userId == memberId) return p.displayName;
    }
    return memberId;
  }

  void _copyProjectSettlement(BuildContext context, SharedProject project, ProjectSettlementSummary summary) {
    final buffer = StringBuffer();
    buffer.writeln('✈️ Projeto Coletivo: ${project.title} • Omni Lar');
    buffer.writeln('💰 Total Gasto: ${summary.totalExpenses.formatted}');
    buffer.writeln('');
    buffer.writeln('✨ Super Pix do Projeto:');
    if (summary.transfers.isEmpty) {
      buffer.writeln('• Todas as contas estão 100% quitadas entre os participantes.');
    } else {
      for (final t in summary.transfers) {
        final toParticipant = project.participants.cast<ProjectParticipant?>().firstWhere(
          (p) => p?.id == t.toMemberId || p?.userId == t.toMemberId || p?.externalName == t.toMemberName,
          orElse: () => null,
        );
        final pix = t.pixKey ?? toParticipant?.pixKey;
        final pixSuffix = (pix != null && pix.isNotEmpty) ? ' (Pix: $pix)' : '';
        buffer.writeln('• ${t.fromMemberName} transfere ${t.amount.formatted} para ${t.toMemberName} (${t.description})$pixSuffix');
      }
    }
    shareText(
      context,
      buffer.toString(),
      onCopied: const SnackBar(
        content: Text('Resumo do rateio copiado!'),
      ),
    );
  }

  void _copySingleProjectTransfer(BuildContext context, SharedProject project, SuperPixTransfer t) {
    final fromParticipant = project.participants.cast<ProjectParticipant?>().firstWhere(
      (p) => p?.id == t.fromMemberId || p?.userId == t.fromMemberId || p?.externalName == t.fromMemberName,
      orElse: () => null,
    );
    final toParticipant = project.participants.cast<ProjectParticipant?>().firstWhere(
      (p) => p?.id == t.toMemberId || p?.userId == t.toMemberId || p?.externalName == t.toMemberName,
      orElse: () => null,
    );

    final pixKey = t.pixKey ?? toParticipant?.pixKey;
    final pixInfo = (pixKey != null && pixKey.trim().isNotEmpty) ? '\n🔑 Chave Pix de ${t.toMemberName}: $pixKey' : '';

    final msg =
        'Oi ${t.fromMemberName}! No fechamento do projeto "${project.title}" no Omni Lar, ficou acertado você transferir ${t.amount.formatted} para ${t.toMemberName} para quitar a sua parte (${t.description}).$pixInfo';

    shareText(
      context,
      msg,
      phone: fromParticipant?.phone,
      onCopied: const SnackBar(
        content: Text('Mensagem de cobrança copiada!'),
      ),
    );
  }

  IconData _getProjectIcon(ProjectType type) {
    switch (type) {
      case ProjectType.trip:
        return Icons.flight_takeoff_rounded;
      case ProjectType.assetPurchase:
        return Icons.home_work_rounded;
      case ProjectType.investment:
        return Icons.savings_rounded;
      case ProjectType.event:
        return Icons.celebration_rounded;
      case ProjectType.generic:
        return Icons.folder_shared_rounded;
    }
  }

  String _getProjectTypeName(ProjectType type) {
    switch (type) {
      case ProjectType.trip:
        return 'Viagem / Férias';
      case ProjectType.assetPurchase:
        return 'Compra de Imóvel / Reforma';
      case ProjectType.investment:
        return 'Investimento / Reserva';
      case ProjectType.event:
        return 'Evento / Festa';
      case ProjectType.generic:
        return 'Projeto Coletivo';
    }
  }

  Future<void> _showParticipantsDialog(BuildContext context, SharedProject project) async {
    final cubit = context.read<ProjectsCubit>();
    final messenger = ScaffoldMessenger.of(context);

    var houseMembers = <HouseMember>[];
    try {
      houseMembers = await cubit.financeRepository.getMembers();
    } catch (_) {}
    if (!context.mounted) return;

    final rows = <_ParticipantRow>[
      for (final m in houseMembers)
        _ParticipantRow(
          id: project.participants.where((p) => p.userId == m.id).firstOrNull?.id,
          userId: m.id,
          name: m.name.split(' ').first,
          included: project.participants.any((p) => p.userId == m.id),
          percent: project.participants
              .where((p) => p.userId == m.id)
              .map((p) => p.defaultSplitPercent?.round())
              .firstOrNull,
          pixKey: project.participants.where((p) => p.userId == m.id).firstOrNull?.pixKey,
          phone: project.participants.where((p) => p.userId == m.id).firstOrNull?.phone,
        ),
      for (final p in project.participants)
        if (!houseMembers.any((m) => m.id == p.userId))
          _ParticipantRow(
            id: p.id,
            userId: p.userId,
            name: p.displayName,
            included: true,
            percent: p.defaultSplitPercent?.round(),
            pixKey: p.pixKey,
            phone: p.phone,
          ),
    ];

    void splitEqually() {
      final active = rows.where((r) => r.included).toList();
      if (active.isEmpty) return;
      final base = 100 ~/ active.length;
      final remainder = 100 % active.length;
      for (int i = 0; i < active.length; i++) {
        active[i].percent = base + (i < remainder ? 1 : 0);
      }
    }

    if (rows.where((r) => r.included).any((r) => r.percent == null)) splitEqually();

    final guestNameController = TextEditingController();
    final guestPhoneController = TextEditingController();
    final guestPixController = TextEditingController();
    bool showAddGuestForm = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final active = rows.where((r) => r.included).toList();
          final total = active.fold<int>(0, (acc, r) => acc + (r.percent ?? 0));
          final canSave = active.isNotEmpty && total == 100 && active.every((r) => (r.percent ?? 0) > 0);

          return AlertDialog(
            title: Text('Participantes de ${project.title}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'As despesas do projeto são divididas entre os participantes, pelo percentual de cada um.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    for (final row in rows)
                      Row(
                        children: [
                          Checkbox(
                            value: row.included,
                            onChanged: (val) => setDialogState(() {
                              row.included = val ?? false;
                              splitEqually();
                            }),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        row.userId == null ? '${row.name} (convidado)' : row.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: row.userId == null ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (row.userId == null) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16),
                                        tooltip: 'Editar Contato e Pix',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () async {
                                          final phoneCtrl = TextEditingController(text: row.phone ?? '');
                                          final pixCtrl = TextEditingController(text: row.pixKey ?? '');
                                          final edited = await showDialog<bool>(
                                            context: dialogCtx,
                                            builder: (editCtx) => AlertDialog(
                                              title: Text('Contato: ${row.name}'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextField(
                                                    controller: phoneCtrl,
                                                    keyboardType: TextInputType.phone,
                                                    decoration: const InputDecoration(
                                                      labelText: 'WhatsApp / Telefone',
                                                      hintText: 'Ex: 11988887777',
                                                      prefixIcon: Icon(Icons.phone_rounded, size: 18),
                                                      isDense: true,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  TextField(
                                                    controller: pixCtrl,
                                                    decoration: const InputDecoration(
                                                      labelText: 'Chave Pix (para receber)',
                                                      hintText: 'CPF, e-mail ou celular',
                                                      prefixIcon: Icon(Icons.pix_rounded, size: 18),
                                                      isDense: true,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(editCtx, false), child: const Text('Cancelar')),
                                                FilledButton(onPressed: () => Navigator.pop(editCtx, true), child: const Text('Salvar')),
                                              ],
                                            ),
                                          );
                                          if (edited == true) {
                                            setDialogState(() {
                                              row.phone = phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null;
                                              row.pixKey = pixCtrl.text.trim().isNotEmpty ? pixCtrl.text.trim() : null;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                                if (row.userId == null && (row.phone != null || row.pixKey != null))
                                  Text(
                                    [
                                      if (row.phone != null && row.phone!.isNotEmpty) '📱 ${row.phone}',
                                      if (row.pixKey != null && row.pixKey!.isNotEmpty) '🔑 Pix: ${row.pixKey}',
                                    ].join(' • '),
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (row.included) ...[
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              tooltip: 'Diminuir',
                              onPressed: () => setDialogState(() {
                                row.percent = ((row.percent ?? 0) - 1).clamp(0, 100);
                              }),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${row.percent ?? 0}%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 18),
                              tooltip: 'Aumentar',
                              onPressed: () => setDialogState(() {
                                row.percent = ((row.percent ?? 0) + 1).clamp(0, 100);
                              }),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: guestNameController,
                            decoration: const InputDecoration(
                              labelText: 'Convidado de fora da casa',
                              hintText: 'Ex: Tio Carlos',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            final name = guestNameController.text.trim();
                            if (name.isEmpty) return;
                            setDialogState(() {
                              rows.add(
                                _ParticipantRow(
                                  id: generateUuidV4(),
                                  userId: null,
                                  name: name,
                                  included: true,
                                  phone: guestPhoneController.text.trim().isNotEmpty ? guestPhoneController.text.trim() : null,
                                  pixKey: guestPixController.text.trim().isNotEmpty ? guestPixController.text.trim() : null,
                                ),
                              );
                              guestNameController.clear();
                              guestPhoneController.clear();
                              guestPixController.clear();
                              showAddGuestForm = false;
                              splitEqually();
                            });
                          },
                          child: const Text('Adicionar'),
                        ),
                      ],
                    ),
                    if (!showAddGuestForm)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setDialogState(() => showAddGuestForm = true),
                          icon: const Icon(Icons.add_link_rounded, size: 14),
                          label: const Text('WhatsApp / Pix do convidado (opcional)', style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: guestPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp (opcional)',
                                hintText: '11988887777',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: guestPixController,
                              decoration: const InputDecoration(
                                labelText: 'Chave Pix (opcional)',
                                hintText: 'CPF, e-mail...',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          total == 100 ? 'Total: 100%' : 'Total: $total% (precisa somar 100%)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: total == 100 ? AppColors.creditGreen : AppColors.debtRed,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setDialogState(splitEqually),
                          child: const Text('Dividir igualmente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: !canSave
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final participants = [
                          for (int i = 0; i < active.length; i++)
                            ProjectParticipant(
                              id: (active[i].id != null && isUuid(active[i].id)) ? active[i].id! : generateUuidV4(),
                              projectId: project.id,
                              userId: active[i].userId,
                              externalName: active[i].name,
                              pixKey: active[i].pixKey,
                              phone: active[i].phone,
                              defaultSplitPercent: active[i].percent!.toDouble(),
                              createdAt: now,
                            ),
                        ];
                        Navigator.pop(dialogCtx);
                        final ok = await cubit.setParticipants(project, participants);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Participantes atualizados. O acerto do projeto foi refeito.'
                                  : 'Não foi possível atualizar os participantes.',
                            ),
                            backgroundColor: ok ? null : AppColors.debtRed,
                          ),
                        );
                      },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showProjectFormDialog(BuildContext context, {SharedProject? projectToEdit}) {
    final isEditing = projectToEdit != null;
    final titleCtrl = TextEditingController(text: projectToEdit?.title ?? '');
    final descCtrl = TextEditingController(text: projectToEdit?.description ?? '');
    final budgetCtrl = TextEditingController(
      text: (projectToEdit?.targetBudget != null && projectToEdit!.targetBudget!.cents > 0)
          ? (projectToEdit.targetBudget!.cents / 100).toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    ProjectType selectedType = projectToEdit?.type ?? ProjectType.trip;
    ProjectStatus selectedStatus = projectToEdit?.status ?? ProjectStatus.active;
    DateTime? startDate = projectToEdit?.startDate;
    DateTime? endDate = projectToEdit?.endDate;
    String? selectedVaultId = projectToEdit?.vaultId;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar Projeto' : 'Novo Projeto / Viagem'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Projeto *',
                          hintText: 'Ex: Férias em Natal, Reforma Lavabo',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Descrição (opcional)',
                          hintText: 'Detalhes ou notas sobre o projeto...',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ProjectType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: 'Tipo de Projeto', isDense: true),
                        items: ProjectType.values.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(_getProjectTypeName(t)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedType = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: budgetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: r'Teto de Orçamento (R$, opcional)',
                          hintText: 'Ex: 4500,00',
                          prefixText: r'R$ ',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Período Previsto (opcional)', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today_rounded, size: 16),
                              label: Text(
                                startDate == null ? 'Data Início' : DateFormat('dd/MM/yy').format(startDate!),
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: startDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  setDialogState(() => startDate = picked);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.event_available_rounded, size: 16),
                              label: Text(
                                endDate == null ? 'Data Fim' : DateFormat('dd/MM/yy').format(endDate!),
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: endDate ?? (startDate ?? DateTime.now()),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  setDialogState(() => endDate = picked);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      if (startDate != null || endDate != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setDialogState(() {
                              startDate = null;
                              endDate = null;
                            }),
                            child: const Text('Limpar datas', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      Builder(builder: (ctx) {
                        final availableVaults = (context.read<ProjectsCubit>().state is ProjectsLoaded)
                            ? (context.read<ProjectsCubit>().state as ProjectsLoaded).vaults
                            : <SavingsVault>[];
                        if (availableVaults.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: DropdownButtonFormField<String?>(
                            initialValue: selectedVaultId,
                            decoration: const InputDecoration(
                              labelText: 'Vincular a uma Caixinha / Reserva (opcional)',
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Nenhuma caixinha')),
                              for (final v in availableVaults)
                                DropdownMenuItem(
                                  value: v.id,
                                  child: Text('${v.name} (${v.currentBalance.formatted})'),
                                ),
                            ],
                            onChanged: (val) => setDialogState(() => selectedVaultId = val),
                          ),
                        );
                      }),
                      if (isEditing) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<ProjectStatus>(
                          initialValue: selectedStatus,
                          decoration: const InputDecoration(labelText: 'Status do Projeto', isDense: true),
                          items: ProjectStatus.values.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text(_getStatusLabel(s)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedStatus = val);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    final rawBudget = budgetCtrl.text.trim();
                    Money? parsedBudget;
                    if (rawBudget.isNotEmpty) {
                      try {
                        final b = Money.parse(rawBudget);
                        if (b.cents > 0) parsedBudget = b;
                      } catch (_) {}
                    }

                    final cubit = context.read<ProjectsCubit>();
                    Navigator.pop(dialogCtx);

                    if (isEditing) {
                      await cubit.updateProject(
                        projectToEdit.copyWith(
                          title: title,
                          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                          type: selectedType,
                          targetBudget: parsedBudget,
                          startDate: startDate,
                          endDate: endDate,
                          status: selectedStatus,
                          vaultId: selectedVaultId,
                          clearVaultId: selectedVaultId == null,
                          updatedAt: DateTime.now(),
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Projeto atualizado com sucesso!')),
                        );
                      }
                    } else {
                      await cubit.createProjectForHouse(
                        title: title,
                        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                        type: selectedType,
                        targetBudget: parsedBudget,
                        startDate: startDate,
                        endDate: endDate,
                        status: selectedStatus,
                        vaultId: selectedVaultId,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Projeto criado com sucesso!')),
                        );
                      }
                    }
                  },
                  child: Text(isEditing ? 'Salvar' : 'Criar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Future<void> _exportProjectPdf(
    BuildContext context,
    SharedProject project,
    ProjectSettlementSummary summary,
    List<HouseExpense> expenses,
    SavingsVault? vault,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await const ProjectReportExport().buildPdf(
        project: project,
        summary: summary,
        expenses: expenses,
        linkedVault: vault,
        resolvePayerName: (id) => _resolveMemberName(summary, project, id),
      );
      final saved = await FilePicker.saveFile(
        fileName: ProjectReportExport.fileNamePdf(project),
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Salvar relatório do projeto em PDF',
        allowedExtensions: const ['pdf'],
        type: FileType.custom,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved != null || kIsWeb
                ? 'Relatório em PDF do projeto salvo com sucesso!'
                : 'Operação cancelada.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao exportar PDF: $e')),
      );
    }
  }

  Future<void> _exportProjectCsv(
    BuildContext context,
    SharedProject project,
    ProjectSettlementSummary summary,
    List<HouseExpense> expenses,
    SavingsVault? vault,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = const ProjectReportExport().buildCsv(
        project: project,
        summary: summary,
        expenses: expenses,
        linkedVault: vault,
        resolvePayerName: (id) => _resolveMemberName(summary, project, id),
      );
      final saved = await FilePicker.saveFile(
        fileName: ProjectReportExport.fileNameCsv(project),
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        dialogTitle: 'Salvar planilha do projeto em CSV',
        allowedExtensions: const ['csv'],
        type: FileType.custom,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved != null || kIsWeb
                ? 'Planilha CSV do projeto salva com sucesso!'
                : 'Operação cancelada.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao exportar CSV: $e')),
      );
    }
  }


}

/// Linha do diálogo de participantes de um projeto.


class _ParticipantRow {
  final String? id;
  final String? userId; // null = convidado de fora da casa
  final String name;
  bool included;
  int? percent;
  String? pixKey;
  String? phone;

  _ParticipantRow({
    this.id,
    required this.userId,
    required this.name,
    required this.included,
    this.percent,
    this.pixKey,
    this.phone,
  });
}
