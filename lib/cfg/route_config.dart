import 'public_links.dart';
import 'sealed_strings.dart';

/// Single access point for app-wide constants. Identity strings are
/// plain (package name, display name) because they must match the
/// store listing; endpoints and credentials resolve lazily through the
/// unscrambler so plaintext never lands in the binary.
///
/// GAME THEME CATEGORY: neither slot nor rocket-crash — Speed Track is
/// an arcade lane-racing game. Per `.cursor/rules/gray_user_agent.mdc`
/// the `appid/appname` User-Agent suffix is **NOT** appended.
class RouteConfig {
  RouteConfig._();

  /// Android applicationId + iOS bundle id. Must exactly match:
  ///   • android/app/build.gradle.kts → applicationId + namespace
  ///   • android/app/src/main/kotlin/**/MainActivity.kt package
  ///   • android/app/google-services.json → package_name (when Firebase lands)
  static const String packageId = 'com.cctvspeed.cctvspeedtrack';

  /// Store id. On Android this is identical to [packageId].
  static const String marketId = 'com.cctvspeed.cctvspeedtrack';

  /// Display name — must match `android:label` in AndroidManifest.xml.
  static const String displayName = 'Speed Track';

  /// iOS App Store numeric id (unused on Android — leave empty).
  static const String storeNumericId = '';

  static String get gateEndpoint => unlockGateEndpoint();
  static String get attributionKey => unlockAttributionKey();
  static String get messagingProject => unlockMessagingProject();

  static const String privacyUrl = privacyPolicyLink;
  static const String helpUrl = supportLink;
  static const String homeUrl = siteHome;

  /// Push invite re-prompt delay (3 days). Do NOT lower without approval —
  /// see the notification-permission section of the gray-flow guide.
  static const int pushInviteCooldownSeconds = 3 * 24 * 60 * 60;

  /// Wait before re-querying attribution when AppsFlyer reports a
  /// possibly-false Organic status on the first callback.
  static const int organicRetryDelaySeconds = 5;
}
