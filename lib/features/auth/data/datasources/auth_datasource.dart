import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/house_member_info.dart';

abstract class AuthDataSource {
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
