import 'dart:convert';

import '../cfg/route_config.dart';
import '../types/gate_verdict.dart';
import 'local_store.dart';
import 'ua_masker.dart';

/// Posts the merged attribution body to the gate endpoint and reads
/// the verdict.
///
/// On an allowed reply the content link and TTL are cached so
/// returning launches can fall back to it if the network later fails.
/// A missing endpoint or any error yields a failure verdict, which
/// routes the user to the native game.
class GateProbe {
  GateProbe(this._store);

  final LocalStore _store;

  Future<GateVerdict> query(Map<String, dynamic> body) async {
    final String endpoint = RouteConfig.gateEndpoint;
    if (endpoint.isEmpty) {
      return GateVerdict.failure('no-endpoint');
    }

    try {
      final dynamic res = await siteAgent
          .post(
            Uri.parse(endpoint),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        return GateVerdict.failure('http-${res.statusCode}');
      }

      final Map<String, dynamic> map =
          jsonDecode(res.body) as Map<String, dynamic>;
      final GateVerdict verdict = GateVerdict.fromMap(map);

      if (verdict.allowed && verdict.hasLink) {
        await _store.writeCachedLink(verdict.link!);
        if (verdict.ttl != null) {
          await _store.writeLinkTtl(verdict.ttl!);
        }
      }
      return verdict;
    } catch (e) {
      return GateVerdict.failure(e.toString());
    }
  }

  Future<String?> cachedLink() => _store.readCachedLink();
}
