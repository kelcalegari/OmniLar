import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/di/service_locator.dart';
import 'package:omni_lar/features/assistant/presentation/cubit/assistant_cubit.dart';
import 'package:omni_lar/features/assistant/domain/entities/assistant_message.dart';
import 'package:omni_lar/features/assistant/presentation/widgets/confirmation_card_widget.dart';
import 'package:omni_lar/features/settings/presentation/widgets/ai_key_config_sheet.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';
import '../../../shopping/presentation/cubit/shopping_cubit.dart';

class AssistantChatPage extends StatefulWidget {
  const AssistantChatPage({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 600,
      child: BlocProvider(
        create: (_) => sl<AssistantCubit>(),
        child: const AssistantChatPage(),
      ),
    );
  }

  @override
  State<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends State<AssistantChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submit() {
    final query = _textController.text.trim();
    if (query.isEmpty) return;
    _textController.clear();
    context.read<AssistantCubit>().sendMessage(query);
    _scrollToBottom();
  }

  void _openAiSettings() async {
    AppHaptics.light();
    await AiKeyConfigSheet.show(context);
    if (mounted) {
      context.read<AssistantCubit>().checkAiKeyStatus();
    }
  }

  void _handleVoiceInput() {
    AppHaptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.mic_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Dica: use a tecla de voz do teclado (Win + H no PC ou microfone do teclado) para ditar.'),
            ),
          ],
        ),
        backgroundColor: AppColors.accent,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = !context.isMobile;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (isDesktop ? 0.85 : 0.9),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assistente Omni Lar',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      BlocBuilder<AssistantCubit, AssistantState>(
                        buildWhen: (prev, curr) => prev.hasCustomKey != curr.hasCustomKey,
                        builder: (context, state) {
                          return GestureDetector(
                            onTap: _openAiSettings,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: state.hasCustomKey ? AppColors.creditGreen : AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  state.hasCustomKey ? 'Chave Pessoal (AI Studio)' : 'Cota Padrão (Toque p/ configurar)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: state.hasCustomKey ? AppColors.creditGreen : theme.textTheme.bodySmall?.color,
                                    decoration: state.hasCustomKey ? null : TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_suggest_outlined),
                  onPressed: _openAiSettings,
                  tooltip: 'Configurar Chave IA',
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Fechar',
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Messages list
          Expanded(
            child: BlocConsumer<AssistantCubit, AssistantState>(
              listener: (context, state) {
                _scrollToBottom();
                final toolName = state.lastExecutedToolName;
                if (toolName != null) {
                  if (toolName.contains('expense') || toolName.contains('finance') || toolName.contains('payment')) {
                    context.read<FinanceCubit>().loadCycleData();
                  }
                  if (toolName.contains('loan') || toolName.contains('p2p') || toolName.contains('installment')) {
                    context.read<P2PCubit>().loadLoans();
                  }
                  if (toolName.contains('shopping') || toolName.contains('item')) {
                    context.read<ShoppingCubit>().loadShoppingData();
                  }
                }
              },
              builder: (context, state) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length + (state.isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == state.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      );
                    }

                    final message = state.messages[index];
                    return _buildMessageItem(context, message);
                  },
                );
              },
            ),
          ),

          // Quick chips / Suggestions
          BlocBuilder<AssistantCubit, AssistantState>(
            builder: (context, state) {
              if (state.messages.isEmpty) return const SizedBox.shrink();
              final lastMsg = state.messages.last;
              if (lastMsg.role != AssistantRole.assistant || lastMsg.quickFollowups == null || lastMsg.quickFollowups!.isEmpty) {
                return const SizedBox.shrink();
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: lastMsg.quickFollowups!.map((sugg) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(
                            sugg.contains('Ajustes') || sugg.contains('chave')
                                ? Icons.key_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 14,
                          ),
                          label: Text(sugg, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            AppHaptics.selection();
                            if (sugg.contains('Ajustes') || sugg.contains('chave')) {
                              _openAiSettings();
                            } else {
                              context.read<AssistantCubit>().sendMessage(sugg);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),

          // Bottom Input Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Pergunte ou peça algo...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark
                          ? AppColors.cardDark
                          : Colors.grey.shade100,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _handleVoiceInput,
                  icon: const Icon(Icons.mic_none_rounded, color: AppColors.accent),
                  tooltip: 'Comando de Voz',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, AssistantMessage message) {
    final theme = Theme.of(context);
    final isUser = message.role == AssistantRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary
              : theme.brightness == Brightness.dark
                  ? AppColors.cardDark
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isUser ? Colors.white : theme.textTheme.bodyMedium?.color,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (message.proposedActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...message.proposedActions.map(
                (act) => ConfirmationCardWidget(
                  proposal: act,
                  onConfirm: () {
                    context.read<AssistantCubit>().confirmAction(message.id, act);
                  },
                  onCancel: () {
                    context.read<AssistantCubit>().cancelAction(message.id, act.id);
                  },
                  onEdit: (updated) {
                    context.read<AssistantCubit>().updateActionProposal(message.id, updated);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
