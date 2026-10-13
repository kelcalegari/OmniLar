import '../../../finance/domain/services/expense_launch_defaults.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/services/ai_config_service.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/entities/financial_cycle_summary.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../shopping/domain/repositories/shopping_repository.dart';
import '../../../shopping/domain/entities/shopping_item.dart';
import '../../../calendar/domain/repositories/calendar_repository.dart';
import '../../../calendar/domain/entities/calendar_event.dart';
import '../../../calendar/domain/entities/task_item.dart';
import '../entities/assistant_message.dart';

class NaturalLanguageInterpretation {
  final String textResponse;
  final List<AssistantActionProposal> actions;
  final List<String> suggestions;
  final bool usingCustomKey;

  const NaturalLanguageInterpretation({
    required this.textResponse,
    this.actions = const [],
    this.suggestions = const [],
    this.usingCustomKey = false,
  });
}

class AssistantInterpreterService {
  final FinanceRepository financeRepository;
  final P2PRepository p2pRepository;
  final ShoppingRepository shoppingRepository;
  final CalendarRepository calendarRepository;
  final AiConfigService? aiConfigService;
  final AuthRepository? authRepository;
  final SupabaseClient? supabaseClient;

  AssistantInterpreterService({
    required this.financeRepository,
    required this.p2pRepository,
    required this.shoppingRepository,
    required this.calendarRepository,
    this.aiConfigService,
    this.authRepository,
    this.supabaseClient,
  });

