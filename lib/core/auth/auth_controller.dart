import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../api/api_client.dart';

enum AuthStatus { unknown, signedOut, signedIn }

@immutable
class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user});
  final AuthStatus status;
  final User? user;

  bool get isSignedIn => status == AuthStatus.signedIn;
}

/// Owns WHO the user is (like the web's Zustand auth store). Server data
/// lives in FutureProviders per feature.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final tokens = ref.read(tokenStorageProvider);
    ref.read(apiClientProvider).onAuthExpired = () {
      state = const AuthState(status: AuthStatus.signedOut);
    };
    if (!tokens.hasSession) {
      return const AuthState(status: AuthStatus.signedOut);
    }
    final cached = tokens.cachedUser;
    // Optimistically signed in from cache; refresh the profile in background.
    Future.microtask(refreshUser);
    return AuthState(
        status: AuthStatus.signedIn,
        user: cached == null ? null : User.fromJson(cached));
  }

  TaskForgeRepository get _repo => ref.read(repositoryProvider);

  Future<void> login(String email, String password) async {
    final data = await _repo.login(email.trim(), password);
    await _persist(
        data['access'] as String, data['refresh'] as String?, data['user']);
  }

  Future<void> register({
    required String email,
    required String firstName,
    required String lastName,
    required String password,
    required String passwordConfirm,
  }) async {
    final data = await _repo.register(
      email: email.trim(),
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      password: password,
      passwordConfirm: passwordConfirm,
    );
    final tokens = Map<String, dynamic>.from(data['tokens'] as Map);
    await _persist(
        tokens['access'] as String, tokens['refresh'] as String?, data['user']);
  }

  Future<void> _persist(
      String access, String? refresh, dynamic userJson) async {
    final storage = ref.read(tokenStorageProvider);
    await storage.save(access: access, refresh: refresh);
    User? user;
    if (userJson is Map) {
      final map = Map<String, dynamic>.from(userJson);
      await storage.saveUser(map);
      user = User.fromJson(map);
    }
    state = AuthState(status: AuthStatus.signedIn, user: user);
  }

  Future<void> refreshUser() async {
    try {
      final user = await _repo.me();
      await ref.read(tokenStorageProvider).saveUser(user.raw);
      if (state.isSignedIn) {
        state = AuthState(status: AuthStatus.signedIn, user: user);
      }
    } catch (_) {
      // Offline or expired — the client interceptor handles expiry.
    }
  }

  void setUser(User user) {
    ref.read(tokenStorageProvider).saveUser(user.raw);
    state = AuthState(status: AuthStatus.signedIn, user: user);
  }

  /// Signs out locally right away; revoking the refresh token on the server
  /// happens in the background so a sleeping server can't block sign out.
  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    final refresh = storage.refresh;
    final access = storage.access;
    final repo = _repo;
    await storage.clear();
    ref.read(currentOrgProvider.notifier).state = null;
    state = const AuthState(status: AuthStatus.signedOut);
    if (refresh != null) {
      repo
          .logout(refresh, access: access)
          .timeout(const Duration(seconds: 20))
          .ignore();
    }
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Currently selected organization slug (persisted).
final currentOrgProvider = StateProvider<String?>((ref) {
  final storage = ref.read(tokenStorageProvider);
  ref.listenSelf((_, next) => storage.saveCurrentOrg(next));
  return storage.currentOrg;
});
