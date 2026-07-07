import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _controller;
  bool _loading = true;

  // The remote pages ship a dark theme (grey text on black) which is hard to
  // read inside the app. We force a clean light theme by injecting CSS once
  // the page has finished loading, regardless of the site's own styling.
  static const String _forceLightThemeJs = r'''
    (function() {
      var style = document.createElement('style');
      style.id = '__speedtrack_readability_override';
      style.innerHTML = `
        html, body { background-color: #ffffff !important; color: #16213e !important; }
        body, p, li, span, div, section, article, main, td, th, label {
          background-color: #ffffff !important;
          color: #16213e !important;
        }
        h1, h2, h3, h4, h5, h6 { color: #0b1220 !important; }
        a { color: #1565c0 !important; }
        input, textarea, select {
          background-color: #ffffff !important;
          color: #16213e !important;
          border: 1px solid #b0bac9 !important;
        }
        button, input[type="submit"] {
          background-color: #1565c0 !important;
          color: #ffffff !important;
        }
      `;
      document.head.appendChild(style);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            await _controller.runJavaScript(_forceLightThemeJs);
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: AppText.label(18)),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.neonCyan),
            ),
        ],
      ),
    );
  }
}
