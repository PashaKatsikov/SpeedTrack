// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// pack_secrets.dart — SpeedTrack keystream secret packer
// ─────────────────────────────────────────────────────────────
// Mirrors lib/scramble/unscrambler.dart. Run with:
//   dart run tool/pack_secrets.dart
// Then paste the printed byte lists into lib/cfg/sealed_strings.dart.
//
// IMPORTANT: seedPhrase / streamLength MUST equal the values in
// lib/scramble/unscrambler.dart. If you change one, change both.
// ─────────────────────────────────────────────────────────────

const String seedPhrase = 'Sp3edTr@ck_c1phR7';
const int streamLength = 34;

List<int> buildStream() {
  int hash = 0x811C9DC5;
  for (final int c in seedPhrase.codeUnits) {
    hash = (hash ^ c) & 0xFFFFFFFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  int state = hash == 0 ? 0x9E3779B9 : hash;
  final List<int> stream = List<int>.filled(streamLength, 0);
  for (int i = 0; i < streamLength; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    state &= 0xFFFFFFFF;
    stream[i] = (state >> 16) & 0xFF;
  }
  return stream;
}

final List<int> stream = buildStream();

List<int> pack(String plain) {
  final List<int> bytes = plain.codeUnits;
  final List<int> out = List<int>.filled(bytes.length, 0);
  for (int i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ^ stream[i % streamLength] ^ (i & 0xFF)) & 0xFF;
  }
  return out;
}

void emit(String label, String plain) {
  if (plain.isEmpty) {
    print('// $label — (empty, populate later)');
    print('const <int>[];\n');
    return;
  }
  final List<int> packed = pack(plain);
  print('// $label  <= "$plain"');
  print('const <int>[${packed.join(', ')}],\n');
}

void main() {
  // Real values for this project (Speed Track):
  const String gateEndpoint = 'https://speedtrrack.com/config.php';
  const String gcdBase = 'https://gcdsdk.appsflyer.com/install_data/v4.0/';
  // Chrome major=149 per policy. Build/patch randomised for THIS project.
  const String chromeVersion = '149.0.7723.87';
  const String webkitVersion = '537.36';

  // AppsFlyer Dev Key + Firebase project number for Speed Track.
  const String attributionKey = '5GfGgdgz6A3SmEyyajJFV7';
  const String messagingProject = '209494791787';

  print('=== Speed Track sealed_strings ===\n');
  emit('gateEndpoint', gateEndpoint);
  emit('gcdBase', gcdBase);
  emit('chromeVersion', chromeVersion);
  emit('webkitVersion', webkitVersion);
  emit('attributionKey', attributionKey);
  emit('messagingProject', messagingProject);
}
