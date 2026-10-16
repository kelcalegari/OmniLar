import '../entities/user_profile.dart';
import '../entities/house.dart';
import '../entities/house_member_info.dart';

abstract class AuthRepository {
  Stream<UserProfile?> get authStateChanges;
  Stream<House?> get houseChanges;

  UserProfile? get currentUser;
  House? get currentHouse;
  bool get isDemoMode;

  /// Há uma sessão salva cujo perfil e casa ainda estão sendo carregados.
  bool get isRestoringSession => false;

  Future<UserProfile> signInWithEmailPassword(String email, String password);
  /// Devolve `null` quando a conta foi criada mas espera a confirmação do
  /// e-mail (código enviado para a caixa postal).
  Future<UserProfile?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
  });

  /// Confirma o e-mail do cadastro com o código recebido e abre a sessão.
  Future<UserProfile> verifySignUpCode({
    required String email,
    required String code,
  });

  /// Reenvia o código de confirmação do cadastro.
  Future<void> resendSignUpCode(String email);

  /// Envia o código de redefinição de senha. Não revela se o e-mail tem conta.
  Future<void> requestPasswordReset(String email);

  /// Confere o código de redefinição, grava a nova senha e abre a sessão.
  Future<UserProfile> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Novo e-mail pedido que ainda espera confirmação, se houver.
  String? get pendingEmailChange => null;

  /// Formas de entrar ligadas à conta ('email', 'google').
  List<String> get signInProviders => const ['email'];

  /// Troca a senha de quem está logado, conferindo a senha atual.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Pede a troca do e-mail de acesso; o Supabase envia o(s) código(s).
  Future<void> requestEmailChange(String newEmail);

  /// Confere um código da troca de e-mail. Devolve `true` quando a troca
  /// terminou e `false` quando ainda falta o código do outro endereço.
  Future<bool> confirmEmailChange({required String email, required String code});
  Future<void> signInDemo({required String memberId});
  Future<void> signOut();
  Future<UserProfile> updateProfile({
    required String fullName,
    String? email,
    String? pixKey,
  });

  Future<List<House>> getUserHouses();
  Future<House> createHouse({required String name, int cycleStartDay = 5});
  Future<House> updateHouse({
    required String houseId,
    String? name,
    int? cycleStartDay,
    String? pixKey,
    String? pixKeyType,
    String? pixKeyHolderName,
    String? pixKeyBank,
  });
  Future<House> joinHouseWithInvite(String inviteCode);
  Future<void> selectHouse(String houseId);
  Future<List<HouseMemberInfo>> getHouseMembers(String houseId);
  Future<String> createHouseInvite(String houseId);
}
