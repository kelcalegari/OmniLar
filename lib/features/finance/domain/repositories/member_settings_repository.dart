import '../entities/member_settings.dart';

/// Ajustes do morador logado na casa atual (tabela `member_settings`, 0095).
abstract class MemberSettingsRepository {
  /// Ajustes gravados; sem linha ainda, o objeto vazio.
  Future<MemberSettings> load();

  /// Grava o objeto inteiro e devolve o que ficou gravado.
  Future<MemberSettings> save(MemberSettings settings);
}
