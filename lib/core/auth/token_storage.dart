import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the JWT pair and cached user (same trade-off as the web app's
/// localStorage `taskforge_auth` key).
class TokenStorage {
  TokenStorage(this._prefs) {
    _access = _prefs.getString(_kAccess);
    _refresh = _prefs.getString(_kRefresh);
  }

  static const _kAccess = 'taskforge_access';
  static const _kRefresh = 'taskforge_refresh';
  static const _kUser = 'taskforge_user';
  static const _kOrg = 'taskforge_current_org';
  static const _kOnboarded = 'taskforge_onboarded';

  final SharedPreferences _prefs;
  String? _access;
  String? _refresh;

  String? get access => _access;
  String? get refresh => _refresh;
  bool get hasSession => _access != null && _refresh != null;

  Future<void> save({required String access, String? refresh}) async {
    _access = access;
    _refresh = refresh;
    await _prefs.setString(_kAccess, access);
    if (refresh != null) await _prefs.setString(_kRefresh, refresh);
  }

  Map<String, dynamic>? get cachedUser {
    final raw = _prefs.getString(_kUser);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(Map<String, dynamic> user) =>
      _prefs.setString(_kUser, jsonEncode(user));

  String? get currentOrg => _prefs.getString(_kOrg);
  Future<void> saveCurrentOrg(String? slug) =>
      slug == null ? _prefs.remove(_kOrg) : _prefs.setString(_kOrg, slug);

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _prefs.remove(_kAccess);
    await _prefs.remove(_kRefresh);
    await _prefs.remove(_kUser);
    await _prefs.remove(_kOrg);
  }
}
