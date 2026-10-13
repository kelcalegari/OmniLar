import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

/// Fonte de demonstração com um aviso de mudança controlado pelo teste.
class _LiveDataSource extends MockFinanceDataSource {
  final changes = StreamController<void>.broadcast();
  int memberReads = 0;

  @override
  Stream<void> watchHouseChanges() => changes.stream;

  @override
  Future<List<HouseMember>> getMembers() {
    memberReads++;
    return super.getMembers();
  }
}

void main() {
  group('FinanceCubit: mudanças feitas em outro aparelho', () {
    test('Vários avisos seguidos recarregam o ciclo uma vez só', () async {
      final ds = _LiveDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(ds));
      await cubit.loadCycleData();
      final readsAfterFirstLoad = ds.memberReads;

      ds.changes.add(null);
      ds.changes.add(null);
      ds.changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(ds.memberReads, readsAfterFirstLoad + 1);
      await cubit.close();
    });

    test('Depois de trocar de casa, o aviso antigo não recarrega mais nada', () async {
      final ds = _LiveDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(ds));
      await cubit.loadCycleData();
      cubit.resetState();
      final reads = ds.memberReads;

      ds.changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(ds.memberReads, reads);
      await cubit.close();
    });
  });
}
