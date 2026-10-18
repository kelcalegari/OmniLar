import '../../domain/entities/user_profile.dart';
import '../../domain/entities/account_deletion_preview.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/house_member_info.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthDataSource _dataSource;

  AuthRepositoryImpl(this._dataSource);

  @override
  Stream<UserProfile?> get authStateChanges => _dataSource.authStateChanges;

  @override
  Stream<House?> get houseChanges => _dataSource.houseChanges;

  @override
  UserProfile? get currentUser => _dataSource.currentUser;

  @override
  House? get currentHouse => _dataSource.currentHouse;

  @override
  bool get isDemoMode => _dataSource.isDemoMode;

  @override
  bool get isRestoringSession => _dataSource.isRestoringSession;

  @override
  Future<UserProfile> signInWithEmailPassword(String email, String password) {
    return _dataSource.signInWithEmailPassword(email, password);
  }

  @override
  Future<UserProfile?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
  }) {
    return _dataSource.signUpWithEmailPassword(
      email: email,
      password: password,
      fullName: fullName,
    );
  }

  @override
  Future<UserProfile> verifySignUpCode({
    required String email,
    required String code,
  }) {
    return _dataSource.verifySignUpCode(email: email, code: code);
  }

  @override
  Future<void> resendSignUpCode(String email) {
    return _dataSource.resendSignUpCode(email);
  }

  @override
  Future<void> requestPasswordReset(String email) {
    return _dataSource.requestPasswordReset(email);
  }

  @override
  Future<UserProfile> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _dataSource.resetPasswordWithCode(
      email: email,
      code: code,
      newPassword: newPassword,
    );
  }

  @override
  String? get pendingEmailChange => _dataSource.pendingEmailChange;

  @override
  List<String> get signInProviders => _dataSource.signInProviders;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _dataSource.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  @override
  Future<void> acceptTerms(String version) => _dataSource.acceptTerms(version);

  @override
  Future<void> setAiConsent(bool given) => _dataSource.setAiConsent(given);

  @override
  Future<String> exportMyData() => _dataSource.exportMyData();

  @override
  Future<AccountDeletionPreview> getAccountDeletionPreview() => _dataSource.getAccountDeletionPreview();

  @override
  Future<void> deleteAccount({required String password}) => _dataSource.deleteAccount(password: password);

  @override
  Future<void> requestEmailChange(String newEmail) {
    return _dataSource.requestEmailChange(newEmail);
  }

  @override
  Future<bool> confirmEmailChange({required String email, required String code}) {
    return _dataSource.confirmEmailChange(email: email, code: code);
  }

  @override
  Future<UserProfile?> signInWithGoogle() {
    return _dataSource.signInWithGoogle();
  }

  @override
  Future<void> signInDemo({required String memberId}) {
    return _dataSource.signInDemo(memberId: memberId);
  }

  @override
  Future<void> signOut() {
    return _dataSource.signOut();
  }

  @override
  Future<UserProfile> updateProfile({
    required String fullName,
    String? email,
    String? pixKey,
  }) {
    return _dataSource.updateProfile(
      fullName: fullName,
      email: email,
      pixKey: pixKey,
    );
  }

  @override
  Future<List<House>> getUserHouses() {
    return _dataSource.getUserHouses();
  }

  @override
  Future<House> createHouse({
    required String name,
    int cycleStartDay = 5,
    int initialReserveCents = 0,
    int initialCashCents = 0,
  }) {
    return _dataSource.createHouse(
      name: name,
      cycleStartDay: cycleStartDay,
      initialReserveCents: initialReserveCents,
      initialCashCents: initialCashCents,
    );
  }

  @override
  Future<House> updateHouse({
    required String houseId,
    String? name,
    int? cycleStartDay,
    String? pixKey,
    String? pixKeyType,
    String? pixKeyHolderName,
    String? pixKeyBank,
  }) {
    return _dataSource.updateHouse(
      houseId: houseId,
      name: name,
      cycleStartDay: cycleStartDay,
      pixKey: pixKey,
      pixKeyType: pixKeyType,
      pixKeyHolderName: pixKeyHolderName,
      pixKeyBank: pixKeyBank,
    );
  }

  @override
  Future<House> joinHouseWithInvite(String inviteCode) {
    return _dataSource.joinHouseWithInvite(inviteCode);
  }

  @override
  Future<void> selectHouse(String houseId) {
    return _dataSource.selectHouse(houseId);
  }

  @override
  Future<List<HouseMemberInfo>> getHouseMembers(String houseId) {
    return _dataSource.getHouseMembers(houseId);
  }

  @override
  Future<String> createHouseInvite(String houseId) {
    return _dataSource.createHouseInvite(houseId);
  }
}
