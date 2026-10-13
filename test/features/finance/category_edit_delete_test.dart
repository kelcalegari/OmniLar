import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';

void main() {
  group('Categorias: editar e excluir', () {
    test('Editar troca o nome e o dono, mantendo o id', () async {
      final ds = MockFinanceDataSource();
      final original = (await ds.getCategories()).first;

      await ds.updateCategory(
        ExpenseCategory(
          id: original.id,
          name: 'Feira e Mercado',
          icon: original.icon,
          colorHex: original.colorHex,
          ownerMemberId: 'member_carlos',
        ),
      );

      final updated = (await ds.getCategories()).firstWhere((c) => c.id == original.id);
      expect(updated.name, 'Feira e Mercado');
      expect(updated.ownerMemberId, 'member_carlos');
    });

    test('Categoria sem lançamentos é excluída', () async {
      final ds = MockFinanceDataSource();
      const nova = ExpenseCategory(
        id: 'cat_teste',
        name: 'Pet Shop',
        icon: 'category',
        colorHex: '#0F766E',
      );
      await ds.addCategory(nova);

      await ds.deleteCategory(nova.id);

      expect((await ds.getCategories()).any((c) => c.id == nova.id), isFalse);
    });

    test('Categoria com lançamentos é recusada e continua na lista', () async {
      final ds = MockFinanceDataSource();
      // 'cat_mercado' tem despesas nos dados de demonstração
      await expectLater(
        ds.deleteCategory('cat_mercado'),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            contains('lançamento'),
          ),
        ),
      );
      expect((await ds.getCategories()).any((c) => c.id == 'cat_mercado'), isTrue);
    });
  });
}
