---
name: omnilar-finance-engine
description: >-
  Use when implementing or testing Omni Lar financial rules: Money in cents,
  financial cycle dates, the three split models (percentage, fixed, category),
  installments with partial payments, forgiveness, renegotiation, and the
  Global Clearing Engine (net settlement / Super Pix).
---

# Omni Lar: Motor Financeiro

Referências: `novoSite/modulo_despesas_de_casa.md`, `modulo_emprestimo.md`, `integracao_modulo_financeiro.md`. A **fonte de verdade é o servidor** (funções SQL / Edge). Dart pode ter uma versão para simulação offline, com os mesmos testes.

## Princípios
1. Valores em **centavos inteiros**. Divisões distribuem o resto (não perder centavos).
2. **Ledger imutável:** pagamento é evento; status é derivado. Correção = estorno ou novo lançamento.
3. Pagamento parcial mantém a parcela como "parcialmente paga" até quitar (RN02 de empréstimos).
4. Perdão não apaga: muda status para perdoado, histórico fica.
5. Renegociação invalida as parcelas pendentes antigas e cria novas, com aceite do credor.

## Rateio (despesas)
- **Porcentagem:** pesos somam 100. Calcular em centavos e distribuir o resto (maior resto primeiro; desempate determinístico por id).
- **Valores fixos:** soma dos valores deve igualar o total da despesa (validar).
- **Categoria com dono:** 100% para o dono da categoria. Se outro membro pagou, gera crédito do pagador contra o dono (pagamento cruzado).

```dart
// Distribuição por maior resto (ex.: 1000 centavos em 3 partes iguais -> 334, 333, 333)
List<int> splitCents(int total, List<int> weights) {
  final sum = weights.fold(0, (a, b) => a + b);
  final base = [for (final w in weights) total * w ~/ sum];
  var rest = total - base.fold(0, (a, b) => a + b);
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final ra = (total * weights[a]) % sum, rb = (total * weights[b]) % sum;
      return rb != ra ? rb.compareTo(ra) : a.compareTo(b);
    });
  for (final i in order) { if (rest-- <= 0) break; base[i]++; }
  return base;
}
```

## Ciclo financeiro
- Ciclo definido por `cycle_start_day` (ex.: 05 a 04 do mês seguinte). Tratar meses curtos (dia 31 em fevereiro), ano bissexto e fuso da Casa.
- Compra no cartão pertence ao ciclo conforme o **fechamento** do cartão (antes ou depois do dia de fechamento).
- Fôlego = saldo do Caixa − compromissos a vencer no ciclo.
- Parcelas futuras (RN01) não negativam o ciclo atual.

## Empréstimos
- Gerador de parcelas: `n` parcelas, resto na última (ou distribuído), datas editáveis antes de confirmar.
- Status derivado da parcela: `futura`, `pendente`, `parcial`, `paga`, `vencida`, `perdoada`, `renegociada`.
- Alocação de pagamento: mais antigas primeiro (FIFO), salvo escolha manual (decisão em aberto, padrão FIFO).

## Motor de Compensação (Super Pix)
Entrada: obrigações do ciclo por par de membros (aportes devidos à Casa, reembolsos da Casa, parcelas P2P do mês).
1. Montar o saldo líquido de cada membro (`+` a receber, `-` a pagar), incluindo a Casa como entidade virtual.
2. Reduzir às **transferências mínimas** (casar maiores devedores com maiores credores).
3. Saída: lista `(de, para, valor)` e o detalhamento do que cada transferência quita.
4. Ao confirmar, liquidar de forma **atômica** (uma transação) e carimbar parcelas/aportes como pagos.

Caso de teste obrigatório (exemplo da RN-INT-02 em `integracao_modulo_financeiro.md`): Kelvynn deve 500 de aporte, deve 100 ao Cris (P2P) e a Casa deve 200 ao Kelvynn. Valor líquido esperado a pagar pelo Kelvynn: **400** (500 − 200 + 100). Observação: o exemplo do doc destina os 400 ao Cris, mas o aporte é devido à Casa. Ao implementar, definir e documentar o destino de cada parcela do valor (decisão em aberto: Casa como entidade virtual) e cobrir com teste.

## Testes mínimos
- Divisão sem perda de centavos (ex.: 100,00 em 3).
- Rateio fixo com soma inválida é rejeitado.
- Fim de mês, ano bissexto e virada de ciclo.
- Pagamento parcial, perdão, renegociação e exclusão de pagamento recalculam o status.
- Compensação: soma dos saldos líquidos sempre zero; nenhuma transferência negativa.
- Idempotência: liquidar duas vezes o mesmo ciclo não duplica.
