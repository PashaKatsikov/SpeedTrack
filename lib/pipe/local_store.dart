import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../types/run_mode.dart';

/// Persistence layer for the gray flow.
///
/// Plain flags live in SharedPreferences; URLs live in the platform
/// secure storage (Keystore on Android). Keys are terse & neutral so
/// a prefs dump does not reveal intent.
class LocalStore {
  LocalStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  static const String _kRunMode = 'st_rm_1';
  static const String _kCachedLink = 'st_cl_blob';
  static const String _kLinkTtl = 'st_cl_ttl';
  static const String _kInviteUntil = 'st_inv_next';
  static const String _kPushAllowed = 'st_push_ok';
  static const String _kPushBlocked = 'st_push_denied';
  static const String _kPendingLink = 'st_pl_blob';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Run mode ──────────────────────────────────────────────
  RunMode readMode() => RunMode.decode(_prefs.getString(_kRunMode));

  Future<void> writeMode(RunMode mode) =>
      _prefs.setString(_kRunMode, mode.encode());

  // ── Cached content link (secure) ──────────────────────────
  Future<String?> readCachedLink() => _secure.read(key: _kCachedLink);

  Future<void> writeCachedLink(String link) =>
      _secure.write(key: _kCachedLink, value: link);

  // ── Link expiry ───────────────────────────────────────────
  int? readLinkTtl() => _prefs.getInt(_kLinkTtl);

  Future<void> writeLinkTtl(int unixSeconds) =>
      _prefs.setInt(_kLinkTtl, unixSeconds);

  bool isLinkStale() {
    final int? ttl = readLinkTtl();
    if (ttl == null) return true;
    return _nowSeconds() >= ttl;
  }

  // ── Push permission state ─────────────────────────────────
  bool isPushGranted() => _prefs.getBool(_kPushAllowed) ?? false;

  Future<void> markPushGranted(bool value) =>
      _prefs.setBool(_kPushAllowed, value);

  /// True once the user denied the OS dialog — Android will never show
  /// it again, so the invite screen must stop reappearing.
  bool isPushDeniedByOs() => _prefs.getBool(_kPushBlocked) ?? false;

  Future<void> markPushDeniedByOs() =>
      _prefs.setBool(_kPushBlocked, true);

  int? readInviteResumeTs() => _prefs.getInt(_kInviteUntil);

  Future<void> writeInviteResumeTs(int unixSeconds) =>
      _prefs.setInt(_kInviteUntil, unixSeconds);

  /// Decides whether to show the push-invite promo before the WebView.
  bool shouldOfferPushInvite() {
    if (isPushGranted()) return false;
    if (isPushDeniedByOs()) return false;
    final int? until = readInviteResumeTs();
    if (until == null) return true;
    return _nowSeconds() >= until;
  }

  // ── One-time push link (secure) ───────────────────────────
  Future<void> stashPendingLink(String? link) async {
    if (link == null) {
      await _secure.delete(key: _kPendingLink);
    } else {
      await _secure.write(key: _kPendingLink, value: link);
    }
  }

  Future<String?> takePendingLink() async {
    final String? link = await _secure.read(key: _kPendingLink);
    if (link != null) await _secure.delete(key: _kPendingLink);
    return link;
  }

  static int _nowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
