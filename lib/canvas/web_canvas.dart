import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../pipe/alert_hub.dart';
import '../pipe/link_pulse.dart';
import '../pipe/local_store.dart';
import '../pipe/ua_masker.dart';
import 'no_wifi_panel.dart';

/// Immersive full-screen WebView for the gray content. Wears the
/// forged device UA, both orientations, immersive system UI,
/// external-scheme hand-off, redirect-loop recovery, live connectivity
/// guard, warm push link loading, third-party cookies, media autoplay,
/// safe-area and keyboard JS fixes.
///
/// The WebView is wrapped in `SafeArea(bottom: false)` so the camera
/// cutout is respected on BOTH orientations (top in portrait, sides in
/// landscape). Bottom inset is left at 0 — the keyboard is handled by
/// the JS scroll fix, not by layout resize.
class WebCanvas extends StatefulWidget {
  const WebCanvas({
    super.key,
    required this.link,
    required this.store,
    required this.alertHub,
    required this.linkPulse,
  });

  final String link;
  final LocalStore store;
  final AlertHub alertHub;
  final LinkPulse linkPulse;

  @override
  State<WebCanvas> createState() => _WebCanvasState();
}

class _WebCanvasState extends State<WebCanvas> with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _spinner = true;
  bool _offlineOpened = false;
  String? _lastMainFrame;
  int _redirectRetries = 0;
  Timer? _offlineDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  static const MethodChannel _fileChannel =
      MethodChannel('speedtrack/filepick');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _goImmersive();
    _buildController();

    widget.alertHub.onLink = (String link) {
      if (mounted) _web.loadRequest(Uri.parse(link));
    };

    // Debounced (700 ms) connectivity drop → No-Wifi. Prevents the VPN-
    // flicker flash on returning launches (see gray_part_pitfalls §3).
    _connSub =
        widget.linkPulse.changes.listen((List<ConnectivityResult> results) {
      final bool allNone = results.isNotEmpty &&
          results.every((ConnectivityResult r) => r == ConnectivityResult.none);
      if (!allNone) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _openOfflineDirect();
      });
    });
  }

  void _goImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _goImmersive();
  }

  void _buildController() {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(siteAgent.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _spinner = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _spinner = false);
          _redirectRetries = 0;
          _neutraliseSafeArea();
          _wireKeyboardScroll();
        },
        onWebResourceError: (WebResourceError err) {
          if (err.isForMainFrame != true) return;
          final String desc = err.description.toLowerCase();

          // Redirect-loop recovery.
          final bool loop = desc.contains('too_many_redirects') ||
              desc.contains('too many redirects') ||
              err.errorCode == -1007 ||
              err.errorCode == -9;
          if (loop && _lastMainFrame != null && _redirectRetries < 3) {
            _redirectRetries++;
            _web.loadRequest(Uri.parse(_lastMainFrame!));
            return;
          }

          // Cover the WebView's native error page IMMEDIATELY (spinner
          // overlay) so the black-robot page is never visible.
          if (mounted) setState(() => _spinner = true);

          final bool isDnsOrDisconnect =
              desc.contains('name_not_resolved') ||
                  desc.contains('err_name_not_resolved') ||
                  desc.contains('internet_disconnected') ||
                  desc.contains('network_changed') ||
                  err.errorCode == -105 ||
                  err.errorCode == -106 ||
                  err.errorCode == -21;

          if (isDnsOrDisconnect) {
            _openOfflineDirect();
          } else {
            _guardOffline();
          }
        },
        onNavigationRequest: (NavigationRequest req) {
          final Uri? uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          const Set<String> inApp = <String>{
            'http',
            'https',
            'about',
            'data',
            'blob',
          };
          if (inApp.contains(uri.scheme)) {
            if (req.isMainFrame) _lastMainFrame = req.url;
            return NavigationDecision.navigate;
          }
          _openExternally(uri);
          return NavigationDecision.prevent;
        },
      ));

    _tuneAndroid();
    _web.loadRequest(Uri.parse(widget.link));
  }

  void _tuneAndroid() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;
    final AndroidWebViewController a =
        _web.platform as AndroidWebViewController;

    a.setMediaPlaybackRequiresUserGesture(false);
    a.setOnPlatformPermissionRequest(
      (PlatformWebViewPermissionRequest req) => req.grant(),
    );
    a.setOnShowFileSelector(_pickFiles);

    final AndroidWebViewCookieManager cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(a, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final List<Object?>? picked =
          await _fileChannel.invokeMethod<List<Object?>>('pick', <String, Object>{
        'multiple': params.mode == FileSelectorMode.openMultiple,
        'mimeTypes': params.acceptTypes
            .where((String t) => t.trim().isNotEmpty)
            .toList(),
      });
      if (picked == null) return const <String>[];
      return picked.whereType<String>().toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _openExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Probe-then-show: for WebView load errors that might be transient.
  Future<void> _guardOffline() async {
    if (_offlineOpened) return;
    final bool online = await widget.linkPulse.isReachable();
    if (online) return;
    _openOfflineDirect();
  }

  /// Immediately swap to the No-Wifi panel. Retry rebuilds the WebView
  /// at the last known main-frame URL.
  void _openOfflineDirect() {
    if (_offlineOpened || !mounted) return;
    _offlineOpened = true;
    final String current = _lastMainFrame ?? widget.link;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => NoWifiPanel(
          onRetryBuild: (_) => WebCanvas(
            link: current,
            store: widget.store,
            alertHub: widget.alertHub,
            linkPulse: widget.linkPulse,
          ),
        ),
      ),
    );
  }

  /// Scrolls focused inputs above the on-screen keyboard. Uses
  /// `behavior:'auto'` (never smooth — smooth fights the keyboard
  /// animation and produces jitter, §3 of the pitfalls guide).
  void _wireKeyboardScroll() {
    _web.runJavaScript(r'''
(function(){
  if (window.__stKbFix) return; window.__stKbFix = true;
  function isField(el){return el&&(el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable);}
  function bring(){
    var el=document.activeElement; if(!isField(el))return;
    var vp=window.visualViewport;
    if(vp){
      var r=el.getBoundingClientRect(); var bottom=vp.offsetTop+vp.height;
      if(r.bottom>bottom-20||r.top<vp.offsetTop){el.scrollIntoView({behavior:'auto',block:'nearest'});}
    } else { el.scrollIntoView({behavior:'auto',block:'nearest'}); }
  }
  document.addEventListener('focusin',function(e){ if(isField(e.target)) setTimeout(bring,350); });
  if(window.visualViewport){
    var prev=window.visualViewport.height;
    window.visualViewport.addEventListener('resize',function(){
      var h=window.visualViewport.height; if(h<prev) setTimeout(bring,120); prev=h;
    });
  }
})();
''');
  }

  /// Neutralises site safe-area CSS variables so notched devices show
  /// no white bands. Only touches known top-spacer classes — NEVER
  /// html / body / #app / #root, which would erase the site's own
  /// horizontal gutters (see webview_safe_area_injection.mdc rule).
  void _neutraliseSafeArea() {
    _web.runJavaScript(r'''
(function(){
  if(window.__stSa) return; window.__stSa=true;
  var ID='__st_sa_v1';
  var CSS=':root{--safe-area-inset-top:0px!important;--safe-area-inset-right:0px!important;'
    +'--safe-area-inset-bottom:0px!important;--safe-area-inset-left:0px!important;'
    +'--sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;'
    +'--safe-top:0px!important;--safe-bottom:0px!important;--safe-left:0px!important;--safe-right:0px!important;}'
    +'.gameview-mobile-header,.app-header,.js-safe-top{padding-top:0!important;margin-top:0!important;}';
  function kbOpen(){ if(!window.visualViewport)return false; return window.visualViewport.height<window.innerHeight*0.75; }
  function apply(){
    if(kbOpen())return;
    var head=document.head||document.documentElement; if(!head)return;
    var m=document.querySelector('meta[name="viewport"]');
    if(m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content')||'')){
      var c=(m.getAttribute('content')||'').replace(/,?\s*viewport-fit\s*=\s*\w+/ig,'').trim();
      m.setAttribute('content', c+(c?', ':'')+'viewport-fit=contain');
    }
    var s=document.getElementById(ID);
    if(!s){ s=document.createElement('style'); s.id=ID; head.appendChild(s); }
    if(s.textContent!==CSS) s.textContent=CSS;
  }
  apply();
  ['pushState','replaceState'].forEach(function(fn){
    var o=history[fn]; history[fn]=function(){var r=o.apply(this,arguments); setTimeout(apply,80); setTimeout(apply,400); return r;};
  });
  window.addEventListener('popstate',function(){setTimeout(apply,80);});
  setInterval(apply,2500);
})();
''');
  }

  Future<void> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    widget.alertHub.onLink = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final bool landscape = mq.orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (!didPop) await _back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // WebView safe-area: keep the notch inset in BOTH
            // orientations (top in portrait, sides in landscape). No
            // bottom inset — the keyboard is handled by JS.
            SafeArea(
              bottom: false,
              child: WebViewWidget(controller: _web),
            ),
            if (_spinner && !landscape)
              const ColoredBox(
                color: Color(0x80000000),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF29B6FF)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
