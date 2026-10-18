import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';

void main() {
  const mercado = ExpenseCategory(id: 'c1', name: 'Supermercado', icon: '', colorHex: '');
  const pet = ExpenseCategory(id: 'c2', name: 'Pet Shop', icon: '', colorHex: '');

  test('só o interruptor do cadastro decide; o nome não conta mais', () {
    expect(mercado.countsAsVariableSpend, isFalse);
    expect(pet.countsAsVariableSpend, isFalse);

    const mercadoFixo = ExpenseCategory(
      id: 'c1', name: 'Supermercado', icon: '', colorHex: '', isVariableSpend: false);
    const petVariavel = ExpenseCategory(
      id: 'c2', name: 'Pet Shop', icon: '', colorHex: '', isVariableSpend: true);
    expect(mercadoFixo.countsAsVariableSpend, isFalse);
    expect(petVariavel.countsAsVariableSpend, isTrue);
  });

  test('o planejador estima só as categorias marcadas como variáveis', () {
    final estimate = const CycleFundingEstimator().calculateEstimate(
      cycle: FinancialCycle(start: DateTime(2026, 10, 5), end: DateTime(2026, 11, 4)),
      members: const [
        HouseMember(id: 'a', name: 'Ana', role: 'owner', defaultSplitPercent: 100),
      ],
      categories: const [
        ExpenseCategory(id: 'c1', name: 'Supermercado', icon: '', colorHex: '', isVariableSpend: false),
        ExpenseCategory(id: 'c2', name: 'Pet Shop', icon: '', colorHex: '', isVariableSpend: true),
      ],
      currentCycleExpenses: const [],
      historicalExpenses: const [],
      currentCycleContributions: const [],
    );
    expect(estimate.variableCategoryEstimates.map((e) => e.categoryId), ['c2']);
  });
}
