import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/admin_datasource.dart';
import '../../domain/entities/account_access.dart';
import '../../domain/entities/admin_models.dart';

enum AdminLoadStatus { initial, loading, success, failure }

class AdminState extends Equatable {
  final AdminLoadStatus status;
  final AdminOverview? overview;
  final List<AdminAccount> accounts;
  final List<AdminAccount> pending;
  final AdminSettings? settings;
  final List<PlanLimit> planLimits;
  final List<AdminAuditEntry> audit;
  final String search;
  final AccountStatus? statusFilter;
  final String? errorMessage;

  const AdminState({
    this.status = AdminLoadStatus.initial,
    this.overview,
    this.accounts = const [],
    this.pending = const [],
    this.settings,
    this.planLimits = const [],
    this.audit = const [],
    this.search = '',
    this.statusFilter,
    this.errorMessage,
  });

  AdminState copyWith({
    AdminLoadStatus? status,
    AdminOverview? overview,
    List<AdminAccount>? accounts,
    List<AdminAccount>? pending,
    AdminSettings? settings,
    List<PlanLimit>? planLimits,
    List<AdminAuditEntry>? audit,
    String? search,
    AccountStatus? statusFilter,
    bool clearStatusFilter = false,
    String? errorMessage,
  }) =>
      AdminState(
        status: status ?? this.status,
        overview: overview ?? this.overview,
        accounts: accounts ?? this.accounts,
        pending: pending ?? this.pending,
        settings: settings ?? this.settings,
        planLimits: planLimits ?? this.planLimits,
        audit: audit ?? this.audit,
        search: search ?? this.search,
        statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props =>
      [status, overview, accounts, pending, settings, planLimits, audit, search, statusFilter, errorMessage];
}

/// Painel administrativo: visão geral, contas, aprovações, configurações e histórico.
class AdminCubit extends Cubit<AdminState> {
  final AdminDataSource _dataSource;

  AdminCubit(this._dataSource) : super(const AdminState());

  Future<void> load() async {
    emit(state.copyWith(status: AdminLoadStatus.loading));
    try {
      final results = await Future.wait([
        _dataSource.getOverview(),
        _dataSource.listAccounts(search: state.search, status: state.statusFilter),
        _dataSource.listAccounts(status: AccountStatus.pending),
        _dataSource.getSettings(),
        _dataSource.listAudit(),
        _dataSource.getPlanLimits(),
      ]);
      if (isClosed) return;
      emit(state.copyWith(
        status: AdminLoadStatus.success,
        overview: results[0] as AdminOverview,
        accounts: results[1] as List<AdminAccount>,
        pending: results[2] as List<AdminAccount>,
        settings: results[3] as AdminSettings,
        audit: results[4] as List<AdminAuditEntry>,
        planLimits: results[5] as List<PlanLimit>,
      ));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(status: AdminLoadStatus.failure, errorMessage: _clean(e)));
    }
  }

  Future<void> filterAccounts({String? search, AccountStatus? status, bool clearStatus = false}) async {
    emit(state.copyWith(search: search, statusFilter: status, clearStatusFilter: clearStatus));
    try {
      final accounts = await _dataSource.listAccounts(search: state.search, status: state.statusFilter);
      if (!isClosed) emit(state.copyWith(accounts: accounts));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(errorMessage: _clean(e)));
    }
  }

  Future<AdminAccountDetail?> accountDetail(String userId) async {
    try {
      return await _dataSource.getAccountDetail(userId);
    } catch (e) {
      emit(state.copyWith(errorMessage: _clean(e)));
      return null;
    }
  }

  /// Devolve quantas contas mudaram, ou nulo se o banco recusou.
  Future<int?> setStatus(List<String> userIds, AccountStatus status, {String? reason}) =>
      _act(() => _dataSource.setAccountStatus(userIds, status, reason: reason));

  Future<bool> updateSettings(AdminSettings settings) async =>
      await _act(() async {
        await _dataSource.updateSettings(settings);
        return 1;
      }) !=
      null;

  /// Devolve quantas contas mudaram, ou nulo se o banco recusou.
  Future<int?> setPlan(List<String> userIds, AccountPlan plan, {DateTime? expiresAt, String? note}) =>
      _act(() => _dataSource.setPlan(userIds, plan, expiresAt: expiresAt, note: note));

  Future<bool> setPlanLimit(AccountPlan plan, PlanResource resource, int? maxValue) async =>
      await _act(() async {
        await _dataSource.setPlanLimit(plan, resource, maxValue);
        return 1;
      }) !=
      null;

  Future<bool> setPlatformAdmin(String userId, bool isAdmin) async =>
      await _act(() async {
        await _dataSource.setPlatformAdmin(userId, isAdmin);
        return 1;
      }) !=
      null;

  Future<int?> _act(Future<int> Function() action) async {
    try {
      final result = await action();
      await load();
      return result;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(errorMessage: _clean(e)));
      return null;
    }
  }

  static String _clean(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
}
