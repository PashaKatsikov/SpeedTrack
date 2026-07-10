import '../scramble/unscrambler.dart';

/// Keystream-packed sensitive strings.
/// Every list here was produced by `dart run tool/pack_secrets.dart`
/// using the seed in `lib/scramble/unscrambler.dart`.
///
/// Do NOT edit these by hand. If you need to rotate a value, change the
/// plaintext in `tool/pack_secrets.dart`, re-run it, and paste the new
/// list here.

// gateEndpoint <= "https://speedtrrack.com/config.php"
const List<int> _gateBytes = <int>[
  75, 114, 151, 40, 40, 245, 96, 241, 103, 102, 237, 171, 199, 238,
  91, 181, 14, 177, 207, 174, 35, 136, 58, 163, 248, 233, 144, 85,
  232, 204, 92, 32, 146, 120,
];

// gcdBase <= "https://gcdsdk.appsflyer.com/install_data/v4.0/"
const List<int> _gcdBytes = <int>[
  75, 114, 151, 40, 40, 245, 96, 241, 115, 117, 236, 189, 199, 241,
  7, 166, 31, 162, 215, 230, 44, 158, 50, 254, 181, 229, 145, 94,
  174, 194, 28, 35, 142, 105, 109, 72, 154, 26, 24, 153, 0, 223,
  64, 0, 128, 216, 174,
];

// chromeVersion <= "149.0.7723.87"
const List<int> _chromeBytes = <int>[
  18, 50, 218, 118, 107, 225, 120, 233, 38, 37, 166, 246, 148,
];

// webkitVersion <= "537.36"
const List<int> _webkitBytes = <int>[22, 53, 212, 118, 104, 249];

// attributionKey <= "5GfGgdgz6A3SmEyyajJFV7"  (AppsFlyer Dev Key)
const List<int> _attribBytes = <int>[
  22, 65, 133, 31, 60, 171, 40, 164, 34, 87, 187, 157, 206, 223, 80, 190,
  14, 184, 238, 198, 22, 208,
];

// messagingProject <= "209494791787"  (Firebase project number / sender id)
const List<int> _fcmProjectBytes = <int>[
  17, 54, 218, 108, 98, 251, 120, 231, 37, 33, 176, 249,
];

String unlockGateEndpoint() => unpack(_gateBytes);
String unlockAttributionKey() => unpack(_attribBytes);
String unlockMessagingProject() => unpack(_fcmProjectBytes);
String unlockChromeVersion() => unpack(_chromeBytes);
String unlockWebkitVersion() => unpack(_webkitBytes);

/// Assembles a GCD retry URL. Returns "" if the base is empty —
/// callers must treat that as "GCD unavailable, keep the SDK data".
String unlockGcdUrl(String appId, String deviceId) {
  final String base = unpack(_gcdBytes);
  if (base.isEmpty) return '';
  final String key = unlockAttributionKey();
  return '$base$appId?devkey=$key&device_id=$deviceId';
}
