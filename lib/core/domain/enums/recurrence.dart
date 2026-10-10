/// Frequência de repetição para eventos da agenda e compromissos do lar.
enum RecurrenceFrequency {
  none,
  daily,
  weekly,
  biweekly,
  monthly,
  yearly;

  String get label {
    switch (this) {
      case RecurrenceFrequency.none:
        return 'Não se repete (Único)';
      case RecurrenceFrequency.daily:
        return 'Todos os dias (Diário)';
      case RecurrenceFrequency.weekly:
        return 'Toda semana (Semanal)';
      case RecurrenceFrequency.biweekly:
        return 'A cada 2 semanas (Quinzenal)';
      case RecurrenceFrequency.monthly:
        return 'Todo mês (Mensal)';
      case RecurrenceFrequency.yearly:
        return 'Todo ano (Anual)';
    }
  }

  String get shortLabel {
    switch (this) {
      case RecurrenceFrequency.none:
        return 'Único';
      case RecurrenceFrequency.daily:
        return 'Diário';
      case RecurrenceFrequency.weekly:
        return 'Semanal';
      case RecurrenceFrequency.biweekly:
        return 'Quinzenal';
      case RecurrenceFrequency.monthly:
        return 'Mensal';
      case RecurrenceFrequency.yearly:
        return 'Anual';
    }
  }
}

/// Escopo de aplicação de edição ou exclusão de um item recorrente.
/// Segue o padrão RFC 5545 / Google Calendar.
enum RecurrenceScope {
  /// Altera ou exclui exclusivamente esta ocorrência pontual, mantendo as demais inalteradas.
  thisInstanceOnly,

  /// Altera ou exclui esta ocorrência e todas as ocorrências subsequentes a partir desta data.
  thisAndFuture,

  /// Altera ou exclui todas as ocorrências da série (passadas, atuais e futuras).
  allInstances;

  String title({required bool isDelete}) {
    switch (this) {
      case RecurrenceScope.thisInstanceOnly:
        return isDelete ? 'Apenas este evento' : 'Apenas este evento';
      case RecurrenceScope.thisAndFuture:
        return isDelete ? 'Este e os próximos eventos' : 'Este e os próximos eventos';
      case RecurrenceScope.allInstances:
        return isDelete ? 'Todos os eventos' : 'Todos os eventos';
    }
  }

  String expenseTitle({required bool isDelete}) {
    switch (this) {
      case RecurrenceScope.thisInstanceOnly:
        return isDelete ? 'Apenas esta fatura deste ciclo' : 'Apenas esta fatura deste ciclo';
      case RecurrenceScope.thisAndFuture:
        return isDelete ? 'Deste ciclo em diante' : 'Deste ciclo em diante';
      case RecurrenceScope.allInstances:
        return isDelete ? 'Todas as faturas da assinatura' : 'Todas as faturas da assinatura';
    }
  }

  String description({required bool isDelete}) {
    switch (this) {
      case RecurrenceScope.thisInstanceOnly:
        return isDelete
            ? 'Exclui somente esta data específica. O resto da repetição continua normal.'
            : 'Modifica somente esta data específica sem afetar os outros dias.';
      case RecurrenceScope.thisAndFuture:
        return isDelete
            ? 'Exclui a partir desta data em diante. O histórico passado permanece salvo.'
            : 'Aplica as alterações a partir desta data para o futuro.';
      case RecurrenceScope.allInstances:
        return isDelete
            ? 'Exclui toda a repetição e todas as suas ocorrências no calendário.'
            : 'Modifica todas as repetições passadas e futuras desta série.';
    }
  }
}
