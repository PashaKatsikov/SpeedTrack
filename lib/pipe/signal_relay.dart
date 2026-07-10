import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../cfg/route_config.dart';
import '../cfg/sealed_strings.dart';
import 'ua_masker.dart';

/// Collects AppsFlyer install/conversion + deep-link + app-open data
/// and folds it into the gate request body.
///
/// Organic false-positive guard: when the first conversion callback
/// reports `af_status == 'Organic'`, we wait a few seconds and re-query
/// the GCD endpoint for the real attribution.
///
/// When no dev key is configured yet, [ignite] short-circuits — the
/// install-data future completes immediately with an empty map so the
/// shell does not stall for 30s before falling back to the game.
class SignalRelay {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _install;
  Map<String, dynamic>? _deepLink;
  Map<String, dynamic>? _appOpen;

  final Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkReady = Completer<void>();

  bool _ignited = false;

  Future<void> ignite() async {
    if (_ignited) return;
    _ignited = true;

    final String devKey = RouteConfig.attributionKey;
    if (devKey.isEmpty) {
      _finishInstall(<String, dynamic>{});
      _finishDeepLink();
      return;
    }

    final AppsFlyerOptions opts = AppsFlyerOptions(
      afDevKey: devKey,
      appId: RouteConfig.storeNumericId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    final AppsflyerSdk sdk = AppsflyerSdk(opts);
    _sdk = sdk;

    sdk.onInstallConversionData((dynamic res) async {
      final Map<String, dynamic> payload = _peel(res);
      final String? status = payload['af_status']?.toString();
      if (status == 'Organic') {
        await Future<void>.delayed(
          Duration(seconds: RouteConfig.organicRetryDelaySeconds),
        );
        final Map<String, dynamic>? refreshed = await _gcdRefresh();
        _install = refreshed ?? payload;
      } else {
        _install = payload;
      }
      _finishInstall(_install ?? <String, dynamic>{});
    });

    sdk.onAppOpenAttribution((dynamic res) {
      _appOpen = _peel(res);
    });

    sdk.onDeepLinking((DeepLinkResult res) {
      final Map<String, dynamic>? click = res.deepLink?.clickEvent;
      if (click != null) _deepLink = Map<String, dynamic>.from(click);
      _finishDeepLink();
    });

    try {
      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _finishInstall(<String, dynamic>{});
      _finishDeepLink();
    }
  }

  Future<Map<String, dynamic>> awaitInstallData({int seconds = 30}) {
    return _installReady.future.timeout(
      Duration(seconds: seconds),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink() {
    return _deepLinkReady.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  Future<String?> uid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Builds the merged gate request body: attribution first, then
  /// deep-link (putIfAbsent), then app-open (putIfAbsent), then device
  /// fields (always overwrite).
  Future<Map<String, dynamic>> assembleGateBody({
    required String locale,
    String? pushToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};

    if (_install != null) body.addAll(_install!);
    _deepLink?.forEach((String k, dynamic v) => body.putIfAbsent(k, () => v));
    _appOpen?.forEach((String k, dynamic v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await uid() ?? '';
    body['bundle_id'] = RouteConfig.packageId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = RouteConfig.marketId;
    body['locale'] = locale;

    // Omit push_token / firebase_project_id entirely when they aren't
    // available — the backend distinguishes "no push subsystem" from
    // "empty token" and mis-routes if either sentinel value leaks.
    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final String project = RouteConfig.messagingProject;
    if (project.isNotEmpty) {
      body['firebase_project_id'] = project;
    }

    if (kDebugMode) {
      debugPrint('[SignalRelay] gate body: ${jsonEncode(body)}');
    }
    return body;
  }

  Future<Map<String, dynamic>?> _gcdRefresh() async {
    try {
      final String? deviceId = await uid();
      if (deviceId == null) return null;
      final String appId = Platform.isIOS
          ? RouteConfig.storeNumericId
          : RouteConfig.packageId;
      final String url = unlockGcdUrl(appId, deviceId);
      if (url.isEmpty) return null;

      final dynamic res = await siteAgent
          .get(
            Uri.parse(url),
            headers: <String, String>{
              'authorization': 'Bearer ${RouteConfig.attributionKey}',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  void _finishInstall(Map<String, dynamic> data) {
    if (!_installReady.isCompleted) _installReady.complete(data);
  }

  void _finishDeepLink() {
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  static Map<String, dynamic> _peel(dynamic res) {
    if (res is! Map) return <String, dynamic>{};
    final dynamic inner = res['payload'] ?? res['data'] ?? res;
    if (inner is Map) {
      return inner.map(
        (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    }
    return <String, dynamic>{};
  }
}
