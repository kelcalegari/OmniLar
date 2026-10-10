import '../../domain/entities/user_profile.dart';
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
  Future<UserProfile> signInWithEmailPassword(String email, String password) {
    return _dataSource.signInWithEmailPassword(email, password);
  }

  @override
  Future<UserProfile> signUpWithEmailPassword({
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
  Future<void> signInDemo({required String memberId}) {
    return _dataSource.signInDemo(memberId: memberId);
  }

  @override
  Future<void> signOut() {
    return _dataSource.signOut();
  }

  @override
  Future<List<House>> getUserHouses() {
    return _dataSource.getUserHouses();
  }

  @override
  Future<House> createHouse({
    required String name,
    int cycleStartDay = 5,
  }) {
    return _dataSource.createHouse(name: name, cycleStartDay: cycleStartDay);
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
