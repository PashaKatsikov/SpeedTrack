import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../cfg/sealed_strings.dart';

/// HTTP client wearing a forged real-device User-Agent.
///
/// Every outbound request (gate POST, GCD retry, notification image
/// fetch) and the WebView itself share this UA so backend fingerprints
/// stay coherent. A default Dart UA would leak instantly.
///
/// The Chrome + WebKit fragments are decoded from `sealed_strings.dart`
/// — never as plaintext literals.
class MaskedClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  String _ua = 'Mozilla/5.0';

  String get userAgent => _ua;

  /// Reads device info and assembles the UA. Call once from `main()`
  /// before constructing any bridge.
  Future<void> warmUp() async {
    final String chrome = _pick(unlockChromeVersion(), '149.0.7723.87');
    final String webkit = _pick(unlockWebkitVersion(), '537.36');

    try {
      final DeviceInfoPlugin probe = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo a = await probe.androidInfo;
        final String tag = a.display.isNotEmpty ? a.display : a.id;
        _ua =
            'Mozilla/5.0 (Linux; Android ${a.version.release}; ${a.brand} ${a.model} Build/$tag) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit';
      } else if (Platform.isIOS) {
        final IosDeviceInfo i = await probe.iosInfo;
        final String os = i.systemVersion.replaceAll('.', '_');
        _ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS $os like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$webkit';
      }
    } catch (_) {
      _ua = 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UP1A.231005.007) '
          'AppleWebKit/$webkit (KHTML, like Gecko) '
          'Chrome/$chrome Mobile Safari/$webkit';
    }
  }

  static String _pick(String value, String fallback) =>
      value.isNotEmpty ? value : fallback;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) {
    req.headers.putIfAbsent('User-Agent', () => _ua);
    return _inner.send(req);
  }

  @override
  void close() => _inner.close();
}

/// Shared client used by every gray-flow bridge.
final MaskedClient siteAgent = MaskedClient();
