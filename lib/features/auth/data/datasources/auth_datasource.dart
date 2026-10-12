import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/house_member_info.dart';

abstract class AuthDataSource {
  Stream<UserProfile?> get authStateChanges;
  Stream<House?> get houseChanges;

  UserProfile? get currentUser;
  House? get currentHouse;
  bool get isDemoMode;

  Future<UserProfile> signInWithEmailPassword(String email, String password);
  Future<UserProfile> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
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
