/// Tratamento do texto das linhas de fatura e extrato: comparar descrições do
/// banco com títulos do app e dar um nome legível ao lançamento.
class StatementText {
  const StatementText._();

  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  // Palavras que aparecem em quase toda descrição e não identificam o lugar
  static const _noise = {
    'ltda', 'eireli', 'cia', 'com', 'comercio', 'servicos', 'loja', 'lojas',
    'pag', 'pagamento', 'compra', 'cartao', 'debito', 'credito', 'pix',
    'parcela', 'parc', 'brasil', 'sao', 'paulo', 'rio', 'janeiro', 'para',
    'the', 'www', 'pagseguro', 'mercadopago', 'ifd',
  };

  static const _lowerWords = {'de', 'da', 'do', 'das', 'dos', 'e', 'em', 'a', 'o'};

  static final _installment = RegExp(
    r'(?:parc(?:ela)?\.?\s*)?(\d{1,2})\s*(?:/|de)\s*(\d{1,2})\s*$',
    caseSensitive: false,
  );

  static String _stripAccents(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_accents[char] ?? char);
    }
    return buffer.toString();
  }

  /// Minúsculas, sem acento e sem pontuação.
  static String normalize(String text) => _stripAccents(text.toLowerCase())
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Palavras que identificam o estabelecimento.
  static Set<String> tokens(String text) => {
        for (final word in normalize(text).split(' '))
          if (word.length >= 3 && !_noise.contains(word) && !RegExp(r'^\d+$').hasMatch(word)) word,
      };

  /// Quanto duas descrições se parecem, de 0 a 1: parcela das palavras da mais
  /// curta que aparecem na outra ("mercado" casa com "supermercado").
  static double similarity(String a, String b) {
    final tokensA = tokens(a);
    final tokensB = tokens(b);
    if (tokensA.isEmpty || tokensB.isEmpty) return 0;

    final shorter = tokensA.length <= tokensB.length ? tokensA : tokensB;
    final longer = identical(shorter, tokensA) ? tokensB : tokensA;
    var hits = 0;
    for (final word in shorter) {
      if (longer.any((other) => other == word || other.contains(word) || word.contains(other))) {
        hits++;
      }
    }
    return hits / shorter.length;
  }

  /// Parcela indicada no fim da descrição ("MAGALU 03/10", "Parcela 3 de 10").
  static ({int number, int total})? installmentOf(String description) {
    final match = _installment.firstMatch(description.trim());
    if (match == null) return null;
    final number = int.parse(match.group(1)!);
    final total = int.parse(match.group(2)!);
    if (number < 1 || total < 2 || number > total) return null;
    return (number: number, total: total);
  }

  /// Nome legível para o lançamento: sem a parcela, sem o número da loja e sem
  /// tudo em maiúsculas ("PAO DE ACUCAR LJ 1234" vira "Pao de Acucar").
  static String cleanTitle(String description) {
    var text = description.trim();
    if (installmentOf(text) != null) text = text.replaceFirst(_installment, '').trim();
    text = text
        .replaceAll(RegExp(r'^(pag|mp|ifd|pg)\s*\*\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(lj|loja|fl|filial)\.?\s*\d+\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b\d{3,}\b'), '')
        .replaceAll(RegExp(r'[*\-–\s]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return description.trim();

    final hasLower = text != text.toUpperCase();
    if (hasLower) return text;

    final words = text.toLowerCase().split(' ');
    return [
      for (var i = 0; i < words.length; i++)
        i > 0 && _lowerWords.contains(words[i])
            ? words[i]
            : words[i][0].toUpperCase() + words[i].substring(1),
    ].join(' ');
  }
}