  /// Processa a mensagem em linguagem natural.
  /// Implementa a estratégia arquitetural "Código primeiro, IA depois":
  /// 1. Consultas frequentes fechadas rodam direto via código/SQL local sem gastar cota de IA.
  /// 2. Perguntas abertas e comandos complexos chamam a Edge Function com Gemini.
  /// 3. Em modo offline, erro de rede ou modo demo, recorre ao processador determinístico com fallback gracioso.
  Future<NaturalLanguageInterpretation> interpretMessage(
    String query, {
    FinancialCycle? currentCycle,
    String? activeMemberId,
    List<AssistantMessage>? history,
  }) async {
    final lower = query.toLowerCase().trim();
    final effectiveMemberId = activeMemberId ?? authRepository?.currentUser?.id ?? 'member_carlos';
    final cycle = currentCycle ??
        FinancialCycle.fromDate(
          date: DateTime.now(),
          cycleStartDay: authRepository?.currentHouse?.cycleStartDay ?? 5,
        );

    // =========================================================================
    // 1. ATALHOS RÁPIDOS SEM IA (Economia de Quota & Velocidade Máxima)
    // =========================================================================
    if (lower == 'quanto sobrou no caixa?' ||
        lower == 'quanto sobrou no caixa' ||
        lower == 'saldo do caixa' ||
        lower == 'fôlego financeiro') {
      return _queryFinancialSummary(cycle);
    }

    if (lower == 'quem deve para quem?' ||
        lower == 'quem deve para quem' ||
        lower == 'resumo de empréstimos' ||
        lower == 'dividas p2p') {
      return _queryP2PBalances(effectiveMemberId);
    }

    if (lower == 'o que falta na lista de compras?' ||
        lower == 'o que falta na lista' ||
        lower == 'compras pendentes') {
      return _queryShoppingList();
    }

    // =========================================================================
    // 2. TENTATIVA DE PROCESSAMENTO VIA EDGE FUNCTION (GEMINI + TOOLS + BYOK)
    // =========================================================================
    final client = supabaseClient;
    final isDemo = authRepository?.isDemoMode ?? false;

    if (client != null && !isDemo) {
      final userApiKey = await aiConfigService?.getUserApiKey();
      final userModel = await aiConfigService?.getSelectedModel();

      try {
        final houseId = authRepository?.currentHouse?.id ?? 'house_default';

        // Prepara contexto resumido para enriquecer a inferência do Gemini
        final contextSummary = await _buildContextSummary(cycle, effectiveMemberId);

        final response = await client.functions.invoke(
          'assistant',
          body: {
            'message': query,
            'houseId': houseId,
            'memberId': effectiveMemberId,
            if (userApiKey != null && userApiKey.isNotEmpty) 'userApiKey': userApiKey,
            if (userModel != null && userModel.isNotEmpty) 'userModel': userModel,
            'contextSummary': contextSummary,
            'history': (history ?? []).map((m) => {
              'role': m.role == AssistantRole.user ? 'user' : 'model',
              'text': m.content,
            }).toList(),
          },
        );

        final data = response.data;
        if (data is Map<String, dynamic>) {
          if (data['success'] == true && data['interpretation'] != null) {
            final interp = data['interpretation'] as Map<String, dynamic>;
            final textResponse = interp['textResponse'] as String? ?? '';
            final rawActions = interp['actions'] as List<dynamic>? ?? [];
            final rawSuggestions = interp['suggestions'] as List<dynamic>? ?? [];

            final actions = rawActions.map((a) {
              final actMap = a as Map<String, dynamic>;
              return AssistantActionProposal(
                id: actMap['id'] as String? ?? 'act_${DateTime.now().millisecondsSinceEpoch}',
                title: actMap['title'] as String? ?? 'Proposta de Ação',
                description: actMap['description'] as String? ?? '',
                toolName: actMap['toolName'] as String? ?? '',
                arguments: (actMap['arguments'] as Map<String, dynamic>?) ?? {},
                status: AssistantActionStatus.proposed,
                isHighRisk: actMap['isHighRisk'] as bool? ?? false,
              );
            }).toList();

            final suggestions = rawSuggestions.map((s) => s.toString()).toList();
            final usingCustomKey = data['usingCustomKey'] as bool? ?? false;

            return NaturalLanguageInterpretation(
              textResponse: textResponse,
              actions: actions,
              suggestions: suggestions,
              usingCustomKey: usingCustomKey,
            );
          } else if (data['quotaExhausted'] == true || data['rateLimited'] == true) {
            final isCustom = data['isCustomKey'] as bool? ?? (userApiKey != null && userApiKey.isNotEmpty);
            if (isCustom) {
              return const NaturalLanguageInterpretation(
                textResponse: '⚠️ Os tokens ou o limite por minuto da sua chave pessoal do Google AI Studio foram esgotados (Erro 429 / RESOURCE_EXHAUSTED).\n'
                    '• No plano gratuito, há um limite de requisições por minuto (RPM) — tente novamente em cerca de 1 minuto.\n'
                    '• Se a cota diária terminou, confira seu painel no Google AI Studio ou alterne para a cota padrão do app em Ajustes.',
                suggestions: [
                  'Configurar chave pessoal nos Ajustes',
                  'Quanto sobrou no Caixa?',
                  'O que falta na lista de compras?',
                ],
                usingCustomKey: true,
              );
            }
            return NaturalLanguageInterpretation(
              textResponse: data['error'] as String? ??
                  'A cota diária gratuita do assistente foi atingida para sua casa.',
              suggestions: const [
                'Configurar chave pessoal nos Ajustes',
                'Quanto sobrou no Caixa?',
                'O que falta na lista de compras?',
              ],
              usingCustomKey: false,
            );
          }
        }
      } on FunctionException catch (fe) {
        if (fe.status == 429) {
          final isCustom = (userApiKey != null && userApiKey.isNotEmpty);
          if (isCustom) {
            return const NaturalLanguageInterpretation(
              textResponse: '⚠️ Os tokens ou limite de requisições por minuto da sua chave pessoal do Google AI Studio foram esgotados (Erro 429 / RESOURCE_EXHAUSTED).\n'
                  'Aguarde cerca de 1 minuto para tentar novamente ou verifique seu painel no Google AI Studio.',
              suggestions: [
                'Configurar chave pessoal nos Ajustes',
                'Quanto sobrou no Caixa?',
                'O que falta na lista de compras?',
              ],
              usingCustomKey: true,
            );
          } else {
            return const NaturalLanguageInterpretation(
              textResponse: 'A cota diária gratuita do assistente para esta casa foi atingida.\n'
                  'Você pode adicionar sua chave pessoal gratuita do Google AI Studio em Ajustes.',
              suggestions: [
                'Configurar chave pessoal nos Ajustes',
                'Quanto sobrou no Caixa?',
                'O que falta na lista de compras?',
              ],
              usingCustomKey: false,
            );
          }
        }
      } catch (_) {
        // Em caso de falha de conexão, erro 500 ou timeout, recai graciosamente no fallback local
      }
    }

    // =========================================================================
    // 3. FALLBACK LOCAL DETERMINÍSTICO (Offline / Demo / Testes)
    // =========================================================================
    return _interpretLocally(query, cycle, effectiveMemberId, history: history);
  }

