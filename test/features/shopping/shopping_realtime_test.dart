import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/shopping/data/datasources/mock_shopping_datasource.dart';
import 'package:omni_lar/features/shopping/data/repositories/shopping_repository_impl.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_item.dart';
import 'package:omni_lar/features/shopping/presentation/cubit/shopping_cubit.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/data/repositories/p2p_repository_impl.dart';

void main() {
  group('Shopping Realtime Sync', () {
    late MockShoppingDataSource dataSource;
    late ShoppingRepositoryImpl repository;
    late ShoppingCubit cubit;

    setUp(() async {
      final financeRepo = FinanceRepositoryImpl(MockFinanceDataSource());
      final p2pRepo = P2PRepositoryImpl(MockP2PDataSource());
      dataSource = MockShoppingDataSource(
        financeRepository: financeRepo,
        p2pRepository: p2pRepo,
      );
      repository = ShoppingRepositoryImpl(dataSource);
      cubit = ShoppingCubit(repository);
      await cubit.loadShoppingData();
    });

    tearDown(() {
      cubit.close();
    });

    test('reflete adição externa de item na stream sem reload manual', () async {
      final initialCount = cubit.state.items.length;

      // Morador parceiro adiciona item diretamente pelo datasource/backend
      await dataSource.addItem(
        const ShoppingItem(
          id: 'item_realtime_1',
          listId: 'list_mercado',
          name: 'Pão de Queijo Realtime',
          quantity: 1,
          estimatedPrice: Money(1500),
        ),
      );

      // Pequena folga para a stream emitir
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.items.length, equals(initialCount + 1));
      expect(
        cubit.state.items.any((item) => item.name == 'Pão de Queijo Realtime'),
        isTrue,
      );
    });

    test('reflete alternância de status de comprado em tempo real', () async {
      final targetItem = cubit.state.items.first;
      final initialStatus = targetItem.isBought;

      // Morador parceiro marca como comprado no supermercado
      await dataSource.toggleItemBought(targetItem.id);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updatedItem =
          cubit.state.items.firstWhere((i) => i.id == targetItem.id);
      expect(updatedItem.isBought, equals(!initialStatus));
    });
  });
}
