/// Which experience the shell locked onto for this install.
///
/// - [gray]   → returning user previously routed to the WebView.
/// - [arcade] → returning user previously routed to the native game.
/// - [fresh]  → first launch, not yet decided.
enum RunMode {
  gray,
  arcade,
  fresh;

  static RunMode decode(String? raw) {
    switch (raw) {
      case 'gray':
        return RunMode.gray;
      case 'arcade':
        return RunMode.arcade;
      default:
        return RunMode.fresh;
    }
  }

  String encode() => name;
}
