import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/features/assistant/domain/entities/assistant_message.dart';
import 'package:omni_lar/features/assistant/domain/services/assistant_interpreter_service.dart';

class AssistantState extends Equatable {
  final List<AssistantMessage> messages;
  final bool isLoading;
  final String? errorMessage;

  const AssistantState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  AssistantState copyWith({
    List<AssistantMessage>? messages,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [messages, isLoading, errorMessage];
}

class AssistantCubit extends Cubit<AssistantState> {
  final AssistantInterpreterService interpreterService;

  AssistantCubit({required this.interpreterService})
      : super(AssistantState(messages: [
          AssistantMessage(
            id: 'msg_welcome',
            role: AssistantRole.assistant,
            content: 'Olá! Sou o Assistente Omni Lar. Posso consultar o caixa da casa, '
                'acompanhar empréstimos pessoais, adicionar itens na lista de compras '
                'ou checar compromissos da agenda. Como posso ajudar agora?',
            createdAt: DateTime.now(),
            quickFollowups: const [
              'Quanto sobrou no Caixa?',
              'O que falta na lista de compras?',
              'Quem deve para quem?',
              'Adicionar leite na lista',
            ],
          ),
        ]));

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    final userMsg = AssistantMessage(
      id: 'msg_u_${DateTime.now().millisecondsSinceEpoch}',
      role: AssistantRole.user,
      content: query,
      createdAt: DateTime.now(),
    );

    emit(state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
    ));

    try {
      final interpretation = await interpreterService.interpretMessage(query);

      final assistantMsg = AssistantMessage(
        id: 'msg_a_${DateTime.now().millisecondsSinceEpoch}',
        role: AssistantRole.assistant,
        content: interpretation.textResponse,
        createdAt: DateTime.now(),
        proposedActions: interpretation.actions,
        quickFollowups: interpretation.suggestions,
      );

      emit(state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
      ));
    } catch (e) {
      final errorMsg = AssistantMessage(
        id: 'msg_err_${DateTime.now().millisecondsSinceEpoch}',
        role: AssistantRole.system,
        content: 'Desculpe, ocorreu um erro ao consultar os dados da casa. '
            'Você também pode acessar as abas correspondentes diretamente pelo menu.',
        createdAt: DateTime.now(),
      );

      emit(state.copyWith(
        messages: [...state.messages, errorMsg],
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Confirmar proposta de ação (RN01)
  Future<void> confirmAction(String messageId, AssistantActionProposal proposal) async {
    emit(state.copyWith(isLoading: true));
    try {
      await interpreterService.executeAction(proposal);

      final updatedMessages = state.messages.map((msg) {
        if (msg.id == messageId) {
          final updatedActions = msg.proposedActions.map((a) {
            if (a.id == proposal.id) {
              return a.copyWith(status: AssistantActionStatus.executed);
            }
            return a;
          }).toList();
          return AssistantMessage(
            id: msg.id,
            role: msg.role,
            content: msg.content,
            createdAt: msg.createdAt,
            proposedActions: updatedActions,
            quickFollowups: msg.quickFollowups,
          );
        }
        return msg;
      }).toList();

      final confirmationFeedback = AssistantMessage(
        id: 'msg_fdb_${DateTime.now().millisecondsSinceEpoch}',
        role: AssistantRole.assistant,
        content: 'Pronto! Ação "${proposal.title}" confirmada e executada com sucesso.',
        createdAt: DateTime.now(),
      );

      emit(state.copyWith(
        messages: [...updatedMessages, confirmationFeedback],
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Erro ao executar ação: $e',
      ));
    }
  }

  /// Cancelar proposta de ação
  void cancelAction(String messageId, String actionId) {
    final updatedMessages = state.messages.map((msg) {
      if (msg.id == messageId) {
        final updatedActions = msg.proposedActions.map((a) {
          if (a.id == actionId) {
            return a.copyWith(status: AssistantActionStatus.cancelled);
          }
          return a;
        }).toList();
        return AssistantMessage(
          id: msg.id,
          role: msg.role,
          content: msg.content,
          createdAt: msg.createdAt,
          proposedActions: updatedActions,
          quickFollowups: msg.quickFollowups,
        );
      }
      return msg;
    }).toList();

    emit(state.copyWith(messages: updatedMessages));
  }
}
