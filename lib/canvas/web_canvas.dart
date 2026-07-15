import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../insight/insight.dart';
import '../pipe/alert_hub.dart';
import '../pipe/link_pulse.dart';
import '../pipe/local_store.dart';
import '../pipe/ua_masker.dart';
import 'no_wifi_panel.dart';

/// Immersive full-screen WebView for the gray content. Wears the
/// forged device UA, both orientations, immersive system UI,
/// external-scheme hand-off, redirect-loop recovery, live connectivity
/// guard, warm push link loading, third-party cookies, media autoplay,
/// safe-area and keyboard JS fixes, and Microsoft Clarity funnel probes.
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
  int _serverRetries = 0;
  static const int _maxServerRetries = 2;
  Timer? _offlineDebounce;
  Timer? _serverRetryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  static const MethodChannel _fileChannel =
      MethodChannel('speedtrack/filepick');

  // Clarity funnel state — reset on each navigation.
  bool _offerReached = false;
  bool _pageHadError = false;

  static final RegExp _depositRx = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

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

    Insight.screen('web');
    Insight.event('web_open');

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
    if (state == AppLifecycleState.resumed) {
      _goImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      Insight.event('web_background');
    }
  }

  void _buildController() {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(siteAgent.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _pageHadError = false;
          if (mounted) setState(() => _spinner = true);
        },
        onPageFinished: (String url) {
          if (mounted) setState(() => _spinner = false);
          _redirectRetries = 0;
          _serverRetries = 0;
          _neutraliseSafeArea();
          _wireKeyboardScroll();
          _installInsightProbe();
          _trackWebPage(url);
        },
        onWebResourceError: (WebResourceError err) {
          if (err.isForMainFrame != true) return;
          _pageHadError = true;

          // Redirect-loop recovery.
          final String desc = err.description.toLowerCase();
          final bool loop = desc.contains('too_many_redirects') ||
              desc.contains('too many redirects') ||
              err.errorCode == -1007 ||
              err.errorCode == -9;
          if (loop && _lastMainFrame != null && _redirectRetries < 3) {
            _redirectRetries++;
            _web.loadRequest(Uri.parse(_lastMainFrame!));
            return;
          }

          // Cover the WebView's native error page IMMEDIATELY.
          if (mounted) setState(() => _spinner = true);

          final String reason = _classifyWebError(err);
          final String failed = _lastMainFrame ?? widget.link;
          final String host = Uri.tryParse(failed)?.host ?? '';

          Insight.event('web_error');
          Insight.tag('web_error_reason', reason);
          Insight.tag('web_last_error',
              '${err.errorCode}:${err.description}'.substring(
                  0,
                  '${err.errorCode}:${err.description}'.length.clamp(0, 255)));
          if (host.isNotEmpty) Insight.tag('web_error_host', host);

          if (!_offerReached) {
            Insight.event('web_offer_unreachable');
            Insight.tag('offer_reached', 'false');
            Insight.tag('offer_unreachable_reason', reason);
          } else {
            Insight.event('web_error_after_load');
          }

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
            _handleServerError();
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
          Insight.event('web_external');
          Insight.tag('web_external_scheme', uri.scheme);
          _openExternally(uri);
          return NavigationDecision.prevent;
        },
      ));

    _web.addJavaScriptChannel(
      'AegisInsight',
      onMessageReceived: (JavaScriptMessage m) => _onWebSignal(m.message),
    );

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

  /// Non-DNS load failure (ERR_CONNECTION_REFUSED / RESET / TIMED_OUT etc.).
  Future<void> _handleServerError() async {
    if (_offlineOpened) return;
    final bool online = await widget.linkPulse.isReachable();
    if (!online) {
      _openOfflineDirect();
      return;
    }
    if (_serverRetries < _maxServerRetries) {
      _serverRetries++;
      final int delayMs = 900 * _serverRetries;
      _serverRetryTimer?.cancel();
      _serverRetryTimer = Timer(Duration(milliseconds: delayMs), () {
        if (!mounted || _offlineOpened) return;
        final String target = _lastMainFrame ?? widget.link;
        _web.loadRequest(Uri.parse(target));
      });
      return;
    }
    _openOfflineDirect();
  }

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

  // ── Clarity funnel helpers ─────────────────────────────────────────

  void _trackWebPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String label = uri == null ? url : '${uri.host}${uri.path}';
    Insight.screenName('web:$label');
    Insight.event('web_page');
    Insight.tag('web_last_url', url.length > 255 ? url.substring(0, 255) : url);

    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null) Insight.tag('offer_host', uri!.host);
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  static String _classifyWebError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') || d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') || d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) { return 'dns_unresolved'; }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) { return 'no_network'; }
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') || d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) {
      return 'ssl_error';
    }
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  /// Idempotent JS probe — reports SPA route changes, deposit / register /
  /// login button clicks, and auth form submits over the `AegisInsight`
  /// channel. Safe to re-inject on every navigation.
  void _installInsightProbe() {
    _web.runJavaScript(r'''
(function(){
  if(window.__aegisInsight)return; window.__aegisInsight=true;
  function send(t){ try{ AegisInsight.postMessage(t); }catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p); } }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){
    var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; };
  });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
      case 'form_submit':
        Insight.event('web_form_submit');
    }
  }

  // ── Keyboard + safe-area JS injections ────────────────────────────

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
    _serverRetryTimer?.cancel();
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
