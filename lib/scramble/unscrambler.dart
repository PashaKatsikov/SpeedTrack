import 'dart:typed_data';

/// Keystream deobfuscator for the Speed Track shell.
///
/// The transform is symmetric: bytes are XORed with a per-project
/// keystream derived from an FNV-1a seed + xorshift32 expansion, plus
/// their own offset in the range. That means two identical plaintext
/// bytes at different offsets encode to different output bytes, which
/// defeats trivial substring matching by store scanners.
///
/// [FINGERPRINT] Both `_seed` and `_streamLen` MUST be unique per
/// project. If either changes, `tool/pack_secrets.dart` must be re-run
/// and every packed list in `lib/cfg/sealed_strings.dart` refreshed.
const String _seed = 'Sp3edTr@ck_c1phR7';
const int _streamLen = 34;

Uint8List _forgeStream() {
  int hash = 0x811C9DC5;
  for (final int c in _seed.codeUnits) {
    hash = (hash ^ c) & 0xFFFFFFFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  int state = hash == 0 ? 0x9E3779B9 : hash;
  final Uint8List out = Uint8List(_streamLen);
  for (int i = 0; i < _streamLen; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    state &= 0xFFFFFFFF;
    out[i] = (state >> 16) & 0xFF;
  }
  return out;
}

final Uint8List _stream = _forgeStream();

/// Decodes a keystream-packed byte list back into the original UTF-8 string.
/// An empty input yields "" — that's the safe fallback used while the
/// template ships before real credentials are packed.
String unpack(List<int> packed) {
  if (packed.isEmpty) return '';
  final Uint8List out = Uint8List(packed.length);
  for (int i = 0; i < packed.length; i++) {
    out[i] = (packed[i] ^ _stream[i % _streamLen] ^ (i & 0xFF)) & 0xFF;
  }
  return String.fromCharCodes(out);
}
