import '../../../finance/domain/entities/house_member.dart';
import '../../domain/entities/project_participant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/share_helper.dart';
import '../../../../core/widgets/omni_logo.dart';
import '../../domain/entities/project_settlement_summary.dart';
import '../../domain/entities/shared_project.dart';
import '../../../settlement/domain/entities/super_pix_transfer.dart';
import '../cubit/projects_cubit.dart';
import '../cubit/projects_state.dart';

class ProjectsHubPage extends StatefulWidget {
  const ProjectsHubPage({super.key});

  @override
  State<ProjectsHubPage> createState() => _ProjectsHubPageState();
}

class _ProjectsHubPageState extends State<ProjectsHubPage> {
  @override
  void initState() {
    super.initState();
    context.read<ProjectsCubit>().loadProjects();
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
            onPressed: () => _showCreateProjectDialog(context),
          ),
        ],
      ),
      body: BlocBuilder<ProjectsCubit, ProjectsState>(
        builder: (context, state) {
          if (state is ProjectsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProjectsError) {
            return Center(child: Text(state.message));
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
                      onPressed: () => _showCreateProjectDialog(context),
                    ),
                  ],
                ),
              );
            }

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
                const SizedBox(height: 20),

                Text('Projetos em Andamento', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                ...projects.map((proj) => _buildProjectCard(context, proj)),

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

  Widget _buildProjectCard(BuildContext context, SharedProject project) {
    final theme = Theme.of(context);
    final iconData = _getProjectIcon(project.type);
    final typeName = _getProjectTypeName(project.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconData, color: AppColors.primary, size: 24),
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
                        Text(
                          typeName,
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryLight),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(project.status.name.toUpperCase()),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              if (project.description != null) ...[
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
            ],
          ),
        ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showParticipantsDialog(context, proj),
              icon: const Icon(Icons.group_outlined, size: 18),
              label: Text('Participantes (${proj.participants.length})'),
            ),
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
        ],
      ),
    );
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
        buffer.writeln('• ${t.fromMemberName} transfere ${t.amount.formatted} para ${t.toMemberName} (${t.description})');
      }
    }
    shareText(
 context,
 buffer.toString(),
 onCopied:
      const SnackBar(
        content: Text('Resumo do rateio copiado!'),
      ),
    );
  }

  void _copySingleProjectTransfer(BuildContext context, SharedProject project, SuperPixTransfer t) {
    final msg =
        'Oi ${t.fromMemberName}! No fechamento do projeto "${project.title}" no Omni Lar, ficou acertado você transferir ${t.amount.formatted} para ${t.toMemberName} para quitar a sua parte (${t.description}).';
    shareText(
 context,
 msg,
 onCopied:
      const SnackBar(
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

  /// Edita quem participa do projeto e o percentual de cada um. As despesas do
  /// projeto são divididas entre os participantes por esses percentuais.
  Future<void> _showParticipantsDialog(BuildContext context, SharedProject project) async {
    final cubit = context.read<ProjectsCubit>();
    final messenger = ScaffoldMessenger.of(context);

    var houseMembers = <HouseMember>[];
    try {
      houseMembers = await cubit.financeRepository.getMembers();
    } catch (_) {}
    if (!context.mounted) return;

    // Uma linha por pessoa: moradores da casa (marcados ou não) e convidados de fora
    final rows = <_ParticipantRow>[
      for (final m in houseMembers)
        _ParticipantRow(
          userId: m.id,
          name: m.name.split(' ').first,
          included: project.participants.any((p) => p.userId == m.id),
          percent: project.participants
              .where((p) => p.userId == m.id)
              .map((p) => p.defaultSplitPercent?.round())
              .firstOrNull,
        ),
      for (final p in project.participants)
        if (!houseMembers.any((m) => m.id == p.userId))
          _ParticipantRow(
            userId: p.userId,
            name: p.displayName,
            included: true,
            percent: p.defaultSplitPercent?.round(),
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

    // Projeto sem percentuais definidos: começa dividido igualmente
    if (rows.where((r) => r.included).any((r) => r.percent == null)) splitEqually();

    final guestController = TextEditingController();

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
                            child: Text(
                              row.userId == null ? '${row.name} (convidado)' : row.name,
                              overflow: TextOverflow.ellipsis,
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: guestController,
                            decoration: const InputDecoration(
                              labelText: 'Convidado de fora da casa',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            final name = guestController.text.trim();
                            if (name.isEmpty) return;
                            setDialogState(() {
                              rows.add(_ParticipantRow(userId: null, name: name, included: true));
                              guestController.clear();
                              splitEqually();
                            });
                          },
                          child: const Text('Adicionar'),
                        ),
                      ],
                    ),
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
                              id: 'part_${now.millisecondsSinceEpoch}_$i',
                              projectId: project.id,
                              userId: active[i].userId,
                              externalName: active[i].name,
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

  void _showCreateProjectDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    ProjectType selectedType = ProjectType.trip;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Novo Projeto / Viagem'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Projeto',
                      hintText: 'Ex: Férias em Natal, Reforma Lavabo',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ProjectType>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: ProjectType.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(_getProjectTypeName(t)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedType = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleCtrl.text.trim().isNotEmpty) {
                      context.read<ProjectsCubit>().createProjectForHouse(
                        title: titleCtrl.text.trim(),
                        type: selectedType,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Criar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Linha do diálogo de participantes de um projeto.
class _ParticipantRow {
  final String? userId; // null = convidado de fora da casa
  final String name;
  bool included;
  int? percent;

  _ParticipantRow({
    required this.userId,
    required this.name,
    required this.included,
    this.percent,
  });
}
