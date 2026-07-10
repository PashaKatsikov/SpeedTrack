/// Parsed response from the gate (config) endpoint.
///
/// Wire format: `{ ok, url, expires, message }` — the JSON keys are
/// mapped verbatim so the backend contract is preserved.
class GateVerdict {
  const GateVerdict({
    required this.allowed,
    this.link,
    this.note,
    this.ttl,
  });

  /// Backend `ok` — true means show the WebView with [link].
  final bool allowed;

  /// Backend `url` — the content URL to load unmodified.
  final String? link;

  /// Backend `message` — diagnostic note.
  final String? note;

  /// Backend `expires` — unix seconds after which [link] should be re-fetched.
  final int? ttl;

  factory GateVerdict.fromMap(Map<String, dynamic> map) {
    return GateVerdict(
      allowed: map['ok'] as bool? ?? false,
      link: map['url'] as String?,
      note: map['message'] as String?,
      ttl: map['expires'] as int?,
    );
  }

  factory GateVerdict.failure(String note) =>
      GateVerdict(allowed: false, note: note);

  bool get hasLink => link != null && link!.isNotEmpty;
}
