import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivity helper for the gray flow.
///
/// [isReachable] does a real DNS probe so captive portals and limited
/// interfaces are treated as offline. VPN, ethernet and bluetooth are
/// all whitelisted — a VPN interface is genuinely a working uplink.
class LinkPulse {
  LinkPulse({Connectivity? connectivity})
      : _cx = connectivity ?? Connectivity();

  final Connectivity _cx;

  static const Set<ConnectivityResult> _liveAdapters = <ConnectivityResult>{
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  Future<bool> isReachable() async {
    final List<ConnectivityResult> states = await _cx.checkConnectivity();
    if (!states.any(_liveAdapters.contains)) return false;

    try {
      final List<InternetAddress> probe = await InternetAddress.lookup(
        'cloudflare.com',
      ).timeout(const Duration(seconds: 7));
      return probe.isNotEmpty && probe.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Stream<List<ConnectivityResult>> get changes => _cx.onConnectivityChanged;
}
