// ignore_for_file: avoid_print
// Renders the four notification/no-wifi background webp files as PNG
// (with an overlaid tinted rectangle showing where our button widgets
// land) so we can eyeball the layout without launching the emulator.
//
// Usage: dart run tool/render_previews.dart
// Outputs go to build/previews/*.png (folder created on demand).

import 'dart:io';
import 'package:image/image.dart' as img;

class Rect {
  const Rect(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;
}

void main() {
  final Directory outDir = Directory('build/previews')..createSync(recursive: true);
  final String assetsDir = 'assets/CCTV_Speed_Track_additional_assets';

  // For each screen we approximate the actual layout done by the Dart
  // canvas widgets so we can eyeball the button positions on the art.

  // Notifications — portrait: Accept 70% × 56dp bottom 9%, Skip below.
  // Notifications — landscape: Accept 32% × 44dp bottom 7%, Skip below.
  _render(
    '$assetsDir/Vertical_Notifications_Screen.webp',
    '${outDir.path}/preview_notification_portrait.png',
    _stackVertical([
      _rectFrom(0.15, 0.83, 0.70, 0.06, 0xFF29B6FF),
      _rectFrom(0.15, 0.90, 0.70, 0.05, 0xFFAAAAAA),
    ]),
  );
  _render(
    '$assetsDir/Horizontal_Notifications_Screen.webp',
    '${outDir.path}/preview_notification_landscape.png',
    _stackVertical([
      _rectFrom(0.34, 0.72, 0.32, 0.08, 0xFF29B6FF),
      _rectFrom(0.34, 0.82, 0.32, 0.06, 0xFFAAAAAA),
    ]),
  );
  _render(
    '$assetsDir/Vertical_Nowifi_Screen.webp',
    '${outDir.path}/preview_nowifi_portrait.png',
    _stackVertical([
      _rectFrom(0.20, 0.85, 0.60, 0.06, 0xFF29B6FF),
    ]),
  );
  _render(
    '$assetsDir/Horizontal_Nowifi_Screen.webp',
    '${outDir.path}/preview_nowifi_landscape.png',
    _stackVertical([
      _rectFrom(0.35, 0.82, 0.30, 0.08, 0xFF29B6FF),
    ]),
  );

  print('Done. See ${outDir.path}/*.png');
}

typedef _Placer = Rect Function(int w, int h);

List<_Placer Function()> _stackVertical(List<_Placer Function()> boxes) => boxes;

_Placer Function() _rectFrom(double x, double y, double w, double h, int color) {
  return () => (int W, int H) => Rect((x * W).round(), (y * H).round(), (w * W).round(), (h * H).round());
}

void _render(String src, String dst, List<_Placer Function()> boxProviders) {
  final File srcFile = File(src);
  if (!srcFile.existsSync()) {
    print('skip (missing): $src');
    return;
  }
  final img.Image? bg = img.decodeWebP(srcFile.readAsBytesSync());
  if (bg == null) {
    print('decode failed: $src');
    return;
  }
  final img.Image out = img.copyResize(bg, width: bg.width, height: bg.height);
  for (final _Placer Function() provider in boxProviders) {
    final Rect r = provider()(out.width, out.height);
    _fillRectSemi(out, r, 0xFF29B6FF, 0.55);
    _borderRect(out, r, 0xFFFFFFFF);
  }
  File(dst).writeAsBytesSync(img.encodePng(out));
  print('wrote $dst');
}

void _fillRectSemi(img.Image out, Rect r, int argb, double alpha) {
  final int a = (255 * alpha).round();
  final int rr = (argb >> 16) & 0xFF;
  final int gg = (argb >> 8) & 0xFF;
  final int bb = argb & 0xFF;
  for (int y = r.top; y < r.top + r.height && y < out.height; y++) {
    for (int x = r.left; x < r.left + r.width && x < out.width; x++) {
      final img.Pixel p = out.getPixel(x, y);
      final int prr = ((p.r.toInt() * (255 - a)) + rr * a) ~/ 255;
      final int pgg = ((p.g.toInt() * (255 - a)) + gg * a) ~/ 255;
      final int pbb = ((p.b.toInt() * (255 - a)) + bb * a) ~/ 255;
      out.setPixelRgba(x, y, prr, pgg, pbb, 255);
    }
  }
}

void _borderRect(img.Image out, Rect r, int argb) {
  final int rr = (argb >> 16) & 0xFF;
  final int gg = (argb >> 8) & 0xFF;
  final int bb = argb & 0xFF;
  for (int x = r.left; x < r.left + r.width && x < out.width; x++) {
    if (r.top >= 0 && r.top < out.height) out.setPixelRgba(x, r.top, rr, gg, bb, 255);
    final int by = r.top + r.height - 1;
    if (by >= 0 && by < out.height) out.setPixelRgba(x, by, rr, gg, bb, 255);
  }
  for (int y = r.top; y < r.top + r.height && y < out.height; y++) {
    if (r.left >= 0 && r.left < out.width) out.setPixelRgba(r.left, y, rr, gg, bb, 255);
    final int bx = r.left + r.width - 1;
    if (bx >= 0 && bx < out.width) out.setPixelRgba(bx, y, rr, gg, bb, 255);
  }
}