  /// Processamento local determinístico via regras e regex.
  Future<NaturalLanguageInterpretation> _interpretLocally(
    String query,
    FinancialCycle cycle,
    String activeMemberId, {
    List<AssistantMessage>? history,
  }) async {
    final lower = query.toLowerCase().trim();

    // -------------------------------------------------------------------------
    // A. RESPOSTA A PERGUNTA DE MEIO DE PAGAMENTO PENDENTE
    // -------------------------------------------------------------------------
    final lastAssistantMsg = (history != null && history.isNotEmpty)
        ? history.lastWhere((m) => m.role == AssistantRole.assistant, orElse: () => history.last)
        : null;

    final isAwaitingPaymentMethod = lastAssistantMsg != null &&
        (lastAssistantMsg.content.toLowerCase().contains('qual meio de pagamento') ||
         lastAssistantMsg.content.toLowerCase().contains('qual o meio de pagamento'));

    if (isAwaitingPaymentMethod) {
      final paymentMethods = await financeRepository.getPaymentMethods();
      final matchedPm = _matchPaymentMethod(lower, paymentMethods);

      if (matchedPm != null) {
        // Extrai título e valor da mensagem anterior do assistente
        final titleMatch = RegExp(r'despesa de "([^"]+)"', caseSensitive: false).firstMatch(lastAssistantMsg.content);
        final pendingTitle = titleMatch?.group(1) ?? 'Despesa';

        final moneyMatch = RegExp(r'R\$\s*(\d+(?:[.,]\d{1,2})?)').firstMatch(lastAssistantMsg.content);
        final pendingCents = moneyMatch != null
            ? Money.parse(moneyMatch.group(1)!.replaceAll(',', '.')).cents
            : 0;

        if (pendingCents > 0) {
          final action = AssistantActionProposal(
            id: 'act_${DateTime.now().millisecondsSinceEpoch}',
            title: 'Lançar Despesa da Casa',
            description: '$pendingTitle: ${Money(pendingCents).format()} • Meio de pagamento: ${matchedPm.name}',
            toolName: 'finance.addExpense',
            arguments: {
              'title': pendingTitle,
              'cents': pendingCents,
              'paidByMemberId': activeMemberId,
              'paymentMethodId': matchedPm.id,
              'paymentMethodName': matchedPm.name,
            },
            status: AssistantActionStatus.proposed,
          );

          return NaturalLanguageInterpretation(
            textResponse: 'Perfeito! Meio de pagamento definido como ${matchedPm.name}. '
                'Criei o cartão de confirmação para a despesa de "$pendingTitle" (${Money(pendingCents).format()}). '
                'Por favor, confirme abaixo para gravar no app:',
            actions: [action],
            suggestions: const [
              'Confirmar',
              'Cancelar',
            ],
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // B. SIMULAÇÃO DE COMPRA / PLANEJAMENTO (RN02 / Seção 4.5)
    // -------------------------------------------------------------------------
    if (lower.contains('dá para comprar') ||
        lower.contains('da pra comprar') ||
        lower.contains('posso comprar') ||
        lower.contains('cabe no orçamento') ||
        lower.contains('cabe no caixa') ||
        lower.contains('estoura o ciclo')) {
      final simMoneyMatch = RegExp(r'(?:r\$\s*|por\s+|de\s+|valor\s+)?(\d+(?:[.,]\d{1,2})?)\s*(?:reais|real)?', caseSensitive: false).firstMatch(query);
      if (simMoneyMatch != null) {
        final valStr = simMoneyMatch.group(1) ?? '0';
        final parsedMoney = Money.parse(valStr.replaceAll(',', '.'));
        if (parsedMoney.cents > 0) {
          final summary = await financeRepository.getCycleSummary(cycle);
          String cleanItem = query
              .replaceAll(simMoneyMatch.group(0) ?? '', '')
              .replaceAll(RegExp(r'\bdá para comprar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bda pra comprar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bposso comprar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bcabe no orçamento\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bcabe no caixa\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bestoura o ciclo\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\breais\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\breal\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'r\$\s*', caseSensitive: false), '')
              .trim();
          cleanItem = cleanItem
              .replaceAll(RegExp(r'^(?:com|de|em|no|na|por|uma|um)\s+', caseSensitive: false), '')
              .trim();
          if (cleanItem.isEmpty) cleanItem = 'este item';

          final folegoCents = summary.folego.cents;
          if (folegoCents >= parsedMoney.cents) {
            final remaining = Money(folegoCents - parsedMoney.cents);
            return NaturalLanguageInterpretation(
              textResponse: 'Sim, cabe no ciclo atual! 🟢\n\n'
                  '• Fôlego livre atual: ${summary.folego.format()}\n'
                  '• Custo estimado ($cleanItem): ${parsedMoney.format()}\n'
                  '• Fôlego restante projetado: ${remaining.format()}\n\n'
                  'Essa compra não compromete as contas e provisões do ciclo (${summary.cycle.label}).',
              suggestions: [
                'Lançar despesa de $cleanItem',
                'Quanto sobrou no Caixa?',
                'Ver contas a vencer',
              ],
            );
          } else {
            final deficit = Money(parsedMoney.cents - folegoCents);
            return NaturalLanguageInterpretation(
              textResponse: 'Atenção: essa compra pode estourar o ciclo atual! ⚠️\n\n'
                  '• Fôlego livre atual: ${summary.folego.format()}\n'
                  '• Custo estimado ($cleanItem): ${parsedMoney.format()}\n'
                  '• Déficit projetado: -${deficit.format()}\n\n'
                  'O saldo livre não é suficiente para cobrir essa compra sem comprometer despesas já compromissadas do ciclo.',
              suggestions: [
                'Registrar aporte no Caixa',
                'Quem deve para quem?',
                'Quanto sobrou no Caixa?',
              ],
            );
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // C. AÇÃO: REGISTRAR APORTE NO CAIXA DA CASA
    // -------------------------------------------------------------------------
    if (lower.contains('aporte') || lower.contains('depositar no caixa') || lower.contains('depositei no caixa')) {
      final moneyMatch = RegExp(r'(?:r\$\s*|por\s+|de\s+|valor\s+)?(\d+(?:[.,]\d{1,2})?)\s*(?:reais|real)?', caseSensitive: false).firstMatch(query);
      if (moneyMatch != null) {
        final valStr = moneyMatch.group(1) ?? '0';
        final parsedMoney = Money.parse(valStr.replaceAll(',', '.'));
        if (parsedMoney.cents > 0) {
          final paymentMethods = await financeRepository.getPaymentMethods();
          final matchedPm = _matchPaymentMethod(lower, paymentMethods);

          final action = AssistantActionProposal(
            id: 'act_${DateTime.now().millisecondsSinceEpoch}',
            title: 'Registrar Aporte no Caixa',
            description: 'Aporte de ${parsedMoney.format()} para o Caixa da Casa${matchedPm != null ? " • via ${matchedPm.name}" : ""}',
            toolName: 'finance.addContribution',
            arguments: {
              'cents': parsedMoney.cents,
              'memberId': activeMemberId,
              if (matchedPm != null) 'paymentMethodId': matchedPm.id,
              if (matchedPm != null) 'paymentMethodName': matchedPm.name,
            },
            status: AssistantActionStatus.proposed,
          );

          return NaturalLanguageInterpretation(
            textResponse: 'Entendido! Preparei a proposta de aporte de ${parsedMoney.format()} para o Fundo Comum da Casa. '
                'Por favor, confirme no cartão abaixo para registrar no Caixa:',
            actions: [action],
            suggestions: const [
              'Confirmar',
              'Cancelar',
            ],
          );
        }
      }
    }

    // Consultas Financeiras
    if (lower.contains('saldo') || lower.contains('fôlego') || lower.contains('quanto sobrou') || lower.contains('caixa')) {
      return _queryFinancialSummary(cycle);
    }

    // Empréstimos e Dívidas P2P
    if (lower.contains('deve') || lower.contains('dívida') || lower.contains('emprestimo') || lower.contains('empréstimo') || lower.contains('p2p')) {
      return _queryP2PBalances(activeMemberId);
    }

    // Ação: Adicionar Item na Lista de Compras
    if (lower.startsWith('adiciona ') || lower.startsWith('adicionar ') || lower.startsWith('compra ') || lower.startsWith('comprar ')) {
      String itemText = lower
          .replaceAll('adicionar ', '')
          .replaceAll('adiciona ', '')
          .replaceAll('comprar ', '')
          .replaceAll('compra ', '')
          .replaceAll(' na lista', '')
          .replaceAll(' de compras', '')
          .replaceAll(' de mercado', '')
          .trim();

      if (itemText.isNotEmpty) {
        final action = AssistantActionProposal(
          id: 'act_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Adicionar à Lista de Compras',
          description: 'Adicionar "$itemText" na lista da casa',
          toolName: 'shopping.addItem',
          arguments: {
            'name': itemText[0].toUpperCase() + itemText.substring(1),
            'quantity': 1.0,
            'unit': 'un',
          },
          status: AssistantActionStatus.proposed,
        );

        return NaturalLanguageInterpretation(
          textResponse: 'Preparei o cartão para incluir este item. Por favor, confirme abaixo para gravar na lista da casa:',
          actions: [action],
          suggestions: const [
            'Adicionar mais um item',
            'O que já temos na lista?',
          ],
        );
      }
    }

    // Consulta de Compras
    if (lower.contains('lista') || lower.contains('compras') || lower.contains('o que falta') || lower.contains('mercado')) {
      return _queryShoppingList();
    }

    // Ação: Registrar Despesa por Linguagem Natural
    final isExpenseVerb = lower.contains('cadastr') ||
        lower.contains('lança') ||
        lower.contains('lanca') ||
        lower.contains('gastei') ||
        lower.contains('comprei') ||
        lower.contains('paguei') ||
        lower.contains('pagar') ||
        lower.contains('despesa');

    final moneyRegex = RegExp(
      r'(?:r\$\s*|por\s+|de\s+|valor\s+)?(\d+(?:[.,]\d{1,2})?)\s*(?:reais|real)?',
      caseSensitive: false,
    );

    if (isExpenseVerb) {
      final match = moneyRegex.firstMatch(query);
      if (match != null) {
        final valStr = match.group(1) ?? '0';
        final parsedMoney = Money.parse(valStr.replaceAll(',', '.'));
        if (parsedMoney.cents > 0) {
          final paymentMethods = await financeRepository.getPaymentMethods();
          final matchedPm = _matchPaymentMethod(lower, paymentMethods);

          // Limpa o título da despesa
          String title = query;
          final matchedText = match.group(0) ?? '';
          if (matchedText.isNotEmpty) {
            title = title.replaceAll(matchedText, '');
          }

          title = title
              .replaceAll(RegExp(r'\bcadastrar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bcadastra\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bcadastre\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\blançar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\blancar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\blança\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\blanca\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bgastei\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bcomprei\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bpaguei\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bpagar\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\bdespesa\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\breais\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\breal\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'r\$\s*', caseSensitive: false), '');

          if (matchedPm != null) {
            title = title
                .replaceAll(RegExp(RegExp.escape(matchedPm.name), caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+cartão\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+cartao\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+pix\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bvia\s+pix\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+vr\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+nubank\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+itau\b', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bno\s+itaú\b', caseSensitive: false), '');
          }

          title = title.trim();
          title = title
              .replaceAll(RegExp(r'^(?:com|de|em|no|na|por)\s+', caseSensitive: false), '')
              .replaceAll(RegExp(r'\s+(?:com|de|em|no|na|por)$', caseSensitive: false), '')
              .trim();

          final cleanTitle = title.isEmpty
              ? 'Despesa'
              : (title[0].toUpperCase() + title.substring(1));

          // RN06: Se NÃO informou o meio de pagamento, pergunta antes de propor a ação
          if (matchedPm == null) {
            final pmSuggestions = paymentMethods.isNotEmpty
                ? paymentMethods.map((pm) => pm.name).toList()
                : const [
                    'Conta Conjunta (Caixa da Casa)',
                    'VR Marina (Vale Refeição)',
                    'Nubank Carlos',
                    'Itaú Marina',
                    'Pix',
                  ];

            return NaturalLanguageInterpretation(
              textResponse: 'Entendido! Para cadastrar a despesa de "$cleanTitle" (${parsedMoney.format()}), '
                  'qual meio de pagamento você utilizou?',
              actions: const [],
              suggestions: pmSuggestions,
            );
          }

          // Se já informou o meio de pagamento, cria a proposta de ação
          final action = AssistantActionProposal(
            id: 'act_${DateTime.now().millisecondsSinceEpoch}',
            title: 'Lançar Despesa da Casa',
            description: '$cleanTitle: ${parsedMoney.format()} • Meio de pagamento: ${matchedPm.name}',
            toolName: 'finance.addExpense',
            arguments: {
              'title': cleanTitle,
              'cents': parsedMoney.cents,
              'paidByMemberId': activeMemberId,
              'paymentMethodId': matchedPm.id,
              'paymentMethodName': matchedPm.name,
            },
            status: AssistantActionStatus.proposed,
          );

          return NaturalLanguageInterpretation(
            textResponse: 'Entendido! Preparei a proposta de lançamento de "$cleanTitle" no valor de '
                '${parsedMoney.format()} via ${matchedPm.name}. Por favor, confirme no cartão abaixo para gravar no app:',
            actions: [action],
            suggestions: const [
              'Confirmar',
              'Cancelar',
            ],
          );
        }
      }
    }

    // Consultas de Agenda e Tarefas
    if (lower.contains('compromisso') || lower.contains('evento') || lower.contains('agenda') || lower.contains('tarefa') || lower.contains('hoje')) {
      final events = await calendarRepository.getEvents();
      final tasks = await calendarRepository.getTasks();
      final overdueTasks = tasks.where((t) => t.isOverdue).length;

      return NaturalLanguageInterpretation(
        textResponse: 'Na agenda da casa temos ${events.length} compromissos agendados.\n'
            'Nas tarefas, há ${tasks.length} ativas, sendo $overdueTasks com prazo vencido.',
        suggestions: const [
          'Ver tarefas atrasadas',
          'Criar novo compromisso',
          'Quem está responsável pela limpeza?',
        ],
      );
    }

    // Resposta padrão inteligente
    return const NaturalLanguageInterpretation(
      textResponse: 'Olá! Sou o assistente do Omni Lar. Conheço o caixa da casa, compromissos da agenda, '
          'itens de compras e empréstimos pessoais. Como posso te apoiar hoje?',
      suggestions: [
        'Quanto sobrou no Caixa?',
        'O que falta na lista de compras?',
        'Quem deve para quem?',
        'Adicionar leite na lista',
      ],
    );
  }

  Future<NaturalLanguageInterpretation> _queryFinancialSummary(FinancialCycle cycle) async {
    final summary = await financeRepository.getCycleSummary(cycle);
    final freeMoney = summary.folego;
    final spentMoney = summary.totalExpensesPaid;

    String statusText = 'confortável e saudável';
    if (summary.status == FolegoStatus.warning) {
      statusText = 'em alerta (menos de 15% de margem)';
    } else if (summary.status == FolegoStatus.danger) {
      statusText = 'no limite / negativo';
    }

    return NaturalLanguageInterpretation(
      textResponse: 'Com base no ciclo atual (${summary.cycle.label}), o Caixa da casa gastou '
          '${spentMoney.format()}. O saldo livre (fôlego) é de ${freeMoney.format()}.\n'
          'O fôlego financeiro está $statusText.',
      suggestions: const [
        'O que vence esta semana?',
        'Quem deve para quem?',
        'Adicionar despesa de supermercado',
      ],
    );
  }

  Future<NaturalLanguageInterpretation> _queryP2PBalances(String activeMemberId) async {
    final loans = await p2pRepository.getLoans();
    int toReceiveCents = 0;
    int toPayCents = 0;

    for (final loan in loans) {
      if (loan.status == LoanStatus.active) {
        if (loan.lenderMemberId == activeMemberId) {
          toReceiveCents += loan.remainingAmount.cents;
        } else if (loan.borrowerMemberId == activeMemberId) {
          toPayCents += loan.remainingAmount.cents;
        }
      }
    }

    final toReceive = Money(toReceiveCents);
    final toPay = Money(toPayCents);
    final net = toReceive - toPay;

    return NaturalLanguageInterpretation(
      textResponse: 'Resumo de acertos pessoais:\n'
          '• A receber de outros: ${toReceive.format()}\n'
          '• A pagar para outros: ${toPay.format()}\n'
          'Saldo P2P líquido: ${net.format()}.',
      suggestions: const [
        'Ver fechamento da casa',
        'Lembrar marina do pagamento',
        'Como funciona a compensação?',
      ],
    );
  }

  Future<NaturalLanguageInterpretation> _queryShoppingList() async {
    final lists = await shoppingRepository.getLists();
    final targetListId = lists.isNotEmpty ? lists.first.id : 'list_default';
    final items = await shoppingRepository.getItems(targetListId);
    final pending = items.where((i) => !i.isBought).toList();

    if (pending.isEmpty) {
      return const NaturalLanguageInterpretation(
        textResponse: 'A lista de compras está em dia! Todos os itens já foram comprados.',
        suggestions: [
          'Adicionar leite e pão',
          'Quanto foi gasto no mercado?',
        ],
      );
    }

    final itemsList = pending.take(5).map((i) => '• ${i.name} (${i.quantity.toInt()} ${i.unit})').join('\n');
    final more = pending.length > 5 ? '\n... e mais ${pending.length - 5} itens.' : '';

    return NaturalLanguageInterpretation(
      textResponse: 'Atualmente temos ${pending.length} itens pendentes na lista de compras:\n$itemsList$more',
      suggestions: const [
        'Adicionar ovos e queijo',
        'Marcar leite como comprado',
        'Ir para a tela de compras',
      ],
    );
  }

  PaymentMethod? _matchPaymentMethod(String lower, List<PaymentMethod> paymentMethods) {
    if (lower.trim().isEmpty) return null;
    final clean = lower.trim().toLowerCase();

    // 1. Match exato ou contenção direta no nome
    for (final pm in paymentMethods) {
      final pmName = pm.name.toLowerCase();
      if (clean.contains(pmName) || pmName.contains(clean)) {
        return pm;
      }
    }

    // 2. Match por termos específicos conhecidos nos nomes cadastrados
    for (final pm in paymentMethods) {
      final pmName = pm.name.toLowerCase();
      if ((clean.contains('nubank') && pmName.contains('nubank')) ||
          (clean.contains('itau') && pmName.contains('itau')) ||
          (clean.contains('itaú') && pmName.contains('itau')) ||
          (clean.contains('vr') && (pmName.contains('vr') || pm.isBenefit)) ||
          (clean.contains('refeição') && (pmName.contains('refeição') || pm.isBenefit)) ||
          (clean.contains('vale refeicao') && (pmName.contains('refeição') || pm.isBenefit)) ||
          (clean.contains('caixa') && pmName.contains('caixa')) ||
          (clean.contains('conjunta') && pmName.contains('conjunta'))) {
        return pm;
      }
    }

    // 3. Meios genéricos como Pix, Dinheiro ou Cartão
    if (clean.contains('pix')) {
      final pixPm = paymentMethods.where((p) => p.name.toLowerCase().contains('pix') || p.type == PaymentMethodType.pix).firstOrNull;
      return pixPm ?? const PaymentMethod(id: 'pm_pix', name: 'Pix', type: PaymentMethodType.pix);
    }
    if (clean.contains('dinheiro') || clean.contains('cash')) {
      final cashPm = paymentMethods.where((p) => p.name.toLowerCase().contains('dinheiro') || p.type == PaymentMethodType.cash).firstOrNull;
      return cashPm ?? const PaymentMethod(id: 'pm_cash', name: 'Dinheiro', type: PaymentMethodType.cash);
    }
    if (clean.contains('cartao') || clean.contains('cartão')) {
      final cardPm = paymentMethods.where((p) => p.type == PaymentMethodType.card).firstOrNull;
      return cardPm ?? (paymentMethods.isNotEmpty ? paymentMethods.first : null);
    }

    return null;
  }

  Future<String> _buildContextSummary(FinancialCycle cycle, String activeMemberId) async {
    try {
      final summary = await financeRepository.getCycleSummary(cycle);
      final lists = await shoppingRepository.getLists();
      final shoppingCount = lists.isNotEmpty
          ? (await shoppingRepository.getItems(lists.first.id)).where((i) => !i.isBought).length
          : 0;
      final events = await calendarRepository.getEvents();
      final tasks = await calendarRepository.getTasks();
      final paymentMethods = await financeRepository.getPaymentMethods();
      final members = await financeRepository.getMembers();

      final pmDescriptions = paymentMethods.map((pm) => '${pm.name} (id: "${pm.id}", tipo: ${pm.type.name})').join('; ');
      final memDescriptions = members.map((m) => '${m.name} (id: "${m.id}")').join('; ');

      return 'Ciclo Atual: ${summary.cycle.label}. Fôlego livre: ${summary.folego.format()}. '
          'Despesas pagas no ciclo: ${summary.totalExpensesPaid.format()}. '
          'Itens pendentes no mercado: $shoppingCount. '
          'Compromissos na agenda: ${events.length}. Tarefas ativas: ${tasks.length}. '
          'Membros da casa: $memDescriptions. '
          'Meios de Pagamento Disponíveis: $pmDescriptions.';
    } catch (_) {
      return 'Contexto geral da casa.';
    }
  }

  /// Executa uma proposta previamente confirmada pelo usuário no Cartão de Confirmação (RN01)
  Future<void> executeAction(AssistantActionProposal proposal, {String? activeMemberId}) async {
    final effectivePayerId = activeMemberId ?? authRepository?.currentUser?.id ?? 'member_carlos';

    switch (proposal.toolName) {
      case 'shopping.addItem':
        String targetListId = proposal.arguments['listId'] as String? ?? 'list_groceries';
        if (targetListId == 'list_groceries') {
          final lists = await shoppingRepository.getLists();
          if (lists.isNotEmpty) {
            targetListId = lists.firstWhere((l) => l.isDefault, orElse: () => lists.first).id;
          }
        }
        final item = ShoppingItem(
          id: 'shop_${DateTime.now().millisecondsSinceEpoch}',
          listId: targetListId,
          name: proposal.arguments['name'] as String? ?? 'Item',
          quantity: (proposal.arguments['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: proposal.arguments['unit'] as String? ?? 'un',
          category: 'Geral',
          isBought: false,
        );
        await shoppingRepository.addItem(item);
        break;

      case 'shopping.toggleBought':
        final itemName = (proposal.arguments['itemName'] as String? ?? '').toLowerCase().trim();
        final lists = await shoppingRepository.getLists();
        final targetListId = lists.isNotEmpty ? lists.first.id : 'list_default';
        final items = await shoppingRepository.getItems(targetListId);
        final targetItem = items.where((i) => i.name.toLowerCase().contains(itemName)).firstOrNull;
        if (targetItem != null) {
          await shoppingRepository.toggleItemBought(targetItem.id);
        }
        break;

      case 'finance.addExpense':
        final payerId = proposal.arguments['paidByMemberId'] as String? ?? effectivePayerId;
        final members = await financeRepository.getMembers();
        final paymentMethods = await financeRepository.getPaymentMethods();
        final categories = await financeRepository.getCategories();
        // Categoria real da casa: a indicada pela proposta (id ou nome), senão mercado
        final category = ExpenseLaunchDefaults.matchCategory(
          categories,
          preferred: (proposal.arguments['categoryId'] ?? proposal.arguments['categoryHint']) as String?,
          nameKeywords: const ['mercado'],
        );
        final splitRule = members.isNotEmpty || category?.ownerMemberId != null
            ? ExpenseLaunchDefaults.splitRule(
                category: category,
                members: members,
                paidByMemberId: payerId,
              )
            : const SplitRule.percentage({'member_carlos': 50.0, 'member_marina': 50.0});

        // 1. Tenta usar paymentMethodId explícito passado nos argumentos da proposta
        String? paymentMethodId = proposal.arguments['paymentMethodId'] as String?;
        if (paymentMethodId == null || paymentMethodId.isEmpty) {
          final pmName = proposal.arguments['paymentMethodName'] as String?;
          if (pmName != null && pmName.isNotEmpty) {
            final matched = _matchPaymentMethod(pmName.toLowerCase(), paymentMethods);
            paymentMethodId = matched?.id;
          }
        }
        // 2. Se ainda não encontrado, tenta o método padrão do pagador ou o primeiro método
        if (paymentMethodId == null || paymentMethodId.isEmpty) {
          final payerMethod = paymentMethods.where((pm) => pm.ownerMemberId == payerId).firstOrNull;
          paymentMethodId = payerMethod?.id ?? (paymentMethods.isNotEmpty ? paymentMethods.first.id : 'pm_card_carlos');
        }

        final expense = HouseExpense(
          id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
          title: proposal.arguments['title'] as String? ?? 'Despesa',
          amount: Money(proposal.arguments['cents'] as int? ?? 0),
          date: DateTime.now(),
          categoryId: category?.id ?? 'cat_groceries',
          paidByMemberId: payerId,
          paymentMethodId: paymentMethodId,
          paidOutOfPocket: ExpenseLaunchDefaults.paidOutOfPocket(
            paymentMethods.where((pm) => pm.id == paymentMethodId).firstOrNull,
          ),
          splitRule: splitRule,
        );
        await financeRepository.addExpense(expense);
        break;

      case 'finance.addContribution':
        final memberId = proposal.arguments['memberId'] as String? ?? effectivePayerId;
        final contrib = Contribution(
          id: 'contrib_${DateTime.now().millisecondsSinceEpoch}',
          memberId: memberId,
          amount: Money(proposal.arguments['cents'] as int? ?? 0),
          date: DateTime.now(),
          paymentMethodId: proposal.arguments['paymentMethodId'] as String?,
        );
        await financeRepository.addContribution(contrib);
        break;

      case 'calendar.addEvent':
        final title = proposal.arguments['title'] as String? ?? 'Compromisso';
        final dateStr = proposal.arguments['dateIso'] as String?;
        DateTime start = DateTime.now().add(const Duration(hours: 1));
        if (dateStr != null) {
          try {
            start = DateTime.parse(dateStr);
          } catch (_) {}
        }
        final event = CalendarEvent(
          id: 'event_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          description: proposal.arguments['description'] as String?,
          startTime: start,
          endTime: start.add(const Duration(hours: 2)),
          createdByMemberId: effectivePayerId,
        );
        await calendarRepository.addEvent(event);
        break;

      case 'tasks.addTask':
        final title = proposal.arguments['title'] as String? ?? 'Tarefa';
        final dueDateStr = proposal.arguments['dueDateIso'] as String?;
        DateTime? dueDate;
        if (dueDateStr != null) {
          try {
            dueDate = DateTime.parse(dueDateStr);
          } catch (_) {}
        }
        final task = TaskItem(
          id: 'task_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          dueDate: dueDate,
          assignedToMemberId: proposal.arguments['assignedToMemberId'] as String?,
          createdByMemberId: effectivePayerId,
          createdAt: DateTime.now(),
        );
        await calendarRepository.addTask(task);
        break;

      default:
        throw UnimplementedError('Ferramenta ${proposal.toolName} não suportada');
    }
  }
}
